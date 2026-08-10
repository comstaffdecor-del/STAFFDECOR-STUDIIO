#!/usr/bin/env python3
"""
step2profile.py — Extraction de profil produit depuis un fichier STEP
(B-rep exact, OCP) -> JSON + PNG (même schéma que dxf2profile.py /
solid2profile.py).

CONTEXTE : certains SKU n'ont ni DXF de coupe ni STL/OBJ exploitable,
mais un fichier STEP (B-rep OpenCASCADE) — c'est en réalité la MEILLEURE
source après le DXF de coupe (voir SPEC.md, §"PRIORITÉ DES FORMATS
SOURCE") : la géométrie B-rep exacte ne souffre d'aucune approximation
de facettisation, contrairement à un maillage triangulé STL.

⚠️ BIBLIOTHÈQUE : OCP SEUL (`cadquery-ocp`), JAMAIS `cadquery` — voir
SPEC.md §"Extension — lecture STEP" pour la justification complète
(conflit numpy documenté). numpy verrouillé à 1.26.4
(tools/dxf_pipeline/requirements-lock.txt).

MÉTHODE — AUCUNE TESSELLATION DU SOLIDE :
  - Import : `STEPControl_Reader` (seul chemin de lecture autorisé).
  - Section : `BRepAlgoAPI_Section` entre le solide B-rep exact et un
    plan perpendiculaire à l'axe long (axe trouvé par ACP sur les
    SOMMETS B-rep du solide, même principe que `find_long_axis` de
    solid2profile.py, mais sur la topologie exacte, jamais un maillage).
    Le résultat est une courbe analytique exacte (segments/arcs/
    B-splines réels) — PAS un contour polygonal approximé par
    triangulation du solide.
  - Représentation en points (`profil_mm`) : les arêtes exactes du
    résultat de section sont discrétisées en points avec la MÊME
    tolérance de flèche que `dxf2profile.py`
    (`FLATTEN_SAGITTA_MM=0.15mm`, réutilisée depuis d2p) — exactement le
    même principe que l'aplatissement des ARC/SPLINE d'un DXF
    (`flatten_entity_to_points`). Ce n'est PAS une tessellation du
    volume (BRepMesh) : seule la courbe 2D résultante, déjà exacte, est
    échantillonnée pour le stockage JSON — au même titre qu'un DXF
    stocke un ARC sous forme de points aplatis, jamais un solide
    entier maillé.
  - Reconstruction du contour fermé : les arêtes de section (non
    ordonnées par `BRepAlgoAPI_Section`) sont assemblées en polygone par
    `shapely.ops.polygonize` sur les polylignes discrétisées (arrondies à
    1e-6 pour éliminer le bruit de précision flottante aux jonctions —
    piège vérifié empiriquement : sans arrondi, deux extrémités
    théoriquement identiques diffèrent de ~1e-13, ce qui fait échouer la
    détection de jonction de shapely et renvoie 0 polygone).

RÈGLES (mêmes principes que dxf2profile.py/solid2profile.py, voir SPEC.md) :

1. UNITÉS : lues en PRIORITÉ depuis l'en-tête STEP réel — deux niveaux :
   (a) `Interface_Static.CVal_s('xstep.cascade.unit')` après
       `ReadFile()`, qui reflète la résolution FAITE PAR OCP de la chaîne
       SI_UNIT / CONVERSION_BASED_UNIT de l'en-tête (voir inspection
       brute ci-dessous — jamais une supposition, valeur réellement lue
       après un ReadFile() réel) ;
   (b) en complément, une inspection TEXTE BRUTE du fichier
       (`raw_step_header`) qui rapporte explicitement `SI_UNIT` vs
       `CONVERSION_BASED_UNIT` et le facteur de conversion déclaré, pour
       transparence totale (affiché en sortie du run, jamais caché).
   Si l'unité résolue n'est ni 'MM' ni 'M' ni 'CM' ni 'IN' (valeurs
   connues d'OCP), ou si `ReadFile` échoue -> repli sur
   `units_override.csv` (même fichier que les 2 autres scripts,
   `source.origine_unite="override"`). Si aucune des deux -> pas de
   supposition : `ERREUR_UNITES`, profil vide. LE BATCH CONTINUE.
   Si l'unité vient de l'en-tête STEP -> `source.origine_unite=
   "step_header"` (nouvelle valeur, jamais utilisée par les 2 autres
   scripts).

2. SOLIDES : un fichier STEP peut être un assemblage multi-corps.
   `nb_solides` est compté RÉELLEMENT (TopExp_Explorer sur TopAbs_SOLID)
   et rapporté dans le log. Si `nb_solides != 1` -> **on ne devine
   jamais** lequel est la référence : `ERREUR_SELECTION`, profil vide,
   message explicite "N solides détectés, application de la règle '1
   fichier = 1 référence'". LE BATCH CONTINUE.

3. ORIENTATION : ACP sur les sommets B-rep du solide (TopAbs_VERTEX,
   `BRep_Tool.Pnt`) — même critère de rejet que solid2profile.py (ratio
   2e/1re valeur propre > ORIENTATION_RATIO_MAX -> ERREUR_ORIENTATION).

4. COUPE : balayage dense le long de l'axe long par `BRepAlgoAPI_Section`
   (résolution STEP_SWEEP_STEP_MM), même logique lisse/orné que
   solid2profile.py (tolérance relative sur l'aire de section,
   AIRE_TOL_RELATIF) : lisse -> coupe médiane ; orné -> UNION (jamais
   l'enveloppe convexe, qui effacerait les gorges concaves — même
   correctif que solid2profile.py) des coupes aux offsets d'aire
   min/max/médiane RÉELLEMENT localisés par le balayage.

5. ORIGINE : recalage mur/plafond par `d2p.detect_wall_and_ceiling_faces`
   — RÉUTILISÉE TELLE QUELLE, aucune réimplémentation divergente.

6. INTERDICTION : jamais de profil de substitution. Toute ambiguïté ->
   statut d'erreur + profil_mm vide.

7. PNG de contrôle : uniquement pour statut == OK, même style visuel que
   les 2 autres scripts, titre avec méthode="section_step".

8. Log détaillé par fichier + CSV récapitulatif du run (même dossier
   logs/ que les 2 autres scripts).

9. CORRESPONDANCE FICHIER -> SKU : lue depuis mapping.csv (même
   fichier), jamais déduite par regex. Repli explicite : nom de fichier
   sans extension.

`source.methode = "section_step"` (nouvelle valeur, distincte de
"section_3d" pour solid2profile.py, absente pour dxf2profile.py).

Usage:
    # Lot pilote (SKU choisis) :
    python3 step2profile.py --step-dir /home/user/flutter_app/assets/step \\
        --sku D718 D705 D720 --out-dir /home/user/flutter_app/assets/profiles

    # Batch complet (tous les .stp/.step du dossier) :
    python3 step2profile.py --step-dir /home/user/flutter_app/assets/step --all \\
        --out-dir /home/user/flutter_app/assets/profiles
"""

import argparse
import csv
import datetime as dt
import re
import sys
from pathlib import Path

import numpy as np

try:
    from OCP.STEPControl import STEPControl_Reader
    from OCP.Interface import Interface_Static
    from OCP.TopAbs import TopAbs_SOLID, TopAbs_VERTEX, TopAbs_EDGE
    from OCP.TopExp import TopExp_Explorer
    from OCP.TopoDS import TopoDS
    from OCP.BRep import BRep_Tool
    from OCP.BRepAlgoAPI import BRepAlgoAPI_Section
    from OCP.BRepAdaptor import BRepAdaptor_Curve
    from OCP.GCPnts import GCPnts_QuasiUniformDeflection
    from OCP.gp import gp_Pln, gp_Pnt, gp_Dir
except ImportError as e:
    print(
        f"ERREUR: OCP indisponible ou incomplet ({e}). "
        f"pip install cadquery-ocp==7.9.3.1.1 (JAMAIS 'cadquery', voir SPEC.md).",
        file=sys.stderr,
    )
    sys.exit(1)

try:
    from shapely.geometry import LineString, Polygon
    from shapely.ops import polygonize, unary_union
except ImportError:
    print("ERREUR: le module 'shapely' n'est pas installé. pip install shapely", file=sys.stderr)
    sys.exit(1)

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ImportError:
    plt = None  # PNG de contrôle désactivé si matplotlib absent (signalé au run)

# --- Import direct des utilitaires PARTAGÉS avec dxf2profile.py : même
# schéma JSON, même logique de faces mur/plafond, même mapping.csv/
# units_override.csv. Aucune réimplémentation divergente. ---
sys.path.insert(0, str(Path(__file__).parent))
import dxf2profile as d2p  # noqa: E402

SCHEMA_VERSION = d2p.SCHEMA_VERSION  # 1 — même schéma, aucune bascule ici

# Tolérance de flèche pour discrétiser les arêtes EXACTES de section en
# points (représentation JSON) — MÊME valeur que dxf2profile.py
# (FLATTEN_SAGITTA_MM) : même principe que l'aplatissement d'un ARC/SPLINE
# DXF, pas une tessellation du solide.
FLATTEN_SAGITTA_MM = d2p.FLATTEN_SAGITTA_MM

# Tolérance relative pour juger deux aires de coupe "identiques" (moulure
# lisse) vs "différentes" (moulure ornée) — même valeur que solid2profile.py.
AIRE_TOL_RELATIF = 0.03

# Rapport (2e valeur propre / 1re valeur propre) au-delà duquel le solide
# n'est plus considéré comme nettement allongé — même seuil que solid2profile.py.
ORIENTATION_RATIO_MAX = 0.5

# Résolution du balayage dense le long de l'axe long, en mm. Plus large
# que solid2profile.py (1.0mm) car chaque section B-rep exacte
# (~5ms/appel mesuré empiriquement sur D718/D705/D720) est plus coûteuse
# qu'une section sur maillage trimesh — 2mm reste largement suffisant
# pour détecter un motif périodique de period >= 10mm (Nyquist) et garde
# un temps de run raisonnable (~1000 coupes pour une barre de 2m).
STEP_SWEEP_STEP_MM = 2.0

# Unités OCP reconnues (valeurs possibles de xstep.cascade.unit) -> mm.
OCP_UNIT_TO_MM = {"MM": 1.0, "CM": 10.0, "M": 1000.0, "IN": 25.4, "FT": 304.8}


# --------------------------------------------------------------------------
# INSPECTION BRUTE DE L'EN-TÊTE STEP (texte, avant tout traitement OCP)
# --------------------------------------------------------------------------

def raw_step_header(path: Path) -> dict:
    """Inspection TEXTE BRUTE de l'en-tête STEP — jamais une supposition,
    tout est extrait par lecture directe du fichier. Retourne un dict:
      - file_description: contenu brut de l'entité FILE_DESCRIPTION
      - length_unit_kind: 'SI_UNIT' ou 'CONVERSION_BASED_UNIT' (nature de
        l'entité effectivement référencée comme LENGTH_UNIT), ou None si
        non trouvée
      - length_unit_factor: facteur de conversion déclaré (float) si
        CONVERSION_BASED_UNIT, sinon None
      - length_unit_si_raw: la ligne SI_UNIT sous-jacente (ex.
        'SI_UNIT(.MILLI.,.METRE.)') si résolvable, sinon None

    Ne lève jamais d'exception : toute anomalie de parsing est renvoyée
    comme None dans les champs concernés (jamais une valeur inventée).
    """
    try:
        text = path.read_text(encoding="ascii", errors="replace")
    except Exception as e:  # noqa: BLE001
        return {
            "file_description": None,
            "length_unit_kind": None,
            "length_unit_factor": None,
            "length_unit_si_raw": None,
            "error": f"{type(e).__name__}: {e}",
        }

    fd_match = re.search(r"FILE_DESCRIPTION\s*\((.*?)\)\s*;", text, re.S)
    file_description = fd_match.group(1).strip() if fd_match else None

    # Repère l'entité #N marquée LENGTH_UNIT() (bloc de définition d'unité
    # composite, ex: "#266=(\nCONVERSION_BASED_UNIT('',#268)\nLENGTH_UNIT()\n...)")
    length_unit_kind = None
    length_unit_factor = None
    length_unit_si_raw = None

    lu_block_match = re.search(
        r"#(\d+)\s*=\s*\(([^;]*?LENGTH_UNIT\s*\(\s*\)[^;]*?)\)\s*;", text, re.S
    )
    if lu_block_match:
        block = lu_block_match.group(2)
        if "CONVERSION_BASED_UNIT" in block:
            length_unit_kind = "CONVERSION_BASED_UNIT"
            ref_match = re.search(r"CONVERSION_BASED_UNIT\s*\(\s*'[^']*'\s*,\s*#(\d+)\s*\)", block)
            if ref_match:
                ref_id = ref_match.group(1)
                meas_match = re.search(
                    rf"#{ref_id}\s*=\s*LENGTH_MEASURE_WITH_UNIT\s*\(\s*LENGTH_MEASURE\s*\(\s*([0-9.eE+-]+)\s*\)\s*,\s*#(\d+)\s*\)",
                    text,
                )
                if meas_match:
                    length_unit_factor = float(meas_match.group(1))
                    si_id = meas_match.group(2)
                    si_match = re.search(
                        rf"#{si_id}\s*=\s*\([^;]*?(SI_UNIT\([^)]*\))[^;]*?\)\s*;", text, re.S
                    )
                    if si_match:
                        length_unit_si_raw = si_match.group(1)
        elif "SI_UNIT" in block:
            length_unit_kind = "SI_UNIT"
            si_match = re.search(r"(SI_UNIT\([^)]*\))", block)
            if si_match:
                length_unit_si_raw = si_match.group(1)

    return {
        "file_description": file_description,
        "length_unit_kind": length_unit_kind,
        "length_unit_factor": length_unit_factor,
        "length_unit_si_raw": length_unit_si_raw,
        "error": None,
    }


def count_solids(shape) -> int:
    """Compte RÉELLEMENT le nombre de TopAbs_SOLID dans une shape OCP —
    jamais une supposition. Utilisé pour appliquer la règle '1 fichier =
    1 référence' (voir docstring module)."""
    exp = TopExp_Explorer(shape, TopAbs_SOLID)
    count = 0
    while exp.More():
        count += 1
        exp.Next()
    return count


def read_step_file(path: Path):
    """Lit un fichier STEP via STEPControl_Reader (seul chemin
    autorisé). Retourne (shape, nb_roots, ocp_unit_str) ou lève une
    exception (capturée par l'appelant)."""
    reader = STEPControl_Reader()
    status = reader.ReadFile(str(path))
    from OCP.IFSelect import IFSelect_RetDone
    if status != IFSelect_RetDone:
        raise ValueError(f"ReadFile a échoué (status={status}, attendu IFSelect_RetDone)")
    # Unité résolue par OCP lui-même (reflète la chaîne SI_UNIT /
    # CONVERSION_BASED_UNIT de l'en-tête) — lu APRÈS ReadFile réel, jamais
    # une valeur par défaut supposée avant lecture.
    ocp_unit_str = Interface_Static.CVal_s("xstep.cascade.unit")
    nb_roots = reader.NbRootsForTransfer()
    ok = reader.TransferRoots()
    if not ok:
        raise ValueError("TransferRoots() a échoué")
    shape = reader.OneShape()
    return shape, nb_roots, ocp_unit_str


# --------------------------------------------------------------------------
# ORIENTATION (ACP sur les sommets B-rep exacts, PAS un maillage)
# --------------------------------------------------------------------------

def collect_solid_vertices(solid) -> np.ndarray:
    """Extrait les coordonnées 3D de tous les sommets B-rep EXACTS du
    solide (TopAbs_VERTEX). Ce ne sont pas des sommets de maillage
    triangulé — c'est la topologie exacte du B-rep (coins réels des
    faces/arêtes)."""
    exp = TopExp_Explorer(solid, TopAbs_VERTEX)
    pts = []
    while exp.More():
        v = TopoDS.Vertex_s(exp.Current())
        p = BRep_Tool.Pnt_s(v)
        pts.append((p.X(), p.Y(), p.Z()))
        exp.Next()
    return np.array(pts, dtype=np.float64)


def find_long_axis(verts: np.ndarray):
    """ACP sur les sommets B-rep exacts. Même principe et même piège
    corrigé que solid2profile.find_long_axis : `origin` est l'extrémité
    RÉELLE (projection minimale sur l'axe), jamais le centroïde — sinon
    la moitié des offsets du balayage dense tomberait hors du solide."""
    centroid = verts.mean(axis=0)
    centered = verts - centroid
    cov = np.cov(centered.T)
    eigvals, eigvecs = np.linalg.eigh(cov)
    order = np.argsort(eigvals)[::-1]
    eigvals = eigvals[order]
    eigvecs = eigvecs[:, order]
    axis = eigvecs[:, 0]
    axis = axis / np.linalg.norm(axis)

    ratio_2_1 = float(eigvals[1] / eigvals[0]) if eigvals[0] > 1e-12 else 1.0

    proj = centered @ axis
    length_mm = float(proj.max() - proj.min())
    origin = centroid + float(proj.min()) * axis

    return origin, axis, ratio_2_1, length_mm


def build_fixed_rotation(axis):
    """MÊME fonction/principe que solid2profile.build_fixed_rotation :
    une rotation fixe (indépendante de la tranche courante), calculée une
    fois par solide, réutilisée pour toutes les coupes -> même repère 2D
    pour toutes, condition nécessaire pour unir plusieurs coupes entre
    elles sans dérive de rotation."""
    from trimesh.geometry import plane_transform
    transform = plane_transform(origin=[0.0, 0.0, 0.0], normal=axis)
    return transform[:3, :3]


# --------------------------------------------------------------------------
# COUPE B-REP EXACTE (BRepAlgoAPI_Section, aucune tessellation du solide)
# --------------------------------------------------------------------------

def section_polygon_at(solid, origin_pt, axis, offset_along_axis: float, fixed_rotation):
    """Coupe le solide B-rep EXACT au plan (origin_pt + offset*axis,
    normal=axis) via BRepAlgoAPI_Section — PAS de tessellation du solide.
    Les arêtes résultantes (courbes analytiques exactes) sont discrétisées
    en points avec la tolérance FLATTEN_SAGITTA_MM (même principe que
    l'aplatissement d'un ARC DXF), projetées dans le repère 2D fixe
    (fixed_rotation), puis assemblées en polygone fermé par
    shapely.polygonize.

    Retourne un shapely.Polygon (le plus grand par aire s'il y a
    plusieurs boucles) ou None si la coupe échoue / ne ferme aucun
    contour."""
    plane_origin_pt = origin_pt + offset_along_axis * axis
    plane = gp_Pln(
        gp_Pnt(float(plane_origin_pt[0]), float(plane_origin_pt[1]), float(plane_origin_pt[2])),
        gp_Dir(float(axis[0]), float(axis[1]), float(axis[2])),
    )
    try:
        sec = BRepAlgoAPI_Section(solid, plane, True)
        sec.Build()
        if not sec.IsDone():
            return None
        result = sec.Shape()
    except Exception:
        return None

    u = fixed_rotation[0, :]
    v = fixed_rotation[1, :]

    lines_2d = []
    exp_e = TopExp_Explorer(result, TopAbs_EDGE)
    while exp_e.More():
        try:
            edge = TopoDS.Edge_s(exp_e.Current())
            curve_adapt = BRepAdaptor_Curve(edge)
            disc = GCPnts_QuasiUniformDeflection(curve_adapt, FLATTEN_SAGITTA_MM)
            if disc.IsDone() and disc.NbPoints() >= 2:
                pts_2d = []
                for i in range(1, disc.NbPoints() + 1):
                    p3 = disc.Value(i)
                    p3_arr = np.array([p3.X(), p3.Y(), p3.Z()]) - plane_origin_pt
                    x2 = float(np.dot(p3_arr, u))
                    y2 = float(np.dot(p3_arr, v))
                    # Arrondi à 1e-6 : élimine le bruit de précision
                    # flottante aux jonctions d'arêtes (vérifié
                    # empiriquement -- sans arrondi, deux extrémités
                    # théoriquement identiques diffèrent de ~1e-13 et
                    # font échouer polygonize, qui renvoie alors 0
                    # polygone).
                    pts_2d.append((round(x2, 6), round(y2, 6)))
                if len(pts_2d) >= 2:
                    lines_2d.append(pts_2d)
        except Exception:
            pass
        exp_e.Next()

    if not lines_2d:
        return None

    linestrings = [LineString(l) for l in lines_2d if len(l) >= 2]
    try:
        polys = list(polygonize(linestrings))
    except Exception:
        return None
    if not polys:
        return None
    best = max(polys, key=lambda p: p.area)
    if best.is_empty or best.area <= 0:
        return None
    return best


def sample_areas_along_axis(solid, origin_pt, axis, length_mm, fixed_rotation):
    """Balayage dense de l'aire de section tous les STEP_SWEEP_STEP_MM le
    long de l'axe long — même principe que solid2profile.py
    (sample_areas_along_axis), résolution adaptée au coût plus élevé
    d'une section B-rep exacte (voir constante STEP_SWEEP_STEP_MM)."""
    margin = max(length_mm * 0.02, 2.0)
    positions = np.arange(margin, length_mm - margin, STEP_SWEEP_STEP_MM)
    areas = np.empty(len(positions), dtype=np.float64)
    for i, pos in enumerate(positions):
        poly = section_polygon_at(solid, origin_pt, axis, pos, fixed_rotation)
        areas[i] = poly.area if poly is not None else np.nan
    return positions, areas


# --------------------------------------------------------------------------
# TRAITEMENT D'UN FICHIER
# --------------------------------------------------------------------------

def process_one_step(path: Path, fichier_to_sku=None, units_override=None):
    """Traite un fichier STEP. Retourne (record_dict, log_dict, header_info).

    Ne lève jamais d'exception hors de cette fonction pour un fichier
    individuel : toute erreur est capturée et transformée en statut
    d'erreur, afin que le batch puisse toujours continuer (même contrat
    que dxf2profile.process_one_dxf / solid2profile.process_one_mesh)."""
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
        "nb_solides": "",
        "unite_ocp": "",
        "unite_kind_brut": "",
        "unite_facteur_brut": "",
        "origine_unite": "",
        "message": "",
    }

    # --- INSPECTION BRUTE DE L'EN-TÊTE, avant tout traitement OCP ---
    header = raw_step_header(path)

    try:
        shape, nb_roots, ocp_unit_str = read_step_file(path)
    except Exception as e:  # noqa: BLE001
        msg = f"{type(e).__name__}: {e}"
        log["statut"] = "ERREUR_LECTURE"
        log["message"] = msg
        rec = d2p.build_error_record(sku, path.name, "ERREUR_LECTURE", None, msg)
        rec["source"]["methode"] = "section_step"
        return rec, log, header

    nb_solides = count_solids(shape)
    log["nb_solides"] = nb_solides
    log["unite_ocp"] = ocp_unit_str or ""
    log["unite_kind_brut"] = header.get("length_unit_kind") or ""
    log["unite_facteur_brut"] = header.get("length_unit_factor") or ""

    if nb_solides != 1:
        msg = (
            f"{nb_solides} solide(s) detecte(s) dans {path.name} -- regle "
            f"'1 fichier = 1 reference' appliquee : AUCUNE supposition sur "
            f"lequel serait la reference. ERREUR_SELECTION."
        )
        log["statut"] = "ERREUR_SELECTION"
        log["message"] = msg
        rec = d2p.build_error_record(sku, path.name, "ERREUR_SELECTION", None, msg)
        rec["source"]["methode"] = "section_step"
        return rec, log, header

    exp_solid = TopExp_Explorer(shape, TopAbs_SOLID)
    solid = TopoDS.Solid_s(exp_solid.Current())

    # --- UNITÉS ---
    scale_to_mm = None
    origine_unite = None
    insunits_exposed = None
    if ocp_unit_str in OCP_UNIT_TO_MM:
        scale_to_mm = OCP_UNIT_TO_MM[ocp_unit_str]
        origine_unite = "step_header"
        insunits_exposed = None  # pas un $INSUNITS DXF, jamais exposé comme tel
        log["message"] = (
            f"Unite lue dans l'en-tete STEP (xstep.cascade.unit='{ocp_unit_str}' "
            f"apres ReadFile reel ; en-tete brut: kind={header.get('length_unit_kind')}, "
            f"facteur={header.get('length_unit_factor')}, si_sous_jacent="
            f"{header.get('length_unit_si_raw')}) -> {scale_to_mm}x vers mm."
        )
    else:
        override = units_override.get(sku) or units_override.get(path.name)
        if override:
            insunits_raw, override_motif = override
            scale_to_mm = d2p.INSUNITS_TO_MM.get(insunits_raw)
            origine_unite = "override"
            if scale_to_mm is None:
                msg = f"$INSUNITS={insunits_raw} (via units_override.csv) n'a pas de table de conversion mm connue."
                log["statut"] = "ERREUR_UNITES"
                log["message"] = msg
                rec = d2p.build_error_record(sku, path.name, "ERREUR_UNITES", None, msg, origine_unite="override")
                rec["source"]["methode"] = "section_step"
                return rec, log, header
            log["message"] = f"Unite forcee via units_override.csv (en-tete STEP non resolue: '{ocp_unit_str}'): insunits={insunits_raw} ({override_motif})"
        else:
            msg = (
                f"Unite d'en-tete STEP non resolue ('{ocp_unit_str}') ET aucune "
                f"entree dans units_override.csv pour '{sku}' ou '{path.name}'. "
                f"AUCUNE supposition -> ERREUR_UNITES."
            )
            log["statut"] = "ERREUR_UNITES"
            log["message"] = msg
            rec = d2p.build_error_record(sku, path.name, "ERREUR_UNITES", None, msg)
            rec["source"]["methode"] = "section_step"
            return rec, log, header

    log["origine_unite"] = origine_unite

    # --- ORIENTATION (ACP sur sommets B-rep exacts) ---
    verts_native = collect_solid_vertices(solid)
    if len(verts_native) < 4:
        msg = f"Solide {path.name} degenere ({len(verts_native)} sommets B-rep)."
        log["statut"] = "ERREUR_LECTURE"
        log["message"] = msg
        rec = d2p.build_error_record(sku, path.name, "ERREUR_LECTURE", None, msg, origine_unite=origine_unite)
        rec["source"]["methode"] = "section_step"
        return rec, log, header

    origin_pt, axis, ratio_2_1, length_native = find_long_axis(verts_native)
    length_mm = length_native * scale_to_mm

    if ratio_2_1 > ORIENTATION_RATIO_MAX:
        msg = (
            f"Solide {path.name} pas nettement allonge (ratio 2e/1re valeur "
            f"propre = {ratio_2_1:.3f} > seuil {ORIENTATION_RATIO_MAX}). "
            f"ERREUR_ORIENTATION."
        )
        log["statut"] = "ERREUR_ORIENTATION"
        log["message"] = msg
        rec = d2p.build_error_record(sku, path.name, "ERREUR_ORIENTATION", None, msg, origine_unite=origine_unite)
        rec["source"]["methode"] = "section_step"
        return rec, log, header

    # --- COUPES : balayage dense B-rep exact le long de l'axe long ---
    # Toutes les coupes/aires sont calculées en unite NATIVE du fichier
    # (origin_pt/axis en coordonnees natives), la conversion mm n'est
    # appliquee qu'a la toute fin sur les points du polygone retenu --
    # coherent avec la conversion appliquee sur length_mm ci-dessus.
    fixed_rotation = build_fixed_rotation(axis)
    positions_native, areas_native = sample_areas_along_axis(
        solid, origin_pt, axis, length_native, fixed_rotation
    )

    valid_mask = ~np.isnan(areas_native)
    if valid_mask.sum() == 0:
        msg = (
            f"Aucune coupe valide sur le balayage dense de {path.name} "
            f"({len(positions_native)} positions testees). Solide non ferme "
            f"(non watertight) ou axe long mal identifie."
        )
        log["statut"] = "ERREUR_SELECTION"
        log["message"] = msg
        rec = d2p.build_error_record(sku, path.name, "ERREUR_SELECTION", None, msg, origine_unite=origine_unite)
        rec["source"]["methode"] = "section_step"
        return rec, log, header

    valid_areas = areas_native[valid_mask]
    valid_positions = positions_native[valid_mask]
    area_min = float(valid_areas.min())
    area_max = float(valid_areas.max())
    area_ref = float(valid_areas.mean())
    aires_diff = area_ref > 0 and (area_max - area_min) / area_ref > AIRE_TOL_RELATIF

    mid_target = length_native / 2.0
    mid_idx = int(np.argmin(np.abs(valid_positions - mid_target)))
    mid_offset = float(valid_positions[mid_idx])

    if not aires_diff:
        chosen_poly = section_polygon_at(solid, origin_pt, axis, mid_offset, fixed_rotation)
        if chosen_poly is None:
            fallback_offset = float(valid_positions[0])
            chosen_poly = section_polygon_at(solid, origin_pt, axis, fallback_offset, fixed_rotation)
        motif_record = None
        motif_type = "lisse"
        periode_mm = None
    else:
        min_offset = float(valid_positions[int(np.argmin(valid_areas))])
        max_offset = float(valid_positions[int(np.argmax(valid_areas))])
        envelope_offsets = sorted({min_offset, max_offset, mid_offset})
        envelope_polys = [
            section_polygon_at(solid, origin_pt, axis, off, fixed_rotation)
            for off in envelope_offsets
        ]
        envelope_polys = [p for p in envelope_polys if p is not None]
        chosen_poly = None
        if envelope_polys:
            union_result = unary_union(envelope_polys)
            if union_result.geom_type == "MultiPolygon":
                chosen_poly = max(union_result.geoms, key=lambda p: p.area)
            else:
                chosen_poly = union_result
        # Détection de période : PAS implémentée dans cette 1ère version
        # de step2profile.py (scipy.find_peaks disponible mais non câblé
        # ici pour rester dans le périmètre demandé -- pilote 3 SKU,
        # priorité au chemin lisse/orné correct). periode_mm=None,
        # signalé explicitement, jamais inventé.
        periode_mm = None
        motif_type = "variable"
        motif_record = {
            "type": motif_type,
            "periode_mm": periode_mm,
            "methode": "non_calculee_step2profile_v1",
            "auto": True,
            "profil_source": "union_sections",
        }

    if chosen_poly is None or chosen_poly.is_empty:
        msg = f"Polygone de coupe retenu vide/invalide dans {path.name}."
        log["statut"] = "ERREUR_SELECTION"
        log["message"] = msg
        rec = d2p.build_error_record(sku, path.name, "ERREUR_SELECTION", None, msg, origine_unite=origine_unite)
        rec["source"]["methode"] = "section_step"
        return rec, log, header

    coords = list(chosen_poly.exterior.coords)
    if len(coords) >= 2 and coords[0] == coords[-1]:
        coords = coords[:-1]
    # Conversion mm appliquée ICI (les coupes ont été calculées en unité
    # native du fichier STEP, pas encore en mm).
    pts_mm = [(float(x) * scale_to_mm, float(y) * scale_to_mm) for x, y in coords]
    pts_mm = d2p.ensure_clockwise(pts_mm)

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

    record = {
        "sku": sku,
        "marque": "",
        "famille": None,
        "source": {
            "fichier": path.name,
            # insunits=None : un fichier STEP n'a pas d'en-tête
            # $INSUNITS au sens DXF -- jamais fabriqué à partir de
            # xstep.cascade.unit, qui est exposé séparément dans le log,
            # pas dans le JSON produit (même principe que
            # solid2profile.py pour source.insunits=None).
            "insunits": None,
            "unite_retenue": "mm",
            "origine_unite": origine_unite,
            "methode": "section_step",
        },
        "profil_mm": [[x, y] for x, y in pts_mm_shifted],
        "face_pose_mur": {"indices": wall_idx, "auto": wall_auto},
        "face_pose_plafond": {"indices": ceiling_idx, "auto": ceiling_auto},
        "bbox_mm": {"w": bbox_w, "h": bbox_h},
        "hauteur_mur_mm": hauteur_mur_mm,
        "projection_plafond_mm": projection_plafond_mm,
        "motif": motif_record,
        "assets": {"albedo": None, "normal": None, "height": None},
        "longueur_barre_mm": round(length_mm, 1) if length_mm else None,
        "longueur_barre_mm_origine": "mesure_brep" if length_mm else None,
        "prix_ml": None,
        "statut": "OK",
        "version_schema": SCHEMA_VERSION,
        "_message": (
            f"Coupe B-rep exacte (BRepAlgoAPI_Section, axe long ratio="
            f"{ratio_2_1:.4f}), motif={motif_type}, {len(pts_mm_shifted)} sommets "
            f"(discretises a {FLATTEN_SAGITTA_MM}mm de fleche, pas une "
            f"tessellation du solide). Aire min/moy/max sur balayage dense "
            f"({len(valid_areas)} coupes valides / {len(positions_native)}, pas "
            f"{STEP_SWEEP_STEP_MM}mm): {round(area_min * scale_to_mm**2, 1)} / "
            f"{round(area_ref * scale_to_mm**2, 1)} / "
            f"{round(area_max * scale_to_mm**2, 1)} mm2. "
            f"Unite: {origine_unite} ({ocp_unit_str})."
            + (
                f" {nb_dedup_retires} sommet(s) confondu(s)/colineaire(s) "
                f"retire(s) a la source (< {d2p.DEDUP_TOLERANCE_MM}mm)."
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

    return record, log, header


def write_control_png(record: dict, out_dir: Path):
    """PNG de contrôle, même style visuel que dxf2profile.py/solid2profile.py.
    Uniquement pour statut == OK."""
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
    title = (
        f"{sku} — methode: section_step — motif: {motif_txt}\n"
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
    parser.add_argument("--step-dir", default="/home/user/flutter_app/assets/step")
    parser.add_argument("--out-dir", default="/home/user/flutter_app/assets/profiles")
    parser.add_argument("--mapping", default=str(Path(__file__).parent / "mapping.csv"))
    parser.add_argument("--units-override", default=str(Path(__file__).parent / "units_override.csv"))
    parser.add_argument("--sku", nargs="*", default=None,
                         help="Liste explicite de SKU a traiter (resolus via mapping.csv en priorite, "
                              "sinon par nom de fichier <sku>.stp/<sku>.step).")
    parser.add_argument("--all", action="store_true", help="Traiter tous les .stp/.step du dossier --step-dir")
    args = parser.parse_args()

    step_dir = Path(args.step_dir)
    out_dir = Path(args.out_dir)
    control_dir = out_dir / "control"
    logs_dir = Path(__file__).parent / "logs"
    out_dir.mkdir(parents=True, exist_ok=True)
    control_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    if not step_dir.exists():
        print(f"ERREUR: dossier introuvable: {step_dir}", file=sys.stderr)
        sys.exit(1)

    fichier_to_sku = d2p.load_mapping(Path(args.mapping))
    sku_to_fichier = {v: k for k, v in fichier_to_sku.items()}
    units_override = d2p.load_units_override(Path(args.units_override))

    if args.sku:
        targets = []
        for sku in args.sku:
            fname = sku_to_fichier.get(sku)
            if fname:
                p = step_dir / fname
            else:
                p = None
                for ext in (".stp", ".step"):
                    candidate = step_dir / f"{sku}{ext}"
                    if candidate.exists():
                        p = candidate
                        break
                if p is None:
                    p = step_dir / f"{sku}.stp"
            if not p.exists():
                print(f"AVERTISSEMENT: {p} introuvable, ignore.", file=sys.stderr)
                continue
            targets.append(p)
    elif args.all:
        targets = sorted(step_dir.glob("*.stp")) + sorted(step_dir.glob("*.step"))
    else:
        print("ERREUR: fournir --sku SKU1 SKU2 ... ou --all", file=sys.stderr)
        sys.exit(1)

    if not targets:
        print("Aucun fichier a traiter.")
        return

    print(f"Traitement de {len(targets)} fichier(s) STEP ...")
    print("(Regle: le batch continue toujours, meme en cas d'erreur sur un fichier.)\n")

    logs = []
    n_ok = 0
    n_err = 0

    for path in targets:
        print(f"=== {path.name} — INSPECTION BRUTE (avant tout traitement) ===")
        header = raw_step_header(path)
        print(f"  FILE_DESCRIPTION brut: {header.get('file_description')!r}")
        print(f"  Unite (bloc LENGTH_UNIT) : kind={header.get('length_unit_kind')}, "
              f"facteur={header.get('length_unit_factor')}, "
              f"si_sous_jacent={header.get('length_unit_si_raw')!r}")

        record, log, header2 = process_one_step(
            path, fichier_to_sku=fichier_to_sku, units_override=units_override
        )
        print(f"  Nombre de solides (TopAbs_SOLID, compte reel): {log.get('nb_solides')}")
        print(f"  Unite resolue par OCP (xstep.cascade.unit apres ReadFile): {log.get('unite_ocp')!r}")
        if log.get("nb_solides") not in ("", 1):
            print(f"  ⚠️  {log.get('nb_solides')} solide(s) -- regle '1 fichier = 1 reference' "
                  f"appliquee, AUCUNE supposition.")

        logs.append(log)

        json_path = d2p.write_json(record, out_dir)
        status_icon = "OK " if record["statut"] == "OK" else "ERR"
        print(f"  [{status_icon}] {record['sku']:12s} statut={record['statut']:18s} -> {json_path.name}")

        if record["statut"] == "OK":
            n_ok += 1
            png_path = write_control_png(record, control_dir)
            if png_path:
                print(f"      PNG de controle -> {png_path}")
            elif plt is None:
                print("      (PNG de controle non genere: matplotlib indisponible)")
        else:
            n_err += 1
            print(f"      {record.get('_message', '')}")
        print()

    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = logs_dir / f"run_step_{timestamp}.csv"
    fieldnames = list(logs[0].keys())
    with log_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(logs)

    print("=== Resume du run ===")
    print(f"Total traite : {len(targets)}")
    print(f"  OK          : {n_ok}")
    print(f"  Erreurs     : {n_err}")
    print(f"Log detaille  : {log_path}")


if __name__ == "__main__":
    main()
