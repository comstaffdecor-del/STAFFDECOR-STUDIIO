// Constante partagée pour les garde-fous de comptage sur la couverture
// `gate_sanite_rapport.csv` / `assets/profiles/index.json`.
//
// Historique : 31 SKU gate-OK depuis le batch Piste A initial. Le
// 2026-08-26, le patch two-pass sweep (`step2profile.py`,
// STEP_SWEEP_COARSE_MM/STEP_SWEEP_BUDGET_S) a résolu les 23 SKU
// ERREUR_TIMEOUT (root cause : TIMEOUT_SECONDS=90 trop court face au
// coût réel du balayage dense) ; 22 des 23 ont été rejoués (D892 exclu,
// bloqué en lecture STEP elle-même, hors périmètre du patch), donnant
// 17 extractions statut=OK, dont 8 passent le gate de sanité -> 39 SKU
// gate-OK au total (31 + 8).
//
// 2026-08-XX (batch tolérance-bruit) : `ASSERTION_TOL_MM` (critère
// bloquant 2, débord bbox_mm/profil_mm) passe de 0.001mm à 0.5mm --
// lue depuis la SOURCE UNIQUE `assets/config/gate_config.json`, partagée
// avec `lib/core/perspective/profile_dims.dart`. Justification PHYSIQUE
// (tolérance de fabrication d'un moulage en plâtre), pas ajustée sur la
// liste de SKU : sur le batch de calibration, le bruit de reconstruction
// va de 0.000 à 0.111mm, le plus petit défaut géométrique réel observé
// est de 1.94mm -- 0.5mm se situe au milieu de cet écart d'un ordre de
// grandeur. 4 SKU dont TOUS les motifs bloquants étaient du bruit pur
// (< 0.111mm) repassent OK : D569, D617, D815, D840 -> 39 + 4 = 43.
// Les SKU à défaut géométrique réel (>= 1.94mm) ou à motif indépendant
// de cette tolérance (CONTRAT_LOADER_PLAFOND_VIDE) restent rejetés --
// D898, D561, D578, D628, D814 -- verrouillé explicitement par un test
// de garde dédié (`tolerance_relaxation_guard_test.dart`), PAS par ce
// seul compteur global (qui ne distingue pas "tolérance relevée" de
// "contrôle désactivé").
//
// Pourquoi une constante nommée unique plutôt que "43" recopié en dur
// dans chaque fichier de test : la valeur EST un pin volontaire (le
// garde-fou doit rougir si le générateur ou le gate divergent), mais
// disperser ce pin dans cinq assertions séparées transforme chaque
// futur batch d'extraction en cinq modifications synchronisées à la
// main -- source d'erreur exactement du type que ces tests existent
// pour prévenir. Une seule constante, un seul futur point d'édition.
//
// NE PAS dériver cette valeur dynamiquement depuis index.json ici :
// le garde-fou perdrait sa fonction (il doit pouvoir CONSTATER un écart
// entre "ce que le code produit" et "ce qu'on attend qu'il produise",
// pas se recalibrer silencieusement sur ce que le code produit déjà).
const int kExpectedGateOkCount = 43; // 39 historiques + 4 recalés (batch tolérance-bruit 0.001mm->0.5mm)

// Complément : SKU dont le fichier `assets/profiles/<ref>.json` existe
// avec `statut: "OK"` mais qui sont ABSENTS de index.json (statut_gate
// != "OK"). Historique : 25 (16 "à risque de crash" sous l'ancien
// assert() + 9 "subtils" rejetés gate). Après le batch22 : 25 + 9
// nouveaux SUSPECT_GEOMETRIE (D561, D569, D578, D617, D628, D814, D815,
// D840, D898) = 34. Après le batch tolérance-bruit (4 des 9 repassent
// OK, voir ci-dessus) : 34 - 4 = 30. Vérifié par recalcul indépendant
// (régénération complète de gate_sanite_rapport.csv et
// assets/profiles/index.json, pas une simple copie de l'observation
// "Actual: <N>" d'un run d'échec).
const int kExpectedHorsGateButFileExistsCount = 30;
