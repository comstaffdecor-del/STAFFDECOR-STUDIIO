#!/usr/bin/env python3
"""
extract_catalogue_refs.py — Extraction fiable des 458 références de
lib/data/catalogue_data.dart (ref/nom/famille/sfam/unite/barre/prix).

Parsing par regex sur chaque bloc `Produit(...)` — pas d'exécution Dart,
juste une extraction textuelle stricte des champs nommés. Écrit
catalogue_data_refs.csv (une ligne par référence Dart).
"""
import csv
import re
import sys

DART_PATH = "../../lib/data/catalogue_data.dart"
OUTPUT_CSV = "catalogue_data_refs.csv"

BLOCK_RE = re.compile(r"Produit\(\s*(.*?)\n\s*\),", re.DOTALL)
FIELD_RE = re.compile(r"(\w+):\s*(?:'((?:[^'\\]|\\.)*)'|([\d.]+)|null)")


def parse_produit_block(block_text):
    fields = {}
    for m in FIELD_RE.finditer(block_text):
        key = m.group(1)
        if m.group(2) is not None:
            fields[key] = m.group(2)
        elif m.group(3) is not None:
            fields[key] = m.group(3)
    return fields


def main():
    with open(DART_PATH, encoding="utf-8") as f:
        content = f.read()

    # Isoler uniquement la liste catalogueGed (avant catalogueGedAvecDwg)
    start = content.index("const List<Produit> catalogueGed = [")
    end = content.index("final List<Produit> catalogueGedAvecDwg")
    body = content[start:end]

    rows = []
    for block_match in BLOCK_RE.finditer(body):
        fields = parse_produit_block(block_match.group(1))
        if "ref" not in fields:
            continue
        rows.append({
            "ref": fields.get("ref", ""),
            "nom": fields.get("nom", ""),
            "famille": fields.get("famille", ""),
            "sfam": fields.get("sfam", ""),
            "unite": fields.get("unite", ""),
            "barre": fields.get("barre", ""),
            "prix": fields.get("prix", ""),
            "a_dwg": "True" if "dwg" in fields else "False",
        })

    print(f"Références extraites de catalogue_data.dart : {len(rows)}")

    with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["ref", "nom", "famille", "sfam", "unite", "barre", "prix", "a_dwg"])
        writer.writeheader()
        writer.writerows(rows)

    # Vérifications brutes demandées
    refs = [r["ref"] for r in rows]
    print(f"Références uniques : {len(set(refs))}")
    dupes = [r for r in set(refs) if refs.count(r) > 1]
    print(f"Doublons de ref (devrait être 0) : {dupes}")

    from collections import Counter
    print("\nRépartition par famille :")
    for fam, n in Counter(r["famille"] for r in rows).most_common():
        print(f"  {fam:15s}: {n}")


if __name__ == "__main__":
    sys.exit(main())
