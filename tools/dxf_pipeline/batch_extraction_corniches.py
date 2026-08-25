#!/usr/bin/env python3
"""batch_extraction_corniches.py — Extraction STEP par lots des corniches
restantes (Piste A, 3e passe). Enchaîne step2profile.py fichier par
fichier, en sous-processus ISOLÉ par SKU, avec les contraintes imposées :

  - Périmètre : UNIQUEMENT les SKU de BATCH_CORNICHES_SKUS
    (step_pilot_download.py — 79 corniches restantes, .stp/.step, déjà
    téléchargées). Jamais de fallback .stl dans ce script.
  - Lots de 30 fichiers, avec un POINT D'ÉTAPE (rapport CSV partiel +
    résumé imprimé) après chaque lot.
  - ERREUR_TIMEOUT si un fichier dépasse 90 secondes : le sous-processus
    est lancé dans sa PROPRE session (start_new_session=True) et, en cas
    de dépassement, tout son groupe de processus est tué explicitement
    (os.killpg + SIGKILL) — jamais un simple timeout du Bash tool, qui ne
    garantit pas la mort du processus Python sous-jacent (incident déjà
    observé lors d'une passe précédente : un lancement en arrière-plan
    avait laissé un process orphelin malgré le timeout apparent de
    l'outil appelant).
  - NORMALISATION SKU -> FICHIER : mapping.csv en PRIORITÉ (comme
    step2profile.py/dxf2profile.py), à défaut <SKU>.stp/<SKU>.step
    (recherche insensible à la casse). Si mapping.csv contient PLUSIEURS
    entrées distinctes pour le MÊME SKU, ou si plusieurs fichiers du
    dossier correspondent au même SKU par nom insensible à la casse :
    ERREUR NOMMÉE `AmbiguousSkuMappingError` — JAMAIS un choix arbitraire
    ("deviner"). Le SKU est marqué ERREUR_MAPPING_AMBIGU dans le rapport
    de batch, le batch continue sur les autres fichiers.
  - Le batch ne répare/ne supprime jamais rien côté extraction déjà faite
    (13 corniches + TAL26 traités lors des passes précédentes, hors
    périmètre de ce script).

Ce script ne réimplémente AUCUNE logique d'extraction : il délègue
entièrement à `step2profile.py --sku <SKU>` (même schéma JSON, même
contrat mapping.csv/units_override.csv). Son seul rôle est
l'orchestration : résolution SKU->fichier avec détection d'ambiguïté,
isolation par sous-processus avec timeout dur, découpage en lots,
rapport de batch.

Usage:
    python3 batch_extraction_corniches.py --run
    python3 batch_extraction_corniches.py --check-only   # résolution SKU->fichier seule, aucune extraction
"""

import argparse
import csv
import datetime as dt
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).parent
STEP_DIR = Path("/home/user/flutter_app/assets/step")
OUT_DIR = Path("/home/user/flutter_app/assets/profiles")
MAPPING_PATH = HERE / "mapping.csv"
LOGS_DIR = HERE / "logs"

TIMEOUT_SECONDS = 90
LOT_SIZE = 30

sys.path.insert(0, str(HERE))
from step_pilot_download import BATCH_CORNICHES_SKUS  # noqa: E402 (source de vérité unique du périmètre)


class AmbiguousSkuMappingError(RuntimeError):
    """Levée quand la résolution SKU -> fichier .stp/.step est ambiguë
    (plusieurs candidats distincts) — jamais de choix arbitraire."""


def load_mapping_rows():
    if not MAPPING_PATH.exists():
        return []
    with MAPPING_PATH.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def resolve_sku_to_file(sku_upper: str, mapping_rows, step_dir: Path) -> Path:
    """Résout un SKU (forme majuscule, ex. 'D505') vers son fichier
    .stp/.step dans `step_dir`. Retourne le Path, ou None si aucun
    candidat. Lève AmbiguousSkuMappingError si plusieurs candidats
    DISTINCTS existent (mapping.csv contradictoire, ou plusieurs
    fichiers correspondant au même SKU par nom insensible à la casse) --
    jamais de choix arbitraire entre eux."""
    # Priorité 1 : mapping.csv (correspondance EXACTE de SKU, colonne
    # 'sku', comparaison insensible à la casse — cohérent avec
    # dxf2profile.load_mapping qui indexe par nom de fichier -> sku).
    mapping_matches = [
        r for r in mapping_rows
        if (r.get("sku") or "").strip().upper() == sku_upper
    ]
    if mapping_matches:
        distinct_files = sorted({(r.get("fichier") or "").strip() for r in mapping_matches})
        if len(distinct_files) > 1:
            raise AmbiguousSkuMappingError(
                f"SKU {sku_upper}: {len(distinct_files)} entrées mapping.csv "
                f"distinctes pointent vers des fichiers différents "
                f"({distinct_files}) -- mapping.csv contradictoire, correction "
                f"manuelle requise, aucun choix arbitraire effectué."
            )
        fname = distinct_files[0]
        path = step_dir / fname
        return path if path.exists() else None

    # Priorité 2 : nom de fichier <SKU>.stp / <SKU>.step exact.
    for ext in (".stp", ".step"):
        candidate = step_dir / f"{sku_upper}{ext}"
        if candidate.exists():
            return candidate

    # Priorité 3 (dernier recours) : recherche insensible à la casse sur
    # le nom (hors extension) parmi tous les .stp/.step du dossier.
    candidates = [
        p for p in step_dir.iterdir()
        if p.suffix.lower() in (".stp", ".step") and p.stem.strip().upper() == sku_upper
    ]
    if len(candidates) > 1:
        raise AmbiguousSkuMappingError(
            f"SKU {sku_upper}: {len(candidates)} fichiers du dossier "
            f"correspondent par nom insensible à la casse "
            f"({sorted(p.name for p in candidates)}) -- ajouter une entrée "
            f"mapping.csv explicite pour lever l'ambiguïté, aucun choix "
            f"arbitraire effectué."
        )
    if len(candidates) == 1:
        return candidates[0]
    return None


def run_one_sku(sku_upper: str) -> dict:
    """Lance `step2profile.py --sku <SKU>` en sous-processus ISOLÉ
    (session dédiée), avec timeout dur de TIMEOUT_SECONDS. Si dépassé :
    tue explicitement tout le groupe de processus (jamais un simple
    timeout d'outil appelant, qui ne garantit pas la terminaison
    effective du process Python sous-jacent -- cf. incident déjà
    rencontré). step2profile.py écrit lui-même le JSON/PNG et son propre
    log détaillé (logs/run_step_*.csv) ; ce script ne fait qu'orchestrer
    et rapporter le résultat au niveau batch."""
    cmd = [
        sys.executable, str(HERE / "step2profile.py"),
        "--sku", sku_upper,
        "--step-dir", str(STEP_DIR),
        "--out-dir", str(OUT_DIR),
        "--mapping", str(MAPPING_PATH),
    ]
    start = time.time()
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        start_new_session=True,  # groupe de processus dédié -> killpg possible
    )
    try:
        stdout, stderr = proc.communicate(timeout=TIMEOUT_SECONDS)
        elapsed = time.time() - start
        return {
            "sku": sku_upper,
            "statut_batch": "TRAITE" if proc.returncode == 0 else "ERREUR_SOUS_PROCESSUS",
            "returncode": proc.returncode,
            "elapsed_s": round(elapsed, 1),
            "message": "" if proc.returncode == 0 else f"code retour {proc.returncode}: {stderr.strip()[-500:]}",
        }
    except subprocess.TimeoutExpired:
        elapsed = time.time() - start
        # Timeout dur dépassé : tue le GROUPE de processus entier
        # (le sous-processus Python peut lui-même avoir lancé des
        # threads/enfants OCP) -- jamais un simple proc.kill() qui ne
        # tuerait que le PID immédiat.
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            proc.communicate(timeout=5)
        except Exception:  # noqa: BLE001
            pass
        return {
            "sku": sku_upper,
            "statut_batch": "ERREUR_TIMEOUT",
            "returncode": None,
            "elapsed_s": round(elapsed, 1),
            "message": f"Timeout > {TIMEOUT_SECONDS}s -- processus tué (groupe complet).",
        }


def chunk(lst, size):
    for i in range(0, len(lst), size):
        yield lst[i:i + size]


def check_only():
    mapping_rows = load_mapping_rows()
    skus = sorted(s.upper() for s in BATCH_CORNICHES_SKUS)
    print(f"=== batch_extraction_corniches --check-only : {len(skus)} SKU ===\n")
    ambigus, introuvables, ok = [], [], []
    for sku in skus:
        try:
            path = resolve_sku_to_file(sku, mapping_rows, STEP_DIR)
        except AmbiguousSkuMappingError as e:
            print(f"  ⚠️  [{sku}] AMBIGU: {e}")
            ambigus.append(sku)
            continue
        if path is None:
            print(f"  ❌ [{sku}] INTROUVABLE (ni mapping.csv, ni <SKU>.stp/.step)")
            introuvables.append(sku)
        else:
            print(f"  ✅ [{sku}] -> {path.name}")
            ok.append(sku)
    print(f"\nRésolus: {len(ok)} | Ambigus: {len(ambigus)} | Introuvables: {len(introuvables)}")
    return ok, ambigus, introuvables


def run_batch():
    mapping_rows = load_mapping_rows()
    skus = sorted(s.upper() for s in BATCH_CORNICHES_SKUS)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)

    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    report_path = LOGS_DIR / f"batch_corniches_{timestamp}.csv"

    all_results = []
    lots = list(chunk(skus, LOT_SIZE))
    print(f"=== BATCH CORNICHES : {len(skus)} SKU en {len(lots)} lot(s) de {LOT_SIZE} max ===\n")

    for lot_idx, lot in enumerate(lots, start=1):
        print(f"--- Lot {lot_idx}/{len(lots)} ({len(lot)} SKU) ---")
        for sku in lot:
            try:
                path = resolve_sku_to_file(sku, mapping_rows, STEP_DIR)
            except AmbiguousSkuMappingError as e:
                print(f"  ⚠️  [{sku}] ERREUR_MAPPING_AMBIGU: {e}")
                all_results.append({
                    "sku": sku, "statut_batch": "ERREUR_MAPPING_AMBIGU",
                    "returncode": None, "elapsed_s": 0.0, "message": str(e),
                })
                continue
            if path is None:
                msg = f"Aucun fichier .stp/.step trouve pour {sku} (ni mapping.csv, ni nom par defaut)."
                print(f"  ❌ [{sku}] ERREUR_FICHIER_INTROUVABLE: {msg}")
                all_results.append({
                    "sku": sku, "statut_batch": "ERREUR_FICHIER_INTROUVABLE",
                    "returncode": None, "elapsed_s": 0.0, "message": msg,
                })
                continue

            print(f"  [{sku}] -> {path.name} ... ", end="", flush=True)
            result = run_one_sku(sku)
            all_results.append(result)
            print(f"{result['statut_batch']} ({result['elapsed_s']}s)")

        # --- POINT D'ÉTAPE entre lots : rapport partiel écrit sur disque ---
        with report_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=["sku", "statut_batch", "returncode", "elapsed_s", "message"])
            writer.writeheader()
            writer.writerows(all_results)

        n_traite = sum(1 for r in all_results if r["statut_batch"] == "TRAITE")
        n_err = len(all_results) - n_traite
        print(f"--- Point d'étape après lot {lot_idx}/{len(lots)} : "
              f"{len(all_results)}/{len(skus)} SKU traités "
              f"({n_traite} TRAITE, {n_err} en erreur) -- rapport: {report_path} ---\n")

    print("=== BILAN FINAL BATCH CORNICHES ===")
    par_statut = {}
    for r in all_results:
        par_statut.setdefault(r["statut_batch"], []).append(r["sku"])
    for statut, skus_list in sorted(par_statut.items()):
        print(f"  {statut:28s}: {len(skus_list)}")
        if statut != "TRAITE":
            print(f"      -> {skus_list}")
    print(f"\nRapport complet : {report_path}")
    return all_results, report_path


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check-only", action="store_true", help="Resolution SKU->fichier seule, aucune extraction.")
    ap.add_argument("--run", action="store_true", help="Lance le batch reel.")
    args = ap.parse_args()

    if args.check_only:
        check_only()
        return
    if args.run:
        run_batch()
        return
    print("ERREUR: fournir --check-only ou --run", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
