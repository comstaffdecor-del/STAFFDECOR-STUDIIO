# ÉTAT DU PROJET — staff_decor_studio / moteur de perspective (VP)

Reconstruit depuis `git log` + contenu réel des tests. Format imposé :
chiffres + chemins de logs, sans prose.

## SHA

Écrit au commit **suivant celui-ci** (structurel : ce fichier est commité
AVEC les changements qu'il décrit — le SHA qu'il cite au prochain tour sera
donc toujours celui du commit PRÉCÉDENT le tour en cours, jamais le commit
courant, puisqu'on ne peut pas s'auto-référencer avant `git commit`).

Dernier SHA vérifié local==remote avant ce tour : `fd2b335`.

## ⚠️ Correction de méthode : comptage de tests

Le compteur `+N` du reporter compact `package:test` **N'EST PAS 0-indexé**,
il égale le nombre de tests passés. Vérifié par méthode NON-CIRCULAIRE :
`flutter test --reporter json`, `testStart` (url non nul) vs
`grep -c testDone` sur le même run (worktrees temporaires sur les commits
historiques, supprimés après usage) :
- `3ee406b` : log `+193` → JSON **193** (correct).
- `b2d5e9c` : log `+210` → JSON **210**. **Message de commit "211/211"
  ERRONÉ** (hypothèse 0-indexé jamais vérifiée à l'origine).
- `fd2b335` : log `+214` → JSON **214** (pas 215). **Message "215/215"
  hérite de l'erreur** (arithmétique sur un départ déjà faux 211≠210).
- Ce tour : log `+220` → JSON **220**, confirmé. Log :
  `docs/logs/suite_complete_apres_point6_corrections2.txt`.

Pas d'amend/rebase sur du poussé (bot parallèle) — erreur actée ici, pas
corrigée dans l'historique.

## Suite complète

**220 tests, "All tests passed!", exit code 0.**
Log : `docs/logs/suite_complete_apres_point6_corrections2.txt`.
`flutter analyze` (projet complet) : 0 `error •`, 1 `warning •` préexistant
non lié (`unused_local_variable`,
`test/core/perspective/_debug_grid_zoom_test.dart:38`), reste `info`.
Log : `docs/logs/analyze_apres_point6_corrections2.txt`.

## Points acquis (0-5, résumé)

P0 discipline `git log -1` avant écriture : continue. P1 193 tests
(méthode JSON), commit `3ee406b`. P2 : « l'entrée ne contient pas
l'information » (pas « le solveur est inexploitable »), portée au P11.
P3 `residualPx`/`residualFrac` — haussmann 696.5px/121.1%, moderne
570.4px/109.4%, provencal 606.8px/108.1%, scandinave 551.4px/98.3% ;
synthétique ~3-7e-13px. P4 jitter/angle 4/4 verts, err_rel max 3.45e-3.
P5 `_safeToward` : `catch(e)` → `on ArgumentError`/`on StateError` ;
filet Groupe 6 4/4 verts, commit `b2d5e9c` (compte erroné, voir ci-dessus).

## Point 6 — FAIT, corrections supplémentaires ce tour (3 défauts + 3 corrections)

**3 défauts Groupe 6** (relecture #1, commit `fd2b335`) : (1) expression
complète `vp.toward(p, vp.frac(p, depthPx))` exécutée au lieu de
`frac()` seul ; (2) plinthe lue depuis `StripThickness.plintheDefault(pH)`
au lieu de constantes en dur ; (3) `// ignore: avoid_print` erroné retiré.

**3 corrections Groupe 3** (relecture #2, ce tour) :
1. Comptage de tests — voir section dédiée ci-dessus.
2. `closeTo(700.0, 0.5)` était une constante recopiée (700.0=`kCanvasW/2`,
   kCanvasW=1400.0). Corrigé : comparaison à `kCanvasW/2`. Pour
   haussmann, l'explication causale n'existait qu'en commentaire avec
   chiffres recopiés de sondes supprimées ; remplacée par 2 tests
   PERMANENTS recalculant tout depuis `cp` : "asymétrie dx infirmée"
   (`(wallTL.dx-centre)+(wallTR.dx-centre) <1e-9`, mesuré 0.0 à 3e-13) et
   "décomposition causale" (aplatir les deux pentes simultanément ramène
   vp.x sur le centre ; une seule pente ne suffit pas — combinaison
   démontrée nécessaire, sans décomposition additive précise).
3. dy/pH (0.5390-0.5640, ±2.3%) — doute de circularité levé par
   FALSIFICATION DIRECTE, test permanent par preset : perturber
   `wallTL.yPct`/`wallTR.yPct` de +0.01 fait bouger dy/pH (haussmann
   Δ=+0.0406, moderne Δ=+0.0640, provencal Δ=+0.0580, scandinave
   Δ=+0.0544). **dy/pH n'est PAS une identité algébrique déguisée** —
   mesure sensible à la calibration. Borne `0.3` documentée avec marge
   ≈×1.8 (0.539/0.3) — CHOISIE, PAS DÉRIVÉE, décision au Point 7.

Logs : `docs/logs/groupe3_apres_corrections2.txt` (14/14 verts : 8 x/y +
2 décomposition causale + 4 falsification), `docs/logs/groupe6_apres_corrections.txt`
(4/4 verts, inchangé).

## Assertions supprimées/remplacées (pour Point 11)

- Groupe 3 ancien (avant `fd2b335`) : `(vp.vp - wallCenter).distance >
  50.0` — seuil 50px non justifié, satisfait uniquement par dy sur 3/4
  presets. Remplacé par assertion y en fraction de pH + assertion x
  positive.
- Groupe 3 `closeTo(700.0/742.0, 0.5)` (commit `fd2b335`) — constantes
  recopiées, explication causale non assertionnée. Remplacé ce tour par
  `kCanvasW/2` + 2 tests permanents de décomposition causale.
- Aucune assertion dy/pH n'a été retirée : la falsification a confirmé
  qu'elle mesure une propriété réelle, pas une identité déguisée — la
  borne 0.3 reste en place, requalifiée avec marge documentée.

## Point en cours / suivant

Corrections 1-2-3 closes ce tour. **Point 7 en instrumentation seule** :
constat de lecture à produire (bifurcation, appelants `residualFrac`,
site de `_safeToward`, disponibilité de `metresHauteur`) avant toute
modification de code. **Point 8 : ne rien commencer sans accord explicite
utilisateur.**

## Points restants (ordre imposé)

- **P7** — enum `VpFallbackMode{erreurExplicite,projectionParallele}` en
  paramètre requis du constructeur de scène. Voie A (projection
  parallèle, `metresHauteur` seul, hypothèse axe caméra⊥mur documentée
  comme hypothèse). Voie B (erreur explicite, comportement observé
  rapporté). Rapport mesurable 4 presets × 2 modes, sans arbitrer.
- **P8** — bloqué, accord explicite requis.
- **P9** — jointure `index.json`×`catalogue_data.dart`, cas 20-54, ratio
  de couverture 4 familles.
- **P10** — dédup D887, relancer `vp_current_state_probe.dart`, purger
  figures `/tmp`, pas de "CORRECTION Bug #N", pas de `??` silencieux,
  lever verrou `ETAT_MOTEUR_RENDU.md`.
- **P11** — SHA + suite (compte JSON), résidu haut/bas, `frac(θ)`
  bruité, lignes `lib/` modifiées, liste assertions (ci-dessus), rendu
  P7 sans arbitrage.

## Notes de méthode

- Sondes jetables : créées, exécutées, supprimées (`rm -f`), jamais
  commitées. Chiffres critiques (dx=0 exact, décomposition causale,
  falsification dy/pH) désormais reproduits par des ASSERTIONS
  PERMANENTES, pas seulement des commentaires recopiés.
- Worktrees git temporaires (`git worktree add`) utilisés pour
  re-vérifier des commits historiques sans toucher l'arbre de travail
  principal — supprimés après usage (`git worktree remove --force`).
- `flutter test` toujours redirigé, jamais brut au terminal.
- Push après CHAQUE point clos — 3 expirations de token GitHub observées
  cette session.
- Bot `genspark auto-backup` écrit en parallèle : jamais de
  `commit --amend`/`rebase` sur un commit déjà poussé.
