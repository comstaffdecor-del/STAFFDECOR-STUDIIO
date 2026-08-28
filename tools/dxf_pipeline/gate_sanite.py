#!/usr/bin/env python3
"""gate_sanite.py — GATE DE SANITÉ post-extraction (Piste A, brief calibration).

CONTEXTE : step2profile.py/solid2profile.py écrivent statut=OK sur des
profils qui, on vient de le vérifier sur l'échantillon pilote, peuvent être
géométriquement invalides sans que le script d'extraction ne s'en aperçoive
(picker de face mal aligné, dégénérescence en triangle, bruit de
tessellation). Ce gate ne RÉPARE ni ne SUPPRIME rien — il MARQUE. Un
profil qui échoue un critère BLOQUANT reçoit `statut_gate: "SUSPECT_GEOMETRIE"`
et la liste des motifs qui ont déclenché ce statut ; le JSON produit par
step2profile.py reste inchangé sur disque, ce script produit un rapport
séparé (jamais de réécriture in-place des profils).

RÈGLE DIRECTRICE (imposée) : le critère 1 (contrat loader) doit être une
COPIE LITTÉRALE des conditions de rejet de `loadProfileDims`
(lib/core/perspective/profile_dims.dart) — jamais une variante. Tout écart
entre ce gate et le loader créerait des profils marqués "sains" par le
gate mais rejetés silencieusement par l'app (ou l'inverse), ce qui est
précisément le piège que ce script existe pour éviter.

DÉCISION BLOQUANT / NON BLOQUANT (calibration sur les 18 pilotes) : sur cet
échantillon, les critères 3 à 6 n'ont attrapé AUCUN profil que les critères
1 et 2 n'attrapaient déjà — sauf un FAUX POSITIF (D748, 31 sommets, profil
visuellement sain, rejeté à tort par BRUIT_TESSELLATION). Calibrer un seuil
sur un échantillon où le critère démontre une valeur nulle et une erreur
serait arbitraire. Décision : seuls les critères 1 et 2 sont BLOQUANTS et
déterminent `statut_gate`. Les critères 3 à 6 restent calculés et rapportés,
mais uniquement comme DRAPEAUX (champ `drapeaux`, JSON et CSV) — ils ne
contribuent plus jamais à `statut_gate`. Cet invariant est central : le
gate ne doit jamais marquer OK un profil que loadProfileDims rejetterait
silencieusement (garanti par le critère 1+2 étant la copie littérale du
contrat), et il ne doit jamais marquer SUSPECT sur la seule foi d'un critère
qui s'est avéré, sur les données disponibles, sans pouvoir discriminant
propre. Le batch sur ~165 profils donnera la distribution réelle de ces
drapeaux ; c'est sur cette distribution (n=165, pas n=1) que d'éventuels
seuils bloquants futurs devront être choisis.

CRITÈRES BLOQUANTS (2, déterminent statut_gate) :
  1. CONTRAT_LOADER_*        — reprise exacte des 4 conditions de rejet
     de loadProfileDims (statut, profil_mm non vide, indices mur/plafond
     non vides), PLUS un seuil de 3 points minimum (plus strict que le
     loader littéral qui accepte tout non-vide, jamais moins strict).
  2. DEBORD_PLAN_MUR/PLAFOND — reprise littérale de l'assertion debug du
     loader (tolérance lue depuis assets/config/gate_config.json,
     SOURCE UNIQUE partagée avec le loader Dart -- 0.5mm depuis le
     batch tolérance-bruit du 2026-08-XX, 0.001mm avant -- jamais une
     valeur recopiée en dur séparément dans ce fichier).

CRITÈRES NON BLOQUANTS (4, calculés et rapportés comme drapeaux uniquement,
AUCUN effet sur statut_gate) :
  3. SOMMETS_INSUFFISANTS    — sommets EFFECTIFS (après suppression des
     sommets quasi colinéaires, angle intérieur > 175°), seuil indicatif 5.
     ATTENTION — DÉFAUT CONNU, NON CORRIGÉ : ce compte SOUS-ESTIME les
     profils courbes (voir avertissement détaillé dans la docstring de
     `sommets_effectifs()`). Ne doit pas servir de critère bloquant en
     l'état.
  4. BRUIT_TESSELLATION      — nombre de segments de la boucle fermée dont
     la longueur est < 1% de la diagonale bbox. Seuil indicatif PROVISOIRE.
     Défaut connu : ne distingue pas des segments courts GROUPÉS/consécutifs
     (probable détail réel, ex. feuillure — cas D748, faux positif observé)
     d'segments courts DISPERSÉS sur le contour (probable bruit de
     tessellation — cas PLIN20). Reformulation candidate (comptage de
     grappes plutôt que de segments) à décider après la distribution sur
     le batch de ~165, pas avant.
  5. JITTER_CONTOUR          — inversions de signe de dy entre deux
     segments ADJACENTS tous deux < 2% de diag, zone morte |dy| < 0.5%
     de diag (évite les faux positifs sur profils ornementaux riches à
     inversions légitimes, ex. D748/31 sommets). Seuil indicatif PROVISOIRE.
     Constat sur les 18 pilotes : count=0 partout, y compris PLIN20 (les
     inversions candidates y échouent toutes le filtre zone-morte ou le
     filtre longueur-segments-adjacents). Conservé tel quel car il ne
     change aucune décision actuellement ; si le batch de ~165 confirme un
     compte nul généralisé alors que des profils sortent visuellement
     bruités, la formulation sera considérée morte et supprimée sans
     regret.
  6. SECTION_PLATE           — ratio min(w,h)/max(w,h) < 0.15, PORTÉE
     LIMITÉE : appliqué uniquement aux SKU de la famille corniche/moulure
     (liste explicite ci-dessous — le champ JSON `famille` est toujours
     null en pratique dans ce jeu de données, aucune détection auto
     possible depuis le JSON seul). Jamais appliqué à une plinthe dans
     cette passe (elles sont plates par nature, ce n'est pas un signal
     d'anomalie pour elles) — à ne pas transposer sans révision explicite.

SIGNAL NON BLOQUANT SUPPLÉMENTAIRE (ne contribue jamais à statut_gate ni aux
drapeaux — informatif uniquement) :
  - projection_plafond_mm == bbox_mm.w (égalité exacte) : signe probable
    d'un plan de pose dégénéré (observé sur PLIN20).
"""

import argparse
import csv
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).parent
DEFAULT_PROFILES_DIR = HERE.parent.parent / "assets" / "profiles"
DEFAULT_OUTPUT_CSV = HERE / "gate_sanite_rapport.csv"
GATE_CONFIG_JSON = HERE.parent.parent / "assets" / "config" / "gate_config.json"


def _load_assertion_tol_mm() -> float:
    """Lit `assertion_tol_mm` depuis `assets/config/gate_config.json` —
    SOURCE UNIQUE partagée avec `lib/core/perspective/profile_dims.dart`
    (`_loadAssertionTolMm`). Voir ce JSON pour la justification physique
    de la valeur et l'historique du changement 0.001mm -> 0.5mm.

    FAIL-CLOSED, imposé, symétrique du côté Dart : si le fichier est
    absent, illisible ou malformé, on retombe sur l'ANCIENNE tolérance
    stricte (0.001mm) — jamais une valeur plus permissive par défaut. Ne
    JAMAIS recopier 0.5 en dur ici en guise de secours : ce serait
    réintroduire la duplication que ce fichier JSON existe pour éliminer.
    """
    fallback_strict = 0.001
    try:
        with open(GATE_CONFIG_JSON, encoding="utf-8") as fp:
            data = json.load(fp)
        v = data.get("assertion_tol_mm")
        if isinstance(v, (int, float)) and v > 0:
            return float(v)
    except (OSError, json.JSONDecodeError, AttributeError):
        pass
    print(
        f"ATTENTION: {GATE_CONFIG_JSON} indisponible/invalide -- "
        f"repli sur l'ancienne tolerance stricte ({fallback_strict}mm), "
        "jamais une valeur plus permissive par defaut.",
        file=sys.stderr,
    )
    return fallback_strict


# --- Seuils fixes (spécifiés, non provisoires) ---------------------------
ANGLE_COLINEAIRE_DEG = 175.0
SOMMETS_EFFECTIFS_MIN = 5
ASSERTION_TOL_MM = _load_assertion_tol_mm()
PLATITUDE_RATIO_MAX = 0.15
PROFIL_MM_MIN_POINTS = 3

# --- Seuils indicatifs (critères NON BLOQUANTS 3 à 5 — drapeaux only) ---
BRUIT_SEG_RATIO = 0.01          # 1% de diag
BRUIT_SEUIL_PROVISOIRE = 3      # nombre de segments sous le seuil
JITTER_SEG_RATIO = 0.02         # 2% de diag (les deux segments adjacents)
JITTER_DEADZONE_RATIO = 0.005   # 0.5% de diag (zone morte |dy|)
JITTER_SEUIL_PROVISOIRE = 3     # nombre d'inversions

# Portée du critère 6 (SECTION_PLATE) — liste explicite, PAS de détection
# automatique depuis le champ JSON `famille` (toujours null en pratique
# dans ce jeu de données). TAL26 classé "moulure" (catalogue: "Talon pour
# PLIN25.PC.SP") — classification manuelle, à confirmer si contestée.
FAMILLE_CORNICHE_MOULURE_SKUS = {
    "D555", "D562", "D576", "D614", "D620", "D631", "D705", "D706",
    "D709", "D718", "D720", "D748", "D891", "TAL26",
}


def polygon_closed_segments(pts):
    n = len(pts)
    return [(pts[i], pts[(i + 1) % n]) for i in range(n)]


def seg_len(p0, p1):
    return math.hypot(p1[0] - p0[0], p1[1] - p0[1])


def interior_angle_deg(p_prev, p_i, p_next):
    """Angle (degrés) entre les vecteurs p_i->p_prev et p_i->p_next.
    ~180° = p_i quasi colinéaire avec ses deux voisins (sommet
    superflu, candidat à suppression pour le compte de sommets
    effectifs)."""
    v1 = (p_prev[0] - p_i[0], p_prev[1] - p_i[1])
    v2 = (p_next[0] - p_i[0], p_next[1] - p_i[1])
    n1 = math.hypot(*v1)
    n2 = math.hypot(*v2)
    if n1 == 0 or n2 == 0:
        return 180.0  # point dégénéré confondu avec un voisin -> traité comme colinéaire
    cos_a = max(-1.0, min(1.0, (v1[0] * v2[0] + v1[1] * v2[1]) / (n1 * n2)))
    return math.degrees(math.acos(cos_a))


def sommets_effectifs(pts):
    """Retourne (n_brut, n_effectifs, indices_supprimes). Suppression en
    UNE passe sur le polygone original (pas de suppression itérative en
    cascade) — simple, déterministe, suffisant pour distinguer un
    polygone dégénéré (PLIN12) d'une corniche à arêtes vives (D706).

    ATTENTION — DÉFAUT CONNU (non corrigé, NON BLOQUANT pour cette
    raison précise) : n_eff SOUS-ESTIME les profils courbes. Chaque point
    n'est comparé qu'à ses DEUX VOISINS D'ORIGINE — sur un arc discrétisé
    finement (ex. D718 : quinze points consécutifs à 175.02° chacun), tous
    les points restent localement quasi colinéaires avec leurs voisins
    immédiats même si l'arc, pris dans son ensemble, a une flèche/courbure
    réelle et significative. Résultat observé : D718 tombe de n_brut=22 à
    n_eff=6, D720 de 25 à 6 — un arc entier disparaît en cascade. Cette
    métrique mesure donc le nombre de COINS DURS, pas le nombre de sommets
    UTILES ; ce n'est pas une marge mince sur le seuil, c'est la métrique
    elle-même qui est fausse pour les profils courbes. Direction de
    correction pour plus tard (NON implémentée ici, à ne coder qu'après
    validation) : mesurer l'écart perpendiculaire en millimètres au
    segment joignant les voisins retenus — simplification à la
    Douglas-Peucker avec tolérance en fraction de diagonale — car cet
    écart s'accumule le long d'un arc et le préserve, contrairement à
    l'angle local qui reste proche de 180° tout au long d'une courbe fine
    et s'élimine ainsi à tort. C'est pourquoi ce critère est un DRAPEAU
    non bloquant : il ne doit pas servir de critère bloquant en l'état.
    """
    n = len(pts)
    if n < 3:
        return n, n, []
    removed = []
    kept = 0
    for i in range(n):
        p_prev = pts[(i - 1) % n]
        p_i = pts[i]
        p_next = pts[(i + 1) % n]
        ang = interior_angle_deg(p_prev, p_i, p_next)
        if ang > ANGLE_COLINEAIRE_DEG:
            removed.append(i)
        else:
            kept += 1
    return n, kept, removed


def bruit_tessellation_count(pts, diag):
    seuil = diag * BRUIT_SEG_RATIO
    lens = [seg_len(a, b) for a, b in polygon_closed_segments(pts)]
    return sum(1 for L in lens if L < seuil), lens


def jitter_count(pts, diag):
    """Inversions de signe de dy entre segments ADJACENTS, filtrées :
    - zone morte : un dy dont |dy| < deadzone n'est jamais considéré
      comme porteur de signe (évite de compter une inversion sur un
      quasi-plat).
    - les DEUX segments adjacents à l'inversion doivent être < seg_seuil
      (2% de diag) — cible le tremblement local, pas une vraie alternance
      de pente sur un motif ornemental riche à grands segments."""
    n = len(pts)
    lens = [seg_len(a, b) for a, b in polygon_closed_segments(pts)]
    dys = [pts[(i + 1) % n][1] - pts[i][1] for i in range(n)]
    deadzone = diag * JITTER_DEADZONE_RATIO
    seg_seuil = diag * JITTER_SEG_RATIO
    count = 0
    details = []
    for i in range(n):
        prev_i = (i - 1) % n
        dy_prev, dy_cur = dys[prev_i], dys[i]
        if abs(dy_prev) < deadzone or abs(dy_cur) < deadzone:
            continue
        if (dy_prev > 0) == (dy_cur > 0):
            continue
        if lens[prev_i] < seg_seuil and lens[i] < seg_seuil:
            count += 1
            details.append((prev_i, i))
    return count, details


def check_gate(sku, data):
    """Applique les critères. Retourne un dict complet.

    `motifs` (bloquant) : uniquement critères 1 et 2 (contrat loader +
    débord de plan). Détermine `statut_gate`.

    `drapeaux` (non bloquant) : critères 3 à 6 (sommets effectifs, bruit
    de tessellation, jitter, platitude). Toujours calculés et rapportés,
    mais SANS AUCUN EFFET sur `statut_gate` — voir décision de calibration
    en tête de fichier. Les valeurs brutes de chaque critère (y compris
    pour ceux dont le seuil est indicatif) sont TOUJOURS rapportées,
    indépendamment de la présence d'un drapeau à ce seuil."""
    motifs = []       # BLOQUANT -> statut_gate
    drapeaux = []     # NON BLOQUANT -> champ drapeaux uniquement
    profil = data.get("profil_mm") or []
    statut = data.get("statut")
    face_mur_idx = (data.get("face_pose_mur") or {}).get("indices") or []
    face_plafond_idx = (data.get("face_pose_plafond") or {}).get("indices") or []
    bbox = data.get("bbox_mm") or {}
    w, h = bbox.get("w"), bbox.get("h")

    # --- Critère 1 (BLOQUANT) : contrat loader (copie littérale + seuil >=3 pts) ---
    if statut != "OK":
        motifs.append("CONTRAT_LOADER_STATUT_NON_OK")
    if len(profil) < PROFIL_MM_MIN_POINTS:
        motifs.append(f"CONTRAT_LOADER_PROFIL_INSUFFISANT (n={len(profil)})")
    if not face_mur_idx:
        motifs.append("CONTRAT_LOADER_MUR_VIDE")
    if not face_plafond_idx:
        motifs.append("CONTRAT_LOADER_PLAFOND_VIDE")

    can_geom = (
        statut == "OK"
        and len(profil) >= PROFIL_MM_MIN_POINTS
        and w is not None and h is not None
        and w > 0 and h > 0
    )

    diag = math.hypot(w, h) if (can_geom) else None
    debord_mur_mm = None
    debord_plafond_mm = None
    n_brut = len(profil)
    n_eff = None
    bruit_n = None
    jitter_n = None
    platitude_ratio = None
    platitude_applique = False

    # --- Critère 2 (BLOQUANT) : débord de plan (réplique littérale de l'assertion) ---
    if can_geom and face_mur_idx:
        wallX = profil[face_mur_idx[0]][0]
        maxdx = max(abs(p[0] - wallX) for p in profil)
        debord_mur_mm = abs(maxdx - w)
        if debord_mur_mm > ASSERTION_TOL_MM:
            motifs.append(f"DEBORD_PLAN_MUR (ecart={debord_mur_mm:.3f}mm)")

    if can_geom and face_plafond_idx:
        ceilY = profil[face_plafond_idx[0]][1]
        maxdy = max(abs(p[1] - ceilY) for p in profil)
        debord_plafond_mm = abs(maxdy - h)
        if debord_plafond_mm > ASSERTION_TOL_MM:
            motifs.append(f"DEBORD_PLAN_PLAFOND (ecart={debord_plafond_mm:.3f}mm)")

    # --- Critère 3 (NON BLOQUANT — drapeau) : sommets effectifs ---
    if can_geom:
        n_brut, n_eff, _removed = sommets_effectifs(profil)
        if n_eff < SOMMETS_EFFECTIFS_MIN:
            drapeaux.append(
                f"SOMMETS_INSUFFISANTS (brut={n_brut}, effectifs={n_eff})"
            )

    # --- Critères 4 et 5 (NON BLOQUANTS — drapeaux) : comptes TOUJOURS
    # calculés et rapportés, seuil indicatif appliqué uniquement pour
    # décider de la présence du drapeau (jamais de statut_gate) ---
    if can_geom and diag:
        bruit_n, _ = bruit_tessellation_count(profil, diag)
        if bruit_n >= BRUIT_SEUIL_PROVISOIRE:
            drapeaux.append(
                f"BRUIT_TESSELLATION (count={bruit_n}, seuil_indicatif="
                f"{BRUIT_SEUIL_PROVISOIRE})"
            )
        jitter_n, _ = jitter_count(profil, diag)
        if jitter_n >= JITTER_SEUIL_PROVISOIRE:
            drapeaux.append(
                f"JITTER_CONTOUR (count={jitter_n}, seuil_indicatif="
                f"{JITTER_SEUIL_PROVISOIRE})"
            )

    # --- Critère 6 (NON BLOQUANT — drapeau) : platitude, portée limitée
    # corniche/moulure ---
    if can_geom:
        platitude_ratio = min(w, h) / max(w, h)
        platitude_applique = sku in FAMILLE_CORNICHE_MOULURE_SKUS
        if platitude_applique and platitude_ratio < PLATITUDE_RATIO_MAX:
            drapeaux.append(f"SECTION_PLATE (ratio={platitude_ratio:.3f})")

    # --- Signal non bloquant supplémentaire (informatif, hors drapeaux) ---
    proj = data.get("projection_plafond_mm")
    signal_projection_egale_bbox_w = (
        proj is not None and w is not None and proj == w
    )

    return {
        "sku": sku,
        "statut_gate": "SUSPECT_GEOMETRIE" if motifs else "OK",
        "motifs": motifs,
        "drapeaux": drapeaux,
        "n_sommets_brut": n_brut,
        "n_sommets_effectifs": n_eff,
        "debord_mur_mm": debord_mur_mm,
        "debord_plafond_mm": debord_plafond_mm,
        "bruit_tessellation_count": bruit_n,
        "jitter_contour_count": jitter_n,
        "platitude_ratio": platitude_ratio,
        "platitude_critere_applique": platitude_applique,
        "signal_projection_egale_bbox_w": signal_projection_egale_bbox_w,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--profiles-dir", default=str(DEFAULT_PROFILES_DIR))
    ap.add_argument("--output", default=str(DEFAULT_OUTPUT_CSV))
    ap.add_argument(
        "--sku", nargs="*", default=None,
        help="Limiter le rapport a ces SKU (sinon: tout assets/profiles/*.json)",
    )
    args = ap.parse_args()

    profiles_dir = Path(args.profiles_dir)
    if not profiles_dir.exists():
        print(f"ERREUR: dossier introuvable: {profiles_dir}", file=sys.stderr)
        sys.exit(1)

    files = sorted(profiles_dir.glob("*.json"))
    if args.sku:
        wanted = set(args.sku)
        files = [f for f in files if f.stem in wanted]

    results = []
    for f in files:
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            print(f"ATTENTION: JSON illisible {f.name}: {e}", file=sys.stderr)
            continue
        sku = data.get("sku", f.stem)
        results.append(check_gate(sku, data))

    fieldnames = [
        "sku", "statut_gate", "motifs", "drapeaux", "n_sommets_brut",
        "n_sommets_effectifs", "debord_mur_mm", "debord_plafond_mm",
        "bruit_tessellation_count", "jitter_contour_count",
        "platitude_ratio", "platitude_critere_applique",
        "signal_projection_egale_bbox_w",
    ]
    with open(args.output, "w", newline="", encoding="utf-8") as fp:
        writer = csv.DictWriter(fp, fieldnames=fieldnames)
        writer.writeheader()
        for r in results:
            row = dict(r)
            row["motifs"] = "; ".join(r["motifs"])
            row["drapeaux"] = "; ".join(r["drapeaux"])
            writer.writerow(row)

    nb_ok = sum(1 for r in results if r["statut_gate"] == "OK")
    nb_suspect = sum(1 for r in results if r["statut_gate"] == "SUSPECT_GEOMETRIE")
    nb_drapeaux = sum(1 for r in results if r["drapeaux"])
    print(f"=== gate_sanite: {len(results)} profils analyses -> {args.output} ===")
    print(f"  OK (statut_gate)           : {nb_ok}")
    print(f"  SUSPECT_GEOMETRIE (bloquant): {nb_suspect}")
    print(f"  avec >=1 drapeau (non bloquant, info): {nb_drapeaux}")
    print()
    for r in results:
        marker = "⚠️ " if r["statut_gate"] == "SUSPECT_GEOMETRIE" else "✅ "
        print(f"{marker}{r['sku']:8s} n_brut={r['n_sommets_brut']} "
              f"n_eff={r['n_sommets_effectifs']} "
              f"bruit={r['bruit_tessellation_count']} "
              f"jitter={r['jitter_contour_count']} "
              f"platitude={r['platitude_ratio']}")
        for m in r["motifs"]:
            print(f"      - [BLOQUANT] {m}")
        for d in r["drapeaux"]:
            print(f"      - [drapeau]  {d}")


if __name__ == "__main__":
    main()
