#!/usr/bin/env python3
"""build_profiles_index.py — Générateur de `assets/profiles/index.json`.

CONTEXTE (brief de câblage, étape 0) : `assets/profiles/` contient 62
fichiers JSON produits par le pipeline d'extraction (`step2profile.py` /
`dxf2profile.py`), dont 56 en `statut: "OK"` — mais seuls 31 d'entre eux
passent le gate de sanité (`gate_sanite.py`, `statut_gate == "OK"`).
`ProfileDimsCache` (`lib/core/perspective/profile_dims_cache.dart`)
dérivait jusqu'ici sa couverture d'`AssetManifest.json`, qui liste les 56
sans distinction — 16 d'entre eux font lever un `assert()` du loader
Dart (`profile_dims.dart`) en mode debug (bug corrigé dans le même
commit que ce script), et les 9 autres passent silencieusement avec des
dimensions non garanties.

Ce script est la SEULE source de vérité pour "quelles refs le cache
Flutter doit-il essayer de charger" : il lit `gate_sanite_rapport.csv`
(déjà produit par `gate_sanite.py`, jamais recalculé ici — pas de
duplication de logique de gate) et écrit `assets/profiles/index.json`,
la liste exacte des SKU `statut_gate == "OK"`.

RÈGLE FAIL-CLOSED (imposée par le brief) : si ce script échoue, tourne
sur un rapport vide, ou obsolète, `index.json` ne doit JAMAIS contenir
un SKU non gate-OK. Le générateur écrit un tableau vide plutôt qu'un
fichier absent en cas de rapport vide — un `index.json` absent ou
illisible côté Dart doit conduire le cache à ne rien charger et à
retomber sur le ratio pixels (jamais un repli sur AssetManifest.json,
qui ressusciterait le bug).

Usage :
    python3 tools/dxf_pipeline/build_profiles_index.py

Régénérer après chaque run de gate_sanite.py.
"""

import csv
import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
DEFAULT_GATE_CSV = HERE / "gate_sanite_rapport.csv"
DEFAULT_OUTPUT = HERE.parent.parent / "assets" / "profiles" / "index.json"


def build_index(gate_csv: Path) -> list[str]:
    """Lit le rapport de gate et renvoie la liste triée des SKU
    `statut_gate == "OK"`. Ne recalcule AUCUN critère — lecture pure du
    verdict déjà produit par gate_sanite.py (pas de duplication de
    logique de gate dans ce script)."""
    if not gate_csv.exists():
        print(f"ERREUR: rapport de gate introuvable: {gate_csv}", file=sys.stderr)
        return []

    with open(gate_csv, newline="", encoding="utf-8") as fp:
        rows = list(csv.DictReader(fp))

    ok_skus = sorted(r["sku"] for r in rows if r.get("statut_gate") == "OK")
    return ok_skus


def main() -> None:
    gate_csv = DEFAULT_GATE_CSV
    output = DEFAULT_OUTPUT

    ok_skus = build_index(gate_csv)

    if not ok_skus:
        print(
            "ATTENTION: aucun SKU gate-OK trouve — index.json sera un "
            "tableau vide (comportement fail-closed voulu, PAS une erreur "
            "silencieuse : le cache Flutter ne chargera plus aucun profil "
            "reel tant que ce rapport n'aura pas ete regenere).",
            file=sys.stderr,
        )

    output.parent.mkdir(parents=True, exist_ok=True)
    with open(output, "w", encoding="utf-8") as fp:
        json.dump({"refs": ok_skus}, fp, indent=2, ensure_ascii=False)
        fp.write("\n")

    print(f"=== build_profiles_index: {len(ok_skus)} SKU gate-OK -> {output} ===")
    for sku in ok_skus:
        print(f"  {sku}")


if __name__ == "__main__":
    main()
