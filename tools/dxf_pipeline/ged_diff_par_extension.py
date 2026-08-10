#!/usr/bin/env python3
"""
ged_diff_par_extension.py — Point 4 du tour : décompte par extension du diff GED.

Contexte : le dernier `ged_fetch.py --check-only` (voir historique git b2a338f) avait
produit manifest.csv avec 1023 fichiers .dwg/.dxf (build_manifest.py restreint
volontairement le manifest à ces deux extensions, cf. son docstring). Un crawl complet
frais (toutes extensions, mêmes 987 fiches référence, même fonction
`crawl_full_corpus()` réutilisée depuis ged_fetch.py) permet de calculer :

    ajouts = URLs_de_téléchargement(crawl_frais) - URLs_de_téléchargement(manifest.csv)

Ce script :
  1. Charge manifest.csv (download_url déjà connus, restreints dwg/dxf par construction).
  2. Charge le crawl frais complet, toutes extensions (fichier JSON caché fourni via
     --cache-json, ou crawl live si absent — utilise ged_fetch.login()+crawl_full_corpus()).
  3. Calcule l'ensemble des "ajouts" (présents dans le crawl frais, absents du manifest).
  4. Décompte ces ajouts par extension : nombre de fichiers + volume total (parsing des
     tailles affichées type "89.98 Ko" / "1.2 Mo" -> Ko).
  5. Liste les 10 premiers noms pour .stl et pour .step/.stp parmi les ajouts.
  6. Écrit ged_diff_par_extension.csv (une ligne par fichier ajouté) + imprime le
     récapitulatif chiffré brut.

Usage :
    python3 ged_diff_par_extension.py --cache-json /tmp/ged_all_files2.json
    python3 ged_diff_par_extension.py                 # crawl live (long, ~987 fiches)
"""
import argparse
import csv
import json
import re
import sys
from collections import Counter, defaultdict

MANIFEST_PATH = "manifest.csv"
OUTPUT_CSV = "ged_diff_par_extension.csv"

EXT_BUCKETS = {
    "dwg": "dwg",
    "dxf": "dxf",
    "stl": "stl",
    "step": "step_stp",
    "stp": "step_stp",
    "skp": "skp",
}


def taille_en_ko(size_str):
    """Parse une taille affichée GED type '89.98 Ko' / '1.2 Mo' / '512 octets' -> float Ko."""
    if not size_str:
        return 0.0
    s = size_str.strip().replace(",", ".")
    m = re.match(r"([\d.]+)\s*(Ko|Mo|Go|octets?|o)\b", s, re.IGNORECASE)
    if not m:
        return 0.0
    val = float(m.group(1))
    unit = m.group(2).lower()
    if unit.startswith("mo"):
        return val * 1024
    if unit.startswith("go"):
        return val * 1024 * 1024
    if unit.startswith("o") or unit.startswith("octet"):
        return val / 1024
    return val  # Ko


def load_manifest_urls(path):
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    return set(r["download_url"] for r in rows)


def load_fresh_crawl(cache_json_path):
    if cache_json_path:
        with open(cache_json_path, encoding="utf-8") as f:
            return json.load(f)
    # Crawl live (fallback si pas de cache) — réutilise ged_fetch.py existant
    import ged_fetch as gf
    base_url, email, password = gf.load_credentials()
    import requests
    session = requests.Session()
    session.headers.update({"User-Agent": gf.USER_AGENT})
    gf.login(session, base_url, email, password, verbose=True)
    result = gf.crawl_full_corpus(session, base_url, verbose=True)
    return result["all_files"]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--manifest", default=MANIFEST_PATH)
    parser.add_argument("--cache-json", default=None,
                         help="Chemin vers un JSON de crawl complet déjà réalisé (évite un re-crawl live).")
    parser.add_argument("--output", default=OUTPUT_CSV)
    args = parser.parse_args()

    manifest_urls = load_manifest_urls(args.manifest)
    fresh_files = load_fresh_crawl(args.cache_json)

    fresh_by_url = {f["download_url"]: f for f in fresh_files}
    fresh_urls = set(fresh_by_url.keys())

    additions_urls = fresh_urls - manifest_urls
    removed_urls = manifest_urls - fresh_urls

    print(f"=== DIFF GED (crawl frais toutes extensions vs manifest.csv dwg/dxf-only) ===")
    print(f"Fichiers dans manifest.csv (baseline, {args.manifest}): {len(manifest_urls)}")
    print(f"Fichiers dans le crawl frais (toutes extensions, {len(fresh_files)} fiches parcourues): {len(fresh_urls)}")
    print(f"AJOUTS (fresh - manifest): {len(additions_urls)}")
    print(f"RETRAITS (manifest - fresh): {len(removed_urls)}")

    additions = [fresh_by_url[u] for u in additions_urls]

    # --- Décompte par extension (nombre + volume) ---
    count_by_ext = Counter()
    volume_ko_by_ext = defaultdict(float)
    for f in additions:
        ext = (f.get("ext") or "").lower()
        count_by_ext[ext] += 1
        volume_ko_by_ext[ext] += taille_en_ko(f.get("size", ""))

    print(f"\n=== AJOUTS PAR EXTENSION ===")
    for ext, n in count_by_ext.most_common():
        vol_ko = volume_ko_by_ext[ext]
        vol_mo = vol_ko / 1024
        print(f"  .{ext:6s} : {n:5d} fichiers — {vol_mo:9.2f} Mo ({vol_ko:.1f} Ko)")

    total_n = sum(count_by_ext.values())
    total_vol_mo = sum(volume_ko_by_ext.values()) / 1024
    print(f"  {'TOTAL':7s} : {total_n:5d} fichiers — {total_vol_mo:9.2f} Mo")

    # --- Regroupement par bucket demandé : dwg, dxf, stl, step/stp, skp, autres ---
    bucket_count = Counter()
    bucket_vol_ko = defaultdict(float)
    for f in additions:
        ext = (f.get("ext") or "").lower()
        bucket = EXT_BUCKETS.get(ext, "autres")
        bucket_count[bucket] += 1
        bucket_vol_ko[bucket] += taille_en_ko(f.get("size", ""))

    print(f"\n=== AJOUTS PAR BUCKET (dwg/dxf/stl/step_stp/skp/autres) ===")
    for bucket in ["dwg", "dxf", "stl", "step_stp", "skp", "autres"]:
        n = bucket_count.get(bucket, 0)
        vol_mo = bucket_vol_ko.get(bucket, 0.0) / 1024
        print(f"  {bucket:10s} : {n:5d} fichiers — {vol_mo:9.2f} Mo")

    # --- 10 premiers noms pour .stl et .step/.stp ---
    stl_additions = [f for f in additions if (f.get("ext") or "").lower() == "stl"]
    step_additions = [f for f in additions if (f.get("ext") or "").lower() in ("step", "stp")]

    print(f"\n=== .stl parmi les ajouts : {len(stl_additions)} — 10 premiers ===")
    if stl_additions:
        for f in stl_additions[:10]:
            print(f"  - [{f['sku']}] {f['filename']} — {f['size']} — {f['download_url']}")
    else:
        print("  (aucun)")

    print(f"\n=== .step/.stp parmi les ajouts : {len(step_additions)} — 10 premiers ===")
    if step_additions:
        for f in step_additions[:10]:
            print(f"  - [{f['sku']}] {f['filename']} — {f['size']} — {f['download_url']}")
    else:
        print("  (aucun)")

    # --- Conditionnelle : .step=0 dans la GED alors que le suivi annonce des STEP ---
    n_step_total_ged = sum(1 for f in fresh_files if (f.get("ext") or "").lower() in ("step", "stp"))
    print(f"\n=== VÉRIFICATION CONDITIONNELLE (point 4 du tour) ===")
    print(f"Fichiers .step/.stp dans le crawl frais COMPLET (pas seulement les ajouts): {n_step_total_ged}")
    if n_step_total_ged == 0:
        print("  -> .step = 0 sur toute la GED : les fichiers STEP annoncés par le suivi sont chez le BE, non publiés.")
        print("  -> DÉCISION : step2profile.py est reporté ; télécharger un lot de .stl réels à la place.")
    else:
        print(f"  -> {n_step_total_ged} fichier(s) STEP existent réellement sur la GED (annoncés OU non par le suivi).")
        print("  -> step2profile.py PEUT être engagé sur ces fichiers réels (pas de report nécessaire).")

    # --- Écriture CSV des ajouts ---
    fieldnames = ["sku", "filename", "ext", "size", "download_url", "reference_url"]
    with open(args.output, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in additions:
            writer.writerow({k: row.get(k, "") for k in fieldnames})
    print(f"\nCSV des ajouts écrit : {args.output} ({len(additions)} lignes)")


if __name__ == "__main__":
    sys.exit(main())
