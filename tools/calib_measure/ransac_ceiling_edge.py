#!/usr/bin/env python3
"""Mesure RANSAC de la ligne "filet sous denticules" (Bug 2, Option B).

CE QUE CE SCRIPT MESURE (et ce qu'il NE mesure PAS) :

  Il mesure la ligne visible du "filet" (fine moulure lisse sous le rang de
  denticules de la corniche EXISTANTE, déjà présente sur la photo
  haussmann.jpg), PAS l'arête théorique mur∩plafond (qui est occultée,
  invisible sur cette photo -- voir la discussion Option A/Option B dans
  persp_calib.dart et calib_to_camera.dart). Le décalage vertical vers
  l'arête théorique (`PerspCalib.ceilEdgeOffsetM`) reste une mesure
  SEPARÉE, non traitée par ce script (nécessiterait une mesure indépendante
  de la hauteur en saillie de la corniche existante -- non disponible en
  brut à ce jour).

MÉTHODE (imposée, remplace la recherche argmax de gradient sur bande fixe
plafond -- abandonnée car elle sature en faux positifs sur une corniche
ornée) :

  1. Seed : ligne horizontale a priori y0(x) = Y0_SEED (estimation visuelle
     grossière, non retenue comme résultat final).
  2. Passe 1 : pour chaque x d'un échantillonnage régulier sur
     x in [X_MIN, X_MAX], extrait le profil de luminance dans une fenêtre
     verticale glissante de demi-largeur WIN1_HALF centrée sur y0(x).
     Corrèle (Pearson) ce profil lissé (gaussien, sigma=SMOOTH_SIGMA) avec
     un noyau de bord en marche (step kernel, +-1 de part et d'autre du
     centre testé), à chaque décalage entier possible dans la fenêtre ;
     retient le décalage de corrélation |r| maximale, puis affine en
     sous-pixel par interpolation parabolique des 3 corrélations autour du
     maximum. Rejette la colonne si |r_max| < CORR_THRESHOLD_PASS1.
     Ajuste une droite (moindres carrés ordinaires) sur les points retenus
     -> (pente1, ordonnée1).
  3. Passe 2 (raffinement) : refait la même détection par colonne, mais
     centrée cette fois sur la prédiction y_pred(x) = pente1*x + ordonnée1
     (fenêtre plus étroite, WIN2_HALF), avec le même seuil de rejet
     CORR_THRESHOLD_PASS2 (potentiellement différent). Puis ajuste la
     droite finale par RANSAC (ligne = 2 points tirés au hasard parmi les
     points retenus de la passe 2, comptage des inliers sous tolérance
     RANSAC_INLIER_TOL_PX, meilleur modèle = plus grand nombre d'inliers,
     puis ré-ajustement moindres carrés final sur les seuls inliers).

SORTIE BRUTE (imprimée sur stdout, jamais résumée sans avoir été produite
par ce script) : nombre de colonnes échantillonnées / retenues passe 1 /
retenues passe 2 (avant RANSAC) / inliers RANSAC (retenus finaux) /
rejetées (colonnes totales - inliers finaux), pente finale, ordonnée à
l'origine finale, résidu RMS (sur les inliers finaux), et les deux points
évalués (ceilL, ceilR) aux abscisses X_EVAL_L / X_EVAL_R.
"""
import json
import random
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter1d

# ---- Paramètres (tous explicites, aucun magique caché) ----
IMAGE_PATH = "assets/demo_scenes/haussmann.jpg"
X_MIN, X_MAX, X_STEP = 280, 1900, 5          # échantillonnage régulier imposé
Y0_SEED = 165.0                                # seed grossier (a priori visuel, PAS un résultat)
WIN1_HALF = 40                                 # demi-largeur fenêtre d'EXTRACTION passe 1 (px) -- doit être > KERNEL_HALF pour laisser de la marge de glissement
WIN2_HALF = 20                                 # demi-largeur fenêtre d'EXTRACTION passe 2 (px), resserrée sur la prédiction -- doit rester > KERNEL_HALF
KERNEL_HALF = 8                                # demi-largeur du noyau de bord en marche (px) -- distinct de WIN*_HALF (bug initial : les deux étaient confondus, fenêtre de recherche = 0 pixel de marge)
SMOOTH_SIGMA = 1.2                             # lissage gaussien du profil avant corrélation
CORR_THRESHOLD_PASS1 = 0.55
CORR_THRESHOLD_PASS2 = 0.55
RANSAC_INLIER_TOL_PX = 3.0
RANSAC_ITERS = 2000
RANSAC_SEED = 20260810                         # graine fixe -> reproductible
X_EVAL_L = 300.0                               # proche de l'actuel ceilL px~307.2, extrapolation minimale
X_EVAL_R = 1900.0                              # borne droite du domaine mesuré (cf. limite prudente utilisateur ~1850-1900)


def step_kernel(n_half):
    """Noyau de bord en marche, longueur 2*n_half, moyenne nulle."""
    k = np.concatenate([-np.ones(n_half), np.ones(n_half)])
    return k


def pearson_corr(a, b):
    a = a - a.mean()
    b = b - b.mean()
    denom = np.sqrt((a * a).sum() * (b * b).sum())
    if denom < 1e-9:
        return 0.0
    return float((a * b).sum() / denom)


def detect_edge_in_column(profile_1d, y_start, kernel_half):
    """Cherche, dans profile_1d (déjà extrait sur [y_start, y_start+len),
    longueur = 2*win_half avec win_half > kernel_half pour laisser une
    marge de glissement), le décalage (indice local) de corrélation |r|
    maximale avec un noyau de bord en marche de longueur 2*kernel_half, en
    testant tous les centres possibles c in [kernel_half, len-kernel_half).
    Retourne (y_subpixel_absolu, r_max_signe) ou (None, 0.0) si aucun centre
    testable (fenêtre d'extraction trop courte).
    """
    n = len(profile_1d)
    kernel = step_kernel(kernel_half)
    best_c = None
    best_r = 0.0
    corrs = {}
    for c in range(kernel_half, n - kernel_half):
        window = profile_1d[c - kernel_half:c + kernel_half]
        r = pearson_corr(window, kernel)
        corrs[c] = r
        if abs(r) > abs(best_r):
            best_r = r
            best_c = c
    if best_c is None:
        return None, 0.0
    # Raffinement sous-pixel par interpolation parabolique des corrélations
    # (en |r|) autour du maximum, sur les 3 points c-1, c, c+1 si disponibles.
    c = best_c
    if (c - 1) in corrs and (c + 1) in corrs:
        r_m1, r_0, r_p1 = abs(corrs[c - 1]), abs(corrs[c]), abs(corrs[c + 1])
        denom = (r_m1 - 2 * r_0 + r_p1)
        if abs(denom) > 1e-9:
            delta = 0.5 * (r_m1 - r_p1) / denom
            delta = max(-1.0, min(1.0, delta))
        else:
            delta = 0.0
    else:
        delta = 0.0
    y_sub = y_start + c + delta
    return y_sub, best_r


def extract_column(arr, x, y_center, win_half):
    h = arr.shape[0]
    y_start = int(round(y_center - win_half))
    y_end = int(round(y_center + win_half))
    y_start = max(0, y_start)
    y_end = min(h, y_end)
    raw = arr[y_start:y_end, x].astype(np.float64)
    smoothed = gaussian_filter1d(raw, sigma=SMOOTH_SIGMA)
    return smoothed, y_start


def run_pass(arr, xs, y_pred_fn, win_half, kernel_half, corr_threshold):
    retained = []
    rejected_x = []
    for x in xs:
        y_center = y_pred_fn(x)
        profile, y_start = extract_column(arr, x, y_center, win_half)
        y_sub, r = detect_edge_in_column(profile, y_start, kernel_half)
        if y_sub is None or abs(r) < corr_threshold:
            rejected_x.append(x)
            continue
        retained.append((x, y_sub, r))
    return retained, rejected_x


def ols_fit(points):
    xs = np.array([p[0] for p in points], dtype=np.float64)
    ys = np.array([p[1] for p in points], dtype=np.float64)
    A = np.vstack([xs, np.ones_like(xs)]).T
    slope, intercept = np.linalg.lstsq(A, ys, rcond=None)[0]
    return float(slope), float(intercept)


def ransac_fit(points, iters, tol, seed):
    rng = random.Random(seed)
    pts = [(p[0], p[1]) for p in points]
    n = len(pts)
    if n < 2:
        raise ValueError("RANSAC: pas assez de points retenus pour ajuster une droite.")
    best_inliers = []
    best_slope, best_intercept = None, None
    for _ in range(iters):
        i, j = rng.sample(range(n), 2)
        x1, y1 = pts[i]
        x2, y2 = pts[j]
        if abs(x2 - x1) < 1e-6:
            continue
        slope = (y2 - y1) / (x2 - x1)
        intercept = y1 - slope * x1
        residuals = [abs(y - (slope * x + intercept)) for x, y in pts]
        inliers = [k for k, r in enumerate(residuals) if r <= tol]
        if len(inliers) > len(best_inliers):
            best_inliers = inliers
            best_slope, best_intercept = slope, intercept
    if best_slope is None:
        raise ValueError("RANSAC: aucun modèle valide trouvé (tous les tirages dégénérés).")
    inlier_pts = [pts[k] for k in best_inliers]
    final_slope, final_intercept = ols_fit(inlier_pts)
    residuals_final = [
        (y - (final_slope * x + final_intercept)) for x, y in inlier_pts
    ]
    rms = float(np.sqrt(np.mean(np.square(residuals_final))))
    return final_slope, final_intercept, best_inliers, rms


def main():
    im = Image.open(IMAGE_PATH).convert("L")
    arr = np.asarray(im, dtype=np.float64)
    h, w = arr.shape
    print(f"[info] image={IMAGE_PATH} shape(H,W)=({h},{w})")

    xs = list(range(X_MIN, X_MAX + 1, X_STEP))
    n_sampled = len(xs)
    print(f"[pass1] x_sampling: X_MIN={X_MIN} X_MAX={X_MAX} X_STEP={X_STEP} n_sampled={n_sampled}")

    # ---- Passe 1 : seed horizontal ----
    retained1, rejected1 = run_pass(
        arr, xs, y_pred_fn=lambda x: Y0_SEED, win_half=WIN1_HALF,
        kernel_half=KERNEL_HALF, corr_threshold=CORR_THRESHOLD_PASS1,
    )
    print(f"[pass1] retenues={len(retained1)} rejetees={len(rejected1)} (seuil |r|>={CORR_THRESHOLD_PASS1})")
    if len(retained1) < 2:
        print("[FATAL] passe 1 : trop peu de colonnes retenues pour amorcer un ajustement.")
        sys.exit(1)
    slope1, intercept1 = ols_fit([(p[0], p[1]) for p in retained1])
    print(f"[pass1] droite amorce (moindres carres, PAS le resultat final) : pente={slope1:.6f} ordonnee={intercept1:.4f}")

    # ---- Passe 2 : raffinement centre sur la prediction passe 1 ----
    y_pred_fn2 = lambda x: slope1 * x + intercept1
    retained2, rejected2 = run_pass(
        arr, xs, y_pred_fn=y_pred_fn2, win_half=WIN2_HALF,
        kernel_half=KERNEL_HALF, corr_threshold=CORR_THRESHOLD_PASS2,
    )
    n_rejected2 = n_sampled - len(retained2)
    print(f"[pass2] retenues={len(retained2)} rejetees={n_rejected2} (seuil |r|>={CORR_THRESHOLD_PASS2}, fenetre demi-largeur={WIN2_HALF})")
    if len(retained2) < 2:
        print("[FATAL] passe 2 : trop peu de colonnes retenues pour RANSAC.")
        sys.exit(1)

    # ---- RANSAC final sur les points de la passe 2 ----
    final_slope, final_intercept, inlier_idx, rms = ransac_fit(
        retained2, iters=RANSAC_ITERS, tol=RANSAC_INLIER_TOL_PX, seed=RANSAC_SEED,
    )
    n_inliers = len(inlier_idx)
    n_total_columns = n_sampled
    n_outliers_ransac = len(retained2) - n_inliers
    n_rejected_total = n_total_columns - n_inliers

    y_at_L = final_slope * X_EVAL_L + final_intercept
    y_at_R = final_slope * X_EVAL_R + final_intercept

    print("")
    print("==================== RESULTAT BRUT (RANSAC final) ====================")
    print(f"colonnes echantillonnees total       = {n_total_columns}")
    print(f"colonnes retenues passe1             = {len(retained1)}")
    print(f"colonnes retenues passe2 (pre-RANSAC) = {len(retained2)}")
    print(f"inliers RANSAC (retenus finaux)      = {n_inliers}")
    print(f"outliers RANSAC (parmi retenues passe2) = {n_outliers_ransac}")
    print(f"rejetees au total (colonnes - inliers)  = {n_rejected_total}")
    print(f"pente finale (dy/dx, convention image y-vers-le-bas) = {final_slope:.6f}")
    print(f"ordonnee a l'origine finale (px, x=0)   = {final_intercept:.4f}")
    print(f"residu RMS (inliers, px)               = {rms:.4f}")
    print(f"point evalue ceilL : x={X_EVAL_L:.1f} y={y_at_L:.4f}")
    print(f"point evalue ceilR : x={X_EVAL_R:.1f} y={y_at_R:.4f}")
    print("========================================================================")

    out = {
        "image": IMAGE_PATH,
        "image_shape_hw": [h, w],
        "params": {
            "X_MIN": X_MIN, "X_MAX": X_MAX, "X_STEP": X_STEP,
            "Y0_SEED": Y0_SEED, "WIN1_HALF": WIN1_HALF, "WIN2_HALF": WIN2_HALF,
            "SMOOTH_SIGMA": SMOOTH_SIGMA,
            "CORR_THRESHOLD_PASS1": CORR_THRESHOLD_PASS1,
            "CORR_THRESHOLD_PASS2": CORR_THRESHOLD_PASS2,
            "RANSAC_INLIER_TOL_PX": RANSAC_INLIER_TOL_PX,
            "RANSAC_ITERS": RANSAC_ITERS,
            "RANSAC_SEED": RANSAC_SEED,
            "X_EVAL_L": X_EVAL_L, "X_EVAL_R": X_EVAL_R,
        },
        "pass1_seed_line": {"slope": slope1, "intercept": intercept1, "n_retained": len(retained1), "n_rejected": len(rejected1)},
        "pass2": {"n_retained_pre_ransac": len(retained2), "n_rejected": n_rejected2},
        "ransac_final": {
            "n_columns_sampled": n_total_columns,
            "n_inliers": n_inliers,
            "n_outliers_within_pass2": n_outliers_ransac,
            "n_rejected_total": n_rejected_total,
            "slope": final_slope,
            "intercept": final_intercept,
            "rms_residual_px": rms,
            "ceilL_px": {"x": X_EVAL_L, "y": y_at_L},
            "ceilR_px": {"x": X_EVAL_R, "y": y_at_R},
        },
        "retained_points_pass2": [{"x": p[0], "y": p[1], "r": p[2]} for p in retained2],
        "inlier_indices_into_retained_points_pass2": inlier_idx,
    }
    out_path = "tools/calib_measure/ransac_ceiling_edge_result.json"
    with open(out_path, "w") as f:
        json.dump(out, f, indent=2)
    print(f"[info] resultat detaille ecrit dans {out_path}")


if __name__ == "__main__":
    main()
