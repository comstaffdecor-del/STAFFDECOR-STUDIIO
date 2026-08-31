#!/usr/bin/env python3
"""step_text_inspect.py — Inspection TEXTE BRUTE d'un fichier STEP (ISO-10303-21),
sans passer par OCP.

CONTEXTE (incident D892, 2026-08-31) : le pipeline d'extraction standard
(step2profile.py) traite chaque SKU via STEPControl_Reader.ReadFile() +
TransferRoots(), suivis d'un balayage de coupe. Sur D892.stp (10 315 135
octets), ce chargement OCP a été observé bloqué pendant 20 min 10 s SANS
COMPLÉTION, tué manuellement à cette borne fixée d'avance (voir
docs/INCIDENT_D892_IMPORT.md pour le détail horodaté). Comme le process a
été tué avant la fin de step2profile.py:main(), AUCUN run_step_*.csv n'a
été écrit pour ce run — ce script sert à produire, sans dépendre d'OCP, une
pièce justificative alternative, traçable et committable, décrivant l'état
DÉCLARATIF du fichier (ce qui est écrit dans le texte STEP), pour
distinguer deux hypothèses avant d'écrire quoi que ce soit à un
fournisseur :

  (a) le solide est topologiquement invalide (non manifold / coque
      ouverte / auto-intersectant) -> demande de reconstruction ;
  (b) le solide est topologiquement propre mais contient localement une
      densité de données démesurée (ex: courbes B-spline à des milliers
      de points de contrôle) -> demande de simplification/décimation,
      PAS de reconstruction.

MÉTHODE — comptage textuel, aucune tessellation, aucun chargement OCP :
  1. Comptage d'occurrences (grep -o | wc -l, PAS `grep -c` qui compte des
     LIGNES : une entité STEP peut se replier sur plusieurs lignes, et
     `grep -c` sous-compterait) des mots-clés topologiques structurants
     (MANIFOLD_SOLID_BREP, CLOSED_SHELL, OPEN_SHELL, BREP_WITH_VOIDS,
     ADVANCED_FACE, ...). Un CLOSED_SHELL sans OPEN_SHELL et un
     MANIFOLD_SOLID_BREP présent sont des indices déclaratifs de solide
     fermé (NE PROUVENT PAS l'absence d'auto-intersection : c'est une
     lecture du texte, pas une vérification booléenne CAO réelle — à
     énoncer comme tel dans toute correspondance).
  2. Distribution de taille des entités B_SPLINE_CURVE_WITH_KNOTS : la
     regex extrait la liste de points de contrôle (références '#N' dans
     la parenthèse d'arguments) par entité, et rapporte les valeurs
     aberrantes (> outlier_threshold points de contrôle) par rapport à la
     médiane de l'ensemble.

LIMITE EXPLICITE : ceci n'est PAS un vérificateur de solide (pas de test
d'auto-intersection réel, pas de test watertight numérique). C'est une
lecture déclarative du fichier, destinée à orienter un diagnostic entre
deux hypothèses avant d'écrire à un fournisseur — jamais une preuve
géométrique formelle.

Usage:
    python3 step_text_inspect.py FICHIER.stp [FICHIER2.stp ...]
    python3 step_text_inspect.py --out docs/incident_d892_step_inspect.txt \
        assets/step/D615.stp assets/step/D629.stp assets/step/D802.stp \
        assets/step/D880.stp assets/step/D887.step assets/step/D892.stp
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import re
import statistics
import sys
from pathlib import Path

TOPOLOGY_KEYWORDS = [
    "MANIFOLD_SOLID_BREP",
    "BREP_WITH_VOIDS",
    "SHELL_BASED_SURFACE_MODEL",
    "CLOSED_SHELL",
    "OPEN_SHELL",
    "ADVANCED_FACE",
    "B_SPLINE_SURFACE_WITH_KNOTS",
]

# Seuil au-dessus duquel une courbe B-spline est reportée comme aberrante.
# Choisi ainsi : sur D892.stp, la mediane des 545 courbes est de 34 points
# de controle (references '#N') ; ce seuil isole nettement les 4 courbes a
# 5032-6894 points sans dependre d'un chiffre cible.
DEFAULT_OUTLIER_THRESHOLD = 1000

ENTITY_LINE_RE = re.compile(r"^#\d+\s*=")
BSPLINE_CURVE_RE = re.compile(
    r"(#\d+)\s*=\s*B_SPLINE_CURVE_WITH_KNOTS\s*\((.*?)\)\s*;", re.DOTALL
)
REF_RE = re.compile(r"#\d+")


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def count_keyword_occurrences(text: str, keyword: str) -> int:
    """Compte les OCCURRENCES du mot-cle (equivalent grep -o | wc -l),
    jamais le nombre de LIGNES (grep -c) : une entite STEP peut se
    replier sur plusieurs lignes, grep -c sous-compterait."""
    return len(re.findall(re.escape(keyword), text))


def count_total_entities(text: str) -> int:
    """Nombre de lignes de definition d'entite '#N = TYPE(...)'."""
    return sum(1 for line in text.splitlines() if ENTITY_LINE_RE.match(line))


def bspline_curve_sizes(text: str) -> list[int]:
    """Pour chaque B_SPLINE_CURVE_WITH_KNOTS, nombre de references '#N'
    dans son bloc d'arguments (proxy du nombre de points de controle,
    ceux-ci etant References a des CARTESIAN_POINT distincts)."""
    sizes = []
    for _entity_id, body in BSPLINE_CURVE_RE.findall(text):
        sizes.append(len(REF_RE.findall(body)))
    return sizes


def inspect_file(path: Path, outlier_threshold: int) -> str:
    text = path.read_text(errors="replace")
    lines = []
    lines.append(f"=== {path.name} ===")
    lines.append(f"  chemin        : {path}")
    lines.append(f"  taille        : {path.stat().st_size} octets")
    lines.append(f"  sha256        : {sha256_of(path)}")
    lines.append(f"  nb entites    : {count_total_entities(text)}")
    lines.append("  mots-cles topologiques (occurrences, pas des lignes) :")
    for kw in TOPOLOGY_KEYWORDS:
        lines.append(f"    {kw:<30} {count_keyword_occurrences(text, kw)}")

    sizes = bspline_curve_sizes(text)
    if sizes:
        sizes_sorted = sorted(sizes, reverse=True)
        med = statistics.median(sizes)
        outliers = [s for s in sizes_sorted if s > outlier_threshold]
        lines.append(
            f"  B_SPLINE_CURVE_WITH_KNOTS : {len(sizes)} courbes, "
            f"mediane={med:.0f} points de controle (proxy via refs '#N')"
        )
        if outliers:
            total_pts = sum(sizes)
            outlier_pts = sum(outliers)
            pct = 100.0 * outlier_pts / total_pts if total_pts else 0.0
            lines.append(
                f"    -> {len(outliers)} courbe(s) aberrante(s) "
                f"(> {outlier_threshold} points) : {outliers}"
            )
            lines.append(
                f"    -> ces courbes concentrent {outlier_pts}/{total_pts} "
                f"references de points ({pct:.1f}%)"
            )
        else:
            lines.append("    -> aucune courbe aberrante detectee au seuil choisi")
    else:
        lines.append("  B_SPLINE_CURVE_WITH_KNOTS : aucune dans ce fichier")

    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", type=Path)
    parser.add_argument(
        "--outlier-threshold",
        type=int,
        default=DEFAULT_OUTLIER_THRESHOLD,
        help=f"seuil (nb de points de controle) au-dela duquel une courbe "
        f"B-spline est reportee comme aberrante (defaut: {DEFAULT_OUTLIER_THRESHOLD})",
    )
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args()

    out_lines = [
        "step_text_inspect.py — inspection texte brute (sans OCP)",
        f"Genere le : {dt.datetime.now().isoformat(timespec='seconds')}",
        "Methode : comptage d'occurrences de mots-cles topologiques + "
        "distribution des tailles de courbes B-spline. Voir docstring du "
        "script pour la limite explicite (lecture declarative, pas une "
        "preuve geometrique formelle).",
        "",
    ]
    for path in args.files:
        if not path.exists():
            print(f"ATTENTION: fichier introuvable, ignore : {path}", file=sys.stderr)
            continue
        out_lines.append(inspect_file(path, args.outlier_threshold))
        out_lines.append("")

    output = "\n".join(out_lines)
    print(output)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(output, encoding="utf-8")
        print(f"\nEcrit dans : {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
