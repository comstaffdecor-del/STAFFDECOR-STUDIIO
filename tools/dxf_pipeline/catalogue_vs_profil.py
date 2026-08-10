#!/usr/bin/env python3
"""
catalogue_vs_profil.py — RECOUPEMENT catalogue papier (catalogue.csv) vs
géométrie mesurée (assets/profiles/*.json).

CONTEXTE : catalogue.csv (produit par catalogue2csv.py) porte les cotes
imprimées dans le tarif papier Staff Décor (source de vérité commerciale).
assets/profiles/*.json porte les cotes MESURÉES sur la géométrie réelle
(DXF ou maillage STL, via dxf2profile.py / solid2profile.py). Ce script
ne remplace jamais l'une par l'autre : il les confronte et rapporte les
écarts, pour que l'utilisateur puisse juger (ex. "D898 fait-il vraiment
200x301mm ?").

RÈGLE DE DÉCISION (imposée) :
  - écart relatif < 2%  -> VALIDE (la géométrie est confirmée par le papier)
  - écart relatif > 2%  -> ALERTE (les deux valeurs sont affichées, jamais
    arbitrée automatiquement — c'est à l'humain de trancher)
  - aucune cote catalogue OU aucune géométrie mesurée disponible pour un
    champ -> AUCUNE_COTE_CATALOGUE / AUCUNE_GEOMETRIE_MESUREE (jamais un
    faux VALIDE ni une ALERTE inventée sur une comparaison impossible).

CORRECTIF (RECADRAGE utilisateur) — COMPARABILITÉ DES GRANDEURS :
la version précédente cherchait, pour CHAQUE cote catalogue, le champ
géométrique mesuré donnant l'écart relatif le PLUS FAIBLE, parmi TOUS
les champs mesurés disponibles sans distinction de nature — ce qui
pouvait apparier une cote de SECTION (ex. `cote1_mm`=largeur du profil)
contre une LONGUEUR DE BARRE mesurée (`longueur_barre_mm`), simplement
parce que l'écart numérique était, par coïncidence, le plus petit des
champs disponibles. Une largeur comparée à une longueur n'est PAS une
alerte dimensionnelle réelle, c'est un bug d'appariement : les deux
grandeurs ne mesurent pas la même chose et leur écart n'a aucun sens
physique. RÈGLE DÉSORMAIS (imposée, plus de recherche du "meilleur
écart" tous champs confondus) : chaque cote catalogue n'est comparée
QU'AUX champs mesurés de MÊME NATURE, via une table de correspondance
explicite fermée (`COMPARABLE_FIELDS_MAP` ci-dessous) :
  - cote de SECTION (`diametre_mm`, `hauteur_mm`, `cote1_mm`, `cote2_mm`,
    `cote3_mm`, `epaisseur_mm`) <-> UNIQUEMENT `bbox_mm.w` / `bbox_mm.h`
    (les deux dimensions mesurées de la bounding box du profil de coupe
    — jamais `longueur_barre_mm`, qui n'est pas une cote de section).
  - LONGUEUR / mètre linéaire (`longueur_barre_mm` catalogue, unité
    catalogue = "ml") <-> UNIQUEMENT `longueur_barre_mm` mesuré (source
    maillage 3D uniquement — voir NOTE ci-dessous).
Si aucun champ mesuré de la nature attendue n'est disponible (ex. SKU
géré par dxf2profile.py, qui ne mesure structurellement jamais de
longueur de barre) -> statut `NON_COMPARABLE` (PAS `ALERTE`, PAS
`AUCUNE_GEOMETRIE_MESUREE` : il existe peut-être une géométrie mesurée,
mais d'une autre nature, incomparable à cette cote catalogue précise).
Parmi les champs comparables restants, on garde le meilleur écart (ex.
hésitation légitime entre bbox_mm.w et bbox_mm.h pour une cote catalogue
neutre `cote1_mm`/`cote2_mm` — voir point 4 ci-dessous, jamais résolue à
un niveau supérieur).

COLONNES `cote1_mm`/`cote2_mm`/`cote3_mm` RESTENT NEUTRES (confirmé,
imposé) : catalogue2csv.py ne devine JAMAIS laquelle est la hauteur et
laquelle la projection — c'est la comparaison géométrique ci-dessus
(via bbox_mm.w/h) qui tranche, jamais une affectation a priori.

CORRESPONDANCE SKU : le catalogue et le pipeline géométrique ne partagent
pas toujours exactement la même écriture de référence (observé réellement
sur ce jeu de données, pas une hypothèse) — résolue via `normalize_sku()`
(réutilisée depuis dxf2profile.py, une seule implémentation, jamais deux
algorithmes de normalisation parallèles). Exemples réels :
  - "1145c" (assets/profiles/1145c.json, minuscule — nom de fichier DXF
    d'origine) vs "1145C" (catalogue.csv, tel qu'imprimé) -> normalisés
    tous deux en "1145C" -> correspondance trouvée, journalisée
    explicitement (colonne `correspondance_sku` = "normalisee"), jamais
    silencieuse.
  - "20-54" (assets/profiles/20-54.json) vs "20.54" (catalogue.csv, tel
    qu'imprimé : "20.54  1/2 colonne Ø 14 H. 200 cm + 30 cm") -> tiret et
    point sont désormais UNIFIÉS (pas supprimés) par `normalize_sku()` en
    un même séparateur canonique -> les deux normalisent en "20-54" ->
    correspondance trouvée et journalisée ("normalisee"). Choix motivé
    empiriquement : supprimer purement le séparateur ferait collisionner
    "20.01" et "2001" (deux références RÉELLEMENT distinctes du
    catalogue, vérifié sur les 1596 lignes), alors que l'unifier en un
    seul type de séparateur ne produit AUCUNE collision.
  - TOUTE correspondance non exacte (repli casse OU normalisation) reste
    journalisée dans un CSV dédié à la relecture humaine — voir
    `correspondances_non_exactes.csv` ci-dessous.

CHAMPS GÉOMÉTRIQUES DISPONIBLES (schéma SPEC.md, tels que produits par le
pipeline DXF/3D) : `bbox_mm.w`, `bbox_mm.h`, `hauteur_mur_mm`,
`projection_plafond_mm`, `longueur_barre_mm`. Seuls `bbox_mm.w`/`.h` et
`longueur_barre_mm` participent au recoupement (voir table de
comparabilité ci-dessus) — `hauteur_mur_mm`/`projection_plafond_mm` sont
des PROJECTIONS D'USAGE (face d'appui mur/plafond), pas des cotes de
section brutes comparables à une désignation catalogue générique.

SORTIE :
  - recoupement_catalogue_vs_profil.csv : sku, correspondance_sku,
    designation, cote_catalogue_champ, cote_catalogue_mm,
    cote_mesuree_champ, cote_mesuree_mm, ecart_pct, statut
  - correspondances_non_exactes.csv : sku_profil, sku_catalogue,
    type_correspondance (journal de relecture humaine, point 5 demandé
    explicitement par l'utilisateur)

Ces fichiers vont dans tools/dxf_pipeline/ (comme catalogue.csv), PAS dans
assets/ (règle SPEC.md — assets/ est en écriture additive uniquement,
jamais un rapport de recoupement généré par un script).
"""

import argparse
import csv
import json
import sys
from pathlib import Path

# Réutilise normalize_sku() — une seule implémentation de la
# normalisation SKU, jamais un second algorithme parallèle.
sys.path.insert(0, str(Path(__file__).parent))
from dxf2profile import normalize_sku  # noqa: E402

HERE = Path(__file__).parent
DEFAULT_CATALOGUE_PATH = HERE / "catalogue.csv"
DEFAULT_PROFILES_DIR = HERE.parent.parent / "assets" / "profiles"
DEFAULT_OUTPUT_PATH = HERE / "recoupement_catalogue_vs_profil.csv"
DEFAULT_LOG_CORRESPONDANCES_PATH = HERE / "correspondances_non_exactes.csv"

ECART_TOL_PCT = 2.0

# Cotes catalogue à confronter (colonnes de catalogue.csv, cf. docstring
# catalogue2csv.py). L'ordre ne préjuge d'aucune correspondance.
CATALOGUE_DIM_FIELDS = [
    "diametre_mm", "hauteur_mm", "cote1_mm", "cote2_mm", "cote3_mm",
    "epaisseur_mm", "longueur_barre_mm",
]

# Table de comparabilité FERMÉE (RECADRAGE utilisateur) : chaque cote
# catalogue n'est comparée QU'AUX champs géométriques mesurés de même
# NATURE physique. Une cote de section ne se compare jamais à une
# longueur de barre, et réciproquement — cf. docstring module.
COMPARABLE_FIELDS_MAP = {
    "diametre_mm": ("bbox_mm.w", "bbox_mm.h"),
    "hauteur_mm": ("bbox_mm.w", "bbox_mm.h"),
    "cote1_mm": ("bbox_mm.w", "bbox_mm.h"),
    "cote2_mm": ("bbox_mm.w", "bbox_mm.h"),
    "cote3_mm": ("bbox_mm.w", "bbox_mm.h"),
    "epaisseur_mm": ("bbox_mm.w", "bbox_mm.h"),
    "longueur_barre_mm": ("longueur_barre_mm",),
}

# RÈGLE (imposée) — SEUIL LONGUEUR PRÉSUMÉE : dans un tarif de moulure,
# aucune cote de SECTION physique (largeur/hauteur/épaisseur d'un profil
# de coupe) ne dépasse plausiblement 1 mètre. Une valeur >= 1000mm
# trouvée dans un champ cote-de-SECTION (hauteur_mm/cote1_mm/cote2_mm/
# cote3_mm/epaisseur_mm — PAS longueur_barre_mm, qui EST déjà une
# longueur) est presque certainement une LONGUEUR DE BARRE mal classée
# par extract_dimensions_mm() (ex. SKU 1000 "Pilastre cannelé 23 x 250
# cm" -> cote2_mm=2500.0, en réalité la hauteur du pilastre en barre,
# pas une cote de section). RÈGLE : ne JAMAIS reclasser silencieusement
# la valeur à l'extraction (catalogue2csv.py reste neutre, cf. son
# docstring) — on la signale ICI, au moment du recoupement géométrique,
# avec un statut dédié LONGUEUR_PRESUMEE et un marqueur "auto": true
# (reclassification AUTOMATIQUE par heuristique de seuil, jamais
# confirmée manuellement — distincte d'une VALIDE/ALERTE qui elles
# s'appuient sur une mesure géométrique réelle).
#
# CORRECTIF (RECADRAGE utilisateur) — `diametre_mm` EXCLU de
# SECTION_FIELDS : contrairement à une cote de moulure (largeur/hauteur
# de profil de coupe), le DIAMÈTRE d'une rosace/plafonnier/plafond
# PEUT légitimement dépasser 1 mètre — ce n'est pas une longueur de
# barre déguisée, c'est une vraie dimension de la pièce. Cas motivant
# réel : M303 "Rosace Ø 70 cm" — le principe s'applique de façon
# générale aux rosaces de grand diamètre du même catalogue (vérifié :
# M504 Ø103cm=1030mm, M404 Ø104cm=1040mm, M604 Ø158cm=1580mm, M605
# Ø146cm=1460mm, M422 Ø100cm=1000mm, M503 Ø100cm=1000mm, PL.R200
# Ø206cm=2060mm, PL503C.BC Ø100cm=1000mm — 8 cas réels dans
# catalogue.csv, TOUS des diamètres réels, AUCUN n'est une longueur de
# barre). `diametre_mm` reste dans COMPARABLE_FIELDS_MAP (toujours
# comparé à bbox_mm.w/bbox_mm.h) mais ne déclenche plus jamais
# LONGUEUR_PRESUMEE, quelle que soit sa valeur.
#
# ⚠️ CONSTAT NON CORRIGÉ ICI (hors périmètre demandé, signalé pour
# décision utilisateur) : `cote1_mm`/`cote2_mm` >= 1000mm comptent
# ÉGALEMENT de nombreux cas légitimes non liés à une longueur de barre
# — dimensions réelles de panneaux/encadrements/plafonniers plats (ex.
# "Encadrement 150 x 96 cm" -> cote1_mm=1500.0 : une vraie face de
# panneau, pas une longueur). Vérifié : 92 lignes cote1_mm et 56 lignes
# cote2_mm >= 1000mm dans catalogue.csv, dont la majorité sont des
# familles PANNEAUX MURAUX / ENCADREMENTS DE MIROIRS / LUMINAIRES
# PLAFONNIERS (faces planes, pas des barres) et seule une minorité
# (familles PILASTRES/COLONNES, motif "H. NNN cm") sont de vraies
# longueurs mal classées. La règle actuelle sur-marque donc probablement
# ces panneaux/encadrements/plafonniers en LONGUEUR_PRESUMEE — non
# corrigé ici (hors périmètre explicite du point 5), à traiter par
# familles si demandé (ex. limiter le seuil aux familles PILASTRES/
# COLONNES plutôt qu'à tous les SKU cote1/cote2_mm).
SECTION_FIELDS = (
    "hauteur_mm", "cote1_mm", "cote2_mm", "cote3_mm", "epaisseur_mm",
)
LONGUEUR_PRESUMEE_SEUIL_MM = 1000.0


def load_catalogue(path):
    """sku -> liste de rows (liste car un sku peut théoriquement apparaître
    plusieurs fois si le tarif le répète — catalogue2csv.py a déjà vérifié
    0 doublon sur ce document, mais on ne suppose pas que ça restera vrai
    pour un futur tarif)."""
    rows = {}
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            rows.setdefault(row["sku"], []).append(row)
    return rows


def load_profiles(dirpath):
    """sku (tel qu'écrit DANS le JSON, champ `sku`) -> dict JSON complet."""
    profiles = {}
    skipped = []
    for p in sorted(dirpath.glob("*.json")):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            skipped.append((p.name, str(e)))
            continue
        profiles[data.get("sku", p.stem)] = data
    return profiles, skipped


def match_sku(catalogue_skus, profil_sku):
    """Retourne (sku_catalogue_correspondant, type_correspondance) ou
    (None, "AUCUNE") si rien de fiable.

    Ordre de résolution (jamais de correspondance floue au-delà de ces
    3 niveaux, chacun journalisé distinctement par l'appelant) :
      1. "exact"      : égalité caractère pour caractère.
      2. "casse_differente" : différence de casse UNIQUEMENT (repli
         historique conservé — ex. "1145c" vs "1145C" matche déjà à ce
         niveau, avant même la normalisation complète).
      3. "normalisee" : égalité après normalize_sku() (unifie point/tiret/
         espaces/casse, cf. dxf2profile.normalize_sku) — ex. "20-54" vs
         "20.54". Résolu UNIQUEMENT si un seul SKU catalogue normalise
         vers la même clé (ambiguïté = pas de correspondance, jamais
         deviné arbitrairement parmi plusieurs candidats)."""
    if profil_sku in catalogue_skus:
        return profil_sku, "exact"

    lower_map = {}
    for k in catalogue_skus:
        lower_map.setdefault(k.lower(), []).append(k)
    candidates = lower_map.get(profil_sku.lower())
    if candidates and len(set(candidates)) == 1:
        return candidates[0], "casse_differente"

    norm_map = {}
    for k in catalogue_skus:
        norm_map.setdefault(normalize_sku(k), []).append(k)
    norm_candidates = norm_map.get(normalize_sku(profil_sku))
    if norm_candidates and len(set(norm_candidates)) == 1:
        return norm_candidates[0], "normalisee"

    return None, "AUCUNE"


def profil_geometry_fields(profil_json):
    """Extrait les champs géométriques MESURÉS comparables (valeurs non
    nulles/non nulles-par-défaut uniquement — un bbox 0x0 de statut
    ERREUR_SELECTION n'est pas une mesure, c'est une absence)."""
    out = {}
    bbox = profil_json.get("bbox_mm") or {}
    if bbox.get("w"):
        out["bbox_mm.w"] = float(bbox["w"])
    if bbox.get("h"):
        out["bbox_mm.h"] = float(bbox["h"])
    if profil_json.get("hauteur_mur_mm"):
        out["hauteur_mur_mm"] = float(profil_json["hauteur_mur_mm"])
    if profil_json.get("projection_plafond_mm"):
        out["projection_plafond_mm"] = float(profil_json["projection_plafond_mm"])
    if profil_json.get("longueur_barre_mm"):
        out["longueur_barre_mm"] = float(profil_json["longueur_barre_mm"])
    return out


def compare_one(catalogue_row, profil_geom):
    """Pour chaque cote catalogue non vide, cherche la meilleure
    correspondance UNIQUEMENT parmi les champs géométriques mesurés de
    même NATURE (cf. COMPARABLE_FIELDS_MAP, RECADRAGE utilisateur —
    plus de recherche du meilleur écart tous champs confondus, qui
    pouvait apparier une largeur à une longueur).

    Retourne une liste de dicts de résultat (un par cote catalogue non
    vide trouvée dans la ligne) :
      - NON_COMPARABLE si aucun champ mesuré de la nature attendue
        n'existe dans COMPARABLE_FIELDS_MAP pour ce cfield (ne devrait
        pas arriver, table fermée et exhaustive sur CATALOGUE_DIM_FIELDS
        — garde-fou défensif).
      - AUCUNE_GEOMETRIE_MESUREE si aucune mesure DU TOUT n'est
        disponible pour ce profil (profil_geom vide).
      - NON_COMPARABLE si profil_geom contient des mesures, mais AUCUNE
        de la nature comparable attendue (ex. dxf2profile.py : jamais de
        longueur_barre_mm mesurée -> une cote catalogue longueur_barre_mm
        reste NON_COMPARABLE, jamais faussement associée à bbox_mm.w).
      - LONGUEUR_PRESUMEE (auto=true) si cfield est une cote de SECTION
        (SECTION_FIELDS) mais que sa valeur >= LONGUEUR_PRESUMEE_SEUIL_MM
        (1000mm) : reclassification heuristique AUTOMATIQUE en longueur
        de barre présumée, PAS une alerte dimensionnelle (aucune section
        de moulure ne fait 1 mètre) — priorité sur toute autre logique,
        vérifié avant la table de comparabilité.
      - VALIDE / ALERTE sinon, sur le meilleur écart parmi les SEULS
        champs comparables disponibles.

    Chaque dict résultat porte aussi "auto": bool — True uniquement pour
    LONGUEUR_PRESUMEE (reclassification automatique non confirmée),
    False pour tous les autres statuts (mesure ou absence directe)."""
    results = []
    for cfield in CATALOGUE_DIM_FIELDS:
        raw = catalogue_row.get(cfield)
        if raw in (None, "", "None"):
            continue
        try:
            val = float(raw)
        except ValueError:
            continue
        if val <= 0:
            continue

        if cfield in SECTION_FIELDS and val >= LONGUEUR_PRESUMEE_SEUIL_MM:
            results.append({
                "cote_catalogue_champ": cfield,
                "cote_catalogue_mm": val,
                "cote_mesuree_champ": "",
                "cote_mesuree_mm": "",
                "ecart_pct": "",
                "statut": "LONGUEUR_PRESUMEE",
                "auto": True,
            })
            continue

        allowed_fields = COMPARABLE_FIELDS_MAP.get(cfield)
        if not allowed_fields:
            # Table fermée et exhaustive sur CATALOGUE_DIM_FIELDS : ne
            # devrait jamais se produire, garde-fou défensif seulement.
            results.append({
                "cote_catalogue_champ": cfield,
                "cote_catalogue_mm": val,
                "cote_mesuree_champ": "",
                "cote_mesuree_mm": "",
                "ecart_pct": "",
                "statut": "NON_COMPARABLE",
                "auto": False,
            })
            continue

        if not profil_geom:
            results.append({
                "cote_catalogue_champ": cfield,
                "cote_catalogue_mm": val,
                "cote_mesuree_champ": "",
                "cote_mesuree_mm": "",
                "ecart_pct": "",
                "statut": "AUCUNE_GEOMETRIE_MESUREE",
                "auto": False,
            })
            continue

        comparable_geom = {
            gfield: gval for gfield, gval in profil_geom.items()
            if gfield in allowed_fields
        }
        if not comparable_geom:
            # Le profil a bien des mesures, mais aucune de la NATURE
            # attendue pour cette cote catalogue précise — pas une
            # absence de géométrie, une incompatibilité de nature.
            results.append({
                "cote_catalogue_champ": cfield,
                "cote_catalogue_mm": val,
                "cote_mesuree_champ": "",
                "cote_mesuree_mm": "",
                "ecart_pct": "",
                "statut": "NON_COMPARABLE",
                "auto": False,
            })
            continue

        best_field, best_val, best_ecart = None, None, None
        for gfield, gval in comparable_geom.items():
            ecart_pct = abs(gval - val) / val * 100.0
            if best_ecart is None or ecart_pct < best_ecart:
                best_field, best_val, best_ecart = gfield, gval, ecart_pct

        statut = "VALIDE" if best_ecart <= ECART_TOL_PCT else "ALERTE"
        results.append({
            "cote_catalogue_champ": cfield,
            "cote_catalogue_mm": val,
            "cote_mesuree_champ": best_field,
            "cote_mesuree_mm": best_val,
            "ecart_pct": round(best_ecart, 2),
            "statut": statut,
            "auto": False,
        })
    return results


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--catalogue", default=str(DEFAULT_CATALOGUE_PATH))
    ap.add_argument("--profiles-dir", default=str(DEFAULT_PROFILES_DIR))
    ap.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH))
    ap.add_argument("--log-correspondances", default=str(DEFAULT_LOG_CORRESPONDANCES_PATH))
    args = ap.parse_args()

    catalogue_path = Path(args.catalogue)
    profiles_dir = Path(args.profiles_dir)
    output_path = Path(args.output)
    log_correspondances_path = Path(args.log_correspondances)

    if not catalogue_path.exists():
        print(f"ERREUR: catalogue introuvable: {catalogue_path}", file=sys.stderr)
        sys.exit(1)
    if not profiles_dir.exists():
        print(f"ERREUR: dossier profils introuvable: {profiles_dir}", file=sys.stderr)
        sys.exit(1)

    catalogue = load_catalogue(catalogue_path)
    profiles, skipped_profiles = load_profiles(profiles_dir)

    if skipped_profiles:
        print("ATTENTION — JSON de profil illisibles, ignorés (pas une erreur bloquante):")
        for name, err in skipped_profiles:
            print(f"  {name}: {err}")

    print(f"Catalogue: {len(catalogue)} SKU distincts (depuis {catalogue_path.name})")
    print(f"Profils géométriques: {len(profiles)} SKU (depuis {profiles_dir})")

    catalogue_skus = set(catalogue.keys())
    out_rows = []
    log_correspondances_rows = []
    nb_match_exact = 0
    nb_match_non_exact = 0
    nb_sans_correspondance = []

    for profil_sku, profil_json in profiles.items():
        matched_sku, match_type = match_sku(catalogue_skus, profil_sku)
        if matched_sku is None:
            nb_sans_correspondance.append(profil_sku)
            out_rows.append({
                "sku": profil_sku,
                "correspondance_sku": "AUCUNE",
                "designation": "",
                "cote_catalogue_champ": "",
                "cote_catalogue_mm": "",
                "cote_mesuree_champ": "",
                "cote_mesuree_mm": "",
                "ecart_pct": "",
                "statut": "SKU_INTROUVABLE_DANS_CATALOGUE",
                "auto": False,
            })
            continue

        if match_type == "exact":
            nb_match_exact += 1
        else:
            nb_match_non_exact += 1
            # Journal de relecture humaine (point 5 demandé explicitement) :
            # TOUTE correspondance non exacte (casse OU normalisation)
            # tracée ici, jamais silencieuse.
            log_correspondances_rows.append({
                "sku_profil": profil_sku,
                "sku_catalogue": matched_sku,
                "type_correspondance": match_type,
            })

        profil_geom = profil_geometry_fields(profil_json)
        catalogue_rows = catalogue[matched_sku]
        for crow in catalogue_rows:
            comparisons = compare_one(crow, profil_geom)
            if not comparisons:
                out_rows.append({
                    "sku": profil_sku,
                    "correspondance_sku": match_type,
                    "designation": crow.get("designation", ""),
                    "cote_catalogue_champ": "",
                    "cote_catalogue_mm": "",
                    "cote_mesuree_champ": "",
                    "cote_mesuree_mm": "",
                    "ecart_pct": "",
                    "statut": "AUCUNE_COTE_CATALOGUE",
                    "auto": False,
                })
                continue
            for comp in comparisons:
                out_rows.append({
                    "sku": profil_sku,
                    "correspondance_sku": match_type,
                    "designation": crow.get("designation", ""),
                    **comp,
                })

    fieldnames = [
        "sku", "correspondance_sku", "designation", "cote_catalogue_champ",
        "cote_catalogue_mm", "cote_mesuree_champ", "cote_mesuree_mm",
        "ecart_pct", "statut", "auto",
    ]
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in out_rows:
            writer.writerow(row)

    # Journal des correspondances non exactes (point 5 demandé) — écrit
    # même s'il est vide (0 ligne + en-tête), jamais silencieusement omis.
    with open(log_correspondances_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["sku_profil", "sku_catalogue", "type_correspondance"])
        writer.writeheader()
        for row in log_correspondances_rows:
            writer.writerow(row)

    nb_valide = sum(1 for r in out_rows if r["statut"] == "VALIDE")
    nb_alerte = sum(1 for r in out_rows if r["statut"] == "ALERTE")
    nb_non_comparable = sum(1 for r in out_rows if r["statut"] == "NON_COMPARABLE")
    nb_longueur_presumee = sum(1 for r in out_rows if r["statut"] == "LONGUEUR_PRESUMEE")
    nb_aucune_cote = sum(1 for r in out_rows if r["statut"] == "AUCUNE_COTE_CATALOGUE")
    nb_aucune_geom = sum(1 for r in out_rows if r["statut"] == "AUCUNE_GEOMETRIE_MESUREE")
    nb_sku_introuvable = sum(1 for r in out_rows if r["statut"] == "SKU_INTROUVABLE_DANS_CATALOGUE")

    print(f"\n=== recoupement_catalogue_vs_profil.csv écrit ({len(out_rows)} lignes) -> {output_path} ===")
    print(f"  SKU profils avec correspondance EXACTE dans le catalogue   : {nb_match_exact}")
    print(f"  SKU profils avec correspondance NON EXACTE (journalisée)   : {nb_match_non_exact}")
    print(f"  SKU profils SANS AUCUNE correspondance catalogue           : {len(nb_sans_correspondance)}")
    if nb_sans_correspondance:
        print(f"    -> {', '.join(nb_sans_correspondance)}")
    print(f"  Comparaisons VALIDE (écart <= {ECART_TOL_PCT}%)  : {nb_valide}")
    print(f"  Comparaisons ALERTE (écart > {ECART_TOL_PCT}%)   : {nb_alerte}")
    print(f"  NON_COMPARABLE (natures différentes, pas une alerte) : {nb_non_comparable}")
    print(f"  LONGUEUR_PRESUMEE (cote >= {LONGUEUR_PRESUMEE_SEUIL_MM:.0f}mm, auto=true)  : {nb_longueur_presumee}")
    print(f"  Cote catalogue absente pour ce produit          : {nb_aucune_cote}")
    print(f"  Géométrie mesurée absente pour ce produit       : {nb_aucune_geom}")
    print(f"  SKU introuvable dans catalogue.csv               : {nb_sku_introuvable}")
    print(f"Journal des correspondances non exactes -> {log_correspondances_path} ({len(log_correspondances_rows)} lignes)")

    if nb_alerte:
        print("\n--- Détail des ALERTES (écart > 2%, grandeurs COMPARABLES uniquement) ---")
        for r in out_rows:
            if r["statut"] == "ALERTE":
                print(
                    f"  {r['sku']} ({r['designation']}): catalogue "
                    f"{r['cote_catalogue_champ']}={r['cote_catalogue_mm']}mm vs "
                    f"mesuré {r['cote_mesuree_champ']}={r['cote_mesuree_mm']}mm "
                    f"-> écart {r['ecart_pct']}%"
                )

    if nb_longueur_presumee:
        print(
            f"\n--- Détail LONGUEUR_PRESUMEE (cote >= "
            f"{LONGUEUR_PRESUMEE_SEUIL_MM:.0f}mm reclassée AUTO, à confirmer) ---"
        )
        for r in out_rows:
            if r["statut"] == "LONGUEUR_PRESUMEE":
                print(
                    f"  {r['sku']} ({r['designation']}): "
                    f"{r['cote_catalogue_champ']}={r['cote_catalogue_mm']}mm "
                    f"-> présumée LONGUEUR DE BARRE, pas une cote de section"
                )


if __name__ == "__main__":
    main()
