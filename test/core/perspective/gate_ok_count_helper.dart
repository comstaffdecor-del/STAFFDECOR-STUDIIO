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
// Pourquoi une constante nommée unique plutôt que "39" recopié en dur
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
const int kExpectedGateOkCount = 39; // 31 historiques + 8 recalés (batch22, 2026-08-26)

// Complément : SKU dont le fichier `assets/profiles/<ref>.json` existe
// avec `statut: "OK"` mais qui sont ABSENTS de index.json (statut_gate
// != "OK"). Historique : 25 (16 "à risque de crash" sous l'ancien
// assert() + 9 "subtils" rejetés gate). Après le batch22 : 25 + 9
// nouveaux SUSPECT_GEOMETRIE (D561, D569, D578, D617, D628, D814, D815,
// D840, D898) = 34. Vérifié par recalcul indépendant (script Python,
// hors suite de test) avant ce pin -- pas une simple copie de
// l'observation "Actual: <34>" du run d'échec.
const int kExpectedHorsGateButFileExistsCount = 34;
