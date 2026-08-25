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

# --- Périmètre BATCH CORNICHES (Piste A, 3e passe) ------------------------
# Les 79 SKU corniches restants (classification_t1_t4.csv, famille=
# 'Corniches', format_exploitable=True) qui possèdent au moins un candidat
# .stp/.step réel dans ged_diff_par_extension.csv et ne sont PAS déjà sur
# disque (13 déjà présents depuis les passes précédentes : d555, d562,
# d576, d614, d620, d631, d705, d706, d709, d718, d720, d748, d891).
# Recoupement effectué le jour du run (classification_t1_t4.csv x
# ged_diff_par_extension.csv) : sur les 165 corniches exploitables, 92 ont
# un .stp/.step réel (13 déjà téléchargées + ces 79) ; 51 sont stl-only
# (hors périmètre de ce batch, qui est .stp/.step UNIQUEMENT sur décision
# explicite) ; 22 n'ont AUCUN candidat dans aucun format (ni stp/step ni
# stl) -- signalé, jamais silencieux, voir rapport de batch.
BATCH_CORNICHES_SKUS = {
    "d106", "d110", "d113", "d113m", "d114", "d114m", "d116", "d117",
    "d505", "d515", "d520", "d545", "d550", "d560", "d561", "d563",
    "d564", "d565", "d567", "d568", "d569", "d577", "d578", "d579",
    "d601", "d604", "d605", "d606", "d607", "d608", "d609", "d610",
    "d611", "d612", "d615", "d616", "d617", "d621", "d622", "d624",
    "d625", "d626", "d628", "d629", "d630", "d632", "d633", "d650",
    "d651", "d652", "d653", "d656", "d657", "d702", "d703", "d704",
    "d707", "d708", "d710", "d712", "d715", "d717", "d749", "d801",
    "d802", "d814", "d815", "d820", "d830", "d835", "d840", "d880",
    "d886", "d887", "d888", "d892", "d896", "d898", "d901",
}

# SKU corniches exploitables SANS AUCUN candidat de téléchargement dans
# ged_diff_par_extension.csv (ni stp/step ni stl) -- à rapporter comme
# "non téléchargeable en l'état", jamais à deviner une source. Liste figée
# au moment du recoupement (à revérifier si ged_diff_par_extension.csv est
# régénéré).
BATCH_CORNICHES_SANS_CANDIDAT = {
    "d101", "d102", "d103", "d104", "d107", "d108", "d118", "d510",
    "d556", "d570", "d574", "d575", "d580", "d713", "d845", "d846",
    "d880a", "d894", "d903", "ebp0430", "us0740", "us1040",
}
ALLOWED_EXTS = {"stp", "step", "stl"}
THROTTLE_SECONDS = 0.3


def load_ged_diff_rows():
    with open(GED_DIFF_PATH, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def select_pilot_rows(rows, wanted_skus=None, exts_allowed=None):
    """Filtre par SKU exact (insensible casse) dans `wanted_skus` (par
    défaut PILOT_SKUS, pour compatibilité historique), ext dans
    `exts_allowed` (par défaut ALLOWED_EXTS), PUIS priorité par SKU :
    .stp/.step retenu si présent, .stl retenu SEULEMENT si aucun
    .stp/.step n'existe pour ce SKU (voie STEP jugée plus sûre/déjà
    prouvée — brief Piste A 2e passe). Jamais les deux formats pour un
    même SKU dans ce lot. Retourne aussi la liste des SKU demandés sans
    aucun candidat (transparence, pas de silence)."""
    wanted = wanted_skus if wanted_skus is not None else PILOT_SKUS
    exts = exts_allowed if exts_allowed is not None else ALLOWED_EXTS
    candidates_by_sku = {}
    for row in rows:
        sku_lower = row["sku"].strip().lower()
        if sku_lower not in wanted:
            continue
        ext_lower = row["ext"].strip().lower()
        if ext_lower not in exts:
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

    missing_skus = sorted(wanted - matched_skus)
    return selected, missing_skus


def dest_path_for(row):
    ext_lower = row["ext"].strip().lower()
    if ext_lower in ("stp", "step"):
        return STEP_DIR / row["filename"]
    elif ext_lower == "stl":
        return STL_DIR / row["filename"]
    else:
        return None  # extension inattendue (ne devrait pas arriver via ALLOWED_EXTS), ignoré explicitement


def check_only(wanted_skus=None, exts_allowed=None, label="LOT PILOTE STEP"):
    wanted = wanted_skus if wanted_skus is not None else PILOT_SKUS
    exts = exts_allowed if exts_allowed is not None else ALLOWED_EXTS
    rows = load_ged_diff_rows()
    selected, missing_skus = select_pilot_rows(rows, wanted, exts)

    print(f"=== {label} — simulation (--check-only, aucun réseau) ===")
    print(f"SKU demandés: {sorted(wanted)}")
    print(f"Filtre: ext in {exts}\n")

    if missing_skus:
        print(f"⚠️  SKU demandés SANS AUCUN candidat éligible (absents de "
              f"ged_diff_par_extension.csv sous cette forme exacte, ou sans "
              f"fichier dans les extensions demandées) : {missing_skus}\n")

    for row in selected:
        dest = dest_path_for(row)
        exists = dest.exists() if dest else False
        status = "DÉJÀ PRÉSENT (serait ignoré, idempotent)" if exists else "À TÉLÉCHARGER"
        print(f"  [{row['sku']}] {row['filename']} ({row['size']}) -> {dest} [{status}]")

    print(f"\nTotal: {len(selected)} fichier(s).")
    return selected, missing_skus


def download(wanted_skus=None, exts_allowed=None):
    wanted = wanted_skus if wanted_skus is not None else PILOT_SKUS
    exts = exts_allowed if exts_allowed is not None else ALLOWED_EXTS
    try:
        base_url, email, password = load_credentials()
    except GedAccessError as e:
        print(f"ERREUR: {e}", file=sys.stderr)
        sys.exit(1)

    rows = load_ged_diff_rows()
    selected, missing_skus = select_pilot_rows(rows, wanted, exts)

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
    parser.add_argument(
        "--batch-corniches", action="store_true",
        help=(
            "Utilise BATCH_CORNICHES_SKUS (79 corniches restantes, Piste A "
            "3e passe) au lieu de PILOT_SKUS, et restreint aux extensions "
            ".stp/.step UNIQUEMENT (jamais .stl dans ce batch, décision "
            "explicite)."
        ),
    )
    args = parser.parse_args()

    if args.batch_corniches:
        wanted, exts, label = BATCH_CORNICHES_SKUS, {"stp", "step"}, "BATCH CORNICHES (79 restantes)"
    else:
        wanted, exts, label = PILOT_SKUS, ALLOWED_EXTS, "LOT PILOTE STEP"

    if args.check_only:
        check_only(wanted, exts, label)
        return
    if args.download:
        download(wanted, exts)
        return
    print("ERREUR: fournir --check-only ou --download", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
