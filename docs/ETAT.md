# ÉTAT DU PROJET — staff_decor_studio / moteur de perspective (VP)

Reconstruit depuis `git log` + contenu réel des tests. Format imposé :
chiffres + chemins de logs, sans prose.

## SHA

Écrit au commit **suivant celui-ci** (structurel : ce fichier est commité
AVEC les changements qu'il décrit — le SHA qu'il cite au prochain tour sera
donc toujours celui du commit PRÉCÉDENT le tour en cours, jamais le commit
courant, puisqu'on ne peut pas s'auto-référencer avant `git commit`).

Dernier SHA vérifié local==remote avant ce tour : `3d3c9b1`. Un commit
bot intercalé (`449e664`, "genspark auto-backup", un seul fichier de
sonde jetable) a été nettoyé en début de ce tour (§0 du brief Point
6bis) — voir Notes de méthode.

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
- Tour précédent : log `+220` → JSON **220**, confirmé. Log :
  `docs/logs/suite_complete_apres_point6_corrections2.txt`.
- Ce tour (Point 6bis, +12 tests Groupe 3bis nets : 8 tests initiaux
  remplacés/complétés par 8 (affinité+discontinuité ×4 presets) + 4
  (identité universelle ×4 presets) = 12, contre 220+8=228 attendu avant
  correction — l'ancien test haussmann unique (1) a été remplacé par 4
  tests par preset (+3 net) : 220+8+4=232) : log `+232` → JSON **232**
  (`testDone` avec `hidden:false`, tous `result:success`), confirmé. Log :
  `docs/logs/point6bis.txt`.

Pas d'amend/rebase sur du poussé (bot parallèle) — erreur actée ici, pas
corrigée dans l'historique.

## Suite complète

**232 tests, "All tests passed!", exit code 0.**
Log : `docs/logs/point6bis.txt`.
`flutter analyze` (projet complet) : 0 `error •`, 1 `warning •` préexistant
non lié (`unused_local_variable`,
`test/core/perspective/_debug_grid_zoom_test.dart:38`), reste `info`.

## Points acquis (0-5, résumé)

P0 discipline `git log -1` avant écriture : continue. P1 193 tests
(méthode JSON), commit `3ee406b`. P2 : « l'entrée ne contient pas
l'information » (pas « le solveur est inexploitable »), portée au P11.
P3 `residualPx`/`residualFrac` — haussmann 696.5px/121.1%, moderne
570.4px/109.4%, provencal 606.8px/108.1%, scandinave 551.4px/98.3% ;
synthétique ~3-7e-13px. P4 jitter/angle 4/4 verts, err_rel max 3.45e-3.
P5 `_safeToward` : `catch(e)` → `on ArgumentError`/`on StateError` ;
filet Groupe 6 4/4 verts, commit `b2d5e9c` (compte erroné, voir ci-dessus).

## Point 6bis — FAIT (diagnostic complet de l'anomalie -78,0px)

**Racine identifiée, mesurée, pas supposée** : l'anomalie -78,0px repérée en
Point 6 n'est PAS une perturbation continue de la géométrie — c'est une
**bascule de branche discrète** dans `VanishingPoint.compute`
(`vanishing_point.dart` ligne 224, `vpFinite = vpTop ?? vpBottom`).

**Mécanisme** : à δ_deg = -0.01 EXACTEMENT, sur les 4 presets simultanément,
`wallTL.yPct == ceilL.yPct` (et le pendant droit) — invariant de
construction des 4 presets démo (`lib/models/persp_calib.dart`), pas un
hasard du pas choisi. `lineIntersect` renvoie alors `null`
(`denom.abs() < 0.001`, `persp_geometry.dart`) ⇒ `vpTop == null` ⇒ repli
sur `vpBottom` (constant : ne dépend que de wallBL/wallBR/floorL/floorR,
jamais perturbés par ce balayage) ⇒ `residualPx` devient `null` (pas
`0.0` — un seul couple produit une intersection, aucun résidu n'est
mesurable).

**Deux régimes géométriques DISTINCTS à cette même coïncidence** (vocabulaire
tenu selon la mesure, pas par convention) :
- **moderne/provencal/scandinave** (symétriques en x) : les deux fuyantes
  hautes deviennent **CONFONDUES** (même droite) — position indéterminée,
  pas de direction bien définie. `residualPx` décroît de façon monotone et
  BORNÉE en approchant δ_deg (moderne : 570,4 à δ=0 → 531,8 à δ=-0.0099),
  puis s'éteint d'un coup à δ_deg exact.
- **haussmann** (asymétrique) : les deux fuyantes deviennent **PARALLÈLES**
  au sens strict (droites distinctes, jamais confondues) — direction bien
  définie, position à l'infini. `residualPx` DIVERGE en approchant δ_deg
  (696,5 à δ=0 → 4224,5 à δ=-0.0099), puis s'éteint d'un coup à δ_deg exact.
Dans les deux cas, `lineIntersect` renvoie `null` identiquement — mais la
géométrie sous-jacente diffère, d'où la distinction terminologique.

**Résultat central** : dy/pH est affine et continue en δ, INCLUDING à la
limite δ_deg — sur moderne, la limite prédite par la droite affine
(extrapolation depuis les points non dégénérés, signe constant vérifié)
vaut EXACTEMENT 0,500, alors que la valeur observée (via le repli `??`)
vaut 0,372. **L'écart de 0,128 est intégralement produit par le repli**,
pas par la géométrie. Il n'y a AUCUNE singularité dans la géométrie ; il y
en a une dans le code.

**Écart -78,0px expliqué (coïncidence arithmétique de grille, close, rien à
construire dessus)** : sur moderne, `dy` évolue par incréments EXACTS de
39,0px par pas de balayage de 0.01 sur `yPct`, soit 8×4,875 (4,875 =
0,005 × 975px, le pas natif de calibration `yPct` × la hauteur du canvas).
L'écart entre la valeur affine extrapolée à δ_deg et la valeur observée via
le repli vaut exactement 78,0 = 16×4,875 = 2×39,0 : deux pas de grille
entiers, produits par la distance (en pas de 0.01) entre le point
d'extrapolation et le point de repli. Vérifié par calcul direct sur les
valeurs mesurées, pas par coïncidence apparente.

**Décision `??` (écrite avant tout code Point 7)** — deux voies honnêtes,
pas trois. La voie "VP à l'infini, w=0" est FACTUELLEMENT FAUSSE sur 3
presets/4 : quand les droites sont confondues, le VP n'est pas à l'infini,
il est INDÉTERMINÉ (tout point de la droite convient) — renvoyer w=0
affirmerait une direction que la donnée ne contient pas. Restent : (i) un
drapeau de bascule exposé à l'appelant, (ii) l'exception remontant dans
`_safeToward`. Seul (i) ne modifie ni le rendu ni le comportement
observable — donc seul lui est committable avant le Point 7, sans
préempter ce que le Point 7 doit mesurer (le Point 7 tranchera entre
Voie A/Voie B sur la base d'un enum `VpFallbackMode` explicite, sans
valeur par défaut).

**Couverture de la branche w=0** : vérifiée par grep sur tout `test/`
(aucune occurrence de `isAtInfinity` suivie de `isTrue`) — AUCUN test ne
l'atteint aujourd'hui. Le `??` la rend inatteignable dès qu'un seul des
deux couples est fini, ce qui est le cas sur les 4 presets réels à tout δ
testé (`vpBottom` toujours fini). C'est exactement le mécanisme que la
voie A du Point 7 (projection parallèle) voudrait utiliser : jamais
exercée par la calibration réelle actuelle.

**Conséquence pour le Point 7** : aucune garde continue sur `residualFrac`
ne peut anticiper cette dégénérescence sur 3 presets/4 (bascule discrète,
pas un seuil qui se rapprocherait progressivement) ; sur le 4e
(haussmann), elle n'avertirait que sur l'axe horizontal déjà établi comme
sous-déterminé au Groupe 3.

**Correction d'une mesure publiée par erreur ce tour** : l'hypothèse
initiale (brief) prévoyait que `residualPx(0)` vs l'écart entre VP baseline
et VP de repli serait une "mesure non triviale" sur haussmann (asymétrique)
et une identité algébrique triviale seulement sur les 3 presets symétriques
(même abscisse). Mesuré à 10 décimales : **c'est une identité UNIVERSELLE,
vraie sur les 4 presets sans exception**, y compris haussmann où les
abscisses de VP baseline et VP de repli sont DIFFÉRENTES
(741,9966... ≠ 727,9977...) — donc l'hypothèse "a-b vs |a-b| coïncident
par symétrie" ne s'applique même pas à ce cas. La vraie raison, plus
fondamentale que la symétrie : `residualPx` est PAR DÉFINITION
`dist(vpTop, vpBottom)` (cas "couple haut fini"), et `vpBottom` est
invariant sous une perturbation qui ne touche que le couple haut (vérifié
bit à bit) — donc `écart(baseline,repli) = dist(vpTop(0), vpBottom(0)) =
residualPx(0)`, algébriquement, sur tout preset. Corrigé dans
`vp_frac_degenere_test.dart` (Groupe 3bis) avant commit — l'hypothèse
initiale erronée n'a jamais été committée.

**Deux formulations imprécises retirées de ce document** (identifiées ce
tour, présentes uniquement dans le docstring du test — jamais committées
sous cette forme dans `ETAT.md`) :
- "dy/pH bouge... de façon proportionnelle au sens physique (delta positif
  ⇒ dy/pH augmente)" — généralisation à partir d'un seul signe de
  perturbation testé (+0.01) ; ne permet pas de conclure à une
  proportionnalité pour tout δ. Remplacée par le résultat plus précis et
  vérifié : dy/pH est affine en δ (Groupe 3bis), hors du point de bascule
  de branche.
- Toute formulation du type "residualPx est l'amplitude du saut" —
  imprécise : `residualPx(0)` est la distance entre VP-haut et VP-bas
  mesurée à UN SEUL δ (=0), pas un saut entre deux δ différents. Le
  "saut" observable (78,0px sur moderne) est un artefact de grille, voir
  ci-dessus — distinct de `residualPx`.

Logs : `docs/logs/sweep_diagnostic_delta.txt` (balayage 0.01, archive),
`docs/logs/sweep_diagnostic_delta_fin.txt` (balayage fin, pas jusqu'à
0.0025, autour de δ_deg), `docs/logs/point6bis.txt` (suite complète après
ce point).

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

Point 6bis clos ce tour (diagnostic complet -78,0px, 2 tests permanents
Groupe 3bis par preset, décision `??` documentée). **Point 7 après
validation seulement** — constat de lecture déjà produit au tour
précédent (bifurcation, appelants `residualFrac`, site de `_safeToward`,
disponibilité de `metresHauteur`), 4 faits acquis à y verser :
- early return `RoomPainter.paint()` avant le calcul VP ⇒ 2 sites/3
  atteignent la bifurcation, pas 3 (`comparateur_screen.dart` pane
  "avant" : `withProducts: false`, jamais atteint).
- une exception dans `paint()` d'un `CustomPainter` produit une
  `FlutterError` de frame — à MESURER, pas présupposer.
- `metresHauteur` n'est aujourd'hui consommé que par `case 'Corniches'`
  (`room_painter.dart`) — la voie A élargit sa portée, hypothèse
  géométrique à écrire explicitement.
- ajouter la scène synthétique comme ligne témoin ("chemin nominal").

Enum `VpFallbackMode{erreurExplicite,projectionParallele}` en paramètre
requis (sans défaut). Livrable 4 presets × 2 modes, sans arbitrage.
**Point 8 : ne rien commencer sans accord explicite utilisateur.**

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
