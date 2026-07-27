#!/usr/bin/env python3
"""
pilot_download.py — Téléchargement du LOT PILOTE, et rien d'autre.

Périmètre strict (imposé) : uniquement les fichiers de type 2D ou
INDETERMINE, de moins de 1,5 Mo, pour les SKU listés dans
PILOT_SKUS ci-dessous. Toute autre ligne du manifeste est ignorée.

Lecture seule côté GED (GET uniquement, jamais de POST/PUT/DELETE sur un
fichier). Idempotent : si le fichier destination existe déjà avec une
taille non-nulle, il n'est PAS retéléchargé. 300 ms entre deux requêtes
de téléchargement (throttle poli).

Source de vérité : manifest.csv (déjà construit par un crawl lecture
seule antérieur). Ce script ne re-crawle rien, il se contente de se
logger et de télécharger les download_url déjà connus, filtrés par SKU
exact (jamais de correspondance approximative/regex sur le SKU).

Usage:
    python3 pilot_download.py --check-only   # liste ce qui SERAIT téléchargé, sans rien télécharger
    python3 pilot_download.py --download     # télécharge réellement (idempotent)
"""

import argparse
import csv
import sys
import time
from pathlib import Path

import requests

from ged_fetch import load_credentials, login, GedAccessError, USER_AGENT

HERE = Path(__file__).parent
MANIFEST_PATH = HERE / "manifest.csv"
DWG_DIR = Path("/home/user/flutter_app/assets/dwg")
DXF_DIR = Path("/home/user/flutter_app/assets/dxf")

# --- Périmètre strict du lot pilote --------------------------------------
# SKU demandés explicitement par l'utilisateur. Comparaison insensible à
# la casse contre la colonne 'sku' du manifeste, mais EXACTE (pas de
# sous-chaîne, pas de regex) : un SKU absent du manifeste sous cette forme
# exacte est simplement ignoré (rapporté comme "introuvable", jamais
# deviné/substitué).
PILOT_SKUS = {
    "1101", "1102", "1101e", "1101h", "1140c", "1145c",
    "0900", "1000", "1005", "20-54",
}
MAX_SIZE_MO = 1.5
ALLOWED_TYPES = {"2D", "INDETERMINE"}
THROTTLE_SECONDS = 0.3


def load_manifest_rows():
    with open(MANIFEST_PATH, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def select_pilot_rows(rows):
    """Filtre strict : SKU exact (insensible casse) dans PILOT_SKUS, type
    dans ALLOWED_TYPES, taille < MAX_SIZE_MO. Retourne aussi la liste des
    SKU demandés qui n'ont produit AUCUNE ligne sélectionnée (pour
    transparence, pas de silence)."""
    selected = []
    matched_skus = set()
    for row in rows:
        sku_lower = row["sku"].strip().lower()
        if sku_lower not in PILOT_SKUS:
            continue
        taille_mo = int(row["taille_octets_estimee"]) / 1024 / 1024
        if row["type_presume"] not in ALLOWED_TYPES:
            continue
        if taille_mo >= MAX_SIZE_MO:
            continue
        selected.append(row)
        matched_skus.add(sku_lower)

    missing_skus = sorted(PILOT_SKUS - matched_skus)
    return selected, missing_skus


def dest_path_for(row):
    ext = row["extension"].strip().lower()
    if ext == "dwg":
        return DWG_DIR / row["nom_fichier"]
    elif ext == "dxf":
        return DXF_DIR / row["nom_fichier"]
    else:
        return None  # extension inattendue, ignoré explicitement


def check_only():
    rows = load_manifest_rows()
    selected, missing_skus = select_pilot_rows(rows)

    print(f"=== LOT PILOTE — simulation (--check-only, aucun réseau) ===")
    print(f"SKU demandés: {sorted(PILOT_SKUS)}")
    print(f"Filtre: type in {ALLOWED_TYPES}, taille < {MAX_SIZE_MO} Mo\n")

    if missing_skus:
        print(f"⚠️  SKU demandés SANS AUCUN candidat éligible (absents du "
              f"manifeste sous cette forme exacte, ou uniquement du 3D, ou "
              f"tous >= {MAX_SIZE_MO} Mo): {missing_skus}\n")

    total_mo = 0.0
    for row in selected:
        dest = dest_path_for(row)
        taille_mo = int(row["taille_octets_estimee"]) / 1024 / 1024
        total_mo += taille_mo
        exists = dest.exists() if dest else False
        status = "DÉJÀ PRÉSENT (serait ignoré, idempotent)" if exists else "À TÉLÉCHARGER"
        print(f"  [{row['sku']}] {row['nom_fichier']} ({taille_mo:.2f} Mo, "
              f"{row['type_presume']}) -> {dest} [{status}]")

    print(f"\nTotal: {len(selected)} fichier(s), {total_mo:.2f} Mo cumulés (avant déduplication idempotente).")
    return selected, missing_skus


def download():
    try:
        base_url, email, password = load_credentials()
    except GedAccessError as e:
        print(f"ERREUR: {e}", file=sys.stderr)
        sys.exit(1)

    rows = load_manifest_rows()
    selected, missing_skus = select_pilot_rows(rows)

    if missing_skus:
        print(f"⚠️  SKU demandés sans candidat éligible: {missing_skus}")

    DWG_DIR.mkdir(parents=True, exist_ok=True)
    DXF_DIR.mkdir(parents=True, exist_ok=True)

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
        if dest is None:
            print(f"  [SKIP] extension inattendue pour {row['nom_fichier']!r}, ignoré.")
            continue

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

    print(f"\n=== BILAN LOT PILOTE ===")
    print(f"Téléchargés : {len(downloaded)}")
    print(f"Déjà présents (idempotent, ignorés) : {len(skipped)}")
    print(f"Échecs : {len(failed)}")
    if failed:
        for row, err in failed:
            print(f"  - [{row['sku']}] {row['nom_fichier']}: {err}")
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
