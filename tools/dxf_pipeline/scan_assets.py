#!/usr/bin/env python3
"""
scan_assets.py — Inventaire DWG/DXF disponibles (assets/dwg/ + assets/dxf/)

Rôle : AVANT toute extraction de profil, faire l'inventaire de ce qui est
disponible en DWG et/ou en DXF, par SKU. Ne modifie, ne complète, ni ne
corrige rien. Ne supprime jamais rien (voir règle permanente en tête de
SPEC.md). Se contente de lire et rapporter.

La correspondance fichier -> SKU N'EST JAMAIS DÉDUITE PAR REGEX : elle est
lue depuis mapping.csv (colonnes: fichier,sku,type). Un fichier absent de
mapping.csv est quand même reporté (sku = nom de fichier sans extension par
défaut) mais avec mapping_absent=True, pour signaler explicitement qu'il
faut compléter mapping.csv.

Usage:
    python3 scan_assets.py
    python3 scan_assets.py --dwg-dir /home/user/flutter_app/assets/dwg \\
                            --dxf-dir /home/user/flutter_app/assets/dxf \\
                            --mapping mapping.csv \\
                            --out inventaire.csv

Colonnes de sortie (inventaire.csv), une ligne par SKU connu (issu de
mapping.csv et/ou des fichiers trouvés sur disque) :
    sku, dwg_present, dwg_fichier, dxf_present, dxf_fichier, statut,
    mapping_absent, insunits_dxf, nb_calques_dxf, calques_dxf,
    nb_polylignes_fermees_candidates_dxf, aire_max_mm2_dxf,
    nb_spline_dxf, nb_arc_dxf, nb_ellipse_dxf, lisible_dxf, erreur_dxf

statut possible :
    - "A_CONVERTIR"      : DWG présent, DXF absent -> à convertir (ODA File Converter)
    - "DXF_PRET"         : DXF présent (que le DWG le soit ou non) -> analysable par dxf2profile.py
    - "AUCUN_FICHIER"     : ni DWG ni DXF trouvé pour ce SKU (référencé seulement dans mapping.csv)
"""

import argparse
import csv
import sys
from pathlib import Path

try:
    import ezdxf
    from ezdxf.entities import LWPolyline, Polyline
except ImportError:
    print("ERREUR: le module 'ezdxf' n'est pas installé. pip install ezdxf", file=sys.stderr)
    sys.exit(1)


NOISY_LAYER_HINTS = (
    "cot", "dim", "texte", "text", "cartouche", "axe", "hatch",
    "hachure", "annot", "titre", "légende", "legende",
)

INSUNITS_TO_MM = {
    1: 25.4, 2: 304.8, 3: 1609344.0, 4: 1.0, 5: 10.0, 6: 1000.0,
    7: 1e9, 8: 0.0254, 9: 0.001, 10: 914.4, 11: 1e-7, 12: 1e-6,
    13: 1e-3, 14: 100.0, 15: 10000.0, 16: 100000.0,
}

INSUNITS_LABELS = {
    0: "non_specifie", 1: "pouces", 2: "pieds", 4: "mm", 5: "cm", 6: "m",
    9: "mils", 10: "yards", 13: "microns", 14: "decimetres",
}


def is_noisy_layer(layer_name: str) -> bool:
    name = (layer_name or "").lower()
    return any(hint in name for hint in NOISY_LAYER_HINTS)


def polygon_area_mm2(points, scale_to_mm):
    if len(points) < 3:
        return 0.0
    area = 0.0
    n = len(points)
    for i in range(n):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % n]
        area += (x1 * scale_to_mm) * (y2 * scale_to_mm) - (x2 * scale_to_mm) * (y1 * scale_to_mm)
    return abs(area) / 2.0


def load_mapping(mapping_path: Path):
    """Charge mapping.csv (fichier,sku,type). Retourne
    (fichier_to_sku: dict, sku_to_files: dict[sku] -> {'dwg': fname|None, 'dxf': fname|None})
    """
    fichier_to_sku = {}
    sku_to_files = {}
    if not mapping_path.exists():
        return fichier_to_sku, sku_to_files
    with mapping_path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            fichier = (row.get("fichier") or "").strip()
            sku = (row.get("sku") or "").strip()
            ftype = (row.get("type") or "").strip().lower()
            if not fichier or not sku:
                continue
            fichier_to_sku[fichier] = sku
            sku_to_files.setdefault(sku, {"dwg": None, "dxf": None})
            if ftype in ("dwg", "dxf"):
                sku_to_files[sku][ftype] = fichier
    return fichier_to_sku, sku_to_files


def analyze_dxf(path: Path) -> dict:
    """Analyse un fichier DXF. Retourne un dict de colonnes _dxf.
    Ne lève jamais d'exception hors de cette fonction."""
    result = {
        "insunits_dxf": "",
        "nb_calques_dxf": 0,
        "calques_dxf": "",
        "nb_polylignes_fermees_candidates_dxf": 0,
        "aire_max_mm2_dxf": "",
        "nb_spline_dxf": 0,
        "nb_arc_dxf": 0,
        "nb_ellipse_dxf": 0,
        "lisible_dxf": False,
        "erreur_dxf": "",
    }
    try:
        doc = ezdxf.readfile(str(path))
    except Exception as e:  # noqa: BLE001
        result["erreur_dxf"] = f"{type(e).__name__}: {e}"
        return result

    result["lisible_dxf"] = True
    insunits = doc.header.get("$INSUNITS", 0)
    result["insunits_dxf"] = insunits if insunits else ""
    scale_to_mm = INSUNITS_TO_MM.get(insunits)

    layers = sorted({layer.dxf.name for layer in doc.layers})
    result["nb_calques_dxf"] = len(layers)
    result["calques_dxf"] = ";".join(layers)

    msp = doc.modelspace()
    closed_candidates = []
    for e in msp.query("LWPOLYLINE POLYLINE"):
        layer = e.dxf.layer
        if is_noisy_layer(layer):
            continue
        try:
            is_closed = e.is_closed
        except Exception:
            is_closed = False
        if not is_closed:
            continue
        try:
            if isinstance(e, LWPolyline):
                pts = [(p[0], p[1]) for p in e.get_points()]
            elif isinstance(e, Polyline):
                pts = [(v.dxf.location.x, v.dxf.location.y) for v in e.vertices]
            else:
                pts = []
        except Exception:
            pts = []
        if len(pts) < 3:
            continue
        closed_candidates.append(pts)

    result["nb_polylignes_fermees_candidates_dxf"] = len(closed_candidates)
    if closed_candidates and scale_to_mm:
        max_area = max(polygon_area_mm2(pts, scale_to_mm) for pts in closed_candidates)
        result["aire_max_mm2_dxf"] = round(max_area, 2)
    elif closed_candidates and not scale_to_mm:
        result["aire_max_mm2_dxf"] = "unite_inconnue"

    result["nb_spline_dxf"] = len(list(msp.query("SPLINE")))
    result["nb_arc_dxf"] = len(list(msp.query("ARC")))
    result["nb_ellipse_dxf"] = len(list(msp.query("ELLIPSE")))

    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dwg-dir", default="/home/user/flutter_app/assets/dwg")
    parser.add_argument("--dxf-dir", default="/home/user/flutter_app/assets/dxf")
    parser.add_argument("--mapping", default=str(Path(__file__).parent / "mapping.csv"))
    parser.add_argument("--out", default=str(Path(__file__).parent / "inventaire.csv"))
    args = parser.parse_args()

    dwg_dir = Path(args.dwg_dir)
    dxf_dir = Path(args.dxf_dir)
    mapping_path = Path(args.mapping)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    fichier_to_sku, sku_to_files = load_mapping(mapping_path)

    dwg_files = sorted(dwg_dir.glob("*.dwg")) if dwg_dir.exists() else []
    dxf_files = sorted(dxf_dir.glob("*.dxf")) if dxf_dir.exists() else []

    dwg_by_name = {p.name: p for p in dwg_files}
    dxf_by_name = {p.name: p for p in dxf_files}

    # Construit la liste des SKU à reporter : ceux de mapping.csv +
    # ceux déduits par défaut (nom de fichier) pour les fichiers présents
    # sur disque mais absents de mapping.csv.
    rows_by_sku = {}  # sku -> row dict

    for sku, files in sku_to_files.items():
        rows_by_sku[sku] = {
            "sku": sku,
            "dwg_present": False,
            "dwg_fichier": "",
            "dxf_present": False,
            "dxf_fichier": "",
            "mapping_absent": False,
        }
        if files["dwg"] and files["dwg"] in dwg_by_name:
            rows_by_sku[sku]["dwg_present"] = True
            rows_by_sku[sku]["dwg_fichier"] = files["dwg"]
        if files["dxf"] and files["dxf"] in dxf_by_name:
            rows_by_sku[sku]["dxf_present"] = True
            rows_by_sku[sku]["dxf_fichier"] = files["dxf"]

    mapped_filenames = set(fichier_to_sku.keys())

    for fname, path in dwg_by_name.items():
        if fname in mapped_filenames:
            continue
        default_sku = path.stem
        row = rows_by_sku.setdefault(default_sku, {
            "sku": default_sku, "dwg_present": False, "dwg_fichier": "",
            "dxf_present": False, "dxf_fichier": "", "mapping_absent": True,
        })
        row["dwg_present"] = True
        row["dwg_fichier"] = fname
        row["mapping_absent"] = True

    for fname, path in dxf_by_name.items():
        if fname in mapped_filenames:
            continue
        default_sku = path.stem
        row = rows_by_sku.setdefault(default_sku, {
            "sku": default_sku, "dwg_present": False, "dwg_fichier": "",
            "dxf_present": False, "dxf_fichier": "", "mapping_absent": True,
        })
        row["dxf_present"] = True
        row["dxf_fichier"] = fname
        row["mapping_absent"] = True

    final_rows = []
    for sku in sorted(rows_by_sku.keys()):
        row = rows_by_sku[sku]

        if row["dxf_present"]:
            statut = "DXF_PRET"
        elif row["dwg_present"]:
            statut = "A_CONVERTIR"
        else:
            statut = "AUCUN_FICHIER"
        row["statut"] = statut

        dxf_cols = {
            "insunits_dxf": "", "nb_calques_dxf": "", "calques_dxf": "",
            "nb_polylignes_fermees_candidates_dxf": "", "aire_max_mm2_dxf": "",
            "nb_spline_dxf": "", "nb_arc_dxf": "", "nb_ellipse_dxf": "",
            "lisible_dxf": "", "erreur_dxf": "",
        }
        if row["dxf_present"]:
            dxf_path = dxf_by_name[row["dxf_fichier"]]
            dxf_cols.update(analyze_dxf(dxf_path))

        row.update(dxf_cols)
        final_rows.append(row)

    fieldnames = [
        "sku", "dwg_present", "dwg_fichier", "dxf_present", "dxf_fichier",
        "statut", "mapping_absent",
        "insunits_dxf", "nb_calques_dxf", "calques_dxf",
        "nb_polylignes_fermees_candidates_dxf", "aire_max_mm2_dxf",
        "nb_spline_dxf", "nb_arc_dxf", "nb_ellipse_dxf",
        "lisible_dxf", "erreur_dxf",
    ]

    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(final_rows)

    n_a_convertir = sum(1 for r in final_rows if r["statut"] == "A_CONVERTIR")
    n_dxf_pret = sum(1 for r in final_rows if r["statut"] == "DXF_PRET")
    n_aucun = sum(1 for r in final_rows if r["statut"] == "AUCUN_FICHIER")
    n_mapping_absent = sum(1 for r in final_rows if r["mapping_absent"])

    print(f"=== Inventaire écrit dans {out_path} ===")
    print(f"Total SKU reportés          : {len(final_rows)}")
    print(f"  A_CONVERTIR (DWG seul)    : {n_a_convertir}")
    print(f"  DXF_PRET                  : {n_dxf_pret}")
    print(f"  AUCUN_FICHIER             : {n_aucun}")
    print(f"  Absents de mapping.csv    : {n_mapping_absent} "
          f"(sku déduit du nom de fichier par défaut — à compléter dans mapping.csv)")

    if not dwg_files and not dxf_files and not sku_to_files:
        print("\nAucun fichier DWG/DXF trouvé et mapping.csv vide : "
              "rien à inventorier pour l'instant. Ceci est normal si aucun "
              "fichier n'a encore été déposé dans assets/dwg/ ou assets/dxf/.")


if __name__ == "__main__":
    main()
