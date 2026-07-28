"""
test_dxf2profile.py — Suite pytest de non-régression sur dxf2profile.py

Utilise les fixtures synthétiques permanentes de tests/fixtures/ :
    TESTOK.dxf      : profil simple en L, INSUNITS=4 (mm) -> doit donner OK
    TESTNOUNIT.dxf  : même profil, $INSUNITS absent -> doit donner ERREUR_UNITES
    TESTAMBIGU.dxf  : deux polylignes fermées de même aire -> ERREUR_SELECTION
    TESTARC.dxf     : profil avec bulge/arc à aplatir -> doit donner OK
    TESTVIDE.dxf    : aucune polyligne fermée exploitable -> ERREUR_SELECTION
    TESTDEDUP.dxf   : profil en L à 8 sommets bruts contenant (1) un sommet
                      colinéaire redondant sur une arête verticale et (2) un
                      doublon exact de fermeture (dernier sommet == premier)
                      -> doit donner OK avec 6 sommets (2 retirés À LA
                      SOURCE par dedupe_consecutive_vertices, pas dans un
                      test/loader en aval). Voir TestDedupSommets ci-dessous.

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


class TestDedupSommets:
    """Vérifie la déduplication À LA SOURCE (dans process_one_dxf, pas dans
    un test ou un loader Dart en aval) des sommets confondus/colinéaires.
    Demande explicite de l'utilisateur : "Un correctif qui vit dans un
    test ne protège pas la production." — donc ces tests vérifient le
    comportement du PIPELINE (process_one_dxf), pas seulement la fonction
    unitaire dedupe_consecutive_vertices (elle-même testée séparément
    ci-dessous par prudence, mais le test qui compte est celui-ci)."""

    def test_fixture_dedup_retire_le_colineaire_et_le_doublon_fermeture(self, tmp_path):
        record, log = _process("TESTDEDUP", tmp_path)
        assert record["statut"] == "OK"
        # 8 sommets bruts dans la fixture -> 6 attendus après dédup (1
        # colinéaire + 1 doublon de fermeture retirés).
        assert len(record["profil_mm"]) == 6
        assert log["nb_sommets_dedup_retires"] == 2

    def test_fixture_dedup_premier_et_dernier_sommet_distincts(self, tmp_path):
        """Le doublon de fermeture ne doit plus exister : premier et
        dernier sommet du profil final doivent être différents."""
        record, _ = _process("TESTDEDUP", tmp_path)
        pts = record["profil_mm"]
        assert pts[0] != pts[-1]

    def test_profil_1000_reel_nb_sommets_reduit_de_50_a_49(self, tmp_path):
        """Non-régression sur le cas RÉEL qui a motivé ce correctif :
        assets/profiles/1000.json avait 50 sommets dont le premier et le
        dernier étaient rigoureusement confondus ((83.0, -30.0) répété) —
        artefact de tracé DXF. Après correctif à la source, le fichier
        source assets/dxf/1000.dxf doit être retraité en 49 sommets, sans
        doublon de fermeture."""
        project_root = Path(__file__).parent.parent.parent
        dxf_path = project_root / "assets" / "dxf" / "1000.dxf"
        assert dxf_path.exists(), f"Fixture réelle manquante: {dxf_path}"
        import dxf2profile as d2p_module

        mapping = d2p_module.load_mapping(Path(__file__).parent / "mapping.csv")
        record, log = d2p_module.process_one_dxf(
            dxf_path, fichier_to_sku=mapping, units_override={}
        )
        assert record["statut"] == "OK"
        assert len(record["profil_mm"]) == 49
        assert log["nb_sommets_dedup_retires"] == 1
        assert record["profil_mm"][0] != record["profil_mm"][-1]

    def test_ezdxf_flattening_duplique_systematiquement_le_sommet_de_fermeture(
        self, tmp_path
    ):
        """Découverte faite en écrivant ce correctif : ezdxf.path.flattening()
        duplique SYSTÉMATIQUEMENT le sommet de fermeture (dernier point ==
        premier point) sur toute polyligne fermée aplatie — pas seulement
        sur le cas 1000.json qui a motivé la demande. TESTOK.dxf (profil
        "propre", sans colinéarité ni doublon dans sa définition source à
        6 sommets) en fournit la preuve : la fixture DXF elle-même n'a que
        6 sommets, mais flatten_entity_to_points() en retourne 7 (doublon
        de fermeture ajouté par ezdxf à l'aplatissement). Ce test
        documente donc explicitement que le correctif profite à TOUS les
        profils OK produits par ce pipeline, pas à un cas isolé."""
        record, log = _process("TESTOK", tmp_path)
        assert record["statut"] == "OK"
        # 6 sommets dans la définition source de la fixture -> 1 retiré
        # (doublon de fermeture ajouté par ezdxf à l'aplatissement).
        assert len(record["profil_mm"]) == 6
        assert log["nb_sommets_dedup_retires"] == 1
        assert record["profil_mm"][0] != record["profil_mm"][-1]


class TestDedupeConsecutiveVerticesUnitaire:
    """Tests unitaires directs sur dedupe_consecutive_vertices (isolés du
    pipeline DXF complet), pour couvrir des cas synthétiques précis sans
    dépendre d'une fixture DXF."""

    def test_doublon_exact_de_fermeture_retire(self):
        pts = [(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)]
        result = d2p.dedupe_consecutive_vertices(pts)
        assert result == [(0, 0), (10, 0), (10, 10), (0, 10)]

    def test_sommet_colineaire_au_milieu_retire(self):
        pts = [(0, 0), (5, 0), (10, 0), (10, 10), (0, 10)]
        result = d2p.dedupe_consecutive_vertices(pts)
        assert result == [(0, 0), (10, 0), (10, 10), (0, 10)]

    def test_sommet_quasi_confondu_sous_tolerance_retire(self):
        pts = [(0, 0), (0.005, 0.002), (10, 0), (10, 10), (0, 10)]
        result = d2p.dedupe_consecutive_vertices(pts)
        assert len(result) == 4

    def test_profil_deja_propre_totalement_inchange(self):
        pts = [(0, 0), (10, 0), (10, 10), (0, 10)]
        result = d2p.dedupe_consecutive_vertices(pts)
        assert result == pts

    def test_jamais_moins_de_3_sommets_par_colinearite(self):
        """Filet de sécurité (étape 2, colinéarité) : un rectangle avec un
        sommet colinéaire ajouté sur CHAQUE côté (8 sommets, dont 4
        colinéaires redondants) doit se réduire aux 4 coins réels, jamais
        moins — même si l'algorithme retirait les colinéaires un par un
        jusqu'à un stade où retirer le suivant ferait descendre sous 3."""
        pts = [
            (0, 0), (5, 0), (10, 0),
            (10, 5), (10, 10),
            (5, 10), (0, 10),
            (0, 5),
        ]
        result = d2p.dedupe_consecutive_vertices(pts)
        assert len(result) >= 3
        assert set(result) == {(0, 0), (10, 0), (10, 10), (0, 10)}

    def test_moins_de_trois_sommets_entree_retournee_telle_quelle(self):
        pts = [(0, 0), (10, 0)]
        result = d2p.dedupe_consecutive_vertices(pts)
        assert result == pts

    def test_ne_fusionne_jamais_deux_sommets_reellement_distants(self):
        """Distance nettement au-dessus de la tolérance (0.01mm) : aucune
        fusion, même si les points sont sur une courbe légèrement
        incurvée (ici volontairement PAS colinéaires, distance point-
        segment > tolérance)."""
        pts = [(0, 0), (5, 1.0), (10, 0), (10, 10), (0, 10)]
        result = d2p.dedupe_consecutive_vertices(pts)
        assert len(result) == 5  # (5, 1.0) est à 1mm de la droite (0,0)-(10,0), pas colinéaire


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
