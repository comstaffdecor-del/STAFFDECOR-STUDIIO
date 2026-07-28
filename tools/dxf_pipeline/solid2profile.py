#!/usr/bin/env python3
"""
solid2profile.py — Extraction de profil produit depuis un MAILLAGE 3D
(STL/OBJ, exporté depuis un 3DSOLID ACIS) -> JSON + PNG + height map

CONTEXTE : de nombreux DXF fabricants Staff Décor ne contiennent aucune
polyligne 2D de coupe (voir dxf2profile.py, statut ERREUR_SELECTION) mais
un modèle 3DSOLID volumique. Ce n'est pas un échec : le volume contient
le galbe ET le relief des ornements — une source plus riche qu'un profil
2D. On ne cherche pas la coupe, on la CALCULE par section planaire du
maillage.

ENTRÉE : un maillage (STL binaire de préférence, OBJ accepté), obtenu par
conversion 3DSOLID -> maillage FAITE HORS DE CE SCRIPT (AutoCAD/BricsCAD
uniquement — voir ALERTE ci-dessous), jamais ici.

⚠️ ALERTE OUTIL (cf. SPEC.md) : ni FreeCAD ni ODA File Converter ne
savent lire un 3DSOLID ACIS (format propriétaire Autodesk). Seul
AutoCAD/BricsCAD peut exporter un STL/OBJ depuis un 3DSOLID. Ne jamais
recommander FreeCAD pour cette étape de conversion.

Produit, par SKU :
  - assets/profiles/<sku>.json         (MÊME schéma que dxf2profile.py,
    version_schema 1 — aucun schéma parallèle. source.methode="section_3d".)
  - assets/profiles/control/<sku>.png  (PNG coté du profil de coupe)
  - assets/profiles/heightmaps/<sku>_height.png (PNG 16 bits, si motif
    variable détecté — assets.height dans le JSON)
  - une ligne de log dans tools/dxf_pipeline/logs/run_<timestamp>.csv

RÈGLES (mêmes principes que dxf2profile.py, cf. SPEC.md) :

1. UNITÉS : un maillage STL/OBJ ne porte pas d'équivalent $INSUNITS
   fiable (STL est nativement sans unité). Priorité : units_override.csv
   (par sku ou nom de fichier) — si absent, ERREUR_UNITES, PROPOSITION
   par plausibilité de bbox consignée dans le log (jamais appliquée),
   profil_mm vide. LE BATCH NE S'ARRÊTE PAS.

2. ORIENTATION : axe long de la barre trouvé par ACP (PCA) sur les
   sommets du maillage — l'axe propre associé à la plus grande valeur
   propre est l'axe d'extrusion. Si le maillage n'est pas nettement
   allongé (rapport 2e/1re valeur propre > 0.5, barre "presque cubique"),
   -> ERREUR_ORIENTATION, profil_mm vide. LE BATCH CONTINUE.

3. COUPE : mesh.section(plane_origin=..., plane_normal=axe long) ->
   Path3D -> to_2D(to_2D=matrice FIXE, voir build_fixed_rotation) ->
   polygone 2D. L'aire de section est échantillonnée par un BALAYAGE
   DENSE le long de l'axe long (résolution AUTOCORR_STEP_MM, voir
   sample_areas_along_axis) — PAS un échantillonnage à 3 abscisses fixes
   (25/50/75%), rejeté après vérification empirique : un motif
   périodique dont la période ne s'aligne pas par hasard avec ces 3
   fractions peut être manqué en totalité (ex. période 42mm sur une
   barre de 2000mm -> les 3 points tombent tous en zone lisse). Décision
   lisse/varié à partir de l'écart (max-min)/moyenne des aires valides du
   balayage (tolérance relative, voir AIRE_TOL_RELATIF) :
   - aires quasi constantes -> moulure lisse, on garde la coupe la plus
     proche du milieu de la barre comme profil.
   - aires variables -> moulure ORNÉE. motif.type="variable", profil de
     pose = UNION (pas enveloppe convexe — une corniche a des gorges
     concaves que le convexe effacerait, détruisant le galbe réel) des
     coupes aux positions d'aire minimale, maximale et médiane RÉELLEMENT
     LOCALISÉES par le balayage (jamais des fractions arbitraires).
     motif.profil_source="union_sections".
   0 coupe valide sur le balayage -> ERREUR_SELECTION, profil_mm vide.
   LE BATCH CONTINUE.

4. ORIGINE : recalée à x=0 sur la face mur, y=0 sur la face plafond —
   même heuristique géométrique que dxf2profile.py
   (detect_wall_and_ceiling_faces, réutilisée telle quelle).

5. INTERDICTION : ne jamais compléter, lisser, ou "corriger" un profil.
   Toute ambiguïté/erreur -> statut d'erreur + profil_mm vide, jamais un
   profil de substitution.

6. Un PNG de contrôle coté est produit uniquement pour statut == OK
   (même style que dxf2profile.py : contour + faces mur/plafond
   surlignées + titre avec méthode="section_3d").

7. Log détaillé par fichier (nb sommets, bbox mm, hauteur mur, projection
   plafond, + colonnes spécifiques : motif_type, motif_periode_mm) + un
   CSV récapitulatif du run (même dossier logs/ que dxf2profile.py).

8. CORRESPONDANCE FICHIER -> SKU : lue depuis mapping.csv, jamais
   déduite par regex. Si le fichier n'y figure pas, sku = nom de fichier
   sans extension (comportement de secours explicite, signalé).

9. MOTIF VARIABLE — PÉRIODE : quand les 3 coupes diffèrent, la période
   du motif (motif.periode_mm) est estimée par AUTOCORRÉLATION de l'aire
   de section échantillonnée le long de l'axe long (voir
   detect_pattern_period). motif.methode = "autocorrelation". Si aucun
   pic net n'est trouvé, motif.periode_mm reste null (jamais une valeur
   inventée) et motif.methode le signale.

10. HEIGHT MAP : pour un motif variable, une carte de hauteur (distance
    à la face de pose, échantillonnée sur une grille axe_long x
    circonférence_profil) est exportée en PNG 16 bits
    (assets/profiles/heightmaps/<sku>_height.png), référencée dans
    assets.height. Base de la normal map du rendu (hors scope de ce
    script). Jamais générée pour un motif lisse (assets.height reste
    null).

Usage:
    # Lot explicite (SKU choisis, résolus via mapping.csv) :
    python3 solid2profile.py --mesh-dir /home/user/flutter_app/assets/solids \\
        --sku 0900 1005 --out-dir /home/user/flutter_app/assets/profiles

    # Batch complet (tous les .stl/.obj du dossier) :
    python3 solid2profile.py --mesh-dir /home/user/flutter_app/assets/solids --all \\
        --out-dir /home/user/flutter_app/assets/profiles

    # Test de validation sur fixtures synthétiques (voir tests/) :
    python3 solid2profile.py --mesh-dir tools/dxf_pipeline/tests/fixtures \\
        --sku TESTSOLIDE_L TESTSOLIDE_DENTICULES \\
        --units-override tests/fixtures/units_override_test.csv \\
        --out-dir /tmp/solid2profile_test
"""

import argparse
import csv
import datetime as dt
import json
import sys
from pathlib import Path

try:
    import numpy as np
except ImportError:
    print("ERREUR: le module 'numpy' n'est pas installé. pip install numpy", file=sys.stderr)
    sys.exit(1)

try:
    import trimesh
except ImportError:
    print(
        "ERREUR: le module 'trimesh' n'est pas installé. "
        "pip install trimesh shapely rtree manifold3d",
        file=sys.stderr,
    )
    sys.exit(1)

try:
    from shapely.geometry import Polygon
    from shapely.ops import unary_union
except ImportError:
    print("ERREUR: le module 'shapely' n'est pas installé. pip install shapely", file=sys.stderr)
    sys.exit(1)

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ImportError:
    plt = None  # PNG de contrôle désactivé si matplotlib absent (signalé au run)

try:
    from PIL import Image
except ImportError:
    Image = None  # height map désactivée si PIL absent (signalé au run)

try:
    from scipy.signal import find_peaks
except ImportError:
    find_peaks = None  # détection de période désactivée si scipy absent (signalé)


# --- Import direct des utilitaires PARTAGÉS avec dxf2profile.py : même
# schéma JSON, même logique de faces mur/plafond, même mapping.csv/
# units_override.csv. Aucune réimplémentation divergente. ---
sys.path.insert(0, str(Path(__file__).parent))
import dxf2profile as d2p  # noqa: E402


SCHEMA_VERSION = d2p.SCHEMA_VERSION  # 1 — même schéma, aucune bascule ici
DEFAULT_BAR_LENGTH_MM = d2p.DEFAULT_BAR_LENGTH_MM

# Tolérance relative pour juger deux aires de coupe "identiques" (moulure
# lisse) vs "différentes" (moulure ornée). 3% : au-delà, on considère qu'il
# ne s'agit plus d'un simple bruit de tessellation.
AIRE_TOL_RELATIF = 0.03

# Rapport (2e valeur propre / 1re valeur propre) au-delà duquel le
# maillage n'est plus considéré comme une barre nettement allongée.
ORIENTATION_RATIO_MAX = 0.5

# Nombre d'échantillons pour la détection de période par autocorrélation
# (résolution en mm le long de l'axe long).
AUTOCORR_STEP_MM = 1.0

# Résolution de la height map (mm entre deux échantillons, le long de
# l'axe long et le long de la circonférence du profil).
HEIGHTMAP_STEP_LONG_MM = 2.0
HEIGHTMAP_STEP_PROFIL = 128  # nombre d'échantillons autour du profil

# Plage de conversion des distances (mm) en niveaux de gris 16 bits pour
# la height map — 0..HEIGHTMAP_MAX_MM mm -> 0..65535.
HEIGHTMAP_MAX_MM = 50.0


def load_mesh(path: Path):
    """Charge un maillage STL/OBJ. Retourne un trimesh.Trimesh unique
    (concatène si le fichier contient une Scene multi-géométries — un
    3DSOLID exporté peut produire plusieurs sous-maillages)."""
    loaded = trimesh.load(str(path), force="mesh")
    if isinstance(loaded, trimesh.Scene):
        geoms = list(loaded.geometry.values())
        if not geoms:
            raise ValueError("Scene vide, aucune géométrie exploitable")
        loaded = trimesh.util.concatenate(geoms)
    return loaded


def find_long_axis(mesh) -> tuple:
    """ACP sur les sommets du maillage. Retourne (origin, axis, ratio_2_1,
    length_mm) où axis est le vecteur unitaire de l'axe long (plus grande
    valeur propre), ratio_2_1 le rapport de la 2e à la 1re valeur propre
    (barre bien allongée si << 1), length_mm l'étendue du maillage
    projetée sur cet axe.

    origin : ⚠️ PIÈGE DÉTECTÉ ET CORRIGÉ pendant le développement — un
    4e bug de repère, distinct des trois autres (cf. CONVENTIONS.md côté
    Dart pour l'inventaire complet). `origin` N'EST PAS le centroïde du
    maillage : c'est le point du maillage à l'extrémité MINIMALE de sa
    projection sur `axis` (le vrai début de la barre). Tout le reste du
    module (sample_areas_along_axis, build_height_map, la sélection
    min/max/médiane dans process_one_mesh) utilise un offset dans
    `[0, length_mm]` MESURÉ DEPUIS `origin` — si `origin` était le
    centroïde (offset 0 = milieu de la barre, comme une première version
    de cette fonction le faisait), la moitié des offsets de
    `sample_areas_along_axis`/`build_height_map` (ceux > length_mm/2)
    tomberait hors du maillage réel dès que le centroïde ACP n'est pas
    exactement au milieu géométrique de la projection (ce qui est le cas
    général, pas un cas limite) — vérifié empiriquement sur
    TESTSOLIDE_DENTICULES : centroïde à proj=0, mais proj réelle
    ∈ [-987.4, +1012.6] (pas symétrique), donc tout offset > 1012.6
    (la moitié des 1921 échantillons du balayage dense) sortait du
    maillage et produisait une height map à moitié nulle."""
    verts = mesh.vertices
    centroid = verts.mean(axis=0)
    centered = verts - centroid
    cov = np.cov(centered.T)
    eigvals, eigvecs = np.linalg.eigh(cov)  # ordre croissant
    order = np.argsort(eigvals)[::-1]
    eigvals = eigvals[order]
    eigvecs = eigvecs[:, order]
    axis = eigvecs[:, 0]
    axis = axis / np.linalg.norm(axis)

    ratio_2_1 = float(eigvals[1] / eigvals[0]) if eigvals[0] > 1e-12 else 1.0

    proj = centered @ axis
    length_mm = float(proj.max() - proj.min())
    # origin = extrémité réelle de la barre (proj minimale), pas le
    # centroïde — voir docstring ci-dessus.
    origin = centroid + float(proj.min()) * axis

    return origin, axis, ratio_2_1, length_mm


def build_fixed_rotation(axis):
    """Construit la matrice de rotation 3x3 FIXE qui ramène le plan de
    normale `axis` sur le plan XY. Cette rotation ne dépend QUE de `axis`
    (jamais des points de la tranche courante) — c'est ce qui garantit
    que toutes les coupes le long de la barre partagent le MÊME repère
    2D (même orientation, pas de rotation/dérive aléatoire d'une tranche
    à l'autre).

    ⚠️ PIÈGE DÉTECTÉ ET CORRIGÉ pendant le développement : `Path3D.to_2D()`
    sans matrice explicite fait un `plane_fit` sur les seuls points de la
    tranche courante -> chaque coupe obtient une origine et une rotation
    LÉGÈREMENT DIFFÉRENTES (vérifié empiriquement : mêmes coordonnées de
    profil, mais décalées/tournées entre deux coupes voisines). Une union
    shapely entre deux polygones ainsi mal alignés produit un résultat
    géométriquement faux. D'où cette fonction : une seule rotation, calculée
    une fois, réutilisée pour toutes les coupes d'un même maillage.
    """
    from trimesh.geometry import plane_transform
    transform = plane_transform(origin=[0.0, 0.0, 0.0], normal=axis)
    return transform[:3, :3]


def section_polygon_at(mesh, origin_pt, axis, offset_along_axis: float, fixed_rotation=None):
    """Coupe le maillage au plan passant par (origin_pt + offset*axis),
    normal=axis. Retourne un shapely.Polygon (le plus grand si plusieurs
    boucles disjointes — cas d'un profil creux ou de bavures de
    tessellation) ou None si aucune section valide.

    fixed_rotation : matrice 3x3 (voir build_fixed_rotation) — si fournie,
    impose le MÊME repère 2D à toutes les coupes d'un même maillage
    (indispensable pour comparer/unir plusieurs coupes entre elles, voir
    docstring de build_fixed_rotation)."""
    plane_origin = origin_pt + offset_along_axis * axis
    try:
        section = mesh.section(plane_origin=plane_origin, plane_normal=axis)
    except Exception:
        return None
    if section is None:
        return None
    try:
        if fixed_rotation is not None:
            to_2d = np.eye(4)
            to_2d[:3, :3] = fixed_rotation
            to_2d[:3, 3] = -fixed_rotation @ plane_origin
            planar, _to_3d = section.to_2D(to_2D=to_2d, check=False)
        else:
            planar, _to_3d = section.to_2D()
    except Exception:
        return None

    polys = planar.polygons_full
    if not polys:
        return None
    # Le plus grand polygone (aire) — même logique que dxf2profile.py
    # (plus grande aire = contour de coupe, pas un artefact de bavure).
    best = max(polys, key=lambda p: p.area)
    if best.is_empty or best.area <= 0:
        return None
    return best


def sample_areas_along_axis(mesh, origin_pt, axis, length_mm, fixed_rotation):
    """Échantillonne l'aire de section tous les AUTOCORR_STEP_MM le long de
    l'axe long. Retourne (positions, areas) — areas peut contenir des NaN
    pour les positions où la coupe a échoué (comblées ensuite par
    interpolation dans detect_pattern_period, jamais utilisées seules pour
    juger lisse/varié).

    Ce balayage dense remplace un échantillonnage à 3 points fixes
    (25/50/75%), délibérément rejeté après vérification empirique : avec
    une période de motif qui ne s'aligne pas par hasard sur ces 3
    fractions (ex. period=42mm sur une barre de 2000mm), les 3 points
    peuvent TOUS tomber en zone lisse et manquer complètement un motif
    ornemental bien réel. Le balayage dense élimine ce risque d'aliasing
    de phase."""
    margin = max(length_mm * 0.02, 2.0)  # évite les faces d'extrémité
    positions = np.arange(margin, length_mm - margin, AUTOCORR_STEP_MM)
    areas = np.empty(len(positions), dtype=np.float64)
    for i, pos in enumerate(positions):
        poly = section_polygon_at(mesh, origin_pt, axis, pos, fixed_rotation)
        areas[i] = poly.area if poly is not None else np.nan
    return positions, areas


def detect_pattern_period(positions, areas, length_mm) -> tuple:
    """Autocorrélation de l'aire de section le long de l'axe long (déjà
    échantillonnée par sample_areas_along_axis, réutilisée pour éviter de
    recouper le maillage deux fois). Retourne (periode_mm | None,
    methode_str). Ne devine jamais une période sans pic net (voir seuil
    de proéminence ci-dessous) : dans ce cas periode_mm=None et
    methode_str l'explique."""
    if find_peaks is None:
        return None, "autocorrelation_indisponible (scipy absent)"
    if positions is None or len(positions) < 8:
        return None, "trop court pour autocorrelation (< 8 echantillons)"

    valid = ~np.isnan(areas)
    if valid.sum() < 8:
        return None, "trop peu de coupes valides pour autocorrelation"

    areas_filled = np.copy(areas)
    if not valid.all():
        # Comblement ponctuel par interpolation linéaire (données
        # manquantes = coupe ratée localement, pas une modification du
        # signal) ; jamais utilisé pour le profil lui-même, seulement pour
        # la détection de période.
        areas_filled[~valid] = np.interp(
            positions[~valid], positions[valid], areas[valid]
        )

    signal = areas_filled - areas_filled.mean()
    if np.allclose(signal, 0.0):
        return None, "aire de section constante (moulure lisse), pas de periode a detecter"

    autocorr = np.correlate(signal, signal, mode="full")
    autocorr = autocorr[len(autocorr) // 2:]  # ne garder que les décalages >= 0
    autocorr /= autocorr[0]  # normalisation

    # On ignore le décalage 0 (pic trivial) et on cherche le premier pic
    # net suivant.
    min_period_samples = max(int(3.0 / AUTOCORR_STEP_MM), 2)  # période plausible >= 3mm
    peaks, properties = find_peaks(
        autocorr[min_period_samples:], prominence=0.15
    )
    if len(peaks) == 0:
        return None, "aucun pic d'autocorrelation net (prominence insuffisante)"

    best_peak_idx = peaks[0] + min_period_samples
    periode_mm = round(float(best_peak_idx * AUTOCORR_STEP_MM), 3)
    return periode_mm, "autocorrelation"


def build_height_map(mesh, origin_pt, axis, length_mm, profile_2d_points_native, fixed_rotation):
    """Construit une height map (distance à la face de pose, échantillonnée
    sur une grille axe_long x pourtour_profil). Retourne un tableau numpy
    uint16 (H, W) ou None si non calculable (maillage non watertight pour
    le ray casting, ou PIL/dépendances absentes — signalé à l'appelant).

    Méthode : pour chaque position le long de l'axe long et chaque point
    du profil de référence (échantillonné régulièrement sur son pourtour),
    on lance un rayon depuis un point légèrement en retrait de la face de
    pose vers l'extérieur, dans la direction normale locale au profil, et
    on mesure la distance jusqu'au premier impact sur le maillage réel.
    Cette distance est la "hauteur" du relief à cet endroit.

    fixed_rotation : la MÊME matrice que celle utilisée par
    section_polygon_at pour produire `profile_2d_points_native` (via
    build_fixed_rotation). ⚠️ PIÈGE DÉTECTÉ pendant le développement (même
    famille que le bug de section_polygon_at) : reconstruire ici une base
    (u, v) perpendiculaire à `axis` de façon INDÉPENDANTE (ex. par un
    produit vectoriel arbitraire) ne garantit PAS de retomber sur le même
    repère que celui utilisé pour extraire les points 2D du profil — cela
    replacerait le profil dans le maillage 3D avec une rotation
    arbitraire autour de l'axe long, donc au mauvais endroit. La relation
    correcte (R étant une rotation orthogonale) est : u = R[0,:], v =
    R[1,:] — ce sont les vecteurs 3D qui, sous R, retombent respectivement
    sur les axes x et y du plan de coupe 2D. D'où l'obligation de recevoir
    `fixed_rotation` en paramètre plutôt que de la reconstruire ici.
    """
    if Image is None or profile_2d_points_native is None or len(profile_2d_points_native) < 3:
        return None

    n_long = max(int(length_mm / HEIGHTMAP_STEP_LONG_MM), 2)
    positions = np.linspace(2.0, length_mm - 2.0, n_long)

    # Base (u, v) DÉRIVÉE de fixed_rotation (voir docstring ci-dessus) —
    # jamais reconstruite indépendamment, pour rester dans le MÊME repère
    # que celui utilisé pour extraire profile_2d_points_native.
    u = np.asarray(fixed_rotation)[0, :]
    v = np.asarray(fixed_rotation)[1, :]

    pts = np.array(profile_2d_points_native)
    n_profil = min(HEIGHTMAP_STEP_PROFIL, len(pts))
    idx_sample = np.linspace(0, len(pts) - 1, n_profil).astype(int)
    profil_sample = pts[idx_sample]

    # Normales locales au profil (perpendiculaire au segment local, dans
    # le plan de coupe), pointant vers l'extérieur (loin du centroïde).
    centroid_2d = pts.mean(axis=0)
    normals_2d = []
    n_pts = len(profil_sample)
    for i in range(n_pts):
        p_prev = profil_sample[(i - 1) % n_pts]
        p_next = profil_sample[(i + 1) % n_pts]
        tangent = p_next - p_prev
        normal = np.array([-tangent[1], tangent[0]])
        norm = np.linalg.norm(normal)
        if norm < 1e-9:
            normals_2d.append(np.array([0.0, 0.0]))
            continue
        normal /= norm
        # orientation vers l'extérieur : si elle pointe vers le centroïde, inverser
        to_centroid = centroid_2d - profil_sample[i]
        if np.dot(normal, to_centroid) > 0:
            normal = -normal
        normals_2d.append(normal)

    heights = np.zeros((n_long, n_profil), dtype=np.float64)
    ray_origins = []
    ray_directions = []
    for zi, z in enumerate(positions):
        base_pt = origin_pt + z * axis
        for pi in range(n_profil):
            p2d = profil_sample[pi]
            n2d = normals_2d[pi]
            world_pt = base_pt + p2d[0] * u + p2d[1] * v
            world_normal = n2d[0] * u + n2d[1] * v
            # Recul de 1mm dans la direction opposée à la normale pour
            # partir de l'intérieur du solide et sortir par le relief.
            ray_origins.append(world_pt - world_normal * 1.0)
            ray_directions.append(world_normal)

    ray_origins = np.array(ray_origins)
    ray_directions = np.array(ray_directions)

    try:
        locations, index_ray, _index_tri = mesh.ray.intersects_location(
            ray_origins, ray_directions, multiple_hits=False
        )
    except Exception:
        return None  # backend ray-casting indisponible (ex: rtree absent)

    dist_by_ray = np.full(len(ray_origins), np.nan)
    if len(locations) > 0:
        dists = np.linalg.norm(locations - ray_origins[index_ray], axis=1)
        dist_by_ray[index_ray] = dists

    dist_by_ray = np.nan_to_num(dist_by_ray, nan=0.0)
    heights = dist_by_ray.reshape(n_long, n_profil)

    heights_clamped = np.clip(heights, 0.0, HEIGHTMAP_MAX_MM)
    heights_16bit = (heights_clamped / HEIGHTMAP_MAX_MM * 65535.0).astype(np.uint16)
    return heights_16bit


def write_height_map_png(heights_16bit, out_path: Path):
    if Image is None or heights_16bit_is_none(heights_16bit):
        return None
    img = Image.fromarray(heights_16bit)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    return out_path


def heights_16bit_is_none(arr):
    return arr is None


def process_one_mesh(path: Path, fichier_to_sku=None, units_override=None,
                      out_dir: Path = None):
    """Traite un fichier maillage (STL/OBJ). Retourne (record_dict, log_dict).

    Ne lève jamais d'exception hors de cette fonction pour un fichier
    individuel : toute erreur est capturée et transformée en statut
    d'erreur, afin que le batch puisse toujours continuer sur les fichiers
    suivants (même contrat que dxf2profile.process_one_dxf).
    """
    fichier_to_sku = fichier_to_sku or {}
    units_override = units_override or {}

    mapping_absent = path.name not in fichier_to_sku
    sku = fichier_to_sku.get(path.name, path.stem)

    log = {
        "sku": sku,
        "fichier": path.name,
        "mapping_absent": mapping_absent,
        "statut": "",
        "nb_sommets": 0,
        "nb_sommets_dedup_retires": 0,
        "bbox_w_mm": "",
        "bbox_h_mm": "",
        "hauteur_mur_mm": "",
        "projection_plafond_mm": "",
        "motif_type": "",
        "motif_periode_mm": "",
        "insunits": "",
        "proposition_unite": "",
        "proposition_motif": "",
        "message": "",
    }

    try:
        mesh = load_mesh(path)
    except Exception as e:  # noqa: BLE001
        log["statut"] = "ERREUR_LECTURE"
        log["message"] = f"{type(e).__name__}: {e}"
        rec = d2p.build_error_record(sku, path.name, "ERREUR_LECTURE", None, log["message"])
        rec["source"]["methode"] = "section_3d"
        return rec, log

    if len(mesh.vertices) < 4 or len(mesh.faces) < 4:
        msg = f"Maillage {path.name} vide ou degenere ({len(mesh.vertices)} sommets, {len(mesh.faces)} faces)."
        log["statut"] = "ERREUR_LECTURE"
        log["message"] = msg
        rec = d2p.build_error_record(sku, path.name, "ERREUR_LECTURE", None, msg)
        rec["source"]["methode"] = "section_3d"
        return rec, log

    # --- UNITÉS ---
    # Un STL/OBJ ne porte pas de $INSUNITS fiable. On dépend entièrement
    # de units_override.csv (même fichier que dxf2profile.py, même
    # colonnes sku_ou_fichier,insunits,motif).
    override = units_override.get(sku) or units_override.get(path.name)
    if not override:
        verts = mesh.vertices
        bbox_native = verts.max(axis=0) - verts.min(axis=0)
        max_dim_native = float(bbox_native.max())
        prop_insunits, prop_label, prop_motif = d2p.propose_unit_by_bbox(
            [(0.0, 0.0), (max_dim_native, 0.0)]
        )
        log["proposition_unite"] = prop_label or ""
        log["proposition_motif"] = prop_motif
        msg = (
            f"Aucune entree dans units_override.csv pour '{sku}' ou '{path.name}'. "
            f"Un maillage STL/OBJ n'a pas d'equivalent $INSUNITS fiable — unite "
            f"NON deduite automatiquement (regle stricte, meme principe que "
            f"dxf2profile.py). "
            + (f"Proposition indicative par plausibilite de bbox: "
               f"insunits={prop_insunits} ({prop_label}) — {prop_motif}. "
               f"Ajouter cette ligne a units_override.csv pour confirmer."
               if prop_insunits is not None else
               f"Aucune proposition plausible calculable ({prop_motif}).")
        )
        log["statut"] = "ERREUR_UNITES"
        log["message"] = msg
        rec = d2p.build_error_record(sku, path.name, "ERREUR_UNITES", None, msg)
        rec["source"]["methode"] = "section_3d"
        return rec, log

    insunits_raw, override_motif = override
    scale_to_mm = d2p.INSUNITS_TO_MM.get(insunits_raw)
    if scale_to_mm is None:
        msg = f"$INSUNITS={insunits_raw} (via units_override.csv) n'a pas de table de conversion mm connue."
        log["statut"] = "ERREUR_UNITES"
        log["message"] = msg
        # insunits=None dans le JSON exposé : un STL/OBJ n'a pas d'en-tête
        # d'unités DXF, insunits_raw n'est ici qu'un facteur d'échelle de
        # substitution (units_override.csv), jamais une valeur de champ DXF.
        rec = d2p.build_error_record(sku, path.name, "ERREUR_UNITES", None, msg, origine_unite="override")
        rec["source"]["methode"] = "section_3d"
        return rec, log

    log["insunits"] = insunits_raw
    log["message"] = f"Unite forcee via units_override.csv: insunits={insunits_raw} ({override_motif})"

    if abs(scale_to_mm - 1.0) > 1e-12:
        mesh = mesh.copy()
        mesh.apply_scale(scale_to_mm)

    # --- ORIENTATION (ACP) ---
    origin_pt, axis, ratio_2_1, length_mm = find_long_axis(mesh)

    if ratio_2_1 > ORIENTATION_RATIO_MAX:
        msg = (
            f"Maillage {path.name} pas nettement allonge (ratio 2e/1re valeur "
            f"propre = {ratio_2_1:.3f} > seuil {ORIENTATION_RATIO_MAX}). "
            f"Impossible d'identifier l'axe long avec confiance -> ERREUR_ORIENTATION."
        )
        log["statut"] = "ERREUR_ORIENTATION"
        log["message"] = msg
        rec = d2p.build_error_record(sku, path.name, "ERREUR_ORIENTATION", None, msg, origine_unite="override")
        rec["source"]["methode"] = "section_3d"
        return rec, log

    # --- COUPES : balayage dense le long de l'axe long ---
    # Remplace l'ancien échantillonnage à 3 abscisses fixes (25/50/75%),
    # rejeté après vérification empirique (voir docstring de
    # sample_areas_along_axis) : un motif périodique peut ne tomber sur
    # AUCUN de ces 3 points par pur hasard de phase et être manqué en
    # totalité. Le même repère 2D fixe (fixed_rotation) est utilisé pour
    # toutes les coupes d'un même maillage, afin qu'elles soient
    # géométriquement comparables/unifiables (voir docstring de
    # build_fixed_rotation).
    fixed_rotation = build_fixed_rotation(axis)
    positions, areas_arr = sample_areas_along_axis(mesh, origin_pt, axis, length_mm, fixed_rotation)

    valid_mask = ~np.isnan(areas_arr)
    if valid_mask.sum() == 0:
        msg = (
            f"Aucune coupe valide sur le balayage dense de {path.name} "
            f"(section() n'a retourne aucun polygone en {len(positions)} positions). "
            f"Maillage peut-etre non watertight ou axe long mal identifie."
        )
        log["statut"] = "ERREUR_SELECTION"
        log["message"] = msg
        rec = d2p.build_error_record(sku, path.name, "ERREUR_SELECTION", None, msg, origine_unite="override")
        rec["source"]["methode"] = "section_3d"
        return rec, log

    valid_areas = areas_arr[valid_mask]
    valid_positions = positions[valid_mask]
    area_min = float(valid_areas.min())
    area_max = float(valid_areas.max())
    area_ref = float(valid_areas.mean())
    aires_diff = area_ref > 0 and (area_max - area_min) / area_ref > AIRE_TOL_RELATIF

    # Coupe médiane (position la plus proche du milieu de la barre),
    # utilisée comme profil de référence pour le cas "lisse" ET comme
    # gabarit natif (pts_mm avant recalage) pour la height map.
    mid_target = length_mm / 2.0
    mid_idx = int(np.argmin(np.abs(valid_positions - mid_target)))
    mid_offset = float(valid_positions[mid_idx])

    if not aires_diff:
        # Moulure lisse : coupe médiane. Si par malchance elle échoue au
        # second appel (rare — section() peut être non déterministe aux
        # limites), on retombe sur la première coupe valide du balayage.
        chosen_poly = section_polygon_at(mesh, origin_pt, axis, mid_offset, fixed_rotation)
        if chosen_poly is None:
            fallback_offset = float(valid_positions[0])
            chosen_poly = section_polygon_at(mesh, origin_pt, axis, fallback_offset, fixed_rotation)
        motif_record = None
        motif_type = "lisse"
        periode_mm = None
        methode_periode = None
    else:
        # Moulure ornée : UNION (pas enveloppe convexe) des coupes aux
        # positions d'aire MINIMALE, MAXIMALE et médiane, réellement
        # localisées par le balayage dense (jamais des fractions
        # arbitraires 25/50/75% — c'est justement ce qui a fait manquer le
        # motif, voir Bug #1) — garantit que la moulure rentre dans le
        # gabarit quel que soit l'endroit du motif le long de la barre.
        #
        # ⚠️ CORRECTION (2ème revue) : l'enveloppe CONVEXE a été abandonnée.
        # Une corniche a des gorges concaves (creux du profil) ; le convexe
        # les efface et détruit le galbe réel de la moulure. On garde
        # l'UNION brute (shapely.unary_union) des 3 polygones de coupe :
        # elle conserve les concavités tout en capturant l'extension
        # maximale des denticules (aire union < aire convex hull —
        # vérifié 2564mm² vs 4002mm² sur TESTSOLIDE_DENTICULES).
        min_offset = float(valid_positions[int(np.argmin(valid_areas))])
        max_offset = float(valid_positions[int(np.argmax(valid_areas))])
        envelope_offsets = sorted({min_offset, max_offset, mid_offset})
        envelope_polys = [
            section_polygon_at(mesh, origin_pt, axis, off, fixed_rotation)
            for off in envelope_offsets
        ]
        envelope_polys = [p for p in envelope_polys if p is not None]
        chosen_poly = None
        if envelope_polys:
            union_result = unary_union(envelope_polys)
            if union_result.geom_type == "MultiPolygon":
                # Rare (coupes disjointes) : on garde le plus grand
                # polygone, même logique que section_polygon_at ci-dessus.
                chosen_poly = max(union_result.geoms, key=lambda p: p.area)
            else:
                chosen_poly = union_result
        periode_mm, methode_periode = detect_pattern_period(positions, areas_arr, length_mm)
        motif_type = "variable"
        motif_record = {
            "type": motif_type,
            "periode_mm": periode_mm,
            "methode": methode_periode if periode_mm is not None else "autocorrelation",
            "auto": True,
            "profil_source": "union_sections",
        }

    if chosen_poly is None or chosen_poly.is_empty:
        msg = f"Polygone de coupe retenu vide/invalide dans {path.name}."
        log["statut"] = "ERREUR_SELECTION"
        log["message"] = msg
        rec = d2p.build_error_record(sku, path.name, "ERREUR_SELECTION", None, msg, origine_unite="override")
        rec["source"]["methode"] = "section_3d"
        return rec, log

    coords = list(chosen_poly.exterior.coords)
    if len(coords) >= 2 and coords[0] == coords[-1]:
        coords = coords[:-1]
    pts_mm = [(float(x), float(y)) for x, y in coords]
    pts_mm = d2p.ensure_clockwise(pts_mm)

    # Déduplication À LA SOURCE des sommets confondus/colinéaires
    # (< d2p.DEDUP_TOLERANCE_MM) — même fonction partagée que
    # dxf2profile.py (voir dedupe_consecutive_vertices), pas une
    # réimplémentation locale. Nécessaire ici aussi : shapely.unary_union
    # (cas motif "variable", coupes ornées) introduit régulièrement des
    # sommets quasi confondus ou colinéaires à la jonction de deux
    # polygones de coupe presque superposés (jitter de tessellation, voir
    # piège #2 documenté dans detect_wall_and_ceiling_faces).
    nb_avant_dedup = len(pts_mm)
    pts_mm = d2p.dedupe_consecutive_vertices(pts_mm)
    nb_dedup_retires = nb_avant_dedup - len(pts_mm)

    wall_idx, wall_auto, ceiling_idx, ceiling_auto, origin_x, origin_y = (
        d2p.detect_wall_and_ceiling_faces(pts_mm)
    )
    pts_mm_shifted = [(round(x - origin_x, 4), round(y - origin_y, 4)) for x, y in pts_mm]

    xs = [p[0] for p in pts_mm_shifted]
    ys = [p[1] for p in pts_mm_shifted]
    bbox_w = round(max(xs) - min(xs), 3) if xs else 0
    bbox_h = round(max(ys) - min(ys), 3) if ys else 0

    hauteur_mur_mm = 0
    if wall_auto and wall_idx:
        wall_ys = [pts_mm_shifted[i][1] for i in wall_idx]
        hauteur_mur_mm = round(abs(max(wall_ys) - min(wall_ys)), 3)

    projection_plafond_mm = 0
    if ceiling_auto and ceiling_idx:
        ceiling_xs = [pts_mm_shifted[i][0] for i in ceiling_idx]
        projection_plafond_mm = round(abs(max(ceiling_xs) - min(ceiling_xs)), 3)

    # --- HEIGHT MAP (uniquement si motif variable) ---
    assets_height = None
    if motif_type == "variable" and Image is not None and out_dir is not None:
        # Le profil natif (non mis à l'échelle mm) sert de gabarit de
        # rayons ; on utilise directement pts_mm_shifted car mesh a déjà
        # été mis à l'échelle mm plus haut (apply_scale).
        height_arr = build_height_map(mesh, origin_pt, axis, length_mm, pts_mm, fixed_rotation)
        if height_arr is not None:
            height_dir = out_dir / "heightmaps"
            height_path = height_dir / f"{sku}_height.png"
            written = write_height_map_png(height_arr, height_path)
            if written is not None:
                assets_height = f"heightmaps/{sku}_height.png"

    record = {
        "sku": sku,
        "marque": "",
        "famille": None,
        "source": {
            "fichier": path.name,
            # insunits=None : un STL/OBJ n'a pas d'en-tête $INSUNITS DXF.
            # insunits_raw n'est qu'un facteur d'échelle de substitution
            # (units_override.csv) — on ne fabrique jamais une valeur de
            # champ DXF à partir de cette substitution.
            "insunits": None,
            "unite_retenue": "mm",
            "origine_unite": "override",
            "methode": "section_3d",
        },
        "profil_mm": [[x, y] for x, y in pts_mm_shifted],
        "face_pose_mur": {"indices": wall_idx, "auto": wall_auto},
        "face_pose_plafond": {"indices": ceiling_idx, "auto": ceiling_auto},
        "bbox_mm": {"w": bbox_w, "h": bbox_h},
        "hauteur_mur_mm": hauteur_mur_mm,
        "projection_plafond_mm": projection_plafond_mm,
        "motif": motif_record,
        "assets": {"albedo": None, "normal": None, "height": assets_height},
        "longueur_barre_mm": round(length_mm, 1) if length_mm else DEFAULT_BAR_LENGTH_MM,
        "prix_ml": None,
        "statut": "OK",
        "version_schema": SCHEMA_VERSION,
        "_message": (
            f"Coupe 3D (axe long ratio={ratio_2_1:.4f}), motif={motif_type}, "
            f"{len(pts_mm_shifted)} sommets. Aire min/moy/max sur balayage dense "
            f"({len(valid_areas)} coupes valides / {len(positions)}): "
            f"{round(area_min, 1)} / {round(area_ref, 1)} / {round(area_max, 1)} mm2."
            + (
                f" {nb_dedup_retires} sommet(s) confondu(s)/colinéaire(s) "
                f"retiré(s) à la source (< {d2p.DEDUP_TOLERANCE_MM}mm)."
                if nb_dedup_retires > 0
                else ""
            )
        ),
        "_layers_found": [],
    }

    log["statut"] = "OK"
    log["nb_sommets"] = len(pts_mm_shifted)
    log["nb_sommets_dedup_retires"] = nb_dedup_retires
    log["bbox_w_mm"] = bbox_w
    log["bbox_h_mm"] = bbox_h
    log["hauteur_mur_mm"] = hauteur_mur_mm
    log["projection_plafond_mm"] = projection_plafond_mm
    log["motif_type"] = motif_type
    log["motif_periode_mm"] = periode_mm if periode_mm is not None else ""
    log["message"] = record["_message"]

    return record, log


def write_control_png(record: dict, out_dir: Path):
    """Génère un PNG coté du profil, même style visuel que dxf2profile.py.
    Uniquement pour statut == OK. Retourne le chemin écrit, ou None si
    matplotlib indisponible."""
    if plt is None:
        return None
    if record["statut"] != "OK" or not record["profil_mm"]:
        return None

    sku = record["sku"]
    pts = record["profil_mm"]
    xs = [p[0] for p in pts] + [pts[0][0]]
    ys = [p[1] for p in pts] + [pts[0][1]]

    fig, ax = plt.subplots(figsize=(6, 6))
    ax.plot(xs, ys, "-o", markersize=2, linewidth=1, color="#1c2c4c")
    ax.fill(xs, ys, alpha=0.15, color="#1c2c4c")

    ax.axhline(0, color="gray", linewidth=0.5, linestyle="--")
    ax.axvline(0, color="gray", linewidth=0.5, linestyle="--")
    ax.plot(0, 0, "r+", markersize=10, markeredgewidth=2)

    # `indices` peut couvrir PLUS de 2 sommets (tous les sommets
    # consécutifs colinéaires de la face réelle, cf.
    # detect_wall_and_ceiling_faces dans dxf2profile.py) : polyligne
    # complète du run, pas seulement ses deux extrémités.
    wall_idx = record["face_pose_mur"]["indices"]
    if wall_idx and len(wall_idx) >= 2:
        wx = [pts[i][0] for i in wall_idx]
        wy = [pts[i][1] for i in wall_idx]
        ax.plot(wx, wy, color="#8a1c1c", linewidth=3, label="Face mur")

    ceiling_idx = record["face_pose_plafond"]["indices"]
    if ceiling_idx and len(ceiling_idx) >= 2:
        cx = [pts[i][0] for i in ceiling_idx]
        cy = [pts[i][1] for i in ceiling_idx]
        ax.plot(cx, cy, color="#1c6a3c", linewidth=3, label="Face plafond")

    bbox = record["bbox_mm"]
    motif = record.get("motif") or {}
    motif_txt = motif.get("type", "lisse")
    periode = motif.get("periode_mm")
    periode_txt = f", periode={periode}mm" if periode else ""
    title = (
        f"{sku} — methode: section_3d — motif: {motif_txt}{periode_txt}\n"
        f"bbox: {bbox['w']} x {bbox['h']} mm — {len(pts)} sommets"
    )
    ax.set_title(title, fontsize=9)
    ax.set_xlabel("x (mm)")
    ax.set_ylabel("y (mm)")
    ax.set_aspect("equal", adjustable="datalim")
    ax.grid(True, linewidth=0.3, alpha=0.5)
    if wall_idx or ceiling_idx:
        ax.legend(fontsize=7, loc="best")

    out_path = out_dir / f"{sku}.png"
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)
    return out_path


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mesh-dir", default="/home/user/flutter_app/assets/solids")
    parser.add_argument("--out-dir", default="/home/user/flutter_app/assets/profiles")
    parser.add_argument("--mapping", default=str(Path(__file__).parent / "mapping.csv"))
    parser.add_argument("--units-override", default=str(Path(__file__).parent / "units_override.csv"))
    parser.add_argument("--sku", nargs="*", default=None,
                         help="Liste explicite de SKU a traiter (resolus via mapping.csv en priorite, "
                              "sinon par nom de fichier <sku>.stl/<sku>.obj). "
                              "Si omis, utiliser --all pour traiter tout le dossier.")
    parser.add_argument("--all", action="store_true", help="Traiter tous les .stl/.obj du dossier --mesh-dir")
    args = parser.parse_args()

    mesh_dir = Path(args.mesh_dir)
    out_dir = Path(args.out_dir)
    control_dir = out_dir / "control"
    logs_dir = Path(__file__).parent / "logs"
    out_dir.mkdir(parents=True, exist_ok=True)
    control_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    if not mesh_dir.exists():
        print(f"ERREUR: dossier introuvable: {mesh_dir}", file=sys.stderr)
        sys.exit(1)

    fichier_to_sku = d2p.load_mapping(Path(args.mapping))
    sku_to_fichier = {v: k for k, v in fichier_to_sku.items()}
    units_override = d2p.load_units_override(Path(args.units_override))

    if args.sku:
        targets = []
        for sku in args.sku:
            fname = sku_to_fichier.get(sku)
            if fname:
                p = mesh_dir / fname
            else:
                p = None
                for ext in (".stl", ".obj"):
                    candidate = mesh_dir / f"{sku}{ext}"
                    if candidate.exists():
                        p = candidate
                        break
                if p is None:
                    p = mesh_dir / f"{sku}.stl"
            if not p.exists():
                print(f"AVERTISSEMENT: {p} introuvable, ignore.", file=sys.stderr)
                continue
            targets.append(p)
    elif args.all:
        targets = sorted(mesh_dir.glob("*.stl")) + sorted(mesh_dir.glob("*.obj"))
    else:
        print("ERREUR: fournir --sku SKU1 SKU2 ... ou --all", file=sys.stderr)
        sys.exit(1)

    if not targets:
        print("Aucun fichier a traiter.")
        return

    print(f"Traitement de {len(targets)} fichier(s) maillage (STL/OBJ) ...")
    print("(Regle: le batch continue toujours, meme en cas d'erreur sur un fichier.)\n")

    logs = []
    n_ok = 0
    n_err = 0

    for path in targets:
        record, log = process_one_mesh(
            path, fichier_to_sku=fichier_to_sku, units_override=units_override, out_dir=out_dir
        )
        logs.append(log)

        json_path = d2p.write_json(record, out_dir)
        status_icon = "OK " if record["statut"] == "OK" else "ERR"
        print(f"[{status_icon}] {record['sku']:12s} statut={record['statut']:18s} -> {json_path.name}")

        if record["statut"] == "OK":
            n_ok += 1
            png_path = write_control_png(record, control_dir)
            if png_path:
                print(f"      PNG de controle -> {png_path}")
            elif plt is None:
                print("      (PNG de controle non genere: matplotlib indisponible)")
            motif = record.get("motif")
            if motif and motif.get("type") == "variable":
                print(f"      Motif VARIABLE detecte -- periode_mm={motif.get('periode_mm')}")
                if record["assets"].get("height"):
                    print(f"      Height map -> {out_dir / record['assets']['height']}")
        else:
            n_err += 1
            print(f"      {record.get('_message', '')}")

    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = logs_dir / f"run_solid_{timestamp}.csv"
    fieldnames = list(logs[0].keys())
    with log_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(logs)

    print("\n=== Resume du run ===")
    print(f"Total traite : {len(targets)}")
    print(f"  OK          : {n_ok}")
    print(f"  Erreurs     : {n_err}")
    print(f"Log detaille  : {log_path}")


if __name__ == "__main__":
    main()
