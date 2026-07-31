#!/usr/bin/env python3
"""
inject_cote_catalogue.py — Alimente assets/profiles/<sku>.json avec les
données DU CATALOGUE PAPIER (catalogue.csv) : cotes commerciales ET PRIX
(`prix_ht`, `prix_ttc`, `unite_prix`, `date_tarif`, `page_source`), dans
un champ séparé `cote_catalogue_mm`, À CÔTÉ des cotes MESURÉES sur la
géométrie (`bbox_mm`, `hauteur_mur_mm`, `projection_plafond_mm` —
produites par dxf2profile.py / solid2profile.py). On ne remplace JAMAIS
l'une par l'autre pour les cotes de SECTION : les deux sources restent
lisibles séparément, la confrontation reste le rôle de
catalogue_vs_profil.py (recoupement), jamais une fusion silencieuse ici.

C'EST UN TARIF : le prix est la donnée qui manquait depuis le début.
`prix_ml` (champ existant du schéma v1, jusqu'ici toujours `null`) est
désormais alimenté quand `unite == "ml"` (le produit se vend au mètre
linéaire) — valeur reprise du `prix_ht` catalogue, explicitement HT (le
TTC reste disponible dans `cote_catalogue_mm.prix_ttc`, jamais fusionné
en un seul nombre ambigu).

AUTORITÉ CATALOGUE SUR `longueur_barre_mm` (RECADRAGE utilisateur,
explicite) : la longueur de barre imprimée au tarif ("Corniche en 2 ml",
"1/2 colonne ... + 30 cm") est une décision COMMERCIALE de découpe — PAS
une propriété du galbe/profil que la géométrie pourrait mesurer.
  - dxf2profile.py (coupe 2D transversale) ne mesure JAMAIS de longueur
    de barre : structurellement absent de son schéma de sortie.
  - solid2profile.py MESURE une étendue de maillage le long de l'axe
    long (`length_mm`) — mais c'est la longueur de l'ÉCHANTILLON scanné,
    pas nécessairement la longueur commerciale standard de vente (qui
    peut différer : un échantillon de scan de 1780mm ne veut pas dire
    que le produit se vend en barres de 1780mm).
  -> RÈGLE : si le catalogue porte une `longueur_barre_mm`, elle devient
     LA valeur autoritaire du champ top-level `longueur_barre_mm`
     (`longueur_barre_mm_origine="catalogue"`). La valeur mesurée sur le
     maillage (si elle existe, uniquement pour les profils
     solid2profile.py) n'est JAMAIS perdue : préservée sous
     `longueur_barre_mm_mesure_maillage_mm`, toujours lisible séparément.
  - Si le catalogue ne porte AUCUNE longueur (cas fréquent : la majorité
    des désignations "A x B cm" sans mention "en N ml") -> on garde la
    valeur mesurée sur le maillage si elle existe
    (`longueur_barre_mm_origine="mesure_maillage"`), sinon `None` +
    `longueur_barre_mm_origine=None` — JAMAIS une valeur par défaut
    inventée (cf. suppression de DEFAULT_BAR_LENGTH_MM dans
    dxf2profile.py/solid2profile.py).

BASCULE DE SCHÉMA (cf. SPEC.md, règle "toute évolution du schéma passe
par une bascule de version_schema et une mise à jour de SPEC.md") :
  version_schema 2 -> 3. Changements : `cote_catalogue_mm` gagne
  `prix_ht`, `prix_ttc`, `unite_prix`, `date_tarif` (en plus de
  `page_source`/`correspondance_sku` déjà présents) ; le top-level gagne
  `longueur_barre_mm_origine` et `longueur_barre_mm_mesure_maillage_mm`
  (voir règle d'autorité ci-dessus) ; `prix_ml` (champ v1 déjà existant)
  est désormais effectivement alimenté. Aucun champ existant n'est
  renommé ni supprimé.

CORRESPONDANCE SKU : réutilise exactement la même logique que
catalogue_vs_profil.py (match_sku, qui s'appuie sur normalize_sku()
de dxf2profile.py) — un seul et même algorithme de correspondance,
jamais deux implémentations parallèles qui pourraient diverger.

RÈGLE assets/ (SPEC.md) : ce script MODIFIE des fichiers existants sous
assets/profiles/*.json — action explicitement demandée par l'utilisateur.
C'est un ajout/mise à jour de champs (écriture additive au niveau du
contenu JSON), jamais une suppression de champ existant, et jamais un
jeu de données produit substitué à un autre. Aucun fichier DWG/DXF/STL
source n'est touché par ce script.

Sortie : réécrit chaque assets/profiles/<sku>.json concerné, et affiche
un rapport récapitulatif (jamais silencieux).
"""

import argparse
import json
import sys
from pathlib import Path

# Réutilise la logique de correspondance SKU et de chargement du
# catalogue déjà écrite et testée dans catalogue_vs_profil.py — une
# seule implémentation, jamais dupliquée.
from catalogue_vs_profil import (
    CATALOGUE_DIM_FIELDS,
    load_catalogue,
    match_sku,
)

HERE = Path(__file__).parent
DEFAULT_CATALOGUE_PATH = HERE / "catalogue.csv"
DEFAULT_PROFILES_DIR = HERE.parent.parent / "assets" / "profiles"

NEW_SCHEMA_VERSION = 3

# Unités catalogue observées réellement dans catalogue.csv (colonne
# `unite`) -> libellé `unite_prix` explicite. "u" (pièce à l'unité) est
# la seule traduction effectuée ; les autres unités observées sont
# reportées telles qu'imprimées (jamais une traduction devinée pour une
# unité qui n'a pas été vérifiée dans le document, ex. "m2" existe dans
# KNOWN_UNITS de catalogue2csv.py mais n'apparaît dans AUCUNE ligne
# réelle de ce tarif — vérifié : 0 occurrence).
UNITE_PRIX_LABELS = {
    "u": "pièce",
    "ml": "ml",
    "Kg": "Kg",
    "cart.": "carton",
    "mul": "mul",
    "m2": "m²",
}


def build_cote_catalogue_mm(catalogue_row, correspondance_sku):
    """Construit l'objet cote_catalogue_mm à partir d'UNE ligne
    catalogue.csv déjà résolue : cotes de section neutres (inchangé) +
    PRIX (prix_ht, prix_ttc, unite_prix, date_tarif) + provenance
    (page_source, correspondance_sku). Retourne None UNIQUEMENT si
    aucune cote ET aucun prix n'est renseigné (jamais un objet vide
    ambigu) — en pratique n'arrive jamais sur ce tarif : chaque ligne
    porte toujours un prix."""
    dims = {}
    has_any = False
    for field in CATALOGUE_DIM_FIELDS:
        raw = catalogue_row.get(field)
        if raw in (None, "", "None"):
            dims[field] = None
            continue
        try:
            dims[field] = float(raw)
            has_any = True
        except ValueError:
            dims[field] = None

    prix_ht = _to_float_or_none(catalogue_row.get("prix_ht"))
    prix_ttc = _to_float_or_none(catalogue_row.get("prix_ttc"))
    unite_raw = (catalogue_row.get("unite") or "").strip()
    unite_prix = UNITE_PRIX_LABELS.get(unite_raw, unite_raw or None)
    date_tarif = catalogue_row.get("date_tarif") or None

    if prix_ht is not None or prix_ttc is not None:
        has_any = True

    if not has_any:
        return None

    dims["prix_ht"] = prix_ht
    dims["prix_ttc"] = prix_ttc
    dims["unite_prix"] = unite_prix
    dims["date_tarif"] = date_tarif
    dims["page_source"] = (
        int(catalogue_row["page_source"]) if catalogue_row.get("page_source") else None
    )
    dims["correspondance_sku"] = correspondance_sku
    return dims


def _to_float_or_none(raw):
    if raw in (None, "", "None"):
        return None
    try:
        return float(raw)
    except ValueError:
        return None


def reconcile_longueur_barre(record, cote):
    """Applique la règle d'AUTORITÉ CATALOGUE sur longueur_barre_mm
    (cf. docstring module). Modifie `record` en place. `cote` peut être
    None (aucune correspondance/cote catalogue) — dans ce cas on ne
    touche à rien de plus que ce que le pipeline géométrique a déjà
    posé (déjà None ou mesure_maillage, jamais de défaut inventé, cf.
    suppression de DEFAULT_BAR_LENGTH_MM)."""
    longueur_catalogue = cote.get("longueur_barre_mm") if cote else None

    # Valeur mesurée par le pipeline géométrique (uniquement possible
    # pour un profil issu de solid2profile.py — dxf2profile.py ne mesure
    # jamais ce champ, il est déjà None dans ce cas).
    longueur_mesuree = record.get("longueur_barre_mm")
    origine_mesuree = record.get("longueur_barre_mm_origine")

    # Préserve la mesure de maillage, si elle existe, SOUS UN AUTRE CHAMP
    # — jamais perdue, quelle que soit la décision d'autorité ci-dessous.
    if origine_mesuree == "mesure_maillage" and longueur_mesuree is not None:
        record["longueur_barre_mm_mesure_maillage_mm"] = longueur_mesuree
    else:
        record.setdefault("longueur_barre_mm_mesure_maillage_mm", None)

    if longueur_catalogue is not None:
        record["longueur_barre_mm"] = longueur_catalogue
        record["longueur_barre_mm_origine"] = "catalogue"
    elif origine_mesuree == "mesure_maillage" and longueur_mesuree is not None:
        # Pas de cote catalogue : on garde la mesure de maillage déjà en
        # place (rien à changer), l'origine est déjà correcte.
        pass
    else:
        record.setdefault("longueur_barre_mm", None)
        record.setdefault("longueur_barre_mm_origine", None)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--catalogue", default=str(DEFAULT_CATALOGUE_PATH))
    ap.add_argument("--profiles-dir", default=str(DEFAULT_PROFILES_DIR))
    ap.add_argument(
        "--dry-run", action="store_true",
        help="N'écrit rien, affiche seulement ce qui SERAIT modifié.",
    )
    args = ap.parse_args()

    catalogue_path = Path(args.catalogue)
    profiles_dir = Path(args.profiles_dir)

    if not catalogue_path.exists():
        print(f"ERREUR: catalogue introuvable: {catalogue_path}", file=sys.stderr)
        sys.exit(1)
    if not profiles_dir.exists():
        print(f"ERREUR: dossier profils introuvable: {profiles_dir}", file=sys.stderr)
        sys.exit(1)

    catalogue = load_catalogue(catalogue_path)
    catalogue_skus = set(catalogue.keys())

    profile_paths = sorted(profiles_dir.glob("*.json"))
    print(f"Catalogue: {len(catalogue)} SKU distincts (depuis {catalogue_path.name})")
    print(f"Fichiers profils trouvés: {len(profile_paths)} (depuis {profiles_dir})")
    if args.dry_run:
        print("--dry-run : AUCUNE écriture ne sera effectuée.\n")

    n_avec_cote = 0
    n_sans_correspondance = 0
    n_correspondance_sans_cote = 0
    n_prix_ml_alimente = 0
    n_longueur_autorite_catalogue = 0

    for p in profile_paths:
        try:
            record = json.loads(p.read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            print(f"  [IGNORÉ] {p.name}: JSON illisible ({e})")
            continue

        profil_sku = record.get("sku", p.stem)
        matched_sku, match_type = match_sku(catalogue_skus, profil_sku)

        if matched_sku is None:
            record["cote_catalogue_mm"] = None
            n_sans_correspondance += 1
            print(f"  {profil_sku:12s} -> AUCUNE correspondance catalogue -> cote_catalogue_mm=null")
            cote = None
        else:
            # 0 doublon SKU garanti par catalogue2csv.py (vérifié à
            # l'écriture) -> une seule ligne attendue.
            catalogue_row = catalogue[matched_sku][0]
            cote = build_cote_catalogue_mm(catalogue_row, match_type)
            record["cote_catalogue_mm"] = cote
            if cote is None:
                n_correspondance_sans_cote += 1
                print(
                    f"  {profil_sku:12s} -> correspondance '{matched_sku}' ({match_type}) "
                    f"trouvée, mais AUCUNE cote/prix chiffré dans le catalogue pour "
                    f"'{catalogue_row.get('designation','')}' -> cote_catalogue_mm=null"
                )
            else:
                n_avec_cote += 1
                print(
                    f"  {profil_sku:12s} -> correspondance '{matched_sku}' ({match_type}) "
                    f"-> prix_ht={cote['prix_ht']} prix_ttc={cote['prix_ttc']} "
                    f"unite_prix={cote['unite_prix']} (page {cote['page_source']}, {cote['date_tarif']})"
                )

            # prix_ml : alimenté uniquement quand le produit se vend au
            # mètre linéaire (unite catalogue == "ml"). Jamais inventé
            # pour une unité différente (pièce, Kg, carton...).
            if cote and cote.get("unite_prix") == "ml" and cote.get("prix_ht") is not None:
                record["prix_ml"] = cote["prix_ht"]
                n_prix_ml_alimente += 1
                print(f"      -> prix_ml (HT, vente au ml) = {cote['prix_ht']}")

        # AUTORITÉ CATALOGUE sur longueur_barre_mm (cf. docstring module).
        avant_origine = record.get("longueur_barre_mm_origine")
        reconcile_longueur_barre(record, cote)
        if record.get("longueur_barre_mm_origine") == "catalogue":
            if avant_origine != "catalogue":
                n_longueur_autorite_catalogue += 1
            print(
                f"      -> longueur_barre_mm = {record['longueur_barre_mm']} "
                f"(AUTORITÉ CATALOGUE, mesure maillage éventuelle préservée "
                f"sous longueur_barre_mm_mesure_maillage_mm="
                f"{record.get('longueur_barre_mm_mesure_maillage_mm')})"
            )

        record["version_schema"] = NEW_SCHEMA_VERSION

        if not args.dry_run:
            clean = {k: v for k, v in record.items() if not k.startswith("_")}
            p.write_text(json.dumps(clean, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"\n=== Résumé ===")
    print(f"  Profils avec cote_catalogue_mm renseignée (cotes+prix) : {n_avec_cote}")
    print(f"  Profils avec correspondance mais AUCUNE cote/prix      : {n_correspondance_sans_cote}")
    print(f"  Profils SANS correspondance catalogue                  : {n_sans_correspondance}")
    print(f"  prix_ml alimenté (unite catalogue == 'ml')             : {n_prix_ml_alimente}")
    print(f"  longueur_barre_mm passée sous autorité catalogue       : {n_longueur_autorite_catalogue}")
    if args.dry_run:
        print("\n(--dry-run actif : aucun fichier n'a été modifié)")
    else:
        print(f"\nFichiers réécrits sous {profiles_dir} (version_schema -> {NEW_SCHEMA_VERSION}).")


if __name__ == "__main__":
    main()
