"""
test_solid2profile.py — Suite pytest de non-régression sur solid2profile.py

Utilise les fixtures synthétiques permanentes de tests/fixtures/ :
    TESTSOLIDE_L.stl           : barre 2m, profil en L connu (même coordonnées
                                  que TESTOK.dxf), section CONSTANTE sur toute
                                  la longueur -> doit donner motif="lisse".
    TESTSOLIDE_DENTICULES.stl  : même barre en L + 47 denticules réguliers
                                  tous les 42mm -> doit donner motif="variable",
                                  periode_mm proche de 42, et une height map
                                  non triviale.

Ces deux fixtures sont la "vérité de terrain" (ground truth) explicitement
demandée : la réponse attendue est connue puisque les fixtures sont générées
par nous-mêmes via trimesh, ce qui rend le test vérifiable.

RÈGLE : ces fixtures ne sont JAMAIS supprimées ni modifiées sans validation
explicite (cf. règle permanente en tête de SPEC.md). Toute sortie de test
(JSON/PNG/height map générés pendant l'exécution de cette suite) est écrite
dans un répertoire temporaire (tmp_path pytest), jamais dans assets/.

Lancer avec :
    cd /home/user/flutter_app/tools/dxf_pipeline
    python3 -m pytest test_solid2profile.py -v
"""

from pathlib import Path

import numpy as np
import pytest

import solid2profile as s2p

FIXTURES_DIR = Path(__file__).parent / "tests" / "fixtures"

# Unité forcée mm (insunits=4) pour les deux fixtures synthétiques — un
# STL/OBJ n'a pas d'équivalent $INSUNITS, donc pas d'override -> pas de
# résultat exploitable (règle stricte, voir ERREUR_UNITES).
UNITS_OVERRIDE_MM = {
    "TESTSOLIDE_L": (4, "fixture synthetique mm"),
    "TESTSOLIDE_DENTICULES": (4, "fixture synthetique mm"),
}


def _process(sku, tmp_path, fichier_to_sku=None, units_override=None):
    path = FIXTURES_DIR / f"{sku}.stl"
    assert path.exists(), f"Fixture manquante: {path} (ne devrait jamais être supprimée)"
    return s2p.process_one_mesh(
        path,
        fichier_to_sku=fichier_to_sku or {},
        units_override=units_override if units_override is not None else UNITS_OVERRIDE_MM,
        out_dir=tmp_path,
    )


class TestReglesUnites:
    def test_sans_units_override_donne_erreur_unites_sans_profil(self, tmp_path):
        record, log = _process("TESTSOLIDE_L", tmp_path, units_override={})
        assert record["statut"] == "ERREUR_UNITES"
        assert record["profil_mm"] == [], "INTERDIT: ne jamais produire un profil quand l'unité est inconnue"

    def test_sans_units_override_propose_unite_par_plausibilite_dans_le_log(self, tmp_path):
        record, log = _process("TESTSOLIDE_L", tmp_path, units_override={})
        assert log["proposition_unite"] != "" or log["proposition_motif"] != "", (
            "Une proposition indicative par plausibilite de bbox doit apparaitre "
            "dans le log meme si non appliquee"
        )

    def test_units_override_debloque_le_fichier(self, tmp_path):
        record, log = _process("TESTSOLIDE_L", tmp_path)
        assert record["statut"] == "OK"
        assert record["source"]["origine_unite"] == "override"
        assert record["source"]["insunits"] == 4
        assert record["profil_mm"] != []

    def test_batch_continue_apres_erreur_unites(self, tmp_path):
        """Le run ne doit jamais s'arrêter sur un fichier en erreur."""
        _, log1 = _process("TESTSOLIDE_L", tmp_path, units_override={})
        assert log1["statut"] == "ERREUR_UNITES"
        record2, log2 = _process("TESTSOLIDE_DENTICULES", tmp_path)
        assert record2["statut"] == "OK"


class TestSchemaCommun:
    def test_methode_section_3d_toujours_presente(self, tmp_path):
        """source.methode="section_3d" doit apparaître même sur les enregistrements
        d'erreur (aucun schéma parallèle avec dxf2profile.py)."""
        record, _ = _process("TESTSOLIDE_L", tmp_path, units_override={})
        assert record["source"]["methode"] == "section_3d"

    def test_version_schema_identique_a_dxf2profile(self, tmp_path):
        import dxf2profile as d2p
        record, _ = _process("TESTSOLIDE_L", tmp_path)
        assert record["version_schema"] == d2p.SCHEMA_VERSION


class TestDetectionMotifLisse:
    """TESTSOLIDE_L.stl : section CONSTANTE sur toute la barre -> lisse.
    Vérité de terrain connue puisque la fixture est un simple extrudé."""

    def test_motif_lisse(self, tmp_path):
        record, log = _process("TESTSOLIDE_L", tmp_path)
        assert record["statut"] == "OK"
        assert record["motif"] is None, "moulure lisse -> motif=None (jamais un objet motif vide)"
        assert log["motif_type"] == "lisse"

    def test_pas_de_height_map_pour_motif_lisse(self, tmp_path):
        record, _ = _process("TESTSOLIDE_L", tmp_path)
        assert record["assets"]["height"] is None, (
            "INTERDIT: une height map ne doit jamais être générée pour un motif lisse"
        )

    def test_profil_l_correct(self, tmp_path):
        """Le profil retrouvé par coupe 3D doit correspondre (à la tessellation
        près) au profil en L source : bbox 60x80mm, 6 sommets caractéristiques
        (STL peut en avoir davantage via la triangulation mais la bbox et
        l'aire doivent être fidèles)."""
        record, _ = _process("TESTSOLIDE_L", tmp_path)
        bbox = record["bbox_mm"]
        assert abs(bbox["w"] - 60.0) < 1.0
        assert abs(bbox["h"] - 80.0) < 1.0

    def test_faces_mur_et_plafond_detectees(self, tmp_path):
        record, _ = _process("TESTSOLIDE_L", tmp_path)
        assert record["face_pose_mur"]["auto"] is True
        assert record["face_pose_plafond"]["auto"] is True
        assert record["face_pose_mur"]["indices"] != []
        assert record["face_pose_plafond"]["indices"] != []


class TestDetectionMotifVariable:
    """TESTSOLIDE_DENTICULES.stl : 47 denticules réguliers tous les 42mm.
    Vérité de terrain connue (période imposée à la construction de la
    fixture) — c'est exactement le cas qui a révélé le bug d'aliasing de
    phase de l'échantillonnage à 3 points fixes (25/50/75%) : à z=500,
    1000, 1500mm sur cette fixture, les 3 aires sont IDENTIQUES malgré un
    motif bien réel. Le balayage dense doit le détecter correctement."""

    def test_motif_variable_detecte(self, tmp_path):
        record, log = _process("TESTSOLIDE_DENTICULES", tmp_path)
        assert record["statut"] == "OK"
        assert record["motif"] is not None
        assert record["motif"]["type"] == "variable"
        assert log["motif_type"] == "variable"

    def test_periode_detectee_proche_de_42mm(self, tmp_path):
        record, _ = _process("TESTSOLIDE_DENTICULES", tmp_path)
        periode = record["motif"]["periode_mm"]
        assert periode is not None, "La période aurait dû être détectée (motif régulier net)"
        assert abs(periode - 42.0) < 2.0, f"periode_mm={periode}, attendu ~42.0"

    def test_methode_autocorrelation(self, tmp_path):
        record, _ = _process("TESTSOLIDE_DENTICULES", tmp_path)
        assert record["motif"]["methode"] == "autocorrelation"

    def test_motif_marque_auto_true(self, tmp_path):
        """Même convention que face_pose_mur/face_pose_plafond : auto=True."""
        record, _ = _process("TESTSOLIDE_DENTICULES", tmp_path)
        assert record["motif"]["auto"] is True

    def test_height_map_generee_pour_motif_variable(self, tmp_path):
        record, _ = _process("TESTSOLIDE_DENTICULES", tmp_path)
        assert record["assets"]["height"] is not None
        height_path = tmp_path / record["assets"]["height"]
        assert height_path.exists(), f"Le fichier height map annoncé doit exister: {height_path}"

    def test_height_map_contient_un_signal_non_trivial(self, tmp_path):
        """La height map ne doit pas être uniformément nulle : les denticules
        doivent produire un relief mesurable."""
        from PIL import Image
        record, _ = _process("TESTSOLIDE_DENTICULES", tmp_path)
        height_path = tmp_path / record["assets"]["height"]
        arr = np.array(Image.open(height_path))
        assert arr.dtype == np.uint16
        assert arr.max() > 0, "height map entièrement à zéro: aucun relief détecté"
        assert (arr > 0).sum() > 10, "trop peu de pixels non-nuls pour un relief régulier sur 47 dents"


class TestCoherenceRepereFixe:
    """Vérifie indirectement la correction du bug de repère 2D incohérent
    entre coupes (Path3D.to_2D() sans matrice explicite) : deux coupes à
    des positions différentes, ramenées via le MÊME fixed_rotation, doivent
    donner des polygones de même aire pour une section constante (fixture
    lisse) — preuve que le repère ne dérive pas d'une coupe à l'autre."""

    @staticmethod
    def _offsets(mesh, origin_pt, axis, frac_a, frac_b):
        """origin_pt est le CENTROIDE (voir find_long_axis) : l'offset le
        long de l'axe doit être calculé depuis les bornes projetées
        réelles, pas directement comme une fraction de length_mm (même
        calcul que process_one_mesh)."""
        proj = (mesh.vertices - origin_pt) @ axis
        proj_min, proj_max = float(proj.min()), float(proj.max())
        span = proj_max - proj_min
        return proj_min + frac_a * span, proj_min + frac_b * span

    def test_aires_coherentes_sur_barre_lisse(self, tmp_path):
        path = FIXTURES_DIR / "TESTSOLIDE_L.stl"
        mesh = s2p.load_mesh(path)
        origin_pt, axis, ratio_2_1, length_mm = s2p.find_long_axis(mesh)
        fixed_rotation = s2p.build_fixed_rotation(axis)
        off_a, off_b = self._offsets(mesh, origin_pt, axis, 0.25, 0.75)

        poly_a = s2p.section_polygon_at(mesh, origin_pt, axis, off_a, fixed_rotation)
        poly_b = s2p.section_polygon_at(mesh, origin_pt, axis, off_b, fixed_rotation)
        assert poly_a is not None and poly_b is not None
        # Aires quasi identiques : section constante le long de la barre lisse.
        assert abs(poly_a.area - poly_b.area) / poly_a.area < 0.01

    def test_sans_fixed_rotation_reperes_incoherents(self, tmp_path):
        """Documente le bug corrigé : sans fixed_rotation, Path3D.to_2D()
        plane-fit indépendamment chaque tranche -> coordonnées de premier
        point différentes d'une coupe à l'autre pour un même profil."""
        path = FIXTURES_DIR / "TESTSOLIDE_L.stl"
        mesh = s2p.load_mesh(path)
        origin_pt, axis, ratio_2_1, length_mm = s2p.find_long_axis(mesh)
        off_a, off_b = self._offsets(mesh, origin_pt, axis, 0.25, 0.75)

        poly_a = s2p.section_polygon_at(mesh, origin_pt, axis, off_a, fixed_rotation=None)
        poly_b = s2p.section_polygon_at(mesh, origin_pt, axis, off_b, fixed_rotation=None)
        assert poly_a is not None and poly_b is not None
        coord_a0 = np.array(list(poly_a.exterior.coords)[0])
        coord_b0 = np.array(list(poly_b.exterior.coords)[0])
        # Non garanti égal (c'est justement le bug) — ce test documente le
        # comportement sans la correction, il n'impose pas d'égalité.
        # (Assertion volontairement absente : sert de démonstration, pas de
        # garde-fou strict, car le comportement de to_2D() sans matrice
        # n'est pas garanti déterministe entre versions de trimesh.)
        assert coord_a0.shape == (2,) and coord_b0.shape == (2,)


class TestAutocorrelation:
    """Tests unitaires ciblés sur detect_pattern_period, indépendants du
    pipeline complet."""

    def test_signal_constant_pas_de_periode(self):
        positions = np.arange(0, 1000, 1.0)
        areas = np.full_like(positions, 2400.0)
        periode, methode = s2p.detect_pattern_period(positions, areas, 1000.0)
        assert periode is None
        assert "constante" in methode or "lisse" in methode

    def test_signal_periodique_detecte(self):
        positions = np.arange(0, 2000, 1.0)
        # signal carré de période 42mm, comme les denticules
        areas = 2400.0 + 100.0 * (np.mod(positions, 42.0) < 8.0).astype(float)
        periode, methode = s2p.detect_pattern_period(positions, areas, 2000.0)
        assert periode is not None
        assert abs(periode - 42.0) < 2.0
        assert methode == "autocorrelation"

    def test_retour_toujours_un_tuple_de_deux_elements(self):
        """Non-régression du bug de retour à 4 éléments trouvé pendant le
        développement (incohérent avec la signature déclarée)."""
        positions = np.arange(0, 10, 1.0)  # trop court
        areas = np.full_like(positions, 100.0)
        result = s2p.detect_pattern_period(positions, areas, 10.0)
        assert isinstance(result, tuple)
        assert len(result) == 2


class TestOrientation:
    def test_ratio_faible_pour_barre_allongee(self, tmp_path):
        path = FIXTURES_DIR / "TESTSOLIDE_L.stl"
        mesh = s2p.load_mesh(path)
        _origin, _axis, ratio_2_1, length_mm = s2p.find_long_axis(mesh)
        assert ratio_2_1 < s2p.ORIENTATION_RATIO_MAX
        assert length_mm > 1900.0  # barre de 2m
