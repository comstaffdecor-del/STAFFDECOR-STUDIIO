#!/usr/bin/env python3
"""
step_pilot_download.py — Téléchargement du LOT PILOTE STEP (généralisé),
et rien d'autre en dehors du périmètre PILOT_SKUS ci-dessous.

Périmètre initial (historique, conservé en commentaire pour mémoire) :
les 3 SKU D718/D705/D720 du pilote step2profile.py, choisis parmi 86
candidats éligibles (famille=='Corniches' ∩ step==1 ∩ .stp/.step réel
dans ged_diff_par_extension.csv), triés par taille ascendante.

PILOT_SKUS est désormais élargi (brief Piste A, 2e passe) : 10 corniches
supplémentaires (les 10 plus petites .stp après D705/D718/D720, hors
celles déjà sur disque) + les 10 plinthes exploitables de
classification_t1_t4.csv. ALLOWED_EXTS est élargi à {stp, step, stl} :
pour un SKU donné, .stp/.step est préféré (voie déjà prouvée par
step2profile.py) et .stl n'est retenu qu'à défaut de .stp/.step
(select_pilot_rows applique cette priorité par SKU, ce n'est pas un
simple filtre d'extension plat — voir la fonction).

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
STL_DIR = Path("/home/user/flutter_app/assets/solids")

# --- Périmètre du lot (élargi, brief Piste A 2e passe) -------------------
# Comparaison insensible à la casse contre la colonne 'sku' de
# ged_diff_par_extension.csv, mais EXACTE (pas de sous-chaîne/regex).
# 3 pilotes historiques déjà sur disque + 10 corniches .stp supplémentaires
# (les 10 plus petites hors pilotes, cf. rapport) + 10 plinthes exploitables.
PILOT_SKUS = {
    # historique (déjà présents, idempotence les ignorera)
    "d718", "d705", "d720",
    # 10 corniches supplémentaires, triées par taille .stp ascendante
    "d706", "d709", "d620", "d562", "d748",
    "d576", "d614", "d631", "d555", "d891",
    # 10 plinthes exploitables (classification_t1_t4.csv, famille=Plinthes)
    "plin08", "plin08m", "plin10", "plin10m", "plin12",
    "plin15", "plin20", "plin38", "tal26", "tal41",
}
ALLOWED_EXTS = {"stp", "step", "stl"}
THROTTLE_SECONDS = 0.3


def load_ged_diff_rows():
    with open(GED_DIFF_PATH, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def select_pilot_rows(rows):
    """Filtre par SKU exact (insensible casse) dans PILOT_SKUS, ext dans
    ALLOWED_EXTS, PUIS priorité par SKU : .stp/.step retenu si présent,
    .stl retenu SEULEMENT si aucun .stp/.step n'existe pour ce SKU (voie
    STEP jugée plus sûre/déjà prouvée — brief Piste A 2e passe). Jamais
    les deux formats pour un même SKU dans ce lot. Retourne aussi la
    liste des SKU demandés sans aucun candidat (transparence, pas de
    silence)."""
    candidates_by_sku = {}
    for row in rows:
        sku_lower = row["sku"].strip().lower()
        if sku_lower not in PILOT_SKUS:
            continue
        ext_lower = row["ext"].strip().lower()
        if ext_lower not in ALLOWED_EXTS:
            continue
        candidates_by_sku.setdefault(sku_lower, []).append(row)

    selected = []
    matched_skus = set()
    for sku_lower, cand_rows in candidates_by_sku.items():
        stp_rows = [r for r in cand_rows if r["ext"].strip().lower() in ("stp", "step")]
        chosen = stp_rows if stp_rows else cand_rows  # .stl seulement si pas de .stp/.step
        # S'il existe plusieurs lignes .stp/.step pour le même SKU (rare),
        # on les garde toutes plutôt que de choisir arbitrairement.
        selected.extend(chosen)
        matched_skus.add(sku_lower)

    missing_skus = sorted(PILOT_SKUS - matched_skus)
    return selected, missing_skus


def dest_path_for(row):
    ext_lower = row["ext"].strip().lower()
    if ext_lower in ("stp", "step"):
        return STEP_DIR / row["filename"]
    elif ext_lower == "stl":
        return STL_DIR / row["filename"]
    else:
        return None  # extension inattendue (ne devrait pas arriver via ALLOWED_EXTS), ignoré explicitement


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
    STL_DIR.mkdir(parents=True, exist_ok=True)

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
            print(f"  [SKIP] extension inattendue pour {row['filename']!r}, ignoré.")
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
