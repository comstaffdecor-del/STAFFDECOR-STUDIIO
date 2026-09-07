"""P12 — service FastAPI de segmentation reelle des plans de piece.

Reference de contrat : docs/P12_BACKEND_CONTRACT.md (a la racine du repo
Flutter). En cas de divergence entre ce fichier et le document, le CODE
du client Dart (lib/core/perspective/http_room_plane_segmenter.dart) fait
foi ; ce service doit s'y conformer, pas l'inverse.

Requete attendue (multipart/form-data, emise par HttpRoomPlaneSegmenter) :
    width  = "512"   (champ texte, decimal)
    height = "384"   (champ texte, decimal)
    image  = <octets JPEG/PNG>, filename="room.jpg", name="image"

Reponse (200 uniquement) :
    {
      "width": 512, "height": 384,
      "labels": ["unknown", "ceiling", "wall", "floor"],
      "rle": [[classIndex, runLength], ...]   // parcours ligne-major
    }

Pipeline : decode -> infere (SegFormer, logits ADE20K 150 classes) ->
upsample BILINEAIRE des logits a (height, width) -> argmax -> mapping
vers les 4 classes de plan -> encodage RLE ligne-major.

L'ordre "upsample logits puis argmax" est deliberement dans ce sens et
jamais l'inverse : interpoler des indices de classe deja discretises
fabrique des classes fantomes aux frontieres, soit precisement la
grandeur que la sonde P12 mesure. C'est aussi ce que fait
post_process_semantic_segmentation() de HuggingFace.

Lancement local (dev) :
    MEASURE_MODE=1 uvicorn main:app --host 0.0.0.0 --port 8000

MEASURE_MODE=1 active un cache LRU borne (cle = sha256(image)+dims),
utile uniquement pendant la phase de mesure (memes 4 photos rejouees
plusieurs fois) ; a laisser desactive en production reelle multi-clients
tant que la politique de cache-par-utilisateur n'a pas ete pensee.
"""

from __future__ import annotations

import hashlib
import io
import os

import numpy as np
import torch
import torch.nn.functional as F
from cachetools import LRUCache
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image
from transformers import SegformerForSemanticSegmentation, SegformerImageProcessor

MODEL_ID = "nvidia/segformer-b0-finetuned-ade-512-512"

# Ordre et orthographe EXACTS attendus par decodeRoomPlaneMaskJson côté
# Dart (kRoomPlaneLabelOrder / RoomPlaneClass.values). Ne pas reordonner.
LABELS = ["unknown", "ceiling", "wall", "floor"]

# Indices ADE20K (0-based, lus depuis id2label, voir garde-fou plus bas)
# -> indices de plan (0=unknown, 1=ceiling, 2=wall, 3=floor).
# ATTENTION : objectInfo150.csv du MIT est 1-based (wall=1, floor=4,
# ceiling=6) ; ces indices-ci sont 0-based, issus de model.config.id2label.
# Ne jamais recopier de memoire l'un a la place de l'autre.
ADE_TO_PLANE = {0: 2, 3: 3, 5: 1}  # wall->2, floor->3, ceiling->1

app = FastAPI(title="P12 room-plane segmentation service")

app.add_middleware(
    CORSMiddleware,
    # CORSMiddleware compare les origines en EGALITE STRICTE : la chaine
    # "http://localhost:*" ne matche rien. allow_origin_regex est requis
    # pour couvrir les ports de dev Flutter Web variables.
    allow_origin_regex=r"^http://localhost(:[0-9]+)?$",
    allow_methods=["POST", "OPTIONS"],
    allow_headers=["*"],
)

_processor = SegformerImageProcessor.from_pretrained(MODEL_ID)
_model = SegformerForSemanticSegmentation.from_pretrained(MODEL_ID).eval()

# Garde-fou de demarrage : le mapping ADE_TO_PLANE ci-dessus n'a de sens
# que si le modele charge utilise bien la convention ADE20K standard.
# Si un modele different est branche un jour sans mettre a jour le
# mapping, on prefere un crash net au demarrage a des masques errones
# servis silencieusement en production.
for _ade_idx, _expected_name in ((0, "wall"), (3, "floor"), (5, "ceiling")):
    _got = _model.config.id2label[_ade_idx]
    if _got != _expected_name:
        raise RuntimeError(
            f"Garde-fou mapping ADE20K: id2label[{_ade_idx}]={_got!r}, "
            f"attendu {_expected_name!r}. ADE_TO_PLANE ne correspond plus "
            f"au modele charge ({MODEL_ID}) - a corriger avant de servir."
        )

MEASURE_MODE = os.getenv("MEASURE_MODE") == "1"
_cache: LRUCache | None = LRUCache(maxsize=64) if MEASURE_MODE else None


def _to_rle(plane_map: np.ndarray) -> list[list[int]]:
    """Encode une carte de classes (height, width) en RLE ligne-major.

    Parcours ligne-major (row-major, C order) : plane_map.reshape(-1)
    de numpy parcourt deja haut->bas puis gauche->droite par defaut,
    ce qui correspond exactement a la convention attendue par
    RoomPlaneMaskResult.decode() cote Dart (flat[y*width+x]).
    """
    flat = plane_map.reshape(-1)
    if flat.size == 0:
        return []
    change = np.flatnonzero(np.diff(flat)) + 1
    starts = np.concatenate(([0], change))
    ends = np.concatenate((change, [flat.size]))
    return [[int(flat[s]), int(e - s)] for s, e in zip(starts, ends)]


@app.post("/segment")
async def segment(
    width: int = Form(...),
    height: int = Form(...),
    image: UploadFile = File(...),
) -> dict:
    if not (16 <= width <= 2048 and 16 <= height <= 2048):
        raise HTTPException(400, "width/height hors bornes [16, 2048]")

    raw = await image.read()
    if not raw:
        raise HTTPException(400, "image vide")

    cache_key = None
    if _cache is not None:
        cache_key = (hashlib.sha256(raw).hexdigest(), width, height)
        cached = _cache.get(cache_key)
        if cached is not None:
            return cached

    try:
        img = Image.open(io.BytesIO(raw)).convert("RGB")
    except Exception as exc:  # image corrompue / format non supporte
        raise HTTPException(400, f"image illisible: {exc}") from exc

    with torch.no_grad():
        inputs = _processor(images=img, return_tensors="pt")
        logits = _model(**inputs).logits  # (1, 150, h_model, w_model)

    # Upsampling BILINEAIRE des LOGITS (valeurs continues) vers la
    # resolution demandee par le client, PUIS argmax. Jamais l'inverse :
    # argmax d'abord puis interpolation nearest/bilineaire sur des
    # indices de classe fabriquerait des classes fantomes aux
    # frontieres - exactement ce que la sonde P12 mesure.
    logits = F.interpolate(
        logits, size=(height, width), mode="bilinear", align_corners=False
    )
    ade_map = logits.argmax(dim=1)[0].cpu().numpy().astype(np.int32)

    plane_map = np.zeros((height, width), dtype=np.int32)  # defaut: unknown (0)
    for ade_idx, plane_idx in ADE_TO_PLANE.items():
        plane_map[ade_map == ade_idx] = plane_idx

    rle = _to_rle(plane_map)

    # Invariant 3 du contrat : la somme des runLength doit valoir
    # exactement width*height. Verifie ici pour echouer cote serveur
    # (log clair) plutot que de laisser le client decouvrir un
    # ArgumentError opaque en cas de bug d'encodage RLE.
    total = sum(r[1] for r in rle)
    if total != width * height:
        raise HTTPException(
            500,
            f"bug interne: somme(runLength)={total} != width*height="
            f"{width * height}",
        )

    result = {"width": width, "height": height, "labels": LABELS, "rle": rle}
    if _cache is not None and cache_key is not None:
        _cache[cache_key] = result
    return result


@app.get("/health")
async def health() -> dict:
    """Endpoint de sante minimal, utile pour curl / probes de deploiement."""
    return {"status": "ok", "model": MODEL_ID, "measure_mode": MEASURE_MODE}
