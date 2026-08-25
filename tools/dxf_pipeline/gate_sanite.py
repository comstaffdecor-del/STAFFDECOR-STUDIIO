#!/usr/bin/env python3
"""gate_sanite.py — GATE DE SANITÉ post-extraction (Piste A, brief calibration).

CONTEXTE : step2profile.py/solid2profile.py écrivent statut=OK sur des
profils qui, on vient de le vérifier sur l'échantillon pilote, peuvent être
géométriquement invalides sans que le script d'extraction ne s'en aperçoive
(picker de face mal aligné, dégénérescence en triangle, bruit de
tessellation). Ce gate ne RÉPARE ni ne SUPPRIME rien — il MARQUE. Un
profil qui échoue un critère reçoit `statut_gate: "SUSPECT_GEOMETRIE"` et
la liste des motifs qui ont déclenché ce statut ; le JSON produit par
step2profile.py reste inchangé sur disque, ce script produit un rapport
séparé (jamais de réécriture in-place des profils).

RÈGLE DIRECTRICE (imposée) : le critère 1 (contrat loader) doit être une
COPIE LITTÉRALE des conditions de rejet de `loadProfileDims`
(lib/core/perspective/profile_dims.dart) — jamais une variante. Tout écart
entre ce gate et le loader créerait des profils marqués "sains" par le
gate mais rejetés silencieusement par l'app (ou l'inverse), ce qui est
précisément le piège que ce script existe pour éviter.

CRITÈRES (6, tous non destructifs, motifs cumulables) :
  1. CONTRAT_LOADER_*        — reprise exacte des 4 conditions de rejet
     de loadProfileDims (statut, profil_mm non vide, indices mur/plafond
     non vides), PLUS un seuil de 3 points minimum (plus strict que le
     loader littéral qui accepte tout non-vide, jamais moins strict).
  2. DEBORD_PLAN_MUR/PLAFOND — reprise littérale de l'assertion debug du
     loader (tolérance 0.001mm, aucune variante).
  3. SOMMETS_INSUFFISANTS    — sommets EFFECTIFS (après suppression des
     sommets quasi colinéaires, angle intérieur > 175°), seuil minimum 5.
  4. BRUIT_TESSELLATION      — nombre de segments de la boucle fermée dont
     la longueur est < 1% de la diagonale bbox. Seuil de rejet PROVISOIRE
     (non figé, voir rapport séparé de comptage brut sur les 18 pilotes).
  5. JITTER_CONTOUR          — inversions de signe de dy entre deux
     segments ADJACENTS tous deux < 2% de diag, zone morte |dy| < 0.5%
     de diag (évite les faux positifs sur profils ornementaux riches à
     inversions légitimes, ex. D748/31 sommets). Seuil PROVISOIRE.
  6. SECTION_PLATE           — ratio min(w,h)/max(w,h) < 0.15, PORTÉE
     LIMITÉE : appliqué uniquement aux SKU de la famille corniche/moulure
     (liste explicite ci-dessous — le champ JSON `famille` est toujours
     null en pratique dans ce jeu de données, aucune détection auto
     possible depuis le JSON seul). Jamais appliqué à une plinthe dans
     cette passe (elles sont plates par nature, ce n'est pas un signal
     d'anomalie pour elles) — à ne pas transposer sans révision explicite.

SIGNAL NON BLOQUANT (ne contribue jamais à statut_gate) :
  - projection_plafond_mm == bbox_mm.w (égalité exacte) : signe probable
    d'un plan de pose dégénéré (observé sur PLIN20).
"""

import argparse
import csv
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).parent
DEFAULT_PROFILES_DIR = HERE.parent.parent / "assets" / "profiles"
DEFAULT_OUTPUT_CSV = HERE / "gate_sanite_rapport.csv"

# --- Seuils fixes (spécifiés, non provisoires) ---------------------------
ANGLE_COLINEAIRE_DEG = 175.0
SOMMETS_EFFECTIFS_MIN = 5
ASSERTION_TOL_MM = 0.001
PLATITUDE_RATIO_MAX = 0.15
PROFIL_MM_MIN_POINTS = 3

# --- Seuils PROVISOIRES (critères 4 et 5 — à calibrer sur le rapport) ---
BRUIT_SEG_RATIO = 0.01          # 1% de diag
BRUIT_SEUIL_PROVISOIRE = 3      # nombre de segments sous le seuil
JITTER_SEG_RATIO = 0.02         # 2% de diag (les deux segments adjacents)
JITTER_DEADZONE_RATIO = 0.005   # 0.5% de diag (zone morte |dy|)
JITTER_SEUIL_PROVISOIRE = 3     # nombre d'inversions

# Portée du critère 6 (SECTION_PLATE) — liste explicite, PAS de détection
# automatique depuis le champ JSON `famille` (toujours null en pratique
# dans ce jeu de données). TAL26 classé "moulure" (catalogue: "Talon pour
# PLIN25.PC.SP") — classification manuelle, à confirmer si contestée.
FAMILLE_CORNICHE_MOULURE_SKUS = {
    "D555", "D562", "D576", "D614", "D620", "D631", "D705", "D706",
    "D709", "D718", "D720", "D748", "D891", "TAL26",
}


def polygon_closed_segments(pts):
    n = len(pts)
    return [(pts[i], pts[(i + 1) % n]) for i in range(n)]


def seg_len(p0, p1):
    return math.hypot(p1[0] - p0[0], p1[1] - p0[1])


def interior_angle_deg(p_prev, p_i, p_next):
    """Angle (degrés) entre les vecteurs p_i->p_prev et p_i->p_next.
    ~180° = p_i quasi colinéaire avec ses deux voisins (sommet
    superflu, candidat à suppression pour le compte de sommets
    effectifs)."""
    v1 = (p_prev[0] - p_i[0], p_prev[1] - p_i[1])
    v2 = (p_next[0] - p_i[0], p_next[1] - p_i[1])
    n1 = math.hypot(*v1)
    n2 = math.hypot(*v2)
    if n1 == 0 or n2 == 0:
        return 180.0  # point dégénéré confondu avec un voisin -> traité comme colinéaire
    cos_a = max(-1.0, min(1.0, (v1[0] * v2[0] + v1[1] * v2[1]) / (n1 * n2)))
    return math.degrees(math.acos(cos_a))


def sommets_effectifs(pts):
    """Retourne (n_brut, n_effectifs, indices_supprimes). Suppression en
    UNE passe sur le polygone original (pas de suppression itérative en
    cascade) — simple, déterministe, suffisant pour distinguer un
    polygone dégénéré (PLIN12) d'une corniche à arêtes vives (D706)."""
    n = len(pts)
    if n < 3:
        return n, n, []
    removed = []
    kept = 0
    for i in range(n):
        p_prev = pts[(i - 1) % n]
        p_i = pts[i]
        p_next = pts[(i + 1) % n]
        ang = interior_angle_deg(p_prev, p_i, p_next)
        if ang > ANGLE_COLINEAIRE_DEG:
            removed.append(i)
        else:
            kept += 1
    return n, kept, removed


def bruit_tessellation_count(pts, diag):
    seuil = diag * BRUIT_SEG_RATIO
    lens = [seg_len(a, b) for a, b in polygon_closed_segments(pts)]
    return sum(1 for L in lens if L < seuil), lens


def jitter_count(pts, diag):
    """Inversions de signe de dy entre segments ADJACENTS, filtrées :
    - zone morte : un dy dont |dy| < deadzone n'est jamais considéré
      comme porteur de signe (évite de compter une inversion sur un
      quasi-plat).
    - les DEUX segments adjacents à l'inversion doivent être < seg_seuil
      (2% de diag) — cible le tremblement local, pas une vraie alternance
      de pente sur un motif ornemental riche à grands segments."""
    n = len(pts)
    lens = [seg_len(a, b) for a, b in polygon_closed_segments(pts)]
    dys = [pts[(i + 1) % n][1] - pts[i][1] for i in range(n)]
    deadzone = diag * JITTER_DEADZONE_RATIO
    seg_seuil = diag * JITTER_SEG_RATIO
    count = 0
    details = []
    for i in range(n):
        prev_i = (i - 1) % n
        dy_prev, dy_cur = dys[prev_i], dys[i]
        if abs(dy_prev) < deadzone or abs(dy_cur) < deadzone:
            continue
        if (dy_prev > 0) == (dy_cur > 0):
            continue
        if lens[prev_i] < seg_seuil and lens[i] < seg_seuil:
            count += 1
            details.append((prev_i, i))
    return count, details


def check_gate(sku, data):
    """Applique les 6 critères. Retourne un dict complet (motifs +
    valeurs brutes de chaque critère, y compris pour les critères 4/5
    dont le seuil est provisoire — le compte brut est TOUJOURS rapporté,
    indépendamment de la décision de rejet à ce seuil)."""
    motifs = []
    profil = data.get("profil_mm") or []
    statut = data.get("statut")
    face_mur_idx = (data.get("face_pose_mur") or {}).get("indices") or []
    face_plafond_idx = (data.get("face_pose_plafond") or {}).get("indices") or []
    bbox = data.get("bbox_mm") or {}
    w, h = bbox.get("w"), bbox.get("h")

    # --- Critère 1 : contrat loader (copie littérale + seuil >=3 pts) ---
    if statut != "OK":
        motifs.append("CONTRAT_LOADER_STATUT_NON_OK")
    if len(profil) < PROFIL_MM_MIN_POINTS:
        motifs.append(f"CONTRAT_LOADER_PROFIL_INSUFFISANT (n={len(profil)})")
    if not face_mur_idx:
        motifs.append("CONTRAT_LOADER_MUR_VIDE")
    if not face_plafond_idx:
        motifs.append("CONTRAT_LOADER_PLAFOND_VIDE")

    can_geom = (
        statut == "OK"
        and len(profil) >= PROFIL_MM_MIN_POINTS
        and w is not None and h is not None
        and w > 0 and h > 0
    )

    diag = math.hypot(w, h) if (can_geom) else None
    debord_mur_mm = None
    debord_plafond_mm = None
    n_brut = len(profil)
    n_eff = None
    bruit_n = None
    jitter_n = None
    platitude_ratio = None
    platitude_applique = False

    # --- Critère 2 : débord de plan (réplique littérale de l'assertion) ---
    if can_geom and face_mur_idx:
        wallX = profil[face_mur_idx[0]][0]
        maxdx = max(abs(p[0] - wallX) for p in profil)
        debord_mur_mm = abs(maxdx - w)
        if debord_mur_mm > ASSERTION_TOL_MM:
            motifs.append(f"DEBORD_PLAN_MUR (ecart={debord_mur_mm:.3f}mm)")

    if can_geom and face_plafond_idx:
        ceilY = profil[face_plafond_idx[0]][1]
        maxdy = max(abs(p[1] - ceilY) for p in profil)
        debord_plafond_mm = abs(maxdy - h)
        if debord_plafond_mm > ASSERTION_TOL_MM:
            motifs.append(f"DEBORD_PLAN_PLAFOND (ecart={debord_plafond_mm:.3f}mm)")

    # --- Critère 3 : sommets effectifs ---
    if can_geom:
        n_brut, n_eff, _removed = sommets_effectifs(profil)
        if n_eff < SOMMETS_EFFECTIFS_MIN:
            motifs.append(
                f"SOMMETS_INSUFFISANTS (brut={n_brut}, effectifs={n_eff})"
            )

    # --- Critères 4 et 5 : comptes TOUJOURS calculés et rapportés,
    # seuil de rejet appliqué à titre PROVISOIRE (motif porte "provisoire"
    # explicitement pour ne jamais être confondu avec un seuil figé) ---
    if can_geom and diag:
        bruit_n, _ = bruit_tessellation_count(profil, diag)
        if bruit_n >= BRUIT_SEUIL_PROVISOIRE:
            motifs.append(
                f"BRUIT_TESSELLATION (count={bruit_n}, seuil_provisoire="
                f"{BRUIT_SEUIL_PROVISOIRE})"
            )
        jitter_n, _ = jitter_count(profil, diag)
        if jitter_n >= JITTER_SEUIL_PROVISOIRE:
            motifs.append(
                f"JITTER_CONTOUR (count={jitter_n}, seuil_provisoire="
                f"{JITTER_SEUIL_PROVISOIRE})"
            )

    # --- Critère 6 : platitude, portée limitée corniche/moulure ---
    if can_geom:
        platitude_ratio = min(w, h) / max(w, h)
        platitude_applique = sku in FAMILLE_CORNICHE_MOULURE_SKUS
        if platitude_applique and platitude_ratio < PLATITUDE_RATIO_MAX:
            motifs.append(f"SECTION_PLATE (ratio={platitude_ratio:.3f})")

    # --- Signal non bloquant ---
    proj = data.get("projection_plafond_mm")
    signal_projection_egale_bbox_w = (
        proj is not None and w is not None and proj == w
    )

    return {
        "sku": sku,
        "statut_gate": "SUSPECT_GEOMETRIE" if motifs else "OK",
        "motifs": motifs,
        "n_sommets_brut": n_brut,
        "n_sommets_effectifs": n_eff,
        "debord_mur_mm": debord_mur_mm,
        "debord_plafond_mm": debord_plafond_mm,
        "bruit_tessellation_count": bruit_n,
        "jitter_contour_count": jitter_n,
        "platitude_ratio": platitude_ratio,
        "platitude_critere_applique": platitude_applique,
        "signal_projection_egale_bbox_w": signal_projection_egale_bbox_w,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--profiles-dir", default=str(DEFAULT_PROFILES_DIR))
    ap.add_argument("--output", default=str(DEFAULT_OUTPUT_CSV))
    ap.add_argument(
        "--sku", nargs="*", default=None,
        help="Limiter le rapport a ces SKU (sinon: tout assets/profiles/*.json)",
    )
    args = ap.parse_args()

    profiles_dir = Path(args.profiles_dir)
    if not profiles_dir.exists():
        print(f"ERREUR: dossier introuvable: {profiles_dir}", file=sys.stderr)
        sys.exit(1)

    files = sorted(profiles_dir.glob("*.json"))
    if args.sku:
        wanted = set(args.sku)
        files = [f for f in files if f.stem in wanted]

    results = []
    for f in files:
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            print(f"ATTENTION: JSON illisible {f.name}: {e}", file=sys.stderr)
            continue
        sku = data.get("sku", f.stem)
        results.append(check_gate(sku, data))

    fieldnames = [
        "sku", "statut_gate", "motifs", "n_sommets_brut",
        "n_sommets_effectifs", "debord_mur_mm", "debord_plafond_mm",
        "bruit_tessellation_count", "jitter_contour_count",
        "platitude_ratio", "platitude_critere_applique",
        "signal_projection_egale_bbox_w",
    ]
    with open(args.output, "w", newline="", encoding="utf-8") as fp:
        writer = csv.DictWriter(fp, fieldnames=fieldnames)
        writer.writeheader()
        for r in results:
            row = dict(r)
            row["motifs"] = "; ".join(r["motifs"])
            writer.writerow(row)

    nb_ok = sum(1 for r in results if r["statut_gate"] == "OK")
    nb_suspect = sum(1 for r in results if r["statut_gate"] == "SUSPECT_GEOMETRIE")
    print(f"=== gate_sanite: {len(results)} profils analyses -> {args.output} ===")
    print(f"  OK           : {nb_ok}")
    print(f"  SUSPECT_GEOMETRIE : {nb_suspect}")
    print()
    for r in results:
        marker = "⚠️ " if r["statut_gate"] == "SUSPECT_GEOMETRIE" else "✅ "
        print(f"{marker}{r['sku']:8s} n_brut={r['n_sommets_brut']} "
              f"n_eff={r['n_sommets_effectifs']} "
              f"bruit={r['bruit_tessellation_count']} "
              f"jitter={r['jitter_contour_count']} "
              f"platitude={r['platitude_ratio']}")
        for m in r["motifs"]:
            print(f"      - {m}")


if __name__ == "__main__":
    main()
