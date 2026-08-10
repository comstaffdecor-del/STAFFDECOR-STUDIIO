#!/usr/bin/env python3
"""
step_pilot_download.py — Téléchargement du LOT PILOTE STEP, et rien d'autre.

Périmètre strict (imposé) : les fichiers .stp/.step des 3 SKU choisis
pour le pilote step2profile.py — D718, D705, D720. Ces 3 SKU ont été
sélectionnés parmi 86 candidats éligibles (intersection triple :
famille=='Corniches' dans catalogue_data_refs.csv ∩ step==1 dans
suivi.csv ∩ fichier .stp/.step réellement présent dans le crawl GED
ged_diff_par_extension.csv), triés par taille de fichier ascendante —
D718 (12.52 Ko), D705 (12.65 Ko), D720 (13.28 Ko) sont les 3 plus
petits, donc les plus rapides/sûrs pour un premier pilote. Les 3 sont
spot-vérifiés cohérents dans classification_t1_t4.csv (famille=Corniches,
type=T1_PROFIL_EXTRUDE, a_step=True, format_exploitable=True) et
suivi.csv (statut_gestion=ACTIF, step=True).

Source de vérité pour les download_url : ged_diff_par_extension.csv
(crawl GED réel, commit 2d5d3e9) — PAS manifest.csv (qui ne couvre que
dwg/dxf). Lecture seule côté GED (GET uniquement). Idempotent : si le
fichier destination existe déjà avec une taille non-nulle, il n'est PAS
retéléchargé. 300 ms entre deux requêtes de téléchargement (throttle poli).

Usage:
    python3 step_pilot_download.py --check-only   # liste ce qui SERAIT téléchargé, sans rien télécharger
    python3 step_pilot_download.py --download     # télécharge réellement (idempotent)
"""

import argparse
import csv
import sys
import time
from pathlib import Path

import requests

from ged_fetch import load_credentials, login, GedAccessError, USER_AGENT

HERE = Path(__file__).parent
GED_DIFF_PATH = HERE / "ged_diff_par_extension.csv"
STEP_DIR = Path("/home/user/flutter_app/assets/step")

# --- Périmètre strict du lot pilote STEP ---------------------------------
# 3 SKU choisis explicitement (voir docstring) parmi les 86 candidats
# éligibles. Comparaison insensible à la casse contre la colonne 'sku' de
# ged_diff_par_extension.csv, mais EXACTE (pas de sous-chaîne/regex).
PILOT_SKUS = {"d718", "d705", "d720"}
ALLOWED_EXTS = {"stp", "step"}
THROTTLE_SECONDS = 0.3


def load_ged_diff_rows():
    with open(GED_DIFF_PATH, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def select_pilot_rows(rows):
    """Filtre strict : SKU exact (insensible casse) dans PILOT_SKUS, ext
    dans ALLOWED_EXTS. Retourne aussi la liste des SKU demandés qui n'ont
    produit AUCUNE ligne sélectionnée (transparence, pas de silence)."""
    selected = []
    matched_skus = set()
    for row in rows:
        sku_lower = row["sku"].strip().lower()
        if sku_lower not in PILOT_SKUS:
            continue
        ext_lower = row["ext"].strip().lower()
        if ext_lower not in ALLOWED_EXTS:
            continue
        selected.append(row)
        matched_skus.add(sku_lower)

    missing_skus = sorted(PILOT_SKUS - matched_skus)
    return selected, missing_skus


def dest_path_for(row):
    return STEP_DIR / row["filename"]


def check_only():
    rows = load_ged_diff_rows()
    selected, missing_skus = select_pilot_rows(rows)

    print(f"=== LOT PILOTE STEP — simulation (--check-only, aucun réseau) ===")
    print(f"SKU demandés: {sorted(PILOT_SKUS)}")
    print(f"Filtre: ext in {ALLOWED_EXTS}\n")

    if missing_skus:
        print(f"⚠️  SKU demandés SANS AUCUN candidat éligible (absents de "
              f"ged_diff_par_extension.csv sous cette forme exacte, ou sans "
              f"fichier .stp/.step) : {missing_skus}\n")

    for row in selected:
        dest = dest_path_for(row)
        exists = dest.exists() if dest else False
        status = "DÉJÀ PRÉSENT (serait ignoré, idempotent)" if exists else "À TÉLÉCHARGER"
        print(f"  [{row['sku']}] {row['filename']} ({row['size']}) -> {dest} [{status}]")

    print(f"\nTotal: {len(selected)} fichier(s).")
    return selected, missing_skus


def download():
    try:
        base_url, email, password = load_credentials()
    except GedAccessError as e:
        print(f"ERREUR: {e}", file=sys.stderr)
        sys.exit(1)

    rows = load_ged_diff_rows()
    selected, missing_skus = select_pilot_rows(rows)

    if missing_skus:
        print(f"⚠️  SKU demandés sans candidat éligible: {missing_skus}")

    STEP_DIR.mkdir(parents=True, exist_ok=True)

    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})

    try:
        final_url, status_post, _ = login(session, base_url, email, password, verbose=True)
    except GedAccessError as e:
        print(f"\nARRÊT — accès bloqué: {e}", file=sys.stderr)
        sys.exit(2)

    print(f"\nLogin OK -> {final_url}\n")

    downloaded, skipped, failed = [], [], []

    for row in selected:
        dest = dest_path_for(row)

        if dest.exists() and dest.stat().st_size > 0:
            print(f"  [IDEMPOTENT] {dest.name} déjà présent ({dest.stat().st_size} octets), non retéléchargé.")
            skipped.append(row)
            continue

        url = row["download_url"]
        try:
            r = session.get(url, timeout=30, stream=True)
        except requests.RequestException as e:
            print(f"  [ERREUR RÉSEAU] {url}: {e}")
            failed.append((row, str(e)))
            time.sleep(THROTTLE_SECONDS)
            continue

        if r.status_code != 200:
            print(f"  [ERREUR HTTP {r.status_code}] {url}")
            failed.append((row, f"HTTP {r.status_code}"))
            time.sleep(THROTTLE_SECONDS)
            continue

        tmp_path = dest.with_suffix(dest.suffix + ".part")
        written = 0
        with open(tmp_path, "wb") as f:
            for chunk in r.iter_content(chunk_size=65536):
                f.write(chunk)
                written += len(chunk)
        tmp_path.rename(dest)

        print(f"  [OK] {row['sku']} -> {dest} ({written} octets téléchargés)")
        downloaded.append(row)
        time.sleep(THROTTLE_SECONDS)

    print(f"\n=== BILAN LOT PILOTE STEP ===")
    print(f"Téléchargés : {len(downloaded)}")
    print(f"Déjà présents (idempotent, ignorés) : {len(skipped)}")
    print(f"Échecs : {len(failed)}")
    if failed:
        for row, err in failed:
            print(f"  - [{row['sku']}] {row['filename']}: {err}")
    if missing_skus:
        print(f"SKU sans candidat éligible : {missing_skus}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check-only", action="store_true", help="Simulation, aucun réseau.")
    parser.add_argument("--download", action="store_true", help="Téléchargement réel, idempotent.")
    args = parser.parse_args()

    if args.check_only:
        check_only()
        return
    if args.download:
        download()
        return
    print("ERREUR: fournir --check-only ou --download", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
