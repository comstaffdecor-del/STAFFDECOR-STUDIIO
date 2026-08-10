#!/usr/bin/env python3
"""
croisement_suivi_manifest_catalogue.py — croise suivi.csv (matrice de
disponibilité BE) x manifest.csv (fichiers réellement présents sur la
GED, scan build_manifest.py) x catalogue.csv (tarif papier) sur le SKU
normalisé (normalize_sku()).

OBJECTIF (demandé explicitement) : produire un décompte fiable —
combien de SKU ont un DXF 2D EXPLOITABLE (present dans manifest.csv,
extension dxf/dwg), combien ont un STEP, combien ont un STL, combien
n'ont RIEN — pour trancher l'ordre de développement sur des chiffres,
pas une intuition.

DISTINCTION IMPORTANTE : suivi.csv annonce ce que le BE DÉCLARE exister
(colonnes booléennes dxf/dwg2d/step/stl...) ; manifest.csv liste ce qui
est RÉELLEMENT téléchargeable sur la GED (download_url par extension).
Les deux peuvent diverger (cf. D105A : suivi dit step=1/skp=1/stl=1,
confirmé présent sur la GED mais sous le SKU groupé "d105a-b", pas
"d105a" — cf. SPEC.md, "Règle — toujours interroger suivi.csv..."). Ce
script rapporte les DEUX vues séparément puis une vue combinée
(exploitable = présent dans manifest.csv, la source la plus proche de
"utilisable par le pipeline maintenant").

SORTIE : tools/dxf_pipeline/croisement_suivi_manifest_catalogue.csv
(une ligne par SKU normalisé, union suivi ∪ manifest ∪ catalogue) +
un récapitulatif chiffré imprimé.
"""
import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from dxf2profile import normalize_sku  # noqa: E402

HERE = Path(__file__).parent
DEFAULT_SUIVI_PATH = HERE / "suivi.csv"
DEFAULT_MANIFEST_PATH = HERE / "manifest.csv"
DEFAULT_CATALOGUE_PATH = HERE / "catalogue.csv"
DEFAULT_OUTPUT_PATH = HERE / "croisement_suivi_manifest_catalogue.csv"

# manifest.csv "extension" -> quel format ça représente pour ce croisement
MANIFEST_EXT_TO_FORMAT = {
    "dxf": "dxf_manifest",
    "dwg": "dwg_manifest",
    "step": "step_manifest",
    "stp": "step_manifest",
    "stl": "stl_manifest",
    "skp": "skp_manifest",
}


def load_suivi(path):
    """sku_normalise -> dict (une seule ligne attendue par sku_normalise,
    vérifié — pas de fusion multi-lignes nécessaire sur ce fichier)."""
    out = {}
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            out[row["sku_normalise"]] = row
    return out


def load_manifest_by_sku(path):
    """sku_normalise -> set des formats manifest présents (dxf_manifest,
    dwg_manifest, step_manifest, stl_manifest, skp_manifest)."""
    out = defaultdict(set)
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            sku_norm = normalize_sku(row["sku"])
            fmt = MANIFEST_EXT_TO_FORMAT.get(row["extension"].lower())
            if fmt:
                out[sku_norm].add(fmt)
    return out


def load_catalogue_skus(path):
    """set des sku_normalise présents dans catalogue.csv."""
    out = set()
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            out.add(normalize_sku(row["sku"]))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--suivi", default=str(DEFAULT_SUIVI_PATH))
    ap.add_argument("--manifest", default=str(DEFAULT_MANIFEST_PATH))
    ap.add_argument("--catalogue", default=str(DEFAULT_CATALOGUE_PATH))
    ap.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH))
    args = ap.parse_args()

    suivi_path = Path(args.suivi)
    manifest_path = Path(args.manifest)
    catalogue_path = Path(args.catalogue)
    output_path = Path(args.output)

    for p in (suivi_path, manifest_path, catalogue_path):
        if not p.exists():
            print(f"ERREUR: fichier introuvable: {p}", file=sys.stderr)
            sys.exit(1)

    suivi = load_suivi(suivi_path)
    manifest_formats = load_manifest_by_sku(manifest_path)
    catalogue_skus = load_catalogue_skus(catalogue_path)

    all_skus = set(suivi.keys()) | set(manifest_formats.keys()) | catalogue_skus

    out_rows = []
    for sku_norm in sorted(all_skus):
        s = suivi.get(sku_norm)
        mf = manifest_formats.get(sku_norm, set())

        dans_suivi = s is not None
        dans_manifest = sku_norm in manifest_formats
        dans_catalogue = sku_norm in catalogue_skus

        # Vue BE-déclaré (suivi.csv) — colonnes booléennes déjà normalisées.
        be_dxf = (s.get("dxf") == "True" or s.get("dwg2d") == "True") if s else False
        be_step = (s.get("step") == "True") if s else False
        be_stl = (s.get("stl") == "True") if s else False

        # Vue GED-réelle (manifest.csv) — ce qui est effectivement
        # téléchargeable aujourd'hui.
        ged_dxf = "dxf_manifest" in mf or "dwg_manifest" in mf
        ged_step = "step_manifest" in mf
        ged_stl = "stl_manifest" in mf

        rien_du_tout = not (be_dxf or be_step or be_stl or ged_dxf or ged_step or ged_stl)

        out_rows.append({
            "sku_normalise": sku_norm,
            "sku_suivi": s.get("sku") if s else "",
            "dans_suivi": dans_suivi,
            "dans_manifest": dans_manifest,
            "dans_catalogue": dans_catalogue,
            "statut_gestion": s.get("statut_gestion") if s else "",
            "be_declare_dxf_ou_dwg2d": be_dxf,
            "be_declare_step": be_step,
            "be_declare_stl": be_stl,
            "ged_reel_dxf_ou_dwg": ged_dxf,
            "ged_reel_step": ged_step,
            "ged_reel_stl": ged_stl,
            "aucun_format_ni_be_ni_ged": rien_du_tout,
        })

    fieldnames = list(out_rows[0].keys()) if out_rows else []
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in out_rows:
            writer.writerow(row)

    nb_total = len(out_rows)
    nb_be_dxf = sum(1 for r in out_rows if r["be_declare_dxf_ou_dwg2d"])
    nb_be_step = sum(1 for r in out_rows if r["be_declare_step"])
    nb_be_stl = sum(1 for r in out_rows if r["be_declare_stl"])
    nb_ged_dxf = sum(1 for r in out_rows if r["ged_reel_dxf_ou_dwg"])
    nb_ged_step = sum(1 for r in out_rows if r["ged_reel_step"])
    nb_ged_stl = sum(1 for r in out_rows if r["ged_reel_stl"])
    nb_rien = sum(1 for r in out_rows if r["aucun_format_ni_be_ni_ged"])

    print(f"=== croisement écrit ({nb_total} SKU, union suivi/manifest/catalogue) -> {output_path} ===")
    print(f"  SKU dans suivi.csv          : {sum(1 for r in out_rows if r['dans_suivi'])}")
    print(f"  SKU dans manifest.csv       : {sum(1 for r in out_rows if r['dans_manifest'])}")
    print(f"  SKU dans catalogue.csv      : {sum(1 for r in out_rows if r['dans_catalogue'])}")
    print()
    print("  --- Vue BE-DÉCLARÉ (suivi.csv, ce que le BE affirme) ---")
    print(f"  DXF/DWG2D déclaré              : {nb_be_dxf}")
    print(f"  STEP déclaré                   : {nb_be_step}")
    print(f"  STL déclaré                    : {nb_be_stl}")
    print()
    print("  --- Vue GED-RÉELLE (manifest.csv, ce qui est téléchargeable AUJOURD'HUI) ---")
    print(f"  DXF/DWG exploitable (manifest) : {nb_ged_dxf}")
    print(f"  STEP exploitable (manifest)    : {nb_ged_step}")
    print(f"  STL exploitable (manifest)     : {nb_ged_stl}")
    print()
    print(f"  SKU SANS AUCUN format (ni BE ni GED, dxf/step/stl)  : {nb_rien}")


if __name__ == "__main__":
    main()
