#!/usr/bin/env python3
"""
test_catalogue_vs_profil.py — tests unitaires de compare_one()
(catalogue_vs_profil.py), en particulier le statut LONGUEUR_PRESUMEE
(cote de section >= 1000mm) ajouté sur demande explicite ("une cote
>= 1000 mm dans un tarif de moulure est une LONGUEUR, pas une
section"). Cas motivant réel : SKU 1000, cote2_mm=2500.0.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from catalogue_vs_profil import compare_one, LONGUEUR_PRESUMEE_SEUIL_MM  # noqa: E402


def _row(**kwargs):
    """Construit une ligne catalogue minimale, tous les CATALOGUE_DIM_FIELDS
    vides sauf ceux fournis explicitement."""
    base = {
        "diametre_mm": "", "hauteur_mm": "", "cote1_mm": "", "cote2_mm": "",
        "cote3_mm": "", "epaisseur_mm": "", "longueur_barre_mm": "",
    }
    base.update(kwargs)
    return base


def test_sku_1000_cote2_2500mm_est_longueur_presumee():
    """Cas motivant réel : cote2_mm=2500.0 (>= seuil) doit être
    LONGUEUR_PRESUMEE/auto=true, PAS une ALERTE contre bbox_mm.w."""
    row = _row(cote1_mm="230.0", cote2_mm="2500.0")
    profil_geom = {"bbox_mm.w": 230.0, "bbox_mm.h": 40.0}
    results = compare_one(row, profil_geom)
    by_field = {r["cote_catalogue_champ"]: r for r in results}

    assert by_field["cote1_mm"]["statut"] == "VALIDE"
    assert by_field["cote1_mm"]["auto"] is False

    assert by_field["cote2_mm"]["statut"] == "LONGUEUR_PRESUMEE"
    assert by_field["cote2_mm"]["auto"] is True
    assert by_field["cote2_mm"]["cote_mesuree_champ"] == ""
    assert by_field["cote2_mm"]["cote_mesuree_mm"] == ""
    assert by_field["cote2_mm"]["ecart_pct"] == ""


def test_seuil_exact_1000mm_est_longueur_presumee():
    """La borne exacte (>=, pas >) doit basculer en LONGUEUR_PRESUMEE."""
    row = _row(cote1_mm=str(LONGUEUR_PRESUMEE_SEUIL_MM))
    results = compare_one(row, {"bbox_mm.w": 999.0})
    assert results[0]["statut"] == "LONGUEUR_PRESUMEE"
    assert results[0]["auto"] is True


def test_juste_sous_le_seuil_reste_comparable():
    """999.9mm doit rester une cote de section normale (VALIDE/ALERTE),
    pas LONGUEUR_PRESUMEE — le seuil ne doit pas être approximatif."""
    row = _row(cote1_mm="999.9")
    results = compare_one(row, {"bbox_mm.w": 999.9})
    assert results[0]["statut"] == "VALIDE"
    assert results[0]["auto"] is False


def test_longueur_barre_mm_jamais_reclassee_en_longueur_presumee():
    """longueur_barre_mm n'est PAS dans SECTION_FIELDS : une grande valeur
    ici est déjà une longueur, elle ne doit jamais devenir LONGUEUR_PRESUMEE
    (ce serait une double reclassification absurde)."""
    row = _row(longueur_barre_mm="2500.0")
    results = compare_one(row, {"longueur_barre_mm": 2500.0})
    assert results[0]["statut"] == "VALIDE"
    assert results[0]["cote_catalogue_champ"] == "longueur_barre_mm"


def test_diametre_mm_grand_egalement_reclasse():
    """La règle s'applique à TOUS les champs de SECTION_FIELDS, pas
    seulement cote1/2/3_mm (ex. diametre_mm, cas 20-54 réel : hauteur_mm)."""
    row = _row(diametre_mm="1500.0")
    results = compare_one(row, {"bbox_mm.w": 150.0})
    assert results[0]["statut"] == "LONGUEUR_PRESUMEE"
    assert results[0]["auto"] is True


def test_toutes_les_lignes_portent_la_cle_auto():
    """Garde-fou de schéma CSV : chaque statut existant (VALIDE, ALERTE,
    NON_COMPARABLE, AUCUNE_GEOMETRIE_MESUREE, LONGUEUR_PRESUMEE) doit
    porter la clé 'auto', jamais absente (DictWriter lèverait sinon)."""
    cases = [
        (_row(cote1_mm="100.0"), {"bbox_mm.w": 100.0}),          # VALIDE
        (_row(cote1_mm="100.0"), {"bbox_mm.w": 200.0}),          # ALERTE
        (_row(longueur_barre_mm="500.0"), {"bbox_mm.w": 500.0}),  # NON_COMPARABLE
        (_row(cote1_mm="100.0"), {}),                             # AUCUNE_GEOMETRIE_MESUREE
        (_row(cote1_mm="1200.0"), {"bbox_mm.w": 120.0}),          # LONGUEUR_PRESUMEE
    ]
    for row, geom in cases:
        for r in compare_one(row, geom):
            assert "auto" in r, f"clé 'auto' manquante pour statut={r['statut']}"
            assert isinstance(r["auto"], bool)
