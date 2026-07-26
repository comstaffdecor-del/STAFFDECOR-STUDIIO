#!/usr/bin/env python3
"""
scan_assets.py — Inventaire des fichiers DXF disponibles dans assets/dxf/

Rôle : AVANT toute extraction de profil, faire l'inventaire de ce qui est
réellement exploitable dans les DXF présents. Ne modifie, ne complète, ni
ne corrige rien. Se contente de lire et rapporter.

Usage:
    python3 scan_assets.py [--dxf-dir /home/user/flutter_app/assets/dxf]
                            [--out /home/user/flutter_app/tools/dxf_pipeline/inventaire.csv]

Pour chaque fichier .dxf trouvé, on rapporte :
    - sku (nom de fichier sans extension)
    - fichier
    - insunits (valeur brute de $INSUNITS, ou vide si absent/0)
    - insunits_label (traduction lisible : mm/cm/m/pouces/absent/non_specifie)
    - nb_calques (nombre de calques du dessin)
    - calques (liste des calques, séparés par ';')
    - nb_polylignes_fermees (LWPOLYLINE/POLYLINE fermées, tous calques)
    - nb_polylignes_fermees_candidates (fermées, hors calques évidents de
      cotation/texte/cartouche/axes — heuristique de nommage, PAS une
      sélection définitive : dxf2profile.py fera la vraie sélection stricte
      par aire)
    - aire_max_mm2 (aire de la plus grande polyligne fermée candidate, si
      convertible en mm avec l'unité détectée — sinon vide)
    - nb_spline / nb_arc / nb_ellipse / nb_hatch / nb_dimension / nb_text
    - lisible (True/False — le fichier a pu être ouvert par ezdxf)
    - erreur (message si lisible=False)

Ce script NE SÉLECTIONNE PAS le contour final et NE PRODUIT AUCUN JSON de
profil. Il sert uniquement à choisir, en connaissance de cause, le lot
pilote de 10 SKU.
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


# Calques dont le nom suggère qu'ils ne contiennent pas le contour de coupe
# (cotation, texte, cartouche, axes). Heuristique de reporting uniquement —
# dxf2profile.py appliquera sa propre règle stricte et indépendante.
NOISY_LAYER_HINTS = (
    "cot", "dim", "texte", "text", "cartouche", "axe", "hatch",
    "hachure", "annot", "titre", "légende", "legende",
)


def is_noisy_layer(layer_name: str) -> bool:
    name = (layer_name or "").lower()
    return any(hint in name for hint in NOISY_LAYER_HINTS)


def polygon_area_mm2(points, scale_to_mm):
    """Aire (valeur absolue) d'un polygone fermé via la formule du lacet,
    après mise à l'échelle en mm. points: liste de (x, y)."""
    if len(points) < 3:
        return 0.0
    area = 0.0
    n = len(points)
    for i in range(n):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % n]
        area += (x1 * scale_to_mm) * (y2 * scale_to_mm) - (x2 * scale_to_mm) * (y1 * scale_to_mm)
    return abs(area) / 2.0


# Table de conversion INSUNITS -> mm (codes DXF standards)
INSUNITS_TO_MM = {
    0: None,       # non spécifié
    1: 25.4,       # pouces
    2: 304.8,      # pieds
    3: 1609344.0,  # miles
    4: 1.0,        # mm
    5: 10.0,       # cm
    6: 1000.0,     # m
    7: 1e9,        # km (improbable mais standard)
    8: 0.0254,     # micro-inches (improbable)
    9: 0.001,      # mils
    10: 914.4,     # yards
    11: 1e-7,      # angstroms
    12: 1e-6,      # nanometres
    13: 1e-3,      # microns
    14: 100.0,     # decimetres
    15: 10000.0,   # decametres
    16: 100000.0,  # hectometres
    17: 1e12,      # gigametres
    18: 1.495978707e14,  # astronomical units (improbable)
    19: 9.4607e18,       # light years (improbable)
    20: 3.0857e19,       # parsecs (improbable)
}

INSUNITS_LABELS = {
    0: "non_specifie",
    1: "pouces",
    2: "pieds",
    4: "mm",
    5: "cm",
    6: "m",
    9: "mils",
    10: "yards",
    13: "microns",
    14: "decimetres",
}


def scan_one_file(path: Path) -> dict:
    row = {
        "sku": path.stem,
        "fichier": path.name,
        "insunits": "",
        "insunits_label": "",
        "nb_calques": 0,
        "calques": "",
        "nb_polylignes_fermees": 0,
        "nb_polylignes_fermees_candidates": 0,
        "aire_max_mm2": "",
        "nb_spline": 0,
        "nb_arc": 0,
        "nb_ellipse": 0,
        "nb_hatch": 0,
        "nb_dimension": 0,
        "nb_text": 0,
        "lisible": False,
        "erreur": "",
    }

    try:
        doc = ezdxf.readfile(str(path))
    except Exception as e:  # noqa: BLE001 - on veut juste rapporter, pas planter le batch
        row["erreur"] = f"{type(e).__name__}: {e}"
        return row

    row["lisible"] = True

    insunits = doc.header.get("$INSUNITS", 0)
    row["insunits"] = insunits if insunits else ""
    row["insunits_label"] = INSUNITS_LABELS.get(insunits, f"code_{insunits}")
    scale_to_mm = INSUNITS_TO_MM.get(insunits)

    layers = sorted({layer.dxf.name for layer in doc.layers})
    row["nb_calques"] = len(layers)
    row["calques"] = ";".join(layers)

    msp = doc.modelspace()

    closed_polys = []  # (layer, area_points_native, is_noisy)
    for e in msp.query("LWPOLYLINE POLYLINE"):
        try:
            is_closed = e.is_closed
        except Exception:
            is_closed = False
        if not is_closed:
            continue
        layer = e.dxf.layer
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
        closed_polys.append((layer, pts, is_noisy_layer(layer)))

    row["nb_polylignes_fermees"] = len(closed_polys)
    candidates = [c for c in closed_polys if not c[2]]
    row["nb_polylignes_fermees_candidates"] = len(candidates)

    if candidates and scale_to_mm:
        max_area = 0.0
        for _, pts, _ in candidates:
            a = polygon_area_mm2(pts, scale_to_mm)
            if a > max_area:
                max_area = a
        row["aire_max_mm2"] = round(max_area, 2)
    elif candidates and not scale_to_mm:
        row["aire_max_mm2"] = "unite_inconnue"

    row["nb_spline"] = len(list(msp.query("SPLINE")))
    row["nb_arc"] = len(list(msp.query("ARC")))
    row["nb_ellipse"] = len(list(msp.query("ELLIPSE")))
    row["nb_hatch"] = len(list(msp.query("HATCH")))
    row["nb_dimension"] = len(list(msp.query("DIMENSION")))
    row["nb_text"] = len(list(msp.query("TEXT MTEXT")))

    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dxf-dir",
        default="/home/user/flutter_app/assets/dxf",
        help="Dossier contenant les .dxf à inventorier",
    )
    parser.add_argument(
        "--out",
        default="/home/user/flutter_app/tools/dxf_pipeline/inventaire.csv",
        help="Fichier CSV de sortie",
    )
    args = parser.parse_args()

    dxf_dir = Path(args.dxf_dir)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if not dxf_dir.exists():
        print(f"ERREUR: dossier introuvable: {dxf_dir}", file=sys.stderr)
        sys.exit(1)

    dxf_files = sorted(dxf_dir.glob("*.dxf"))
    if not dxf_files:
        print(f"Aucun fichier .dxf trouvé dans {dxf_dir}")
        print("Rien à inventorier. (Le batch de conversion DWG->DXF via ODA "
              "File Converter doit être fait au préalable et les .dxf placés ici.)")
        # On écrit quand même un CSV vide avec en-têtes pour cohérence du pipeline
        fieldnames = [
            "sku", "fichier", "insunits", "insunits_label", "nb_calques",
            "calques", "nb_polylignes_fermees", "nb_polylignes_fermees_candidates",
            "aire_max_mm2", "nb_spline", "nb_arc", "nb_ellipse", "nb_hatch",
            "nb_dimension", "nb_text", "lisible", "erreur",
        ]
        with out_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
        return

    print(f"Scan de {len(dxf_files)} fichier(s) DXF dans {dxf_dir} ...")

    rows = []
    for path in dxf_files:
        rows.append(scan_one_file(path))

    fieldnames = list(rows[0].keys())
    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    # Résumé console
    lisibles = [r for r in rows if r["lisible"]]
    illisibles = [r for r in rows if not r["lisible"]]
    insunits_absent = [r for r in lisibles if not r["insunits"]]
    zero_candidats = [r for r in lisibles if r["nb_polylignes_fermees_candidates"] == 0]
    plusieurs_candidats = [r for r in lisibles if r["nb_polylignes_fermees_candidates"] > 1]
    exploitables_ok = [
        r for r in lisibles
        if r["insunits"] and r["nb_polylignes_fermees_candidates"] == 1
    ]

    print()
    print(f"=== Inventaire écrit dans {out_path} ===")
    print(f"Total fichiers DXF          : {len(rows)}")
    print(f"  Lisibles par ezdxf        : {len(lisibles)}")
    print(f"  Illisibles / erreur       : {len(illisibles)}")
    print(f"  $INSUNITS absent/nul      : {len(insunits_absent)}")
    print(f"  0 polyligne fermée cand.  : {len(zero_candidats)}")
    print(f"  >1 polyligne fermée cand. : {len(plusieurs_candidats)}")
    print(f"  A priori exploitables OK  : {len(exploitables_ok)} "
          f"(1 seule candidate + unité connue — dxf2profile.py fera la "
          f"sélection stricte définitive)")

    if illisibles:
        print("\n  Fichiers illisibles :")
        for r in illisibles:
            print(f"    - {r['fichier']}: {r['erreur']}")


if __name__ == "__main__":
    main()
