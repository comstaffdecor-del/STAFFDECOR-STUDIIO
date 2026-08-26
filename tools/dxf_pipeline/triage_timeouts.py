#!/usr/bin/env python3
"""
triage_timeouts.py — Diagnostic PRE-BOUCLE des SKU en ERREUR_TIMEOUT.

But : trancher UNE question, sans jamais lancer la section coûteuse --
les timeouts sont-ils LENTS (N de sections plausible, cout de calcul
reel) ou ABERRANTS (N absurde, donc etendue de coordonnees anormale
en amont -- axe mal trouve, geometrie degeneree/dupliquee) ?

N'appelle JAMAIS BRepAlgoAPI_Section (la section couteuse). Reutilise
UNIQUEMENT les fonctions reelles de step2profile.py, avec leurs
signatures reelles (verifiees par introspection avant ecriture de ce
script, pas devinees) :
  - read_step_file(path) -> (shape, nb_roots, ocp_unit_str)
  - count_solids(shape) -> int
  - collect_solid_vertices(solid) -> np.ndarray
  - find_long_axis(verts) -> (origin, axis, ratio_2_1, length_native)
  - raw_step_header(path) -> dict (inspection texte brute, complementaire)

Point important verifie dans le code source de step2profile.py avant
d'ecrire ce script (process_one_step, lignes 587-590) : le balayage
utilise length_native (coordonnees natives du fichier), PAS length_mm --
commentaire du module, lignes 582-586 : "Toutes les coupes/aires sont
calculees en unite NATIVE du fichier". Donc N = length_native /
STEP_SWEEP_STEP_MM ne depend JAMAIS de scale_to_mm (donc jamais de
units_override.csv) -- seulement de l'etendue de coordonnees BRUTES
et de l'axe trouve par find_long_axis. Un N aberrant ne se corrige
donc pas par une entree dans units_override.csv (qui ne change que la
conversion finale en mm pour le JSON de sortie, pas le nombre de
coupes reellement effectuees).

Ne modifie rien, n'ecrit aucun JSON de production, ne touche pas au
pipeline. Le seul fichier ecrit est son propre rapport CSV.

Usage :
    python3 tools/dxf_pipeline/triage_timeouts.py D116 D515 ...
    python3 tools/dxf_pipeline/triage_timeouts.py --from-csv \
        tools/dxf_pipeline/logs/batch_corniches_20260825_160054.csv \
        --statut ERREUR_TIMEOUT
"""
from __future__ import annotations

import argparse
import csv
import sys
import traceback
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
STEP_DIR = REPO / "assets" / "step"

sys.path.insert(0, str(HERE))
import step2profile as s2p  # noqa: E402

SWEEP = s2p.STEP_SWEEP_STEP_MM  # constante reelle du module, pas de repli


def find_step_file(sku: str) -> Path | None:
    """Le nom de fichier ne suit pas toujours le SKU a la lettre (extension
    .step vs .stp observee sur D887), donc correspondance large."""
    if not STEP_DIR.is_dir():
        return None
    cands = [p for p in STEP_DIR.iterdir()
             if p.suffix.lower() in (".stp", ".step")
             and p.stem.upper() == sku.upper()]
    if not cands:
        cands = [p for p in STEP_DIR.iterdir()
                 if p.suffix.lower() in (".stp", ".step")
                 and p.stem.upper().startswith(sku.upper())]
    if not cands:
        cands = [p for p in STEP_DIR.iterdir()
                 if p.suffix.lower() in (".stp", ".step")
                 and sku.upper() in p.stem.upper()]
    cands.sort(key=lambda p: (p.stem.upper() != sku.upper(), len(p.stem)))
    return cands[0] if cands else None


def triage(sku: str) -> dict:
    row = {
        "sku": sku, "fichier": "", "ocp_unit": "", "nb_solides": "",
        "ratio_2_1": "", "length_native": "", "pas_native": SWEEP,
        "N": "", "verdict": "",
    }
    path = find_step_file(sku)
    if path is None:
        row["verdict"] = "STEP_ABSENT"
        return row
    row["fichier"] = path.name

    try:
        shape, nb_roots, ocp_unit_str = s2p.read_step_file(path)
    except Exception as e:  # noqa: BLE001
        row["verdict"] = f"ECHEC_LECTURE: {type(e).__name__}: {e}"
        return row

    row["ocp_unit"] = ocp_unit_str or "?"
    nb_solides = s2p.count_solids(shape)
    row["nb_solides"] = nb_solides

    if nb_solides != 1:
        row["verdict"] = "MULTI_SOLIDE (ERREUR_SELECTION attendue avant meme le balayage)"
        return row

    try:
        exp_solid = s2p.TopExp_Explorer(shape, s2p.TopAbs_SOLID)
        solid = s2p.TopoDS.Solid_s(exp_solid.Current())
        verts = s2p.collect_solid_vertices(solid)
    except Exception as e:  # noqa: BLE001
        row["verdict"] = f"ECHEC_EXTRACTION_SOMMETS: {type(e).__name__}: {e}"
        traceback.print_exc(limit=3)
        return row

    if len(verts) < 4:
        row["verdict"] = f"SOMMETS_INSUFFISANTS ({len(verts)})"
        return row

    try:
        origin_pt, axis, ratio_2_1, length_native = s2p.find_long_axis(verts)
    except Exception as e:  # noqa: BLE001
        row["verdict"] = f"ECHEC_ACP: {type(e).__name__}: {e}"
        traceback.print_exc(limit=3)
        return row

    row["ratio_2_1"] = round(float(ratio_2_1), 4)
    row["length_native"] = round(float(length_native), 3)

    if ratio_2_1 > s2p.ORIENTATION_RATIO_MAX:
        row["verdict"] = "ERREUR_ORIENTATION attendue (pas nettement allonge) avant le balayage"
        return row

    # N EXACTEMENT comme process_one_step le calcule (margin inclus) --
    # sans jamais appeler section_polygon_at / BRepAlgoAPI_Section.
    margin = max(length_native * 0.02, 2.0)
    n = max(0, int((length_native - 2 * margin) / SWEEP))
    row["N"] = n

    if n > 20000:
        row["verdict"] = f"N_ABERRANT ({n}) -> etendue de coordonnees anormale (axe/geometrie), PAS un probleme d'unite (N independant de scale_to_mm)"
    elif n > 3000:
        row["verdict"] = f"N_ELEVE ({n}) -> cout de calcul plausible (~{n*5/1000:.1f}s a 5ms/coupe)"
    elif n == 0:
        row["verdict"] = "N_NUL -> aucune coupe possible (length_native trop petit vs margin), ERREUR_SELECTION attendue, pas un timeout"
    else:
        row["verdict"] = f"N_PLAUSIBLE ({n}) -> blocage probable DANS la boucle (section individuelle qui coince), pas un volume excessif"

    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("skus", nargs="*")
    ap.add_argument("--from-csv")
    ap.add_argument("--statut", default="ERREUR_TIMEOUT")
    a = ap.parse_args()

    skus = list(a.skus)
    if a.from_csv:
        with open(a.from_csv, newline="") as f:
            for r in csv.DictReader(f):
                vals = " ".join(str(v) for v in r.values())
                if a.statut in vals:
                    skus.append(r.get("sku") or r.get("SKU") or "")
    skus = [s for s in dict.fromkeys(skus) if s]
    if not skus:
        print("Aucun SKU. Passer les SKU en argument ou --from-csv.")
        return 2

    print(f"pas de balayage STEP_SWEEP_STEP_MM = {SWEEP} (unite NATIVE du fichier, "
          f"pas mm -- voir docstring du module)\n")
    cols = ["sku", "fichier", "ocp_unit", "nb_solides", "ratio_2_1",
            "length_native", "N", "verdict"]
    rows = [triage(s) for s in skus]
    w = {c: max(len(c), *(len(str(r.get(c, ""))) for r in rows)) for c in cols}
    print(" | ".join(c.ljust(w[c]) for c in cols))
    print("-+-".join("-" * w[c] for c in cols))
    for r in rows:
        print(" | ".join(str(r.get(c, "")).ljust(w[c]) for c in cols))

    out = HERE / "triage_timeouts_rapport.csv"
    with open(out, "w", newline="") as f:
        wr = csv.DictWriter(f, fieldnames=cols + ["pas_native"])
        wr.writeheader()
        wr.writerows(rows)
    print(f"\n-> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
