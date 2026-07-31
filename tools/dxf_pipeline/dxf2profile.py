#!/usr/bin/env python3
"""
dxf2profile.py — Extraction de profil produit depuis un DXF -> JSON + PNG

Lit un ou plusieurs fichiers .dxf (jamais de .dwg — la conversion DWG->DXF
est faite hors de ce script, via ODA File Converter) et produit, par SKU :
  - assets/profiles/<sku>.json   (schéma défini dans SPEC.md, version 1)
  - assets/profiles/control/<sku>.png (PNG coté du profil tracé)
  - une ligne de log dans tools/dxf_pipeline/logs/run_<timestamp>.csv

RÈGLES (cf. SPEC.md — à relire avant toute modification de ce script) :

1. UNITÉS : lecture de $INSUNITS dans le header DXF (priorité 1).
   - Présent et != 0 -> unité convertie en mm, statut OK, origine_unite=header.
   - Absent ou == 0 -> priorité 2 : lecture de units_override.csv (par sku
     ou par nom de fichier). Si trouvé -> origine_unite=override, unité
     appliquée sans ambiguïté, statut OK.
   - Toujours absent -> le fichier est marqué ERREUR_UNITES. Une
     PROPOSITION d'unité est calculée par plausibilité de bbox (voir
     propose_unit_by_bbox()) et consignée dans le log (colonnes
     proposition_unite / proposition_motif) — jamais appliquée
     automatiquement, profil_mm reste VIDE. LE BATCH NE S'ARRÊTE PAS : il
     continue sur le fichier suivant.

2. SÉLECTION DU CONTOUR : ne garder que la polyligne FERMÉE de plus grande
   aire, sur le "calque de contour". Les calques de cotation/texte/
   cartouche/axes/hachures sont ignorés (heuristique de nom, voir
   NOISY_LAYER_HINTS) et les entités HATCH/DIMENSION/TEXT/MTEXT sont
   ignorées explicitement quel que soit le calque.
   - 0 candidate ou >1 candidate de même aire maximale (ambiguïté réelle)
     -> ERREUR_SELECTION, profil_mm vide, message listant les calques
     trouvés dans le log. Aucun choix implicite. LE BATCH CONTINUE.

3. APLATISSEMENT : SPLINE, ARC, ELLIPSE et bulges de LWPOLYLINE sont
   aplatis en segments via ezdxf.path.from_entity(...).flattening(distance)
   avec distance = 0.15 mm (converti dans l'unité native du dessin avant
   application, puisque flattening() travaille dans l'espace du dessin).

4. ORIGINE : recalée à x=0 sur la face mur, y=0 sur la face plafond
   (voir _detect_wall_ceiling_faces / --wall-side / --ceiling-side).

5. INTERDICTION : ne jamais compléter, lisser, ou "corriger" un profil.
   Toute ambiguïté ou fichier illisible -> statut d'erreur + profil_mm
   vide, jamais un profil de substitution.

6. Un PNG de contrôle coté est produit uniquement pour statut == OK.

7. Log détaillé par fichier (nb sommets, bbox mm, hauteur mur, projection
   plafond) + un CSV récapitulatif du run.

8. CORRESPONDANCE FICHIER -> SKU : lue depuis mapping.csv, jamais déduite
   par regex. Si le fichier n'y figure pas, sku = nom de fichier sans
   extension (comportement de secours explicite, signalé dans le log).

Usage:
    # Lot pilote (SKU choisis explicitement) :
    python3 dxf2profile.py --dxf-dir /home/user/flutter_app/assets/dxf \\
        --sku D570 D545 D560 ... \\
        --out-dir /home/user/flutter_app/assets/profiles

    # Batch complet (tous les .dxf du dossier) :
    python3 dxf2profile.py --dxf-dir /home/user/flutter_app/assets/dxf --all \\
        --out-dir /home/user/flutter_app/assets/profiles
"""

import argparse
import csv
import datetime as dt
import json
import re
import sys
from pathlib import Path

try:
    import ezdxf
    from ezdxf import path as ezpath
    from ezdxf.entities import LWPolyline, Polyline
except ImportError:
    print("ERREUR: le module 'ezdxf' n'est pas installé. pip install ezdxf", file=sys.stderr)
    sys.exit(1)

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ImportError:
    plt = None  # PNG de contrôle désactivé si matplotlib absent (signalé au run)


SCHEMA_VERSION = 1
FLATTEN_SAGITTA_MM = 0.15
# SUPPRIMÉ (demande explicite utilisateur) : DEFAULT_BAR_LENGTH_MM = 2000.
# Cette constante fabriquait une longueur de barre INVENTÉE dès qu'aucune
# mesure/donnée réelle n'existait, déguisée en valeur mesurée -> elle a
# produit 3 fausses alertes de recoupement sur 4 (ex. SKU 0900/1000/1145c :
# le "2000" par défaut était comparé au tarif papier comme s'il s'agissait
# d'une vraie mesure). RÈGLE DÉSORMAIS : une longueur de barre non connue
# = `None` + `longueur_barre_mm_origine=None`, jamais une valeur par
# défaut. Le champ `longueur_barre_mm_origine` indique la provenance :
#   - "mesure_maillage" : mesurée sur un maillage 3D (solid2profile.py,
#     axe long trouvé par ACP) — un profil DXF 2D (coupe transversale
#     seule) ne mesure JAMAIS de longueur de barre, il n'y a donc rien à
#     mesurer ici dans dxf2profile.py.
#   - "catalogue" : donnée COMMERCIALE lue dans le tarif papier
#     (ex. "Corniche en 2 ml", "1,50 ml") — le catalogue fait AUTORITÉ
#     sur ce champ, la géométrie ne peut structurellement pas la mesurer
#     (une longueur de barre commerciale n'est pas une propriété du
#     galbe/profil, c'est une décision de découpe). Voir
#     inject_cote_catalogue.py qui applique cette autorité.
#   - None : ni mesuré, ni connu du catalogue.

NOISY_LAYER_HINTS = (
    "cot", "dim", "texte", "text", "cartouche", "axe", "hatch",
    "hachure", "annot", "titre", "légende", "legende",
)

INSUNITS_TO_MM = {
    1: 25.4, 2: 304.8, 3: 1609344.0, 4: 1.0, 5: 10.0, 6: 1000.0,
    7: 1e9, 8: 0.0254, 9: 0.001, 10: 914.4, 11: 1e-7, 12: 1e-6,
    13: 1e-3, 14: 100.0, 15: 10000.0, 16: 100000.0,
}

INSUNITS_LABELS = {
    0: "non_specifie", 1: "pouces", 2: "pieds", 4: "mm", 5: "cm", 6: "m",
    9: "mils", 10: "yards", 13: "microns", 14: "decimetres",
}


def is_noisy_layer(layer_name: str) -> bool:
    name = (layer_name or "").lower()
    return any(hint in name for hint in NOISY_LAYER_HINTS)


def load_mapping(mapping_path: Path):
    """Charge mapping.csv (fichier,sku,type) -> dict fichier -> sku.
    Ne déduit jamais une correspondance par regex."""
    fichier_to_sku = {}
    if mapping_path.exists():
        with mapping_path.open(newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                fichier = (row.get("fichier") or "").strip()
                sku = (row.get("sku") or "").strip()
                if fichier and sku:
                    fichier_to_sku[fichier] = sku
    return fichier_to_sku


def load_units_override(override_path: Path):
    """Charge units_override.csv (sku_ou_fichier,insunits,motif) -> dict
    clé (sku ou nom de fichier) -> (insunits:int, motif:str).
    Priorité 2, lue seulement quand $INSUNITS est absent/nul dans le DXF."""
    overrides = {}
    if override_path.exists():
        with override_path.open(newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                key = (row.get("sku_ou_fichier") or "").strip()
                insunits_str = (row.get("insunits") or "").strip()
                motif = (row.get("motif") or "").strip()
                if key and insunits_str:
                    try:
                        overrides[key] = (int(insunits_str), motif)
                    except ValueError:
                        continue
    return overrides


def normalize_sku(sku: str) -> str:
    """Normalise une référence SKU pour permettre une correspondance
    fiable entre les différentes sources (noms de fichier DXF/STL, tarif
    papier, mapping.csv) qui n'écrivent pas toujours la même référence à
    l'identique — observé réellement : "20.54" (tarif papier) vs "20-54"
    (nom de fichier assets/dxf/20-54.dxf), "1145C" (tarif) vs "1145c"
    (nom de fichier DXF, minuscule).

    RÈGLES (déterministes, aucune inférence) :
      1. `strip()` + majuscule (insensible à la casse — cf. 1145c/1145C).
      2. Espaces internes supprimés (jamais rencontrés dans ce jeu de
         données réel, mais un SKU ne contient normalement aucun espace).
      3. Point(s) et tiret(s) consécutifs unifiés en UN SEUL tiret `-`
         (jamais supprimés purement : "20.01" et "2001" sont deux
         références RÉELLEMENT distinctes du catalogue — supprimer le
         séparateur au lieu de l'unifier les ferait collisionner, vérifié
         empiriquement sur les 1596 lignes de catalogue.csv : 13
         collisions de ce type si le séparateur est supprimé, 0 si il
         est unifié en tiret).

    Résultat : "20.54" -> "20-54", "20-54" -> "20-54" (même normalisation,
    donc correspondance réussie), "1145c" -> "1145C", "2001" -> "2001",
    "20.01" -> "20-01" (reste distinct de "2001", comme il se doit).

    Toute correspondance obtenue via cette normalisation (donc pas un
    match exact caractère-pour-caractère) DOIT être journalisée par
    l'appelant — jamais silencieuse (cf. CSV de correspondance produit
    par les scripts appelants)."""
    s = (sku or "").strip().upper()
    s = re.sub(r"\s+", "", s)
    s = re.sub(r"[.\-]+", "-", s)
    return s


def propose_unit_by_bbox(points_native):
    """Propose une unité par PLAUSIBILITÉ de la bounding box, quand
    $INSUNITS est absent/nul et qu'aucun units_override.csv ne couvre le
    fichier. Ceci est UNE PROPOSITION INDICATIVE consignée dans le log,
    JAMAIS appliquée automatiquement au profil (profil_mm reste vide dans
    ce cas — voir règle ERREUR_UNITES).

    Heuristique : un profil de moulure Staff Décor mesure typiquement entre
    10 et 400 mm de large/haut (corniches, plinthes, cimaises, rosaces).
    On teste chaque unité DXF standard et on retient celle qui ramène la
    plus grande dimension de la bbox native dans cette plage plausible.

    Retourne (insunits_propose:int, label:str, motif:str) ou
    (None, None, motif_explicatif) si aucune unité ne produit une bbox
    plausible."""
    if not points_native:
        return None, None, "profil vide, aucune proposition possible"

    xs = [p[0] for p in points_native]
    ys = [p[1] for p in points_native]
    max_dim_native = max(max(xs) - min(xs), max(ys) - min(ys))

    if max_dim_native <= 0:
        return None, None, "bbox nulle, aucune proposition possible"

    PLAUSIBLE_MIN_MM = 10.0
    PLAUSIBLE_MAX_MM = 400.0

    candidates = []
    for insunits, scale in INSUNITS_TO_MM.items():
        dim_mm = max_dim_native * scale
        if PLAUSIBLE_MIN_MM <= dim_mm <= PLAUSIBLE_MAX_MM:
            # Score : plus proche du centre de la plage plausible = meilleur
            center = (PLAUSIBLE_MIN_MM + PLAUSIBLE_MAX_MM) / 2.0
            score = abs(dim_mm - center)
            candidates.append((score, insunits, scale, dim_mm))

    if not candidates:
        return None, None, (
            f"aucune unité DXF standard ne ramène la plus grande dimension "
            f"native ({max_dim_native:.3f}) dans la plage plausible "
            f"[{PLAUSIBLE_MIN_MM}-{PLAUSIBLE_MAX_MM}] mm d'un profil de moulure"
        )

    candidates.sort(key=lambda c: c[0])
    _, best_insunits, best_scale, best_dim_mm = candidates[0]
    label = INSUNITS_LABELS.get(best_insunits, f"code_{best_insunits}")
    motif = (
        f"plus grande dimension bbox native={max_dim_native:.3f} -> "
        f"{best_dim_mm:.1f}mm si insunits={best_insunits} ({label}), "
        f"plage plausible moulure [{PLAUSIBLE_MIN_MM}-{PLAUSIBLE_MAX_MM}]mm"
    )
    return best_insunits, label, motif


def polygon_area(points):
    """Formule du lacet — aire absolue (unité native des points)."""
    if len(points) < 3:
        return 0.0
    area = 0.0
    n = len(points)
    for i in range(n):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % n]
        area += x1 * y2 - x2 * y1
    return abs(area) / 2.0


def ensure_clockwise(points):
    """Force le sens horaire (aire signée négative en repère écran y-down
    n'est pas garantie ici : on travaille en repère mathématique standard
    y-up, donc horaire = aire signée négative)."""
    area_signed = 0.0
    n = len(points)
    for i in range(n):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % n]
        area_signed += x1 * y2 - x2 * y1
    if area_signed > 0:  # sens anti-horaire -> inverser
        return list(reversed(points))
    return points


DEDUP_TOLERANCE_MM = 0.01  # cf. SPEC.md — sommets consécutifs confondus ou
# colinéaires en deçà de cette distance sont fusionnés À LA SOURCE (voir
# dedupe_consecutive_vertices ci-dessous). Choisi nettement sous la
# précision de fabrication (dixième de mm) : ne fusionne jamais deux
# sommets réellement distincts, seulement le bruit de tracé/tessellation.


def dedupe_consecutive_vertices(points, tol_mm=DEDUP_TOLERANCE_MM):
    """Supprime, sur un contour FERMÉ (le dernier sommet n'est jamais
    supposé être une répétition explicite du premier — cette fonction
    élimine précisément ce cas s'il se présente), les sommets consécutifs :

    1. CONFONDUS : distance(sommet[i], sommet[i+1]) < tol_mm. Cas typique
       observé : le dernier sommet d'un tracé DXF duplique exactement le
       premier (fermeture explicite côté outil de dessin) — voir
       assets/profiles/1000.json avant correctif (50 sommets, sommet[0] ==
       sommet[49] == (83.0, -30.0)). Le contour est déjà fermé par
       construction (accès par modulo dans sweepMoulure/perimeterMm côté
       Dart) : ce doublon produit une arête de fermeture de longueur nulle
       -> triangle dégénéré en aval.

    2. COLINÉAIRES : un sommet strictement entre deux autres, aligné avec
       eux à moins de tol_mm (distance point-segment), est retiré : il
       n'apporte aucune information géométrique et peut provenir d'un
       artefact de tessellation/aplatissement (ex. jitter de tessellation
       STL entre coupes, cf. docstring de detect_wall_and_ceiling_faces).

    Ce correctif vit ICI (à la source des deux pipelines dxf2profile.py ET
    solid2profile.py, qui importe et appelle cette fonction), PAS dans un
    test ni dans un loader Dart en aval — cf. demande explicite de
    l'utilisateur : "Un correctif qui vit dans un test ne protège pas la
    production."

    Ne modifie JAMAIS le nombre de sommets si aucun doublon/colinéarité
    n'est détecté (aucun lissage implicite d'un profil déjà propre).

    Filet de sécurité (étape 2 uniquement, colinéarité) : ne retire jamais
    un sommet colinéaire si cela ferait descendre le contour sous 3
    sommets — un contour ne peut pas être réduit à moins d'un triangle par
    ce nettoyage de colinéarité. Ce filet ne s'applique PAS à l'étape 1
    (confusion) : un contour véritablement dégénéré en entrée (plusieurs
    sommets réellement confondus au point de ne plus représenter que 1 ou
    2 positions distinctes) n'est de toute façon pas un contour fermé
    valide -> ce cas est déjà écarté plus haut dans le pipeline
    (`polygon_area`/`len(pts) < 3`, voir collect_closed_candidates) avant
    même d'appeler cette fonction ; il n'a jamais été observé sur un
    profil réel."""
    n = len(points)
    if n < 3:
        return list(points)

    def dist(a, b):
        return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5

    def point_segment_distance(p, a, b):
        """Distance du point p au segment [a, b]."""
        ax, ay = a
        bx, by = b
        px, py = p
        abx, aby = bx - ax, by - ay
        seg_len_sq = abx * abx + aby * aby
        if seg_len_sq < 1e-18:
            return dist(p, a)
        t = ((px - ax) * abx + (py - ay) * aby) / seg_len_sq
        t = max(0.0, min(1.0, t))
        proj = (ax + t * abx, ay + t * aby)
        return dist(p, proj)

    # --- Étape 1 : sommets consécutifs confondus (distance < tol_mm). ---
    # Parcours simple, contour fermé (dernier -> premier inclus) : on
    # garde un sommet seulement s'il n'est pas confondu avec le DERNIER
    # sommet déjà conservé.
    deduped = []
    for p in points:
        if deduped and dist(deduped[-1], p) < tol_mm:
            continue
        deduped.append(p)
    # Fermeture : si le dernier sommet conservé est confondu avec le tout
    # premier, on le retire (cas exact du doublon de fermeture DXF).
    if len(deduped) >= 2 and dist(deduped[0], deduped[-1]) < tol_mm:
        deduped.pop()

    if len(deduped) < 3:
        return deduped

    # --- Étape 2 : sommets colinéaires (distance point-segment < tol_mm
    # par rapport au segment formé par ses deux voisins immédiats dans le
    # contour déjà dédoublonné de l'étape 1). Un seul passage : suffisant
    # pour absorber le bruit de tessellation observé (pas de cas connu de
    # colinéarités en chaîne nécessitant plusieurs passages sur les
    # fixtures réelles) ; ne retire jamais un sommet si cela ferait
    # descendre le contour sous 3 sommets. ---
    result = []
    m = len(deduped)
    for i in range(m):
        prev_pt = deduped[(i - 1) % m]
        cur_pt = deduped[i]
        next_pt = deduped[(i + 1) % m]
        # Garde-fou : ne retire ce sommet colinéaire que si le contour
        # conserverait au moins 3 sommets une fois tous les sommets
        # restants ajoutés (m - i - 1 sommets restant à examiner).
        remaining_after = m - (i + 1)
        would_have = len(result) + remaining_after
        if would_have >= 3 and point_segment_distance(cur_pt, prev_pt, next_pt) < tol_mm:
            continue
        result.append(cur_pt)

    if len(result) < 3:
        return deduped  # sécurité : jamais moins de 3 sommets en sortie
    return result


def collect_closed_candidates(msp):
    """Retourne la liste des candidates (layer, points_natifs, entity) pour
    les polylignes FERMÉES, hors calques bruités. Aucune conversion d'unité
    ici — aire calculée en unité native pour la comparaison relative."""
    candidates = []
    for e in msp.query("LWPOLYLINE POLYLINE"):
        layer = e.dxf.layer
        if is_noisy_layer(layer):
            continue
        try:
            is_closed = e.is_closed
        except Exception:
            is_closed = False
        if not is_closed:
            continue

        pts = flatten_entity_to_points(e)
        if len(pts) < 3:
            continue
        candidates.append((layer, pts, e))
    return candidates


def flatten_entity_to_points(entity, sagitta_native=None):
    """Aplati une entité (LWPOLYLINE avec bulges compris, POLYLINE, ou toute
    entité supportée par ezdxf.path.from_entity comme SPLINE/ARC/ELLIPSE) en
    liste de points (x, y) natifs (unité du dessin, pas encore convertie en
    mm). sagitta_native: tolérance de flèche dans l'unité native du dessin
    (si None, on tente une valeur générique via distance=0.01 * bbox, sinon
    on utilise la version discrète native de l'entité sans aplatir de
    courbes tierces)."""
    try:
        p = ezpath.make_path(entity)
        if sagitta_native is None:
            sagitta_native = 0.15  # fallback ; recalculé correctement dans
            # le contexte de main() une fois insunits connu.
        pts = [(v.x, v.y) for v in p.flattening(distance=sagitta_native)]
        if len(pts) >= 3:
            return pts
    except Exception:
        pass

    # Fallback : LWPOLYLINE/POLYLINE natives sans passer par ezdxf.path
    # (couvre le cas où make_path échouerait pour une raison quelconque sur
    # une polyligne pourtant simple).
    try:
        if isinstance(entity, LWPolyline):
            return [(p[0], p[1]) for p in entity.get_points()]
        if isinstance(entity, Polyline):
            return [(v.dxf.location.x, v.dxf.location.y) for v in entity.vertices]
    except Exception:
        pass
    return []


def detect_wall_and_ceiling_faces(points_mm):
    """Détection automatique des faces d'appui mur/plafond.

    Heuristique : la face "mur" est le groupe de sommets consécutifs
    quasi-colinéaires verticaux (dx quasi nul d'un sommet au suivant) le
    plus à gauche (x minimal) ; la face "plafond" est le groupe de sommets
    consécutifs quasi-colinéaires horizontaux le plus haut (y maximal).
    Retourne (wall_indices, wall_auto, ceiling_indices, ceiling_auto,
    origin_x, origin_y) où origin_x/origin_y sont les coordonnées à
    soustraire pour recaler l'origine sur ces faces.

    ⚠️ PIÈGE DÉTECTÉ ET CORRIGÉ (revue utilisateur sur
    TESTSOLIDE_DENTICULES) : une version antérieure ne regardait que LE
    PREMIER segment (sommet i -> sommet i+1) vertical/horizontal trouvé,
    sans poursuivre la collecte sur les sommets suivants tant qu'ils
    restent colinéaires. Sur un maillage tessellé (STL), une face plane
    unique est presque toujours découpée en plusieurs sommets quasi
    confondus (bruit de tessellation ≤ 0.05mm typique) : s'arrêter au
    premier segment ne capture qu'un fragment de la face réelle. Vérifié
    sur TESTSOLIDE_DENTICULES : la face plafond réelle s'étend sur les
    sommets 5 à 12 (x de 0.04 à 68.0mm, tous à y≈0), mais l'ancienne
    version ne retenait que le segment [5,6] (x de 0.04 à 31.52mm) —
    projection_plafond_mm=31.48 au lieu de 68.0. Corrigé : on parcourt le
    contour et on ACCUMULE tous les sommets consécutifs colinéaires
    (au sens de la tolérance ci-dessous) dans un même "run", puis on
    retient le run entier (tous ses indices, pas seulement ses deux
    extrémités) comme face candidate.

    Tolérance : 0.05mm (pas 0.5mm comme l'ancien seuil, qui datait d'un
    usage DXF sans tessellation) — suffisante pour absorber le bruit de
    tessellation STL observé (bruit typique < 0.03mm sur les fixtures
    synthétiques), sans risquer de fusionner deux faces réellement
    distinctes à quelques dixièmes de mm l'une de l'autre.

    ⚠️ PIÈGE #2 DÉTECTÉ ET CORRIGÉ (après passage à l'union des sections,
    voir solid2profile.py) : unir plusieurs polygones de coupe (aux
    positions min/max/médiane) introduit parfois un micro-décrochement à
    la jonction de deux contours quasi identiques mais pas rigoureusement
    superposés (jitter de tessellation entre coupes, ex. dx=0, dy=0.0225mm
    observé sur TESTSOLIDE_DENTICULES). Une arête aussi minuscule est
    à la fois "pas assez horizontale" (dx trop petit) ET "pas assez
    verticale" (dy trop petit) selon la classification stricte
    dx<=TOL-et-dy>TOL / dy<=TOL-et-dx>TOL : elle cassait le run à tort,
    ramenant projection_plafond_mm de 68.0 à 60.0. Corrigé : une arête est
    compatible avec l'EXTENSION d'un run vertical dès que dx<=TOL (sans
    exiger dy>TOL), et compatible avec l'extension d'un run horizontal dès
    que dy<=TOL (sans exiger dx>TOL). Une arête minuscule (dx<=TOL ET
    dy<=TOL) devient ainsi compatible avec les DEUX types de run
    simultanément, ce qui est le comportement voulu : elle ne doit jamais
    interrompre un run en cours, quel qu'il soit.

    Cette détection est une AIDE, pas une correction du profil : si aucune
    face verticale/horizontale nette n'est trouvée, on retourne des indices
    vides avec auto=False et l'origine reste au coin bbox (xmin, ymax) par
    défaut — décision explicite, jamais un "profil corrigé".
    """
    n = len(points_mm)
    if n < 2:
        return [], False, [], False, 0.0, 0.0

    xs = [p[0] for p in points_mm]
    ys = [p[1] for p in points_mm]
    xmin, ymax = min(xs), max(ys)

    TOL = 0.05  # mm de tolérance sur dx/dy pour juger "vertical"/"horizontal"
    # (bruit de tessellation STL/DXF ; voir docstring ci-dessus)

    # --- Classification de chaque arête (sommet i -> sommet i+1) ---
    # Une arête est compatible "vertical" dès que dx<=TOL (peu importe dy) :
    # une micro-arête négligeable (dx<=TOL ET dy<=TOL) est ainsi compatible
    # avec un run vertical EN COURS sans l'interrompre (voir piège #2 dans
    # la docstring ci-dessus). Idem pour "horizontal" via dy<=TOL.
    edge_is_vertical = []
    edge_is_horizontal = []
    for i in range(n):
        x1, y1 = points_mm[i]
        x2, y2 = points_mm[(i + 1) % n]
        dx, dy = abs(x2 - x1), abs(y2 - y1)
        edge_is_vertical.append(dx <= TOL)
        edge_is_horizontal.append(dy <= TOL)

    def collect_runs(edge_flags):
        """Regroupe les arêtes consécutives (avec retour à zéro, contour
        fermé) partageant le même flag=True en "runs". Chaque run est la
        liste ORDONNÉE de tous les indices de SOMMETS qu'il couvre
        (extrémités des arêtes incluses, sans doublon), pas seulement les
        deux extrémités du premier segment. Retourne une liste de runs
        (chacun : liste d'indices de sommets)."""
        runs = []
        seen_edges = [False] * n
        for start in range(n):
            if seen_edges[start] or not edge_flags[start]:
                continue
            # Étend le run vers l'avant tant que les arêtes suivantes ont
            # le même flag (gère le cas où le run traverse l'indice 0,
            # contour fermé).
            edges_in_run = [start]
            seen_edges[start] = True
            j = (start + 1) % n
            while edge_flags[j] and not seen_edges[j] and len(edges_in_run) < n:
                edges_in_run.append(j)
                seen_edges[j] = True
                j = (j + 1) % n
            # Sommets couverts par ces arêtes, dans l'ordre, sans doublon.
            verts = [edges_in_run[0]]
            for e in edges_in_run:
                nxt = (e + 1) % n
                if nxt != verts[0]:
                    verts.append(nxt)
            runs.append(verts)
        return runs

    wall_idx, wall_auto = [], False
    ceiling_idx, ceiling_auto = [], False
    best_wall_x = None
    best_ceiling_y = None

    for verts in collect_runs(edge_is_vertical):
        seg_x = sum(points_mm[v][0] for v in verts) / len(verts)
        if best_wall_x is None or seg_x < best_wall_x:
            best_wall_x = seg_x
            wall_idx = verts
            wall_auto = True

    for verts in collect_runs(edge_is_horizontal):
        seg_y = sum(points_mm[v][1] for v in verts) / len(verts)
        if best_ceiling_y is None or seg_y > best_ceiling_y:
            best_ceiling_y = seg_y
            ceiling_idx = verts
            ceiling_auto = True

    origin_x = best_wall_x if best_wall_x is not None else xmin
    origin_y = best_ceiling_y if best_ceiling_y is not None else ymax

    return wall_idx, wall_auto, ceiling_idx, ceiling_auto, origin_x, origin_y


def guess_famille(sku: str, layers) -> str | None:
    """Devine la famille à partir du nom de calque/SKU. Retourne None si
    aucune correspondance claire — jamais de valeur inventée."""
    hay = (sku + " " + " ".join(layers)).lower()
    if "plin" in hay or sku.upper().startswith("PLIN"):
        return "plinthe"
    if "cimaise" in hay:
        return "cimaise"
    if "rosace" in hay:
        return "rosace"
    if "cornic" in hay or sku.upper().startswith("D"):
        return "corniche"
    return None


def build_error_record(sku, fichier, statut, insunits_raw, message, layers_found=None,
                        origine_unite="header"):
    return {
        "sku": sku,
        "marque": "",
        "famille": None,
        "source": {
            "fichier": fichier,
            "insunits": insunits_raw if insunits_raw else None,
            "unite_retenue": "mm",
            "origine_unite": origine_unite,
        },
        "profil_mm": [],
        "face_pose_mur": {"indices": [], "auto": False},
        "face_pose_plafond": {"indices": [], "auto": False},
        "bbox_mm": {"w": 0, "h": 0},
        "hauteur_mur_mm": 0,
        "projection_plafond_mm": 0,
        "motif": None,
        "assets": {"albedo": None, "normal": None},
        # SUPPRIMÉ : plus de DEFAULT_BAR_LENGTH_MM (valeur inventée). Une
        # longueur non mesurée/non connue = None + origine=None.
        "longueur_barre_mm": None,
        "longueur_barre_mm_origine": None,
        "prix_ml": None,
        "statut": statut,
        "version_schema": SCHEMA_VERSION,
        "_message": message,  # informatif, retiré avant écriture JSON finale si besoin
        "_layers_found": layers_found or [],
    }


def process_one_dxf(path: Path, fichier_to_sku=None, units_override=None):
    """Traite un fichier DXF. Retourne (record_dict, log_dict).

    Ne lève jamais d'exception hors de cette fonction pour un fichier
    individuel : toute erreur est capturée et transformée en statut
    d'erreur, afin que le batch puisse toujours continuer sur les fichiers
    suivants.

    fichier_to_sku : dict issu de mapping.csv (jamais de déduction par regex).
    units_override : dict issu de units_override.csv, clé = sku ou nom de
                      fichier -> (insunits:int, motif:str).
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
        "insunits": "",
        "proposition_unite": "",
        "proposition_motif": "",
        "message": "",
    }

    try:
        doc = ezdxf.readfile(str(path))
    except Exception as e:  # noqa: BLE001
        log["statut"] = "ERREUR_LECTURE"
        log["message"] = f"{type(e).__name__}: {e}"
        rec = build_error_record(sku, path.name, "ERREUR_LECTURE", None, log["message"])
        return rec, log

    insunits_raw = doc.header.get("$INSUNITS", 0)
    log["insunits"] = insunits_raw
    origine_unite = "header"

    if not insunits_raw or insunits_raw == 0:
        # Priorité 2 : units_override.csv, par sku puis par nom de fichier
        override = units_override.get(sku) or units_override.get(path.name)
        if override:
            insunits_raw, override_motif = override
            origine_unite = "override"
            log["insunits"] = insunits_raw
            log["message"] = f"Unité forcée via units_override.csv: insunits={insunits_raw} ({override_motif})"
        else:
            # Toujours pas d'unité connue -> proposition par plausibilité de
            # bbox, purement informative, jamais appliquée.
            msp_tmp = doc.modelspace()
            all_pts_native = []
            for e in msp_tmp.query("LWPOLYLINE POLYLINE"):
                try:
                    if isinstance(e, LWPolyline):
                        all_pts_native.extend([(p[0], p[1]) for p in e.get_points()])
                    elif isinstance(e, Polyline):
                        all_pts_native.extend(
                            [(v.dxf.location.x, v.dxf.location.y) for v in e.vertices]
                        )
                except Exception:
                    continue
            prop_insunits, prop_label, prop_motif = propose_unit_by_bbox(all_pts_native)
            log["proposition_unite"] = prop_label or ""
            log["proposition_motif"] = prop_motif

            msg = (
                f"$INSUNITS absent ou nul dans {path.name}, et aucune entrée "
                f"dans units_override.csv pour '{sku}' ou '{path.name}'. Unité "
                f"NON déduite automatiquement (règle stricte). "
                + (f"Proposition indicative par plausibilité de bbox: "
                   f"insunits={prop_insunits} ({prop_label}) — {prop_motif}. "
                   f"Ajouter cette ligne à units_override.csv pour confirmer."
                   if prop_insunits is not None else
                   f"Aucune proposition plausible calculable ({prop_motif}).")
            )
            log["statut"] = "ERREUR_UNITES"
            log["message"] = msg
            rec = build_error_record(sku, path.name, "ERREUR_UNITES", None, msg, origine_unite="override")
            return rec, log

    scale_to_mm = INSUNITS_TO_MM.get(insunits_raw)
    if scale_to_mm is None:
        msg = f"$INSUNITS={insunits_raw} dans {path.name} n'a pas de table de conversion mm connue."
        log["statut"] = "ERREUR_UNITES"
        log["message"] = msg
        rec = build_error_record(sku, path.name, "ERREUR_UNITES", insunits_raw, msg, origine_unite=origine_unite)
        return rec, log

    msp = doc.modelspace()
    layers_all = sorted({layer.dxf.name for layer in doc.layers})

    sagitta_native = FLATTEN_SAGITTA_MM / scale_to_mm

    candidates = []  # (layer, points_native_flattened, area_native)
    for e in msp.query("LWPOLYLINE POLYLINE"):
        layer = e.dxf.layer
        if is_noisy_layer(layer):
            continue
        try:
            is_closed = e.is_closed
        except Exception:
            is_closed = False
        if not is_closed:
            continue
        pts = flatten_entity_to_points(e, sagitta_native=sagitta_native)
        if len(pts) < 3:
            continue
        area = polygon_area(pts)
        candidates.append((layer, pts, area))

    if not candidates:
        msg = (
            f"Aucune polyligne fermée candidate trouvée dans {path.name}. "
            f"Calques présents: {', '.join(layers_all) if layers_all else '(aucun)'}."
        )
        log["statut"] = "ERREUR_SELECTION"
        log["message"] = msg
        rec = build_error_record(sku, path.name, "ERREUR_SELECTION", insunits_raw, msg, layers_all, origine_unite=origine_unite)
        return rec, log

    max_area = max(c[2] for c in candidates)
    top_candidates = [c for c in candidates if abs(c[2] - max_area) < 1e-9]

    if len(top_candidates) > 1:
        involved_layers = sorted({c[0] for c in top_candidates})
        msg = (
            f"{len(top_candidates)} polylignes fermées partagent l'aire maximale "
            f"dans {path.name} (calques concernés: {', '.join(involved_layers)}). "
            f"Ambiguïté réelle -> aucun choix implicite. "
            f"Calques présents au total: {', '.join(layers_all)}."
        )
        log["statut"] = "ERREUR_SELECTION"
        log["message"] = msg
        rec = build_error_record(sku, path.name, "ERREUR_SELECTION", insunits_raw, msg, layers_all, origine_unite=origine_unite)
        return rec, log

    chosen_layer, chosen_pts_native, chosen_area_native = top_candidates[0]

    # Conversion en mm
    pts_mm = [(x * scale_to_mm, y * scale_to_mm) for x, y in chosen_pts_native]
    pts_mm = ensure_clockwise(pts_mm)

    # Déduplication À LA SOURCE des sommets confondus/colinéaires
    # (< DEDUP_TOLERANCE_MM) — cf. dedupe_consecutive_vertices. Fait avant
    # la détection mur/plafond pour que les indices retournés restent
    # cohérents avec profil_mm final (jamais de décalage d'indices).
    nb_avant_dedup = len(pts_mm)
    pts_mm = dedupe_consecutive_vertices(pts_mm)
    nb_dedup_retires = nb_avant_dedup - len(pts_mm)

    # Détection auto des faces mur/plafond + recalage d'origine
    wall_idx, wall_auto, ceiling_idx, ceiling_auto, origin_x, origin_y = (
        detect_wall_and_ceiling_faces(pts_mm)
    )
    pts_mm_shifted = [(round(x - origin_x, 4), round(y - origin_y, 4)) for x, y in pts_mm]

    xs = [p[0] for p in pts_mm_shifted]
    ys = [p[1] for p in pts_mm_shifted]
    bbox_w = round(max(xs) - min(xs), 3) if xs else 0
    bbox_h = round(max(ys) - min(ys), 3) if ys else 0

    # hauteur_mur_mm : étendue verticale (y) de la face mur détectée, si trouvée
    hauteur_mur_mm = 0
    if wall_auto and wall_idx:
        wall_ys = [pts_mm_shifted[i][1] for i in wall_idx]
        hauteur_mur_mm = round(abs(max(wall_ys) - min(wall_ys)), 3)

    # projection_plafond_mm : étendue horizontale (x) de la face plafond détectée
    projection_plafond_mm = 0
    if ceiling_auto and ceiling_idx:
        ceiling_xs = [pts_mm_shifted[i][0] for i in ceiling_idx]
        projection_plafond_mm = round(abs(max(ceiling_xs) - min(ceiling_xs)), 3)

    famille = guess_famille(sku, layers_all)

    record = {
        "sku": sku,
        "marque": "",
        "famille": famille,
        "source": {
            "fichier": path.name,
            "insunits": insunits_raw,
            "unite_retenue": "mm",
            "origine_unite": origine_unite,
        },
        "profil_mm": [[x, y] for x, y in pts_mm_shifted],
        "face_pose_mur": {"indices": wall_idx, "auto": wall_auto},
        "face_pose_plafond": {"indices": ceiling_idx, "auto": ceiling_auto},
        "bbox_mm": {"w": bbox_w, "h": bbox_h},
        "hauteur_mur_mm": hauteur_mur_mm,
        "projection_plafond_mm": projection_plafond_mm,
        "motif": None,
        "assets": {"albedo": None, "normal": None},
        # dxf2profile.py extrait une COUPE TRANSVERSALE 2D : elle ne
        # mesure structurellement jamais une longueur de barre (ce n'est
        # pas une dimension du profil de coupe). Reste None ici ; seul
        # le catalogue papier (inject_cote_catalogue.py) ou une mesure de
        # maillage 3D (solid2profile.py) peuvent renseigner ce champ.
        "longueur_barre_mm": None,
        "longueur_barre_mm_origine": None,
        "prix_ml": None,
        "statut": "OK",
        "version_schema": SCHEMA_VERSION,
        "_message": (
            f"Contour retenu: calque '{chosen_layer}', "
            f"{len(pts_mm_shifted)} sommets après aplatissement "
            f"(tolérance {FLATTEN_SAGITTA_MM}mm)"
            + (
                f", {nb_dedup_retires} sommet(s) confondu(s)/colinéaire(s) "
                f"retiré(s) à la source (< {DEDUP_TOLERANCE_MM}mm)."
                if nb_dedup_retires > 0
                else "."
            )
        ),
        "_layers_found": layers_all,
    }

    log["statut"] = "OK"
    log["nb_sommets"] = len(pts_mm_shifted)
    log["nb_sommets_dedup_retires"] = nb_dedup_retires
    log["bbox_w_mm"] = bbox_w
    log["bbox_h_mm"] = bbox_h
    log["hauteur_mur_mm"] = hauteur_mur_mm
    log["projection_plafond_mm"] = projection_plafond_mm
    log["message"] = record["_message"]

    return record, log


def write_json(record: dict, out_dir: Path):
    sku = record["sku"]
    clean = {k: v for k, v in record.items() if not k.startswith("_")}
    out_path = out_dir / f"{sku}.json"
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(clean, f, ensure_ascii=False, indent=2)
    return out_path


def write_control_png(record: dict, out_dir: Path):
    """Génère un PNG coté du profil. Uniquement pour statut == OK.
    Retourne le chemin écrit, ou None si matplotlib indisponible."""
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

    # Origine
    ax.axhline(0, color="gray", linewidth=0.5, linestyle="--")
    ax.axvline(0, color="gray", linewidth=0.5, linestyle="--")
    ax.plot(0, 0, "r+", markersize=10, markeredgewidth=2)

    # Face mur / plafond en surbrillance — `indices` peut couvrir PLUS de
    # 2 sommets (tous les sommets consécutifs colinéaires de la face
    # réelle, cf. detect_wall_and_ceiling_faces) : on trace donc la
    # polyligne complète du run, pas seulement ses deux extrémités.
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
    title = (
        f"{sku} — {record.get('famille') or 'famille inconnue'}\n"
        f"bbox: {bbox['w']} x {bbox['h']} mm — {len(pts)} sommets — "
        f"unité source: INSUNITS={record['source']['insunits']}"
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
    parser.add_argument("--dxf-dir", default="/home/user/flutter_app/assets/dxf")
    parser.add_argument("--out-dir", default="/home/user/flutter_app/assets/profiles")
    parser.add_argument("--mapping", default=str(Path(__file__).parent / "mapping.csv"))
    parser.add_argument("--units-override", default=str(Path(__file__).parent / "units_override.csv"))
    parser.add_argument("--sku", nargs="*", default=None,
                         help="Liste explicite de SKU à traiter (résolus via mapping.csv en priorité, "
                              "sinon par nom de fichier <sku>.dxf). "
                              "Si omis, utiliser --all pour traiter tout le dossier.")
    parser.add_argument("--all", action="store_true", help="Traiter tous les .dxf du dossier --dxf-dir")
    args = parser.parse_args()

    dxf_dir = Path(args.dxf_dir)
    out_dir = Path(args.out_dir)
    control_dir = out_dir / "control"
    logs_dir = Path(__file__).parent / "logs"
    out_dir.mkdir(parents=True, exist_ok=True)
    control_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    if not dxf_dir.exists():
        print(f"ERREUR: dossier introuvable: {dxf_dir}", file=sys.stderr)
        sys.exit(1)

    fichier_to_sku = load_mapping(Path(args.mapping))
    sku_to_fichier = {v: k for k, v in fichier_to_sku.items()}
    units_override = load_units_override(Path(args.units_override))

    if args.sku:
        targets = []
        for sku in args.sku:
            # Priorité: mapping.csv (sku -> fichier réel), sinon <sku>.dxf par défaut
            fname = sku_to_fichier.get(sku, f"{sku}.dxf")
            p = dxf_dir / fname
            if not p.exists():
                print(f"AVERTISSEMENT: {p} introuvable, ignoré.", file=sys.stderr)
                continue
            targets.append(p)
    elif args.all:
        targets = sorted(dxf_dir.glob("*.dxf"))
    else:
        print("ERREUR: fournir --sku SKU1 SKU2 ... ou --all", file=sys.stderr)
        sys.exit(1)

    if not targets:
        print("Aucun fichier à traiter.")
        return

    print(f"Traitement de {len(targets)} fichier(s) DXF ...")
    print(f"(Règle: le batch continue toujours, même en cas d'erreur sur un fichier.)\n")

    logs = []
    n_ok = 0
    n_err = 0

    for path in targets:
        record, log = process_one_dxf(path, fichier_to_sku=fichier_to_sku, units_override=units_override)
        logs.append(log)

        json_path = write_json(record, out_dir)
        status_icon = "OK " if record["statut"] == "OK" else "ERR"
        print(f"[{status_icon}] {record['sku']:12s} statut={record['statut']:18s} -> {json_path.name}")

        if record["statut"] == "OK":
            n_ok += 1
            png_path = write_control_png(record, control_dir)
            if png_path:
                print(f"      PNG de contrôle -> {png_path}")
            elif plt is None:
                print(f"      (PNG de contrôle non généré: matplotlib indisponible)")
        else:
            n_err += 1
            print(f"      {record.get('_message', '')}")

    # Écriture du log de run
    timestamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = logs_dir / f"run_{timestamp}.csv"
    fieldnames = list(logs[0].keys())
    with log_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(logs)

    print(f"\n=== Résumé du run ===")
    print(f"Total traité : {len(targets)}")
    print(f"  OK          : {n_ok}")
    print(f"  Erreurs     : {n_err}")
    print(f"Log détaillé  : {log_path}")


if __name__ == "__main__":
    main()
