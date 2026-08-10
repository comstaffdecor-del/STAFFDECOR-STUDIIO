#!/usr/bin/env python3
"""
croisement_catalogue_data_formats.py — Point 1 du tour : ventilation
formats exploitables sur la POPULATION DE RÉFÉRENCE = les 458 refs de
lib/data/catalogue_data.dart (pas suivi.csv, pas manifest.csv — ces deux
derniers ne sont que des SOURCES croisées, cf. point 2 du tour sur l'écart
de population).

Sources croisées, toutes indexées par sku_normalise (normalize_sku,
importé depuis dxf2profile.py — implémentation canonique unique) :
  - catalogue_data_refs.csv (458 refs Dart, produit par extract_catalogue_refs.py)
  - suivi.csv (1766 lignes, déclaratif BE) -> colonnes dxf/step/stl/dwg2d/dwg3d bool
  - manifest.csv (710 SKU, GED réelle, structurellement dwg/dxf-only)

Pour chaque référence catalogue_data.dart, on calcule la disponibilité
"exploitable" par format en combinant les deux sources (BE-déclaré OU
GED-réelle) :
  - a_dxf   : suivi.dxf=True OU manifest contient une entrée .dxf pour ce sku
  - a_step  : suivi.step=True (le manifest ne contient jamais de step, par
              construction — cf. build_manifest.py, restreint dwg/dxf)
  - a_stl   : suivi.stl=True (idem, jamais dans le manifest)
  - a_dwg   : suivi.dwg3d=True OU suivi.dwg2d=True OU manifest contient .dwg
  - aucun   : aucun des quatre au-dessus

Écrit croisement_catalogue_data_formats.csv (458 lignes) + imprime le
tableau chiffré global ET par famille.
"""
import csv
import sys

sys.path.insert(0, ".")
from dxf2profile import normalize_sku  # noqa: E402

CATALOGUE_REFS_CSV = "catalogue_data_refs.csv"
SUIVI_CSV = "suivi.csv"
MANIFEST_CSV = "manifest.csv"
OUTPUT_CSV = "croisement_catalogue_data_formats.csv"


def load_catalogue_refs(path):
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        r["sku_normalise"] = normalize_sku(r["ref"])
    return rows


def load_suivi_by_sku(path):
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    by_sku = {}
    for r in rows:
        sku_n = r["sku_normalise"]
        # En cas de doublon de sku_normalise dans suivi.csv, on fait un OR logique
        existing = by_sku.get(sku_n, {})
        for col in ("dxf", "step", "stl", "dwg3d", "dwg2d"):
            val = r.get(col, "False") == "True"
            existing[col] = existing.get(col, False) or val
        by_sku[sku_n] = existing
    return by_sku


def load_manifest_ext_by_sku(path):
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    by_sku = {}
    for r in rows:
        sku_n = normalize_sku(r["sku"])
        ext = (r.get("extension") or "").lower().lstrip(".")
        by_sku.setdefault(sku_n, set()).add(ext)
    return by_sku


def main():
    catalogue_rows = load_catalogue_refs(CATALOGUE_REFS_CSV)
    suivi_by_sku = load_suivi_by_sku(SUIVI_CSV)
    manifest_by_sku = load_manifest_ext_by_sku(MANIFEST_CSV)

    output_rows = []
    for row in catalogue_rows:
        sku_n = row["sku_normalise"]
        suivi = suivi_by_sku.get(sku_n, {})
        manifest_exts = manifest_by_sku.get(sku_n, set())

        a_dxf = bool(suivi.get("dxf")) or ("dxf" in manifest_exts)
        a_step = bool(suivi.get("step"))  # jamais dans manifest (restriction dwg/dxf)
        a_stl = bool(suivi.get("stl"))    # jamais dans manifest (restriction dwg/dxf)
        a_dwg = bool(suivi.get("dwg3d")) or bool(suivi.get("dwg2d")) or ("dwg" in manifest_exts)
        dans_suivi = sku_n in suivi_by_sku
        dans_manifest = sku_n in manifest_by_sku

        aucun = not (a_dxf or a_step or a_stl or a_dwg)

        output_rows.append({
            "ref": row["ref"],
            "famille": row["famille"],
            "sfam": row["sfam"],
            "sku_normalise": sku_n,
            "dans_suivi": dans_suivi,
            "dans_manifest": dans_manifest,
            "a_dxf": a_dxf,
            "a_step": a_step,
            "a_stl": a_stl,
            "a_dwg_seul": a_dwg and not (a_dxf or a_step or a_stl),
            "aucun_format": aucun,
        })

    fieldnames = ["ref", "famille", "sfam", "sku_normalise", "dans_suivi", "dans_manifest",
                  "a_dxf", "a_step", "a_stl", "a_dwg_seul", "aucun_format"]
    with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(output_rows)

    n = len(output_rows)
    n_dxf = sum(1 for r in output_rows if r["a_dxf"])
    n_step = sum(1 for r in output_rows if r["a_step"])
    n_stl = sum(1 for r in output_rows if r["a_stl"])
    n_dwg_seul = sum(1 for r in output_rows if r["a_dwg_seul"])
    n_aucun = sum(1 for r in output_rows if r["aucun_format"])
    n_dans_suivi = sum(1 for r in output_rows if r["dans_suivi"])
    n_dans_manifest = sum(1 for r in output_rows if r["dans_manifest"])

    print(f"=== TABLEAU 1 : sur les {n} références de catalogue_data.dart ===")
    print(f"  Présentes dans suivi.csv        : {n_dans_suivi} / {n}")
    print(f"  Présentes dans manifest.csv     : {n_dans_manifest} / {n}")
    print(f"  DXF 2D exploitable              : {n_dxf} / {n}")
    print(f"  STEP exploitable                : {n_step} / {n}")
    print(f"  STL exploitable                 : {n_stl} / {n}")
    print(f"  DWG SEUL (aucun DXF/STEP/STL)   : {n_dwg_seul} / {n}")
    print(f"  AUCUN FORMAT du tout            : {n_aucun} / {n}")
    print(f"  Somme de contrôle (dxf+step+stl+dwg_seul+aucun peut être >{n} si formats combinés)")

    print(f"\n=== TABLEAU 1bis : ventilation par famille (sur les 458) ===")
    from collections import defaultdict
    fam_stats = defaultdict(lambda: {"n": 0, "dxf": 0, "step": 0, "stl": 0, "dwg_seul": 0, "aucun": 0})
    for r in output_rows:
        fs = fam_stats[r["famille"]]
        fs["n"] += 1
        fs["dxf"] += r["a_dxf"]
        fs["step"] += r["a_step"]
        fs["stl"] += r["a_stl"]
        fs["dwg_seul"] += r["a_dwg_seul"]
        fs["aucun"] += r["aucun_format"]
    print(f"  {'Famille':15s} {'N':>4s} {'DXF':>5s} {'STEP':>5s} {'STL':>5s} {'DWGseul':>8s} {'Aucun':>6s}")
    for fam, fs in sorted(fam_stats.items(), key=lambda x: -x[1]["n"]):
        print(f"  {fam:15s} {fs['n']:>4d} {fs['dxf']:>5d} {fs['step']:>5d} {fs['stl']:>5d} {fs['dwg_seul']:>8d} {fs['aucun']:>6d}")

    # --- TABLEAU 2 : même ventilation, mais sur les 710 SKU du manifeste ---
    manifest_all_skus = set(manifest_by_sku.keys())
    n_m = len(manifest_all_skus)
    m_dxf = sum(1 for sku in manifest_all_skus if "dxf" in manifest_by_sku[sku] or suivi_by_sku.get(sku, {}).get("dxf"))
    m_step = sum(1 for sku in manifest_all_skus if suivi_by_sku.get(sku, {}).get("step"))
    m_stl = sum(1 for sku in manifest_all_skus if suivi_by_sku.get(sku, {}).get("stl"))
    m_dwg = sum(1 for sku in manifest_all_skus if "dwg" in manifest_by_sku[sku] or suivi_by_sku.get(sku, {}).get("dwg3d") or suivi_by_sku.get(sku, {}).get("dwg2d"))
    m_dwg_seul = sum(
        1 for sku in manifest_all_skus
        if ("dwg" in manifest_by_sku[sku] or suivi_by_sku.get(sku, {}).get("dwg3d") or suivi_by_sku.get(sku, {}).get("dwg2d"))
        and not ("dxf" in manifest_by_sku[sku] or suivi_by_sku.get(sku, {}).get("dxf"))
        and not suivi_by_sku.get(sku, {}).get("step")
        and not suivi_by_sku.get(sku, {}).get("stl")
    )
    m_aucun = n_m - len({
        sku for sku in manifest_all_skus
        if "dxf" in manifest_by_sku[sku] or suivi_by_sku.get(sku, {}).get("dxf")
        or suivi_by_sku.get(sku, {}).get("step") or suivi_by_sku.get(sku, {}).get("stl")
        or "dwg" in manifest_by_sku[sku] or suivi_by_sku.get(sku, {}).get("dwg3d") or suivi_by_sku.get(sku, {}).get("dwg2d")
    })

    print(f"\n=== TABLEAU 2 : sur les {n_m} SKU du manifest.csv (GED dwg/dxf réelle) ===")
    print(f"  DXF 2D exploitable              : {m_dxf} / {n_m}")
    print(f"  STEP exploitable (via suivi)     : {m_step} / {n_m}")
    print(f"  STL exploitable (via suivi)      : {m_stl} / {n_m}")
    print(f"  DWG présent                      : {m_dwg} / {n_m}")
    print(f"  DWG SEUL (aucun DXF/STEP/STL)    : {m_dwg_seul} / {n_m}")
    print(f"  AUCUN des 4 formats              : {m_aucun} / {n_m}")

    print(f"\nCSV écrit : {OUTPUT_CSV} ({n} lignes)")


if __name__ == "__main__":
    sys.exit(main())
