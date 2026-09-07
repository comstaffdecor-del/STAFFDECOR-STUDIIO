"""P12-bis — export visuel du masque de segmentation superpose a la
photo source, pour inspection manuelle (hypothese B du brief : le masque
est-il visuellement correct, meme si les chiffres de la sonde sont
mauvais ?).

Script de diagnostic, non committe comme fonctionnalite du service :
appelle directement /segment (pas de modification du contrat), decode
le RLE recu, colore chaque classe, et sauve deux images cote a cote
(source | masque colore superpose en transparence).

Usage :
    python3 tools/visualize_mask.py <scene> [--do-resize-false]

    <scene> in {haussmann, moderne, provencal, scandinave}
    --do-resize-false : appelle une route de diagnostic separee qui
        desactive le redimensionnement du processeur (hypothese A),
        pour comparaison visuelle directe.

Sortie : /tmp/p12bis_mask_<scene>[_noresize].png
"""

from __future__ import annotations

import argparse
import io
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Reutilise directement les objets du service (meme process Python que
# main.py, pas de nouvel import HTTP) pour pouvoir passer do_resize=False
# sans exposer ce parametre dans le contrat HTTP reel.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import torch  # noqa: E402
import torch.nn.functional as F  # noqa: E402
from main import ADE_TO_PLANE, _model, _processor  # noqa: E402

DEMO_SCENES_DIR = Path(__file__).resolve().parent.parent.parent.parent / "assets" / "demo_scenes"

# Couleurs BGR->RGB lisibles, une par classe de plan (index = classIndex
# du contrat : 0=unknown, 1=ceiling, 2=wall, 3=floor).
PLANE_COLORS = {
    0: (128, 128, 128),  # unknown : gris
    1: (255, 80, 80),    # ceiling : rouge clair
    2: (80, 200, 80),    # wall : vert
    3: (80, 120, 255),   # floor : bleu
}

TARGET_W, TARGET_H = 512, 384


def infer_plane_map(img: Image.Image, do_resize: bool) -> np.ndarray:
    """Reproduit exactement le pipeline de main.py:segment(), avec
    do_resize configurable (jamais expose dans le contrat HTTP reel -
    uniquement pour ce diagnostic local)."""
    with torch.no_grad():
        inputs = _processor(images=img, return_tensors="pt", do_resize=do_resize)
        logits = _model(**inputs).logits

    logits = F.interpolate(
        logits, size=(TARGET_H, TARGET_W), mode="bilinear", align_corners=False
    )
    ade_map = logits.argmax(dim=1)[0].cpu().numpy().astype(np.int32)

    plane_map = np.zeros((TARGET_H, TARGET_W), dtype=np.int32)
    for ade_idx, plane_idx in ADE_TO_PLANE.items():
        plane_map[ade_map == ade_idx] = plane_idx
    return plane_map


def colorize(plane_map: np.ndarray) -> np.ndarray:
    h, w = plane_map.shape
    out = np.zeros((h, w, 3), dtype=np.uint8)
    for idx, color in PLANE_COLORS.items():
        out[plane_map == idx] = color
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("scene", choices=["haussmann", "moderne", "provencal", "scandinave"])
    parser.add_argument("--do-resize-false", action="store_true", dest="no_resize")
    args = parser.parse_args()

    img_path = DEMO_SCENES_DIR / f"{args.scene}.jpg"
    img = Image.open(img_path).convert("RGB")

    do_resize = not args.no_resize
    plane_map = infer_plane_map(img, do_resize=do_resize)

    # Compte par classe pour un resume texte immediat, en plus du PNG.
    unique, counts = np.unique(plane_map, return_counts=True)
    total = plane_map.size
    dist = {int(u): round(int(c) / total, 3) for u, c in zip(unique, counts)}
    print(f"scene={args.scene} do_resize={do_resize} distribution(0=unk,1=ceil,2=wall,3=floor)={dist}")

    mask_colored = colorize(plane_map)
    mask_img = Image.fromarray(mask_colored).resize((TARGET_W, TARGET_H), Image.NEAREST)

    # Source redimensionnee a la meme taille que le masque pour
    # permettre une comparaison cote a cote ET une superposition.
    src_resized = img.resize((TARGET_W, TARGET_H), Image.BILINEAR)

    # Superposition : 55% source, 45% masque colore.
    overlay = Image.blend(src_resized, mask_img, alpha=0.45)

    # Montage cote a cote : source | masque pur | superposition.
    montage = Image.new("RGB", (TARGET_W * 3, TARGET_H))
    montage.paste(src_resized, (0, 0))
    montage.paste(mask_img, (TARGET_W, 0))
    montage.paste(overlay, (TARGET_W * 2, 0))

    suffix = "_noresize" if args.no_resize else ""
    out_path = f"/tmp/p12bis_mask_{args.scene}{suffix}.png"
    montage.save(out_path)
    print(f"ecrit: {out_path} (gauche=source, milieu=masque colore, droite=superposition)")
    print("legende: gris=unknown, rouge=ceiling, vert=wall, bleu=floor")


if __name__ == "__main__":
    main()
