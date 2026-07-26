"""
test_dxf2profile.py — Suite pytest de non-régression sur dxf2profile.py

Utilise les fixtures synthétiques permanentes de tests/fixtures/ :
    TESTOK.dxf      : profil simple en L, INSUNITS=4 (mm) -> doit donner OK
    TESTNOUNIT.dxf  : même profil, $INSUNITS absent -> doit donner ERREUR_UNITES
    TESTAMBIGU.dxf  : deux polylignes fermées de même aire -> ERREUR_SELECTION
    TESTARC.dxf     : profil avec bulge/arc à aplatir -> doit donner OK
    TESTVIDE.dxf    : aucune polyligne fermée exploitable -> ERREUR_SELECTION

RÈGLE : ces fixtures ne sont JAMAIS supprimées ni modifiées sans validation
explicite (cf. règle permanente en tête de SPEC.md). Toute sortie de test
(JSON/PNG générés pendant l'exécution de cette suite) est écrite dans un
répertoire temporaire (tmp_path pytest), jamais dans assets/.

Lancer avec :
    cd /home/user/flutter_app/tools/dxf_pipeline
    python3 -m pytest test_dxf2profile.py -v
"""

from pathlib import Path

import pytest

import dxf2profile as d2p

FIXTURES_DIR = Path(__file__).parent / "tests" / "fixtures"


def _process(sku, tmp_path, fichier_to_sku=None, units_override=None):
    path = FIXTURES_DIR / f"{sku}.dxf"
    assert path.exists(), f"Fixture manquante: {path} (ne devrait jamais être supprimée)"
    return d2p.process_one_dxf(path, fichier_to_sku=fichier_to_sku or {}, units_override=units_override or {})


class TestReglesUnites:
    def test_insunits_present_donne_ok(self, tmp_path):
        record, log = _process("TESTOK", tmp_path)
        assert record["statut"] == "OK"
        assert record["source"]["insunits"] == 4
        assert record["source"]["origine_unite"] == "header"
        assert record["profil_mm"] != []

    def test_insunits_absent_donne_erreur_unites_sans_profil(self, tmp_path):
        record, log = _process("TESTNOUNIT", tmp_path)
        assert record["statut"] == "ERREUR_UNITES"
        assert record["profil_mm"] == [], "INTERDIT: ne jamais produire un profil quand l'unité est inconnue"

    def test_insunits_absent_propose_unite_par_plausibilite_dans_le_log(self, tmp_path):
        record, log = _process("TESTNOUNIT", tmp_path)
        assert log["proposition_unite"] != "", "La proposition d'unité par plausibilité de bbox doit apparaître dans le log"
        assert log["proposition_motif"] != ""
        assert "80" in log["proposition_motif"]  # bbox native = 80 (dimension max du profil de test)

    def test_units_override_debloque_le_fichier(self, tmp_path):
        override = {"TESTNOUNIT": (4, "confirmé par plan papier original")}
        record, log = _process("TESTNOUNIT", tmp_path, units_override=override)
        assert record["statut"] == "OK"
        assert record["source"]["origine_unite"] == "override"
        assert record["profil_mm"] != []

    def test_batch_continue_apres_erreur_unites(self, tmp_path):
        """Le run ne doit jamais s'arrêter sur un fichier en erreur."""
        _, log1 = _process("TESTNOUNIT", tmp_path)
        assert log1["statut"] == "ERREUR_UNITES"
        # Le fichier suivant doit être traitable normalement (pas d'état corrompu)
        record2, log2 = _process("TESTOK", tmp_path)
        assert record2["statut"] == "OK"


class TestSelectionContour:
    def test_ambiguite_deux_polylignes_meme_aire(self, tmp_path):
        record, log = _process("TESTAMBIGU", tmp_path)
        assert record["statut"] == "ERREUR_SELECTION"
        assert record["profil_mm"] == []
        assert "CONTOUR" in log["message"]
        assert "CONTOUR2" in log["message"]

    def test_aucune_polyligne_fermee(self, tmp_path):
        record, log = _process("TESTVIDE", tmp_path)
        assert record["statut"] == "ERREUR_SELECTION"
        assert record["profil_mm"] == []

    def test_selection_ignore_calques_bruites(self, tmp_path):
        """TESTOK a des calques COTATION/HACHURE en plus du calque CONTOUR :
        la sélection doit ignorer ces calques bruités et ne garder que
        CONTOUR."""
        record, log = _process("TESTOK", tmp_path)
        assert record["statut"] == "OK"
        assert "CONTOUR" in log["message"]


class TestAplatissement:
    def test_arc_aplati_en_segments(self, tmp_path):
        record, log = _process("TESTARC", tmp_path)
        assert record["statut"] == "OK"
        # Le profil source a 4 sommets bruts (dont un bulge) ; après
        # aplatissement à 0.15mm de tolérance, on doit obtenir davantage de
        # sommets (l'arc est décomposé en plusieurs segments).
        assert len(record["profil_mm"]) > 4


class TestOrigineEtGeometrie:
    def test_origine_recalee_sur_mur_et_plafond(self, tmp_path):
        record, log = _process("TESTOK", tmp_path)
        assert record["statut"] == "OK"
        assert record["face_pose_mur"]["auto"] is True
        assert record["face_pose_plafond"]["auto"] is True
        # Face mur doit être à x=0 après recalage
        wall_idx = record["face_pose_mur"]["indices"]
        for i in wall_idx:
            assert abs(record["profil_mm"][i][0]) < 1e-6
        # Face plafond doit être à y=0 après recalage
        ceiling_idx = record["face_pose_plafond"]["indices"]
        for i in ceiling_idx:
            assert abs(record["profil_mm"][i][1]) < 1e-6

    def test_bbox_coherente(self, tmp_path):
        record, log = _process("TESTOK", tmp_path)
        assert record["bbox_mm"]["w"] == 60.0
        assert record["bbox_mm"]["h"] == 80.0


class TestInterdictionSubstitution:
    """Vérifie explicitement la règle : jamais de profil de substitution."""

    @pytest.mark.parametrize("sku", ["TESTNOUNIT", "TESTAMBIGU", "TESTVIDE"])
    def test_erreur_ne_produit_jamais_de_profil(self, sku, tmp_path):
        record, log = _process(sku, tmp_path)
        assert record["statut"] != "OK"
        assert record["profil_mm"] == [], (
            f"INTERDIT (cf. SPEC.md): {sku} est en erreur mais profil_mm "
            f"n'est pas vide -> substitution implicite détectée."
        )
        assert record["prix_ml"] is None
        assert record["marque"] == ""


class TestMappingFichierSku:
    def test_sku_par_defaut_est_le_nom_de_fichier(self, tmp_path):
        """Sans mapping.csv, le sku par défaut est le nom de fichier sans
        extension (comportement de secours explicite, jamais une regex)."""
        record, log = _process("TESTOK", tmp_path)
        assert record["sku"] == "TESTOK"
        assert log["mapping_absent"] is True

    def test_mapping_csv_prioritaire_sur_nom_de_fichier(self, tmp_path):
        fichier_to_sku = {"TESTOK.dxf": "D999-REEL"}
        record, log = _process("TESTOK", tmp_path, fichier_to_sku=fichier_to_sku)
        assert record["sku"] == "D999-REEL"
        assert log["mapping_absent"] is False


if __name__ == "__main__":
    import sys
    sys.exit(pytest.main([__file__, "-v"]))
