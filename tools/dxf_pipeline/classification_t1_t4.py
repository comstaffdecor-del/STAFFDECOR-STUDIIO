#!/usr/bin/env python3
"""
classification_t1_t4.py — Point 5e du tour : classe les 458 références de
catalogue_data.dart selon la taxonomie géométrique T1-T4 (définitions
arrêtées lors de tours antérieurs, formalisées dans SPEC.md par ce script/
ce tour), à partir du seul couple (famille, sfam) — AUCUNE mesure
géométrique n'est utilisée ici, c'est une classification déclarative de
principe, pas une vérification bbox.

RÈGLES DE CLASSIFICATION (déterministes, sur famille+sfam) :

  T1 PROFIL EXTRUDÉ  : profil 2D constant balayé le long d'un chemin
                        rectiligne (barre) — familles vendues au ml :
                        Corniches, Moulures, Plinthes, Profils LED.

  T2 RELIEF PLANAIRE  : plaque sensiblement plane avec relief sculpté en
                        surface, vendue au m² ou à la pièce sans dimension
                        de révolution dominante — familles : Parements,
                        Lambris.

  T3 SOLIDE DE RÉVOLUTION : pièce à symétrie radiale autour d'un axe
                        central, dimension dominante = diamètre — sous-
                        famille Rosaces de la famille Encadrements
                        UNIQUEMENT (pas les Encadrements rectangulaires/
                        carrés, cf. T_incertain).

  T4 VOLUME LIBRE     : pièce sculptée unique, non réductible à une
                        extrusion/un relief plan/une révolution (volume
                        libre 3D) — famille Ornements (modillons, fleurs
                        de trumeau...).

  T_INCERTAIN         : cas structurellement mixtes que ce script NE
                        TRANCHE PAS seul, signalés pour décision utilisateur :
                          - Colonnes/Pilastres (14) : fût qui PEUT être vu
                            comme une extrusion (T1, cannelures verticales)
                            OU une révolution (T3, fût tourné) + chapiteau/
                            base qui sont eux du volume libre sculpté (T4)
                            — mélange des trois dans une même pièce.
                          - Encadrements non-Rosaces (Rectangulaires,
                            Carrés, Encastrées — 4 réfs) : le nom
                            "Encadrement" désigne un cadre plat qui
                            RESSEMBLE à du T2 (relief planaire) mais la
                            confusion documentée Encadrement/Rosace (cf.
                            renommage paintEncadrement->paintRosace, tour
                            précédent) rend la frontière fiable seulement
                            pour la sous-famille Rosaces, pas pour le
                            reste de la famille Encadrements.

Croise ensuite avec croisement_catalogue_data_formats.csv (déjà produit ce
tour) pour donner, PAR TYPE, le nombre de références disposant d'au moins
un format exploitable (DXF, STEP ou STL — pas DWG seul, pas aucun).

Écrit classification_t1_t4.csv (458 lignes, colonne 'type' + détail
formats) et imprime le tableau récapitulatif brut.
"""
import csv
import sys
from collections import defaultdict

CATALOGUE_REFS_CSV = "catalogue_data_refs.csv"
FORMATS_CSV = "croisement_catalogue_data_formats.csv"
OUTPUT_CSV = "classification_t1_t4.csv"

T1_FAMILLES = {"Corniches", "Moulures", "Plinthes", "Profils LED"}
T2_FAMILLES = {"Parements", "Lambris"}
T4_FAMILLES = {"Ornements"}
# T3 : uniquement famille Encadrements + sfam Rosaces (voir docstring)
# T_incertain : Colonnes (toute la famille) + Encadrements non-Rosaces


def classify(famille, sfam):
    if famille in T1_FAMILLES:
        return "T1_PROFIL_EXTRUDE"
    if famille in T2_FAMILLES:
        return "T2_RELIEF_PLANAIRE"
    if famille in T4_FAMILLES:
        return "T4_VOLUME_LIBRE"
    if famille == "Encadrements":
        if sfam == "Rosaces":
            return "T3_SOLIDE_DE_REVOLUTION"
        return "T_INCERTAIN"
    if famille == "Colonnes":
        return "T_INCERTAIN"
    return "T_INCERTAIN"  # famille inattendue -> signalée, pas de suppositions


def main():
    with open(CATALOGUE_REFS_CSV, newline="", encoding="utf-8") as f:
        cat_rows = list(csv.DictReader(f))

    with open(FORMATS_CSV, newline="", encoding="utf-8") as f:
        fmt_rows = list(csv.DictReader(f))
    fmt_by_ref = {r["ref"]: r for r in fmt_rows}

    output_rows = []
    for r in cat_rows:
        t = classify(r["famille"], r["sfam"])
        fmt = fmt_by_ref.get(r["ref"], {})
        a_dxf = fmt.get("a_dxf") == "True"
        a_step = fmt.get("a_step") == "True"
        a_stl = fmt.get("a_stl") == "True"
        exploitable = a_dxf or a_step or a_stl
        output_rows.append({
            "ref": r["ref"],
            "famille": r["famille"],
            "sfam": r["sfam"],
            "type": t,
            "a_dxf": a_dxf,
            "a_step": a_step,
            "a_stl": a_stl,
            "format_exploitable": exploitable,
        })

    with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["ref", "famille", "sfam", "type", "a_dxf", "a_step", "a_stl", "format_exploitable"])
        writer.writeheader()
        writer.writerows(output_rows)

    n = len(output_rows)
    print(f"=== CLASSIFICATION T1-T4 sur les {n} références de catalogue_data.dart ===\n")

    by_type = defaultdict(list)
    for r in output_rows:
        by_type[r["type"]].append(r)

    print(f"{'Type':28s} {'N':>4s} {'DXF exploit.':>13s} {'STEP exploit.':>14s} {'STL exploit.':>13s} {'>=1 format':>11s}")
    order = ["T1_PROFIL_EXTRUDE", "T2_RELIEF_PLANAIRE", "T3_SOLIDE_DE_REVOLUTION", "T4_VOLUME_LIBRE", "T_INCERTAIN"]
    total_check = 0
    for t in order:
        rows = by_type.get(t, [])
        n_t = len(rows)
        total_check += n_t
        n_dxf = sum(1 for r in rows if r["a_dxf"])
        n_step = sum(1 for r in rows if r["a_step"])
        n_stl = sum(1 for r in rows if r["a_stl"])
        n_exp = sum(1 for r in rows if r["format_exploitable"])
        print(f"{t:28s} {n_t:>4d} {n_dxf:>13d} {n_step:>14d} {n_stl:>13d} {n_exp:>11d}")

    print(f"\nSomme de contrôle (doit être 458) : {total_check}")

    print(f"\n=== Détail T_INCERTAIN ({len(by_type.get('T_INCERTAIN', []))} réfs) — liste complète, non tranchée ===")
    for r in sorted(by_type.get("T_INCERTAIN", []), key=lambda x: (x["famille"], x["sfam"], x["ref"])):
        print(f"  {r['ref']:12s} | {r['famille']:15s} | {r['sfam']:15s} | exploitable={r['format_exploitable']}")

    print(f"\nCSV écrit : {OUTPUT_CSV} ({n} lignes)")


if __name__ == "__main__":
    sys.exit(main())
