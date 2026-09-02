# ÉTAT DU PROJET — staff_decor_studio / moteur de perspective (VP)

Reconstruit depuis `git log` + contenu réel des tests. Format imposé :
chiffres + chemins de logs, sans prose.

## Errata mutation (SHA `9eaac52`, complété par `d066ddc`)

`9eaac52` et `d066ddc` sont poussés — jamais d'`--amend`/`rebase` sur
l'un ou l'autre. Les corrections suivantes portent sur `9eaac52`
(rétractation initiale) ET sur `d066ddc` lui-même (les deux détails de
séquence — Étage B, chiffres haussmann — corrigés ci-dessous ont été
introduits dans `d066ddc` et sont donc rectifiés ici, sur ce même
fichier, sans réécrire `d066ddc`).

**1. Rétractation** : le message de commit `9eaac52` affirme « la
vérification par mutation confirme que l'assertion de signe existe
comme expect distinct ». Cette conclusion n'est PAS soutenue par le
protocole réellement exécuté à l'époque (mutation `vpTop!` ligne 224 ⇒
`Null check operator used on a null value`, rouge par EXCEPTION, pas
par assertion de signe — un rouge indistinguable de tout crash proche
de δ_deg). Le protocole valide, exécuté CE TOUR (Étages A/B/C, sur
`test/core/perspective/vp_frac_degenere_test.dart` et
`lib/core/perspective/vanishing_point.dart`, arbre restauré entre
chaque étage, `git diff --stat` vide à la fin) donne :
- **Étage A** — neutraliser seul `expect(signs.length, 1, ...)`
  (ligne 754, l'assertion de signe, sans toucher au calcul `signed`) :
  reste du fichier vert. **Rejeu propre, versionné, mesuré sur l'arbre
  POST-`d066ddc`** (le rejeu initial de ce tour n'avait pas laissé de
  preuve versionnée — corrigé ici) : `flutter test
  test/core/perspective/vp_frac_degenere_test.dart --reporter expanded`
  → **`+40: All tests passed!`**, exit code 0 — log complet dans
  `docs/logs/errata_etage_a.txt`. Restauration ensuite,
  `git diff --stat test/` vide. Isolable, aucun couplage collatéral :
  les 40 `test()` du fichier restent tous verts avec cette seule ligne
  neutralisée à l'intérieur d'un seul d'entre eux.
- **Étage B — valeur probante faible, à ne pas présenter comme une
  validation** : inverser la valeur attendue du signe
  (`expect(signs.first, 1.0, ...)`, ligne ajoutée puis retirée, jamais
  commitée) produit un rouge sur les 4 presets avec un message de
  COMPARAISON DE VALEUR authentique (`Expected: <1.0> / Actual:
  <-1.0>`), pas une exception. Mais cette assertion n'existait pas
  avant l'Étage B — elle a été CRÉÉE pour la mutation, puis retirée.
  Trois objets distincts, à ne pas confondre : (i) la constance du
  signe hors δ_deg, qui existe (`expect(signs.length, 1, ...)`,
  ligne 754) ; (ii) la polarité négative hors δ_deg, qui n'existe pas
  comme assertion permanente et a été introduite temporairement pour
  cet étage ; (iii) une garde à la bascule δ_deg, qui n'existe pas et
  ne peut pas exister dans ce test (il exclut structurellement δ_deg,
  voir point 5 ci-dessous). Ainsi redécrit, l'Étage B établit qu'une
  comparaison de doubles échoue par comparaison de valeur — ce qui
  n'était pas en doute — sur une assertion que la mutation a
  elle-même introduite. Il ne dit rien de la suite de tests
  EXISTANTE. **La valeur probante du protocole repose sur l'Étage C
  seul, et sur l'Étage A pour l'indépendance** — pas sur l'Étage B.
- **Étage C** — mutation côté production, ligne 224, PAS `vpTop!` :
  substitution finie et géométriquement significative, symétrique de
  `vpBottom` autour de `(fTL.dy + fBL.dy)/2`. Résultat BRUT initial (une
  seule exécution, collecteur pas encore en place) : **1 seul test
  rouge, PAS 4**, et ce n'est PAS le test de signe (Groupe 3bis
  « affinité ») — celui-ci exclut structurellement δ_deg
  (`retenus = points.entries.where((e) => e.value.$2 != null)`, garde
  `residualPx != null`) et reste donc vert sous cette mutation. Le seul
  rouge observé porte sur le test fusionné 40+4=44 (partie (b),
  `expect(vpDeg.vp, equals(vpBottomIndep), ...)`), et un seul preset
  (haussmann) y apparaissait — la boucle `for (final key in ...)`
  contenant un `expect` throwing s'arrête au premier échec et masque
  les presets suivants dans la même exécution.

**2. Non-monotonie, remplacement complet** : les deux composantes sont
monotones sur l'intervalle balayé — `dx` croissant, `|dy|`
décroissant — et la non-monotonie de `residualPx` naît de leur
COMPOSITION, pas de l'une ou l'autre seule. À `dy` fixé, il n'y aurait
ni minimum ni non-monotonie ; à `dx` fixé, `residualPx = |dy|` serait
monotone décroissant. La phase descendante est portée par `|dy|` — à
δ=0 et δ=−0,0025, `residualPx − |dy|` vaut respectivement 0,1405 puis
0,569 (courbe confondue avec `|dy|` à moins d'un pixel) ; la phase
montante est portée par `dx` dès que `dx²/(2|dy|)` domine, le minimum
se situant au croisement des deux régimes. L'énoncé antérieur
(composante y monotone donc non contributive) était un non-sequitur —
il disparaît.

**3. `w = 0`, deux phrases disjointes, jamais fusionnées sous un
même intitulé causal** : « La discontinuité a deux régimes : bornée à
531,375px sur les trois presets symétriques, non bornée sur
haussmann. » puis, séparément : « `w = 0` est rejeté sur les trois
presets symétriques et valide sur haussmann parce que les deux droites
y sont confondues ou distinctes, ce que le caractère borné/non borné
de la discontinuité ne fonde PAS. »

**4. Garde a priori** (utile pour le Point 7b) : `residualFrac(0)`
se situe entre 0,98 et 1,21 sur les quatre calibrations livrées —
tout seuil inférieur à 0,98 se déclenche donc sur les quatre à la
fois. Une garde a priori calibrée naïvement bloque l'application
entière au lieu de filtrer les cas dégénérés. **Rétractation
(Point 7b-3, item 1)** : la valeur 1,081 précédemment attribuée à
haussmann dans cette clause était celle du PROVENÇAL, pas de
haussmann — la valeur réelle de haussmann est **1,211**
(`residualFrac=121.1%`, `docs/logs/point7b_1.txt`,
`[groupe5-conditionnement] haussmann`). Les bornes de plage
(0,98–1,21) étaient déjà justes — c'est précisément cette justesse
de la plage qui a rendu l'interversion invisible à la relecture :
aucune borne n'était fausse, seule l'attribution nominative d'une
valeur interne l'était. Seule la mesure PAR PRESET (et non la seule
plage) pouvait exposer l'erreur. L'interversion a circulé dans tous
les briefs précédents, y compris ceux de l'assistant. Mesure par
preset, telle que loggée :
```
haussmann  : residualFrac=121.1%
moderne    : residualFrac=109.4%
provencal  : residualFrac=108.1%
scandinave : residualFrac=98.3%
```
Le bloc figé (« 1,081 sur haussmann ») se rétracte ; la mesure du
log l'emporte, provenance citée ci-dessus.

**5. Polarité non gardée hors δ_deg** : le test de signe (Groupe 3bis,
Test 1, `expect(signs.length, 1, ...)`) exclut explicitement δ_deg via
sa garde `residualPx != null` — il ne fournit donc AUCUNE garde
exactement au point de bascule de branche. Ce fait est mis en évidence
par l'Étage C ci-dessus : le Test 1 reste vert sous la mutation de
production, précisément parce qu'il n'évalue jamais le point où la
mutation change quelque chose.

**Limite connue du volet (a), hors périmètre de ce correctif** :
l'incrément `totalPointsVerifies++` du volet (a) (ligne ~1098) reste
gaté par deux `expect` throwing à l'intérieur du même `for (int i...)`
— un écart sur un δ donné masque encore les δ suivants du même preset
dans la même exécution. Seul le volet (b) (repli δ_deg) a été converti
en collecteur ce tour ; le volet (a) n'a pas été touché.

**`avoid_print`, tranché et consigné** : le grep frais
(`grep -n "ignore: avoid_print" test/core/perspective/vp_frac_degenere_test.dart`,
relu **post-`d066ddc`**, sans recalcul) confirme 7 pragmas actifs aux
lignes **149, 234, 746, 897, 1138, 1240, 1300**. Ce ne sont PAS les
lignes pré-collecteur (1126, 1199, 1259) décalées uniformément de +12
— l'édition du collecteur a inséré à trois endroits distincts, dont un
bloc de ~30 lignes entre les anciens 1126 et 1199 ; le décalage n'est
donc pas uniforme sur les trois dernières occurrences (+12, +41, +41).
Chacune des 7 lignes ci-dessus est confirmée immédiatement suivie d'un
`print()` réel (`grep -n -A1`) ; l'orphelin retracté au Point 6bis a
donc bien été traité, aucun pragma mort.
`flutter analyze` filtré sur ce seul fichier
(`flutter analyze 2>&1 | grep "avoid_print" | grep
"vp_frac_degenere_test.dart"`, requis pour ne pas mélanger d'autres
fichiers dans le compte des non-couverts) : 5 `avoid_print` non
couverts par un `ignore` (lignes 366/402/456/505/598), préexistants,
hors périmètre, identiques à la baseline.

**Rejeu Étage C, preuve versionnée** : capture intégrale dans
`docs/logs/errata_mutation_rouge.txt`
(`flutter test test/core/perspective/vp_frac_degenere_test.dart
--reporter expanded`, exit code 1) — **un seul test rouge** (`+27 -1`),
message unique listant les **4 écarts** (haussmann, moderne,
provençal, scandinave) dans l'ordre naturel d'itération des clés,
chacun avec l'`Offset` obtenu et attendu. Valeurs lues dans le log,
pas prédites, **avec la précision réelle du log** (`toString()` sur
`Offset` arrondit à 1 décimale — ce n'est PAS la valeur exacte) :
haussmann `Offset(728.0, 185.3)` vs attendu `Offset(728.0, 750.8)` ;
moderne `Offset(700.0, 170.6)` vs `Offset(700.0, 624.0)` ; provençal
`Offset(700.0, 226.1)` vs `Offset(700.0, 720.9)` ; scandinave
`Offset(700.0, 213.8)` vs `Offset(700.0, 670.0)`. **Correction de
chiffre (haussmann x, corrigée dans CE fichier, pas dans `d066ddc`
lui-même)** : le log affiche `728.0`, mais la valeur EXACTE établie
par `docs/logs/derivation_haussmann_min.txt` (`vpBottom.x (haussmann)
= 1298020/1783 = 727.997757`) est **727,998**, pas 728,0 — écrire
« 728,0 » sur haussmann contredirait l'origine d'erreur déjà consignée
plus bas (« Origine de l'approximation fautive… la constante 700…
réutilisée par erreur… PAS 700 »). Donc : **haussmann x = 727,998
exact, 728,0 au seul titre de la précision du log** ; les trois autres
presets à 700,0 exact ; le hedge ±0,05px (résolution du `toString()`)
couvre l'abscisse comme les ordonnées pour toutes les valeurs listées
ci-dessus — aucune n'est une preuve au centième, seulement une
confirmation à la résolution affichée. `totalPointsVerifies` est resté
à 44 dans cette exécution rouge (pas de `Expected: <44> Actual:
<40>`) : l'incrément inconditionnel (variante (i)) n'a pas été affecté
par le collecteur. Restauration ensuite : `git checkout
lib/core/perspective/vanishing_point.dart`, `git diff --stat lib/`
vide, `flutter test test/core/perspective/vp_frac_degenere_test.dart`
→ `+40: All tests passed!`.

**Reconfirmation de l'axe, même réserve de précision** : le calcul
`axisMirror = (fTL.dy + fBL.dy)/2` sur haussmann donne 468,0 (à la
résolution du log) ; `2·468,0 − 750,75 = 185,25` s'accorde à la valeur
haussmann `185,3` ci-dessus **à ±0,05px, résolution du log** — ce
n'est pas une preuve au centième, seulement une NON-FALSIFICATION à
cette résolution. Les décimales exactes de `axisMirror` et du résultat
restent attribuées à la dérivation rationnelle
(`docs/logs/derivation_haussmann_min.txt`), pas recalculées ici.

## SHA

Écrit au commit **suivant celui-ci** (structurel : ce fichier est commité
AVEC les changements qu'il décrit — le SHA qu'il cite au prochain tour sera
donc toujours celui du commit PRÉCÉDENT le tour en cours, jamais le commit
courant, puisqu'on ne peut pas s'auto-référencer avant `git commit`).

Dernier SHA vérifié local==remote avant ce tour : `ec36eb0` (tree
`9e114d3`, parent `449e664`). Base du Point 7a : arbre `ec36eb0` +
uniquement §B (fusion 4→1 des tests d'identité, suppression de la
scorie `isNotNull` et de `baseCp`, retouches docstring §B ci-dessous),
229/229, `flutter analyze` 0 erreur. `docs/logs/point7.txt` encore
untracked avant ce commit.

## Errata (SHA `ec36eb0`)

`ec36eb0` est poussé — jamais d'`--amend`/`rebase` sur lui. Les deux
corrections suivantes, identifiées PENDANT le Point 7a, sont donc
consignées ici plutôt que réécrites dans l'historique :
- La formulation « L'écart de 0,128 est intégralement produit par le
  repli » (section Point 6bis, "Résultat central" telle qu'écrite dans
  `ec36eb0`) est **numériquement fausse** : l'écart signé exact est
  **−0,872** (extrapolation −0,500 moins valeur observée +0,372), pas
  0,128 — voir « Résultat central, chiffres signés » ci-dessous pour la
  chaîne complète et sa source versionnée
  (`docs/logs/derivation_haussmann_min.txt`).
- L'explication « Écart -78,0px expliqué » par arithmétique de grille
  (8×4,875, 16×4,875=2×39,0) écrite dans `ec36eb0` est **retirée comme
  argument** (pas seulement complétée) : -78,0px est un artefact de
  `.abs()` sur une comparaison entre deux mesures non signées de nature
  différente, la grandeur géométrique réelle et signée sur moderne est
  531,375px, et la divisibilité par 4,875 est une CONSÉQUENCE de la
  grille `yPct` du balayage, jamais une explication causale — voir
  « Le −78,0 en une ligne » ci-dessous.

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
- Point 6bis (tour précédent, commit `ec36eb0`) : log `+232` → JSON
  **232** (`testDone` avec `hidden:false`, tous `result:success`),
  confirmé. Log : `docs/logs/point6bis.txt`.
- Ce tour (Point 7a, §B.1 — fusion des 4 tests d'identité universelle
  ×4 presets en 1 seul test paramétré, net **−3**) : 232−4+1=229
  attendu. Log : `+229` → JSON **229** (`testDone` avec
  `hidden:false`, zéro `result` non-success), confirmé. Log :
  `docs/logs/point7.txt`.

Pas d'amend/rebase sur du poussé (bot parallèle) — erreur actée ici, pas
corrigée dans l'historique.

## Suite complète

**229 tests, "All tests passed!", exit code 0.**
Log : `docs/logs/point7.txt`.
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
  BORNÉE en approchant δ_deg (moderne : 570,375 à δ=0 → 531,765 à
  δ=-0.0099, limite exacte 531,375 — voir chaîne signée ci-dessous), puis
  s'éteint d'un coup à δ_deg exact.
- **haussmann** (asymétrique) : les deux fuyantes deviennent **PARALLÈLES**
  au sens strict (droites distinctes, jamais confondues) — direction bien
  définie, position à l'infini. `residualPx` NE DIVERGE PAS MONOTONEMENT en
  approchant δ_deg — voir « Prédiction haussmann » ci-dessous pour la
  séquence mesurée complète et le minimum — puis s'éteint d'un coup à
  δ_deg exact.
Dans les deux cas, `lineIntersect` renvoie `null` identiquement — mais la
géométrie sous-jacente diffère, d'où la distinction terminologique.

### Prédiction haussmann : confirmée sur le régime, falsifiée sur l'ordonnancement

Le régime lui-même (bornée/monotone sur les 3 presets symétriques,
divergente sur haussmann à l'approche immédiate de δ_deg) est confirmé.
Ce qui est FAUX dans la prédiction initiale (Point 6bis) : l'hypothèse
d'une divergence MONOTONE sur tout l'intervalle balayé. Ordre mesuré à
δ = 0 / −0,0025 / −0,005 / −0,0075 / −0,009 / −0,0095 / −0,0099 :
**696,453 → 689,163 → 683,174 → 687,558 → 774,961 → 1050,763 →
4224,454** — `residualPx(0) = 696,453`, pas 696,5 (arrondi fautif du
tour précédent). La valeur 683,174 à δ=−0,005 est le point de balayage
le plus proche au pas 0,0025 d'un minimum réel, PAS le minimum lui-même
(interdiction du brief : jamais dérivé le minimum par grep sur un
balayage grossier).

**Minimum exact, par calcul** (dérivée `d/dδ[residualPx²]=0`, racine
réelle retenue dans le domaine physique du balayage [−0,05 ; 0,05] — une
seconde racine réelle, −0,2256, existe mais est hors domaine, rejetée) :
**δ_min = −0,0060411, residualPx(δ_min) = 682,1444**. Script et sortie
complète, quatre presets, dans `docs/logs/derivation_haussmann_min.txt`
(sympy, arithmétique rationnelle exacte sur les points de calibration,
jamais un flottant en entrée).

**Origine de l'approximation fautive du tour précédent, écrite
explicitement** : le terme approché `(2,4375/s)²` mesurait
`X(δ) − 700`, alors que la distance qui compte porte sur
`X(δ) − vpBottom.x`. Sur haussmann, `vpBottom.x = 1298020/1783 =
727,998`, PAS 700 — le couple bas y est asymétrique (wallBL 0,900 /
wallBR 0,890, floorL 0,870 / floorR 0,860) exactement comme le couple
haut. La constante 700 (centre canvas, valide sur les 3 presets
symétriques où `vpBottom.x` vaut effectivement `kCanvasW/2`) avait été
réutilisée par erreur sur le seul preset qui n'est pas symétrique. Terme
corrigé : `(2,4375/s − 27,998)² + (665,5 + 532s)²` → minimum ≈ −0,00602 /
682,2 (vérifié numériquement, cohérent à l'ordre de grandeur avec le
calcul exact ci-dessus — l'écart résiduel entre −0,00602 et −0,0060411
vient de l'approximation `s ≈ 5,81(δ+0,01)` elle-même, pas de la
structure du terme corrigé). **L'approximation −0,0056 / 686 du tour
précédent est retirée**, remplacée par le calcul exact ci-dessus.

**Mécanisme de la remontée** (rend tout artefact inutile à invoquer) :
`|dy|` décroît de 696,3125 (δ=0) à 677,661 (δ_min) à 665,746 (δ=−0,0099)
— soit **−18,652px sur l'intervalle [0 ; δ_min]** et **−30,566px sur
l'intervalle [0 ; −0,0099]** (les deux intervalles sont distincts,
toujours écrits explicitement à chaque mention de ce chiffre — l'un
n'est pas un raccourci de l'autre). Pendant ce temps `dx` passe de
13,999 (δ=0) à 78,083 (δ_min) à 4171,666 (δ=−0,0099), STRICTEMENT
croissant en valeur absolue sur tout l'intervalle. La non-monotonie de
`residualPx` est donc portée ENTIÈREMENT par la composante x — la
composante y est monotone (décroissante) sur tout le balayage, minimum
compris.

**`dx(δ_min) = 78,083px` — étiqueté explicitement comme coïncidence
NUMÉRIQUE avec l'artefact −78,0px de moderne, sans lien causal** :
`dx(δ_min)` est une composante horizontale sur haussmann, dérivée de la
non-monotonie de `residualPx` ; l'artefact −78,0px de moderne est un
`.abs()` sur la composante verticale signée d'un `??` — autre preset,
autre grandeur, autre mécanisme, et les deux nombres ne sont même pas
égaux (78,083 ≠ 78,0 exactement). Sans cette étiquette, ce rapprochement
serait « découvert » comme un motif au tour suivant — ce n'en est pas
un.

### Résultat central, chiffres signés (moderne, exact)

`(vp.dy − wallCenterY)/pH` sur la branche `vpTop` (qui se prolonge
CONTINÛMENT en δ, y compris à travers δ_deg — c'est la valeur RENVOYÉE
par `compute()`, via le repli `??`, qui est discontinue, pas la fonction
mathématique `vpTop(δ)` elle-même) : forme close exacte
`−32δ/5 − 141/250`. Valeurs : **−0,564 à δ=0** ; **−0,500 en
prolongement affine à δ_deg** (extrapolation de la droite, pas une
mesure directe — δ_deg est hors du domaine où `vpTop` est défini comme
intersection finie) ; **+0,372 réellement renvoyé** via le repli sur
`vpBottom` ; **écart signé = extrapolé − observé = −0,500 − 0,372 =
−0,872 = −109/125 exactement**. Discontinuité en pixels : **531,375 =
4251/8 en limite exacte** (`lim residualPx(δ→δ_deg⁻)`), **531,765
mesuré à δ=−0,0099** (le point de balayage le plus proche, pas la
limite elle-même). Source versionnée de toute cette chaîne :
`docs/logs/derivation_haussmann_min.txt` (section moderne).

### Le −78,0 en une ligne

Artefact de `.abs()` sur une comparaison entre deux mesures non signées
de nature différente ; la grandeur géométrique réelle est **531,375px,
SIGNÉE**, sur moderne ; la divisibilité par 4,875 (pas natif `yPct` ×
hauteur canvas) est une CONSÉQUENCE de la grille de balayage, jamais une
explication causale — les deux arguments antérieurs (probabilité 1/8,
arithmétique de grille comme explication) sont retirés, pas seulement
complétés.

### Deux formulations à verrouiller

**`residualPx` est un indicateur A PRIORI, jamais un déclencheur** : il
vaut `null` exactement à l'instant où il faudrait qu'il parle (à
δ_deg, où la bascule se produit). Toute phrase du type « residualPx
mesure le saut » est supprimée, remplacée par « écart baseline/repli » —
avec le contre-exemple explicite : 4224,454px à δ=−0,0099 sur haussmann,
une grandeur qui n'a JAMAIS été un saut entre deux valeurs successives,
seulement une distance à un δ fixe.

**La discontinuité a deux régimes, ce qui est AUSSI la justification de
`w=0`** : bornée à 531,375px sur les 3 presets symétriques ; non bornée
sur haussmann. C'est la raison pour laquelle `w=0` (VP à l'infini) est
géométriquement CORRECT sur haussmann (droites distinctes, jamais
confondues, direction bien définie à l'approche de δ_deg) et
FACTUELLEMENT REJETÉ sur les 3 autres (droites CONFONDUES, direction
INDÉFINIE — `w=0` y affirmerait une direction que la donnée ne contient
pas). Cette distinction géométrique, pas une convention de code, motive
le choix Voie A/Voie B du Point 7b.

### `frac()` — deux phrases séparées, à ne pas fusionner

**Fait, vérifié par lecture du prédicat** (`vanishing_point.dart`, ligne
333, `if (result > 1.0)`) : le prédicat exact est `result > 1.0`, où
`result = depthPx / dist(p, vpPos)` ; le docstring (ligne ~338) nomme
explicitement la « corniche/plinthe inversée » comme motif de cette
garde.

**Hypothèse NON VÉRIFIÉE, à ne pas confondre avec le fait ci-dessus** :
que l'encadrement de `wallCenterY` par `vpTop`/`vpBottom` (le défaut
identifié pour le Point 8, voir plus bas) déclencherait cette garde.
Vérifié par calcul sur les 4 presets à δ=0 (calibration de production,
sans balayage) : `wallCenterY` EST encadré par `vpTop.y`/`vpBottom.y`
sur les 4 presets (haussmann 54,4375 ≤ 464,34375 ≤ 750,75 ; moderne
53,625 ≤ 397,3125 ≤ 624 ; provencal 114,094 ≤ 473,497 ≤ 720,879 ;
scandinave 118,6 ≤ 441,883 ≤ 669,967), ET la production ne lève AUCUNE
exception à cette calibration. **L'encadrement de wallCenterY n'implique
donc PAS `frac() > 1`** — c'est le troisième tour où une lecture de
docstring aurait risqué d'être prise pour une démonstration de
prédicat ; ce n'en est pas une ici non plus.

### Décision `??` (écrite avant tout code Point 7b)

Deux voies honnêtes, pas trois. La voie "VP à l'infini, w=0" est
FACTUELLEMENT FAUSSE sur 3 presets/4 : quand les droites sont
confondues, le VP n'est pas à l'infini, il est INDÉTERMINÉ (tout point
de la droite convient) — renvoyer w=0 affirmerait une direction que la
donnée ne contient pas. Restent : (i) un drapeau de bascule exposé à
l'appelant, (ii) l'exception remontant dans `_safeToward`. **Aucune
promesse par régime n'est faite ici** : distinguer "confondues" de
"strictement parallèles" en code est une question de MESURE NULLE
(mesure zéro au sens propre : tout seuil ε>0 introduit pour trancher
recréerait exactement le défaut du `??` qu'on répare — un cas
limite juste sous le seuil retomberait dans le même silence). L'analyse
de régime reste dans ce rapport ; rien n'est promis comme branche
choisie avant les mesures du Point 7b.

**Couverture de la branche w=0** : vérifiée par grep sur tout `test/`
(aucune occurrence de `isAtInfinity` suivie de `isTrue`) — AUCUN test ne
l'atteint aujourd'hui. Le `??` la rend inatteignable dès qu'un seul des
deux couples est fini, ce qui est le cas sur les 4 presets réels à tout δ
testé (`vpBottom` toujours fini). C'est exactement le mécanisme que la
voie A du Point 7b (projection parallèle) voudrait utiliser : jamais
exercée par la calibration réelle actuelle.

**Conséquence pour le Point 7b** : aucune garde continue sur
`residualFrac` ne peut anticiper cette dégénérescence sur 3 presets/4
(bascule discrète, pas un seuil qui se rapprocherait progressivement) ;
sur le 4e (haussmann), elle n'avertirait que sur l'axe horizontal déjà
établi comme sous-déterminé au Groupe 3. Contrainte de conception pour
le Point 7b : la garde ne peut PAS consulter `residualPx` au moment de
la bascule (il y vaut `null`) — elle doit l'avoir lu sur la baseline non
perturbée, en amont.

**Correction d'une mesure publiée par erreur au tour Point 6bis** :
l'hypothèse initiale (brief) prévoyait que `residualPx(0)` vs l'écart
entre VP baseline et VP de repli serait une "mesure non triviale" sur
haussmann (asymétrique) et une identité algébrique triviale seulement
sur les 3 presets symétriques (même abscisse). Mesuré à 10 décimales :
**c'est une identité UNIVERSELLE, vraie sur les 4 presets sans
exception**, y compris haussmann où les abscisses de VP baseline et VP
de repli sont DIFFÉRENTES (741,9966... ≠ 727,9977...) — donc l'hypothèse
"a-b vs |a-b| coïncident par symétrie" ne s'applique même pas à ce cas.
La vraie raison, plus fondamentale que la symétrie : `residualPx` est
PAR DÉFINITION `dist(vpTop, vpBottom)` (cas "couple haut fini"), et
`vpBottom` est invariant sous une perturbation qui ne touche que le
couple haut (vérifié bit à bit) — donc `écart(baseline,repli) =
dist(vpTop(0), vpBottom(0)) = residualPx(0)`, algébriquement, sur tout
preset. Corrigé dans `vp_frac_degenere_test.dart` (Groupe 3bis) avant
commit `ec36eb0` — l'hypothèse initiale erronée n'a jamais été
committée.

### Une ligne pour le Point 8, à ne pas laisser enterrer par le Point 7

**L'encadrement de `wallCenterY` par `vpTop`/`vpBottom`, à la
calibration de PRODUCTION (δ=0, sans balayage), sur les 4 presets,
reste le seul défaut identifié à ce jour qui affecte réellement ce que
l'application affiche** — tout le reste de ce rapport (bascule de
branche à δ_deg, discontinuité, régimes) concerne un point de
calibration synthétique (δ_deg=−0,01) jamais atteint par la calibration
réelle des 4 presets. Point 8 : bloqué, accord explicite requis avant
tout travail sur ce défaut précis.

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

Point 6bis clos au tour précédent (commit `ec36eb0`). **Point 7a clos ce
tour** (§B : docstring de périmètre complété 40+4=44 et mise en garde
"miroir intentionnel" ; vérification par mutation de l'assertion de
signe, rouge confirmé puis restauration propre ; §A : prédiction
haussmann confirmée/falsifiée avec minimum exact dérivé, chaîne signée
moderne exacte, `.abs()`-artefact, `frac()` fait/hypothèse séparés,
Errata `ec36eb0`, dérivation archivée dans
`docs/logs/derivation_haussmann_min.txt`). Commit unique §B+§A, push
immédiat après le commit (règle explicite : jamais de vert non poussé
dans un arbre partagé avec le bot `genspark auto-backup`).

**Point 7b — après le push, PAS encore commencé** — arbitrage explicite
à trancher avant tout code : le paramètre requis (`VpFallbackMode`)
porte-t-il sur `VanishingPoint.compute` (24 sites d'appel à éditer en
test + 1 site de production, refonte de signature qui noierait le diff)
ou sur un point d'entrée dédié (`compute()` intact, documenté comme
régime historique) ? Les deux se défendent, l'implicite ne se défend
pas — raison du choix à écrire ici une fois tranché. Constat de lecture
déjà produit (pas à refaire) :
- bifurcation `vpFinite = vpTop ?? vpBottom` ligne 224 (`vpTop`/
  `vpBottom` lignes 202-203) ;
- `residualPx`/`residualFrac`/`residualExceeds` (lignes 56, 71-76,
  85-89) sans aucun appelant hors du fichier (grep confirmé) ;
- early return `RoomPainter.paint()` (`if (!withProducts ||
  selectedProducts.isEmpty) return;` ligne 135) ⇒ 2 sites/3
  atteignent la bifurcation, pas 3 (`comparateur_screen.dart` pane
  "avant" : `withProducts: false`, jamais atteint) ;
- `metresHauteur` n'est aujourd'hui consommé que par `case 'Corniches'`
  (`room_painter.dart`) — la voie A élargit sa portée, hypothèse
  géométrique à écrire explicitement ;
- `frac()` avec ses trois conditions (`depthPx < 0` → `ArgumentError`,
  `d < 1e-9` → `StateError`, `result > 1` → `StateError`).

3 faits déjà acquis à intégrer au rapport plutôt qu'à redécouvrir : la
branche "projection parallèle" n'est jamais atteinte aujourd'hui, donc
non testée ; sur 3 presets/4 les droites sont confondues et non
parallèles, donc la projection parallèle n'y a pas de direction
définie — la branche est à la fois inatteignable et indéfinie là où
elle serait sollicitée ; `residualPx(δ)` est utilisable comme garde a
priori, lu sur la baseline (jamais au moment de la bascule, où il vaut
`null`).

Livrable Point 7b : 4 presets × 2 modes plus une scène synthétique
témoin — nombre de faces, sommets de corniche, exception éventuelle,
emprise en pixels via `PictureRecorder → toImage → toByteData`
(comptage des pixels non transparents). Sans arbitrage.

**Point 7b-1 — propagation mécanique, FAIT ce tour (commit à suivre).**

Deux décisions actées avant exécution :
1. Pas de `@Deprecated` sur `repliHistoriqueCoupleBas` — juger le
   membre historique serait prématuré avant que 7b-2 ait mesuré les
   deux modes réels. Baseline `analyze` inchangée.
2. Le site de production (`room_painter.dart:139`) reste sur
   `repliHistoriqueCoupleBas` en 7b-1 — CE N'EST PAS une conséquence
   mécanique de l'ajout du paramètre, c'est un arbitrage explicite
   REPORTÉ à 7b-2, justifié par un fait déjà établi : la branche à
   couple unique fini n'est atteinte par AUCUNE des 4 calibrations
   réelles à δ=0 (les deux couples y sont simultanément finis, sauf
   exactement à δ_deg, hors domaine de production) — `erreurExplicite`
   y serait donc mesurablement inerte, mais la bascule elle-même
   (avec son garde-fou amont sur `residualFrac`, jamais `residualPx`
   au moment de la bascule où il est `null` par construction) est
   traitée comme un arbitrage à documenter en 7b-2, pas comme un
   sous-produit de ce commit.

`enum VpFallbackMode { repliHistoriqueCoupleBas, erreurExplicite,
projectionParallele }` — **sans `default:` dans le `switch`** de
`VanishingPoint.compute` (le `switch` couvre les 3 membres
explicitement) : une clause `default:` reproduirait à l'intérieur du
`switch` exactement le défaut que l'absence de valeur par défaut de
l'enum supprime à l'extérieur — l'analyzer signale toute extension
future de l'enum non traitée dans le `switch`.

`erreurExplicite` implémenté POUR DE VRAI dès ce commit (pas un
`UnimplementedError`) — nécessaire pour que la mesure 7b-2 (4 presets ×
2 modes) produise un log lisible : le message porte le couple fini,
le couple dégénéré, les deux points candidats, et le fait que
`residualPx` resterait `null` faute de second point. Calqué sur le
`throw ArgumentError` déjà existant en fin de `compute()` (même type
d'exception, pas de type concurrent). `projectionParallele` reste
`UnimplementedError` documenté, reporté à 7b-2 — sa mise en œuvre
authentique n'a de sens qu'une fois la mesure faite (3 presets/4 avec
droites confondues, direction indéfinie).

**Note importante, actée et non estompée** : implémenter proprement
`erreurExplicite` rend le crash LISIBLE, pas ABSENT. Si un jour la
bascule est décidée en production, la calibration utilisateur
dégénérée passe toujours de « rendu approximatif » à « exception dans
le chemin de peinture », sans qu'aucun test ne l'exerce aujourd'hui —
la formule « vert en CI, régression sur le terrain » reste entière.
Ce correctif ne traite que la lisibilité du message, pas
l'atteignabilité de la branche.

**Compte des sites d'appel — correction d'un sous-comptage découvert
pendant ce commit.** Le grep initial de l'Étape 1
(`grep -rn "VanishingPoint.compute(" lib/ test/`) était scopé à
`lib/`+`test/` et donnait 29 occurrences brutes, dont 24 vrais sites
d'appel (5 exclus : 1 déclaration `factory` + 3 mentions en prose dans
`vp_frac_degenere_test.dart` lignes 957/964/1152 + 1 mention en prose
dans `_synth_vp_harness_test.dart` ligne 2830). **Ce périmètre était
lui-même incomplet** : `flutter analyze`, exécuté après propagation
des 24 sites, a levé `missing_required_argument` sur
`tools/calib_measure/vp_current_state_probe.dart:58` — un 25ᵉ site
d'appel réel, hors de `lib/`+`test/`, jamais couvert par aucun grep de
ce tour ni du précédent. Re-scan sans restriction de répertoire
(hors `build/`) : **30 occurrences brutes, 25 vrais sites d'appel**.
Ce site est une sonde de mesure du comportement "actuel"
(`test('sonde: ImgDraw + distVp effectif par preset (…)')`) —
conservée sur `repliHistoriqueCoupleBas` pour continuer à observer
exactement ce qu'elle observait avant ce commit.

Liste nominative des 25 sites, tous sur `repliHistoriqueCoupleBas`
(production incluse, arbitrage de bascule reporté à 7b-2 — voir
décision 2 ci-dessus) :

| # | Fichier | Ligne(s) |
|---|---|---|
| 1 | `lib/core/perspective/room_painter.dart` | 139 (site de production — conservé, arbitrage reporté 7b-2) |
| 2 | `tools/calib_measure/vp_current_state_probe.dart` | 58 (sonde de mesure — non couvert par le grep initial `lib/+test/`) |
| 3-4 | `test/core/perspective/_debug_calib_bench_test.dart` | 87, 378 |
| 5 | `test/core/perspective/_debug_room_painter_real_render_test.dart` | 221 |
| 6-10 | `test/core/perspective/_synth_vp_harness_test.dart` | 2526, 2558, 2598, 2850, 2910 |
| 11-25 | `test/core/perspective/vp_frac_degenere_test.dart` | 126, 199, 211, 349, 389, 480, 569, 715, 843, 886, 1048, 1113, 1216, 1280, 1381 (numéros PRÉ-insertion, tels que grep les a donnés avant la propagation de ce commit — voir errata post-`d013a07` ci-dessous : le déplacement n'est PAS uniforme, reproduction par commande, pas par arithmétique) |

Contrôle arithmétique (post-correction, re-scan complet du dépôt hors
`build/`) : `grep -rn "fallbackMode: VpFallbackMode.repliHistoriqueCoupleBas"`
→ **25**. `grep -rn "erreurExplicite"` hors déclaration/`case`/message
→ **0 site d'appel** (seulement la déclaration de l'enum, le `case`
du `switch`, la chaîne du message d'erreur, et le commentaire
d'arbitrage dans `room_painter.dart`).

Prédiction écrite avant exécution : 229 verts, compte inchangé, aucun
rouge — tenue, confirmée par recomptage JSON non-circulaire
(`--reporter json`, `testDone && hidden:false`) : 229 entrées, 0
`result != 'success'`. `flutter analyze` : 0 erreur, 1 warning (`srcH`,
inchangé), 106 info — baseline strictement identique à celle déclarée
avant exécution (puisque `@Deprecated` a été refusé).

Log : `docs/logs/point7b_1.txt`.

**Errata post-`d013a07` — trois défauts constatés dans ce commit
même, tranchés sans recalcul.**

**Défaut 1 (le plus grave, récidivant, de la main de l'assistant)** :
la table des « 15 numéros pré-insertion » ci-dessus a été présentée
comme si `d013a07` ne l'avait déplacée que « de +1 chacun » — FAUX. Les
15 insertions du paramètre `fallbackMode:` dans
`vp_frac_degenere_test.dart` sont CUMULATIVES : le site compté en
kᵉ position depuis le haut du fichier se décale de +(k−1) lignes
(l'insertion du site 1 le précède, donc ne le décale pas lui-même ;
seuls les k−1 sites qui le précèdent contribuent chacun +1), PAS de
+1 ni de +k. Concrètement (grep frais post-`d013a07`, aucun recalcul) :
126 reste 126 (k=1, aucune insertion ne le précède, +0), 199→200 (k=2,
+1), 211→213 (k=3, +2), 349→352 (k=4, +3), 389→393 (k=5, +4), 480→485
(k=6, +5), 569→575 (k=7, +6), 715→722 (k=8, +7), 843→851 (k=9, +8),
886→895 (k=10, +9), 1048→1058 (k=11, +10), 1113→1124 (k=12, +11),
1216→1228 (k=13, +12), 1280→1293 (k=14, +13), 1381→1395 (k=15, +14).
C'est exactement la famille d'erreur que `4771ff1` avait rétractée sur
le bloc `avoid_print` (« déplacement uniforme de +12 » — faux, c'était
+12/+41/+41) — reproduite un commit plus tard, par l'assistant qui
venait de la corriger chez autrui, et reproduite UNE TROISIÈME FOIS
dans la formulation « décale de +k » elle-même (corrigée ici, en tête
de 7b-2, sans recalcul — seule la RÈGLE en prose était fausse, la
liste juste au-dessus et le message de commit `0edb4fd` donnaient
déjà les bonnes valeurs).

Corollaire, également confirmé par grep frais, aucun recalcul : ces
mêmes 15 insertions ont re-périmé le bloc `avoid_print` figé par
`4771ff1` ET les 3 mentions en prose citées plus haut comme
non-appels. Reproduction par COMMANDE, pas par liste de numéros (une
liste « rote » à la prochaine insertion, une commande ne rote pas) :
```
grep -n "ignore: avoid_print" test/core/perspective/vp_frac_degenere_test.dart
```
→ 7 pragmas actifs, chacun vérifié par `grep -n -A1` comme suivi
d'un `print()` réel (le compte reste 7 ; une 8ᵉ occurrence du motif
est une mention en prose décrivant un pragma historique déjà
supprimé, PAS un pragma actif). Précision de troncature : seuls
trois des quinze numéros post-insertion apparaissaient dans la
sortie affichée au tour précédent (` — les douze autres avaient bien
été lus au grep mais l'affichage était tronqué) ; c'est la commande
elle-même qui couvre les sept, pas le récit qui la paraphrase.
```
grep -n "VanishingPoint.compute(...).vp\|VanishingPoint.compute(...)" test/core/perspective/vp_frac_degenere_test.dart | grep -v "final \|VanishingPoint.compute($"
```
→ les 3 mentions en prose (précédemment numérotées 957/964/1152,
désormais périmées par les mêmes insertions) sont reproduites par
cette commande, jamais par leurs anciens numéros. Convention retenue
à partir d'ici pour TOUT numéro de ligne dans ce fichier ou tout
fichier soumis à insertion répétée : compte + commande de
reproduction, jamais une liste figée.

**Défaut 2** : le recomptage JSON non-circulaire annoncé dans le
message du commit `d013a07` (229 entrées, 0 non-success) a été produit
dans `/tmp`, non versionné, et — fait plus important — exécuté AVANT
le correctif du site manqué `tools/calib_measure/vp_current_state_probe.dart`.
Le 229 cité reposait donc sur une mesure pré-correctif, jamais
conservée. Refait sur `d013a07` (post-correctif), versionné dans
`docs/logs/point7b_1_json.txt` :
```
flutter test --reporter json > docs/logs/point7b_1_json.txt
# testDone hidden:false : 229 entrées, 0 result != 'success'
```
Résultat numérique identique (229/0), mais désormais reproductible
depuis le disque, pas depuis une exécution non tracée.

**Défaut 3** : l'affirmation « le `switch` couvre les 3 membres
explicitement, l'analyzer signale toute extension future » n'avait
JAMAIS été vérifiée par mutation — exactement le même statut que
l'assertion rétractée en `9eaac52` (affirmée par raisonnement sur le
code, jamais falsifiée par exécution). Mutation appliquée : ajout d'un
4ᵉ membre `sondeExhaustiviteTmp` à `VpFallbackMode`, NON commité.
Résultat, log dans `docs/logs/point7b_1_exhaustivite.txt` :
```
error • The type 'VpFallbackMode' isn't exhaustively matched by the
switch cases since it doesn't match the pattern
'VpFallbackMode.sondeExhaustiviteTmp' • vanishing_point.dart:272:7 •
non_exhaustive_switch_statement
```
Prédiction (`error`, pas un `info`) confirmée exactement. Mutation
retirée immédiatement (`git checkout -- lib/core/perspective/vanishing_point.dart`),
`git diff --stat lib/` vide, `flutter analyze` revenu à la baseline
(0 erreur, 1 warning `srcH`, 106 info).

**Fait central du tour, le plus durable** : `flutter test` (sans
argument, ou avec un argument de RÉPERTOIRE comme `tools/`) NE
COMPILE PAS `tools/` — vérifié explicitement
(`flutter test tools/` exécute la suite standard sous `test/`, 229
verts, sans jamais toucher `vp_current_state_probe.dart` — commande
NOMMÉMENT écartée comme élément de preuve, faux vert lisible comme
une couverture). La suite était donc verte sur un arbre contenant un
site de compilation cassé, et AUCUN recomptage (JSON ou compact)
n'aurait pu le voir — seul `flutter analyze` l'a détecté. **Règle en
dur, retenue pour la suite** : hors de `test/`, le filet est
`flutter analyze`, JAMAIS `flutter test`.

**Mécanisme de collecte, séparé en deux causes distinctes** —
précision apportée en tête de 7b-2, commande discriminante exécutée
sur chemin de FICHIER explicite plutôt que de répertoire :
```
flutter test tools/calib_measure/vp_current_state_probe.dart
```
Résultat : le fichier est COMPILÉ et EXÉCUTÉ (chargement effectif,
sortie de la sonde affichée pour les 4 presets, `+1: All tests
passed!`). Ceci sépare proprement les deux causes possibles : (a) le
NOMMAGE du fichier (`vp_current_state_probe.dart`, sans suffixe
`_test.dart`) l'exclut du glob `*_test.dart` appliqué au PARCOURS
d'un répertoire — confirmé, c'est la cause réelle ; (b)
l'EMPLACEMENT (`tools/` plutôt que `test/`) N'Y EST POUR RIEN — un
chemin de fichier explicite le fait tourner qu'il soit sous `tools/`
ou ailleurs, tant que le suffixe est respecté. Conséquence pratique :
déplacer `vp_current_state_probe.dart` sous `test/` sans renommer ne
le ferait toujours pas tourner via `flutter test` (répertoire) — il
faudrait le renommer en `*_test.dart`. Corollaire inchangé : le
`test()` interne à `vp_current_state_probe.dart` ne tourne dans
aucune CI basée sur `flutter test <répertoire>` — c'est une sonde
morte pour toute collecte par glob, exécutable seulement par chemin
de fichier explicite ou par `flutter analyze`.

**Item de provenance (le 25 « juste » par annulation de deux
erreurs)** : le 25 énoncé par l'assistant avant `d013a07` (15+6+2+1+1)
et le 25 réel post-correction (15+5+2+1+1+1) coïncident numériquement
par ANNULATION de deux erreurs indépendantes et sans lien causal —
un surcomptage de +1 dans `_synth_vp_harness_test.dart` (compté 6 vrais
sites, en réalité 5) contre l'omission complète du fichier
`tools/calib_measure/vp_current_state_probe.dart` (compté 0, en
réalité 1). Sans cette ligne au dossier, la trace se relirait comme
si le 25 initial avait été juste par construction — il ne l'était
pas, il l'est devenu par coïncidence arithmétique entre deux fautes
distinctes.

Conventions retenues à partir d'ici, pour tout le reste du brief :
plus aucun numéro de ligne dérivé par arithmétique (toujours re-greppé
frais) ; pour le bloc `avoid_print`, compte + commande de
reproduction plutôt qu'une liste de numéros ; `git add` sur chemins
explicites, jamais `-A`, le bot d'auto-backup écrivant en parallèle.

## Point 7b-3 — Étage C (pouvoir de détection réel), circularité de
la Mesure 2, arrondi de perpDist, mécanisme de symétrie, clôture 7b

**2. Arrondi de `perpDist` corrigé — trois cas distincts, pas deux.**
`0.0000px` (format `toStringAsFixed(4)` utilisé dans
`test/core/perspective/vp_fallback_mode_test.dart` pour les presets
« confondus ») n'établissait que `< 5×10⁻⁵px`, pas l'exactitude
machine. Reformaté en notation exponentielle
(`.toStringAsExponential(3)`, déjà utilisé pour `crossDirs`) dans le
fichier committé, pour laisser la sortie elle-même trancher. Mesure
brute (`toString()`, sonde `_tmp_provencal_probe_test.dart`, tour
7b-3-bis) : la ventilation à trois cas prédite se confirme, mais
PAS comme 3 nuls-exacts / 1 distinct — **2 nuls-exacts / 1 nul au
bruit machine / 1 distinct** :
- **nul EXACT (bit à bit)** : moderne, scandinave —
  `perpDist=0.0` littéral (`uy=0.0` exact, `crossDirs=0.0` exact).
- **nul AU BRUIT MACHINE, pas exact** : provençal —
  `perpDist=2.8421709430404007e-13`, `crossDirs=4.0602442043434295e-16`.
  Rapport `perpDist/crossDirs=700.0` exactement (confirmé, voir
  clause 6) — la valeur n'est pas un bruit accumulé sans structure,
  mais une annulation à l'échelle de l'ulp qui ne retombe pas sur
  zéro bit à bit, contrairement à moderne/scandinave où l'annulation
  est parfaite dès `uy`.
- **DISTINCT** : haussmann — `perpDist=4.874999999999896px`.

**Chaîne canvas mesurée, provençal (correctif post-audit)** : l'écart
`dy` entre `wallTL` décalé et `ceilL` — `151.43437500000002 −
151.434375 = 2,842×10⁻¹⁴` — divisé par `lenTL=140` donne `2,03×10⁻¹⁶`,
exactement le `uy` mesuré ; multiplié par `vx=1400` (`perpDist =
vx·uy` quand `vy=0`, `ux=1,0`), il redonne `2,842×10⁻¹³`, exactement
le `perpDist` mesuré. La chaîne boucle sur des nombres, et elle est
GÉNÉRALE aux quatre presets, pas propre à provençal seul : moderne et
scandinave y entrent avec un écart `dy` NUL et en sortent à `0,0`
exact, ce qui CONFIRME le mécanisme au lieu de le falsifier — ce qui
échoue pour scandinave, c'est le niveau `pct` (clause 6, correctif
ULP), pas cette chaîne canvas. Provençal est le SEUL preset où cet
écart `dy` est le contributeur UNIQUE de `perpDist` — sur haussmann,
l'écart `dy` existe aussi (`87.75000000000001` vs `87.75`, soit
`1,42×10⁻¹⁴`) mais l'asymétrie de plafond (`ceilL.yPct≠ceilR.yPct`)
domine de QUATORZE ordres de grandeur (`perpDist=4,875`, pas un résidu
d'arrondi). Ne pas lire « valable pour provençal seul » : la mesure a
rendu la chaîne générale, elle ne la restreint pas.

Le texte antérieur de cette clause (« moderne/provencal/scandinave
`perpDist=0.000e+0` exact ») est donc **rétracté sur provençal** :
son affichage `0.000e+0` à 3 décimales masquait encore un résidu non
nul, exactement le phénomène que cette clause avait pour but
d'exposer — la correction devait être poussée jusqu'au `toString()`
complet pour se révéler à elle-même. **Le nul exact n'est pas
garanti par le mécanisme** (clause 6) : le mécanisme (`ceilL.yPct ==
ceilR.yPct`) produit une annulation algébrique EXACTE sur le papier,
mais son exactitude bit à bit en flottant dépend de la façon dont
les pourcentages spécifiques de chaque preset se convertissent en
coordonnées canvas — moderne/scandinave y arrivent, provençal non.
La Mesure 4 (nouveau `test()`, voir clause 6) n'assert que
`lessThan(1e-6)` sur le cas symétrique synthétique — un seuil de
négligeabilité, pas une assertion de nullité bit à bit — ce qui est
exact au vu de ce que la mesure établit réellement, sans
sur-affirmation. Traité en même temps tous les `toStringAsFixed`
remontés par le Bloc 1 de lecture du tour précédent (`residualFrac`
en `.toStringAsFixed(1)`, non concerné, usage d'affichage de plage) ;
seul `perpDist` est reformaté.

**3. Verdict de circularité de la Mesure 2 (`residualFrac`),
rendu par lecture (Bloc 1) puis mutation (Étage C, item C3) :** la
Mesure 2 contient bien un `expect` (pas seulement un `print`), mais
ses 3 seuls `expect` sont VACANTS — `expect(fracs.length,
equals(4))`, `expect(minFrac > 0, isTrue)`, `expect(maxFrac.isFinite,
isTrue)` — aucun ne contraint la VALEUR de `residualFrac`. Mutation
(facteur ×3,0 injecté dans le getter `residualFrac` de
`lib/core/perspective/vanishing_point.dart`, non committée,
restaurée) : les 4 valeurs mesurées se sont déplacées
(121,1%→363,4%, 109,4%→328,1%, 108,1%→324,3%, 98,3%→294,9%) SANS
faire rougir aucun test (`+3: All tests passed!`,
`docs/logs/point7b_3_etage_c.txt`). **Circularité établie par
expérience** : la Mesure 2 est une mesure PUBLIÉE (imprimée,
lisible dans le log), pas une mesure GARDÉE — elle ne peut pas
attraper une régression future du calcul de `residualFrac` lui-même.
Ceci reste correct pour son objet déclaré (rapporter la plage
mesurée, ne décider d'aucun seuil) ; le constat porte uniquement sur
sa capacité de garde, absente par construction.

**4. Retrait de `dart:ui` dans `vp_fallback_mode_test.dart`** —
baseline `flutter analyze` ramenée de 107 à 106 info. Le fichier
neuf reproduisait le lint `unnecessary_import` déjà présent et non
corrigé dans `vp_frac_degenere_test.dart:55` (import redondant avec
`flutter_test`, qui réexporte `Offset`). Le précédent de ce fichier
justifie de NE PAS y toucher là-bas (tolérance déjà actée en 7b-1/
7b-2, hors périmètre de ce commit) ; il ne justifie pas de
REPRODUIRE ce même lint dans un fichier neuf où l'import est retiré
sans coût.

**5. Résultats d'Étage C, étiquetage C/A′ (détail intégral :
`docs/logs/point7b_3_etage_c.txt`)** :
- **C1 [Étage C]** — `case erreurExplicite:` remplacé par le repli
  historique (mutation dans `lib/`) : ROUGE confirmé sur les 4
  presets, volet δ_deg de la Mesure 1 (4 mismatches nommés), volet
  nominal resté vert. Preuve de détection réelle : `throwsArgumentError`
  mord.
- **C2 [tentative A′, verdict établi]** — `throw StateError`
  inconditionnel injecté au début de
  `case repliHistoriqueCoupleBas:` (mutation dans `lib/`, choisie
  pour ÉTABLIR la prédiction plutôt que l'affirmer) : VERT confirmé
  intégralement, y compris sur la Mesure 2 qui appelle explicitement
  ce membre sur les 4 presets nominaux. **Conclusion écrite** : le
  volet nominal de la Mesure 1 ("erreurExplicite ne lève pas sur les
  presets nominaux") est une assertion D'ACCESSIBILITÉ (A′), pas un
  garde comportemental — le chemin de contrôle nominal (les deux
  couples finis) n'atteint JAMAIS le switch `fallbackMode`, donc
  aucune mutation confinée à ce switch ne peut la faire rougir. **Le
  test 1 est à demi mordant** : son volet δ_deg mord réellement (C1),
  son volet nominal ne peut mathématiquement pas mordre sur cette
  branche — plus trompeur qu'un test franchement muet, puisqu'il
  affiche un `expect` qui semble actif.
- **C3 [Étage C]** — mutation ×3,0 sur `residualFrac` (mutation
  dans `lib/`) : voir clause 3 ci-dessus, circularité établie.
- **C4 [A′ ×2, aucune mutation dans `lib/`]** — (a) seuil de
  classification élargi côté test (`perpDist < 5.0` au lieu de
  `< 1e-6`) : reclasse haussmann en "confondue" (bilan 4/0 au lieu de
  3/1), test resté vert (`greaterThanOrEqualTo(3)` tient aussi à 4) ;
  (b) mismatch forcé sur "moderne" (2ᵉ preset, pas le premier) :
  `Actual: ['moderne : SONDE_C4_ARTIFICIELLE_NON_PREMIER']` — confirme
  que le collecteur du test 3 liste l'écart NOMINATIF exact, pas
  seulement le premier élément de la boucle. Les 4 mutations ont été
  restaurées individuellement (`git checkout --`, `git diff --stat
  lib/ test/` vide, relance verte vérifiée après chacune).

**6. Hypothèse de symétrie — mécanisme confirmé, après un premier
échec de construction (détail intégral :
`docs/logs/point7b_3_symetrie.txt`)** : la répartition 3/1
(confondues/distinctes) coïncide avec la symétrie des calibrations —
moderne/provencal/scandinave ont `wallTL.yPct == wallTR.yPct`,
haussmann seul a `wallTL.yPct ≠ wallTR.yPct` (0,100 vs 0,095).
Sonde synthétique falsifiable (préfixe `_tmp_`, créée, mesurée,
supprimée) : **première construction ÉCHOUÉE** — en fixant
`wallTL.yPct`/`wallTR.yPct` indépendamment de `ceilL.yPct`/
`ceilR.yPct`, la précondition (couple haut dégénéré, `vpTop==null`)
n'était pas satisfaite (`vpTop` mesuré fini dans les deux cas,
`perpDist` mesuré à 97 et 102px — sans rapport avec l'hypothèse).
Cause identifiée à ce moment (formulation initiale, **rétractée ci-
dessous, voir Point 7b-3-ter**) : un lien pct `wallTL.yPct − 0,01 =
ceilL.yPct` supposé vérifié EXACTEMENT sur les 4 presets réels — cette
affirmation a été tapée de mémoire, pas relue depuis
`persp_calib.dart`, et s'est révélée FAUSSE au niveau pct pour 3 des 4
presets à la mesure Dart-native ultérieure (Point 7b-3-ter). La vraie
condition de confondues RESTE `ceilL.yPct == ceilR.yPct` (hauteurs de
plafond égales), établie indépendamment par la sonde synthétique
ci-dessous (pas par le lien pct erroné) — voir Point 7b-3-ter pour le
mécanisme correct au niveau canvas. **Seconde construction, respectant
la relation `ceilL.yPct == ceilR.yPct`** : cas symétrique
(`ceilL.yPct=ceilR.yPct=0,100`) → `perpDist=0.0` exact (confirmé par
`toString()` brut, pas seulement par un seuil) ; cas asymétrique
(`ceilL.yPct=0,100`, `ceilR.yPct=0,095`, même écart que haussmann) →
`perpDist=4,875` — identique à la valeur mesurée sur haussmann
lui-même.

**Confirmation quantitative (tour 7b-3-bis, sonde
`_tmp_provencal_probe_test.dart`, supprimée après usage)** : sur
provençal, `ceilL.yPct == ceilR.yPct` (0,140 = 0,140) et
`perpDist/crossDirs = 700,0` EXACTEMENT — 700,0 = `kCanvasW/2`
(`kCanvasW=1400,0`, seule valeur trouvée dans `lib/`/`test/`). **Ce
rapport N'EST PAS une identité qui tiendrait quelles que soient les
valeurs** : il tient PARCE QUE la configuration mesurée est
symétrique (`vy=0`, `ux=1,0`, `dirTR` est le miroir de `dirTL`, donc
`uy' = −uy ⟹ crossDirs = 2·uy` par construction algébrique) — c'est
une conséquence directe de la symétrie étudiée, et ne porte donc
AUCUNE information au-delà de `uy` lui-même. Haussmann, en
configuration asymétrique, le prouve directement : son rapport mesuré
est `perpDist/crossDirs = 5,76×10¹⁶`, sans rapport avec 700,0. Le
constat correct est donc : chez provençal (cas symétrique), le résidu
non nul de la clause 2 est structuré par le même centre de canvas que
le `vp.x` des presets symétriques (`vp_frac_degenere_test.dart`), pas
un bruit indépendant — mais cette structure est elle-même une
CONSÉQUENCE de la symétrie de configuration, pas une propriété
universelle du calcul. La dégradation du rapport en tautologie de FORMULE, pas seulement
d'observation, se vérifie algébriquement : `crossDirs = |ux·uy' −
uy·ux'|`, avec la configuration mesurée `vy=0`, `ux=1,0` et `dirTR`
miroir de `dirTL` (`ux'=1,0`, `uy'=−uy`), donne `crossDirs =
|1,0·(−uy) − uy·1,0| = 2·uy` ; et `perpDist = |vx·uy − vy·ux| =
vx·uy` (puisque `vy=0`) `= 1400·uy`. Le rapport
`perpDist/crossDirs = 1400·uy / (2·uy) = 1400/2 = 700,0 = vx/2` — une
identité de FORMULE, conditionnée strictement par `vy=0`, `ux=1,0` et
le miroir `uy'=−uy`, c'est-à-dire par la symétrie étudiée, PAS
indépendamment des valeurs. Vérifié numériquement sur provençal :
`uy=2,0301...×10⁻¹⁶` → `crossDirs` formule `=4,0602...×10⁻¹⁶`
(mesuré : identique) et `perpDist` formule `=2,8421...×10⁻¹³` (mesuré :
identique). Haussmann, où `ux'≠ux` et `uy'≠−uy` (configuration non
miroir), mesure un rapport de `5,76×10¹⁶`, sans rapport avec 700,0 —
falsifiant directement toute lecture générale du rapport. Sa
justification initiale (« quelles que soient les valeurs ») ne
l'était pas et est ici rétractée ; ce qui reste correct est que le
rapport n'apporte AUCUNE information au-delà de `uy` lui-même. Le
`700,0` de ce rapport (`vx/2`, provençal) et le `700,0` de `vp.x` sur
les presets symétriques (`vp_frac_degenere_test.dart`, `kCanvasW/2`)
ne sont PAS « deux 700 sans lien » — les deux dérivations diffèrent
(l'une vient du rapport `perpDist/crossDirs`, l'autre de la position
horizontale du point de fuite), mais procèdent de la MÊME symétrie
gauche-droite autour de `kCanvasW/2` : ce qui se rétracte n'est pas
l'existence d'un lien, mais l'idée que le rapport `700,0` porterait
une information indépendante de cette symétrie — il n'atteste qu'une
STRUCTURE du résidu (centrée sur `kCanvasW/2`), rien de plus.

Côté haussmann, les deux valeurs, algèbre et mesure, juxtaposées :
`kCanvasH=975,0`, et `0,005 × 975 = 4,875` EXACTEMENT en algèbre ;
la valeur effectivement MESURÉE (Mesure 4, cas asymétrique
synthétique, et clause 2 sur haussmann lui-même) est
`4,874999999999896` — le `4,875` mesuré sur haussmann est donc
**forcé arithmétiquement par l'écart de calibration (0,005) et la
hauteur de canvas commune (975)**, à un résidu d'arrondi flottant
près (`≈1,04×10⁻¹³` d'écart entre l'algèbre exacte et la mesure), ce
n'est pas une coïncidence entre deux mesures indépendantes — la
clause 6 se corrige elle-même sur ce point : le texte antérieur
disait « identique à la valeur mesurée sur haussmann lui-même » comme
une observation ; c'est en réalité une conséquence arithmétique
directe, pas une simple co-occurrence numérique.
Recherche de provenance sur `727,998`/`741,9966` (Bloc 2 du tour
7b-3-bis) : les deux valeurs sont réelles et sourcées dans des logs
versionnés distincts (`derivation_haussmann_min.txt` pour
`vpBottom.x=727,997757` ; `groupe3_apres_split.txt` et autres pour
`vp.x=741,9966348850253`) — ce sont deux observables distincts du
même calcul (position théorique du couple bas seul, avant repli, vs
position finale retournée par `compute()` après repli), non une
interversion d'étiquette à rétracter.

**Verdict** : hypothèse confirmée, avec une précision mécanique que
l'échec initial puis la sonde de confirmation ont rendue explicite —
le 3/1 n'est pas une propriété brute des presets mais de leur
symétrie de plafond (`ceilL.yPct` vs `ceilR.yPct`), combinée au
mécanisme de construction δ_deg PARTAGÉ par les 4 presets réels
(même décalage −0,01 sur les deux points de mur latéral) et à la
géométrie du canvas commun (`kCanvasW`, `kCanvasH`). Un décompte
devient un mécanisme. **Décision de promotion** : la sonde est
promue en `test()` permanent dans `vp_fallback_mode_test.dart`
(Mesure 4) — le mécanisme, une fois confirmé et falsifiable, mérite
un garde de régression sur la relation `ceilL.yPct == ceilR.yPct ⟺
confondues`. **Delta déclaré avant exécution : 232 → 233.**

**7. Clôture de 7b, resserrée.** Établi sur le domaine mesuré (4
presets réels + scènes δ_deg construites) : `residualFrac` sur la
baseline non perturbée ne fournit PAS de garde-fou continu en amont
de la bascule de `room_painter.dart:139` — plage [98,3%, 121,1%]
sans seuil discriminant. **Non établi** : « aucune bascule
défendable n'existe ». Un discriminant BOOLÉEN (un seul couple fini)
est gratuit AU POINT de bascule, puisqu'il en est la condition
d'entrée — mais il dit seulement qu'on est dans la branche, pas si
la calibration sous-jacente est réparable ou catastrophique. C'était
toute la fonction attendue d'un garde CONTINU, et cette fonction
reste non pourvue. L'objection de domaine joue symétriquement : 4
presets plus des scènes δ_deg construites ne fondaient pas
"garde-fou continu inerte" (établi ce tour-ci), ils ne fondent pas
davantage "bascule indéployable" (jamais établi, nulle part). Le 1/4
de `projectionParallele` (haussmann seul distinct) est de même une
PROPRIÉTÉ DE LA CONSTRUCTION δ_deg partagée par les presets (voir
clause 6), pas une propriété indépendante des presets eux-mêmes.
**Étiquette finale retenue** : question mesurable CLOSE (le domaine
mesuré ne fournit pas de garde continu), résidu (arbitrage éventuel
d'une bascule) HORS DE PORTÉE de ce dispositif de mesure — ni "en
attente", ni "impossible". `room_painter.dart:139` reste sur le
membre historique sur ce fondement précis : pas parce qu'aucune
alternative n'existerait, mais parce que le dispositif de mesure
disponible ne peut ni la motiver ni l'exclure.

## Point 7b-3-bis — sonde provençal, provenance, durcissements Étage C
(C3′, C4-1′), 5ᵉ entrée Étage C (C5)

**Sonde provençal + provenance (détail intégral :
`docs/logs/point7b_3_bis_sonde.txt`)** : sur provençal, `perpDist /
crossDirs = 700,0` exactement (`700,0 = kCanvasW/2`), confirmant que
le résidu non nul de la clause 2 est structuré par le même centre de
canvas que le `vp.x` des presets symétriques, pas un bruit
indépendant. Le diagnostic initial d'« origine normalisation » via
`ux==vx`/`uy==vy` était mal posé (comparaison de grandeurs
hétérogènes, unitaire vs longueur) — non confirmé proprement ; la
variante « cas symétrique aux dimensions de provençal » n'est donc
pas écrite, faute de diagnostic la justifiant. Provenance de
`727,998`/`741,9966` (Bloc 2) : les deux valeurs sont réelles et
sourcées dans des logs versionnés distincts (`vpBottom.x=727,997757`
dans `derivation_haussmann_min.txt` ; `vp.x=741,9966348850253` dans
plusieurs logs de suite complète) — deux observables distincts du
même calcul, aucune interversion à rétracter.

**Durcissements Étage C (détail intégral, sorties brutes complètes :
`docs/logs/point7b_3_etage_c.txt`, section « TOUR 7b-3-bis »)** :
- **C3′ [converti A′→C]** : les 3 `expect` vacants de la Mesure 2
  (clause 3) sont complétés par 4 `expect(..., closeTo(valeur_exacte,
  1e-9))` par preset (valeurs sourcées `docs/logs/point7b_2.txt`).
  Rejeu de la mutation ×3,0 (`lib/`) : ROUGE confirmé (`Actual:
  <3.6341749470578257>` vs attendu `1.211391649019275` pour
  haussmann). La Mesure 2 est désormais une mesure GARDÉE, pas
  seulement publiée.
- **C4-1′ [converti A′→C]** : `greaterThanOrEqualTo(3)` complété par
  `equals(3)`, `equals(1)`, et le nom nominatif du preset distinct
  attendu (`['haussmann']`). Rejeu de la mutation du seuil
  (`perpDist < 5.0`, côté test) : ROUGE confirmé (`Actual: <4>` vs
  attendu `<3>`), là où l'ancien seuil bas absorbait silencieusement
  la reclassification 4/0.
- **C5 [5ᵉ entrée Étage C]** : resserrement du seuil de classification
  lui-même (`perpDist < 1e-6` → `perpDist == 0.0`, côté test) :
  provençal (`perpDist=2,842×10⁻¹³`, non nul bit à bit, clause 2)
  bascule en DISTINCTES, bilan 2/2, ROUGE confirmé dès
  `greaterThanOrEqualTo(3)`. **Marge recalculée sur la grandeur
  RÉELLEMENT comparée au seuil dans `estConfondue`** (`perpDist`, pas
  l'écart `dy` en amont de la chaîne, qui n'est pas la quantité
  testée) : `1e-6 / 2,842×10⁻¹³ ≈ 3,52×10⁶`, soit `log₁₀ ≈ 6,55` —
  **entre six et sept décades** (arrondi par excès à « sept décades »
  dans les deux occurrences antérieures de ce chiffre, qui se
  contredisaient en libellé — « sept décades » ici, « SEPT DÉCADES »
  dans `docs/logs/point7b_3_etage_c.txt` — sans jamais citer le
  rapport chiffré ; corrigé dans les deux textes par le rapport
  `≈3,52×10⁶` / `log₁₀≈6,55`). `equals(3)` n'est donc pas fragile pour
  un seuil réaliste ; seule une mutation à l'exactitude bit à bit le
  fait rougir. Ceci motive le choix de la tolérance `1e-6` plutôt que
  de la laisser paraître arbitraire.

Les 3 mutations ont été restaurées individuellement (`git diff
--stat lib/ test/` vide sur `lib/` après chacune, relance verte
vérifiée). Aucun `test()` neuf dans ce lot (compte de tests inchangé
par C3′/C4-1′/C5 — assertions supplémentaires dans les 2 `test()`
existants). `room_painter.dart:139` reste sur le membre historique —
aucune bascule produit touchée.

## Point 7b-3-ter — correctif ULP (clause 6 rétractée sur le lien
pct), correctif pragma `avoid_print` (clause 4 confirmée, pas
réécrite), reformulation du ratio 700,0 (clause 6)

**1. Correctif ULP — le « lien rigide EXACTEMENT » de la clause 6 est
RÉTRACTÉ au niveau pct (détail intégral, sorties brutes complètes :
`docs/logs/point7b_3_ulp_probe.txt`).** Le texte antérieur affirmant
que « les 4 presets réels vérifient tous le lien rigide
`wallTL.yPct − 0,01 = ceilL.yPct` et `wallTR.yPct − 0,01 = ceilR.yPct`
... EXACTEMENT » a été tapé de mémoire (report d'une vérification
Python antérieure, hors session), pas relu depuis `persp_calib.dart`
au moment de l'écriture, et ne couvrait que 3 comparaisons sur les 8
requises (2 paires TL/TR × 4 presets — haussmann a `ceilL≠ceilR`, donc
2 paires distinctes à vérifier, pas 1 comme implicitement traité).
Sonde jetable `_tmp_ulp_test.dart` (confinée `test/`, créée, exécutée,
supprimée) mesurant Dart-natif, par preset, `wallTL.yPct−0,01==
ceilL.yPct`, `wallTR.yPct−0,01==ceilR.yPct`, et — le maillon
réellement en cause — `wallTL_shifté.dy==ceilL.dy` après conversion
canvas (comparaison réellement effectuée par `pg.lineIntersect` sur la
scène `δ_deg`, pas la simple soustraction pct) :

- **Au niveau pct** (8 comparaisons) : SEULES 3 sur 8 sont vraies
  (moderne TL, moderne TR, haussmann TR) ; 5 sont FAUSSES (haussmann
  TL, provencal TL, provencal TR, scandinave TL, scandinave TR) — dont
  le cas exact soulevé : `0,085 − 0,01 == 0,075` est bien FAUX pour
  scandinave (`0,07500000000000001 ≠ 0,075` littéral, 1 ulp d'écart
  au-dessus de 0,075, confirmé). Le « EXACTEMENT » de la clause 6 est
  donc FAUX pour 3 des 4 presets au niveau pct — seul moderne le
  vérifie intégralement.
- **Au niveau canvas** (`wallTL_shifté.dy==ceilL.dy`, la grandeur
  réellement consommée) : moderne (`true`/`true`) et scandinave
  (`true`/`true`) obtiennent l'égalité bit à bit malgré l'échec pct de
  scandinave — la conversion pct→canvas RECOMBINE les arrondis et
  rétablit l'égalité pour scandinave, contredisant toute attribution
  simple « pct exact ⟹ canvas exact ». Provençal (`false`/`false`) ne
  rétablit PAS l'égalité canvas, cohérent avec son résidu mesuré
  (`perpDist=2,842×10⁻¹³`, clause 2). Haussmann est MIXTE
  (`false`/`true`) — sans conséquence sur son statut « distinct »,
  qui reste fondé sur `ceilL.yPct≠ceilR.yPct` (Mesure 4), pas sur ce
  lien wallX-ceilX.

**Conclusion corrigée** : la classification confondue/distincte reste
correctement fondée sur `ceilL.yPct == ceilR.yPct` (établi
indépendamment par la Mesure 4 synthétique, non affecté par ce
correctif). Ce que la clause 6 antérieure attribuait à tort à un
« lien pct exact partagé par les 4 presets » est en réalité une
propriété du niveau CANVAS (pas pct), qui elle-même n'explique QUE la
précision bit à bit du résidu (nul exact vs nul au bruit machine)
DANS le sous-cas où `ceilL.yPct==ceilR.yPct` est déjà vrai — elle
n'est ni nécessaire ni suffisante pour la classification elle-même
(haussmann, mixte, le montre). Aucune conséquence sur le Verdict de la
clause 6 (hypothèse de symétrie confirmée) ni sur la Mesure 4
committée (basée sur `ceilL.yPct==ceilR.yPct`, jamais sur le lien
wallX-ceilX) — seule l'explication accessoire du mécanisme au niveau
pct est corrigée.

**2. Correctif `avoid_print` — clause 4 CONFIRMÉE, pas réécrite
(détail : sortie brute des 3 commandes prescrites ci-dessous).**
Lecture décisive, remplaçant l'investigation antérieure (git stash/
checkout, quasi vacante) :
```
flutter analyze 2>&1 | grep "unnecessary_import\|avoid_print" | grep "vp_fallback_mode_test\|vp_frac_degenere_test"
grep -c "print(" test/core/perspective/vp_fallback_mode_test.dart
grep -c "ignore: avoid_print" test/core/perspective/vp_fallback_mode_test.dart
```
Sortie : la 1ʳᵉ commande isole `vp_fallback_mode_test.dart:356:9 •
avoid_print` — SEULE occurrence dans ce fichier, alors que le pragma
`// ignore: avoid_print` s'y trouvait en ligne 350, séparé du `print(`
par 4 lignes de commentaire explicatif (insérées par le reformatage
clause 2, tour 7b-3). La 2ᵉ et 3ᵉ commande donnent 9=9 (macro-compte
par fichier, insensible à l'adjacence ligne-à-ligne) — ce comptage
global ne détecte PAS ce défaut, confirmant que la 1ʳᵉ commande était
bien la mesure décisive. **Décision appliquée strictement selon la
règle du brief** : `print( − pragmas` locaux à ce site valait 1 (un
print non couvert) → corrigé en déplaçant le pragma immédiatement au-
dessus du `print(` (adjacence rétablie, aucune logique modifiée).
`flutter analyze` retombe à **106 info / 1 warning** (confirmé après
correctif). **La clause 4 N'EST PAS réécrite** : sa prémisse (« retrait
de `dart:ui` ramène 107→106 ») était en réalité CORRECTE — le
défaut résidait dans un site distinct (adjacence du pragma, introduit
par une édition différente du même tour), pas dans l'arithmétique de
la clause 4 elle-même. **Note non actée** : le lint `unnecessary_import`
sur `vp_frac_degenere_test.dart:55` (import `dart:ui` redondant avec
`flutter_test`) SUBSISTE et reste COMPTÉ dans ces 106 — le retirer
donnerait 105 ; ce n'est pas fait ce tour (hors périmètre, tolérance
déjà actée en 7b-1/7b-2, cf. clause 4 originelle). Fichier
`vp_fallback_mode_test.dart` touché
(déplacement de commentaire seul, aucune modification de logique) →
suite complète et recomptage JSON rejoués par mesure (`+233: All
tests passed!`, JSON 233/233/0, tous deux confirmés inchangés,
`docs/logs/point7b_3.txt` et `docs/logs/point7b_3_json.txt`
écrasés avec la sortie fraîche).

**3. Reformulation du ratio `perpDist/crossDirs=700,0` (clause 6)** :
le texte antérieur laissait entendre que ce rapport tiendrait
« quelles que soient les valeurs » — surenchère corrigée directement
dans la clause 6 ci-dessus : le rapport est une CONSÉQUENCE de la
configuration symétrique mesurée (`vy=0`, `ux=1,0`,
`uy'=−uy ⟹ crossDirs=2·uy`), ne porte aucune information au-delà de
`uy`, et NE GÉNÉRALISE PAS — haussmann (asymétrique) mesure un rapport
de `5,76×10¹⁶`, sans rapport avec 700,0. La dégradation en tautologie
reste correcte, seule sa justification initiale l'était mal.

**Point 8 : ne rien commencer sans accord explicite utilisateur —
toujours bloqué, sans intitulé enregistré.**

## Points restants (ordre imposé)

- **P7a** — FAIT ce tour (§B + §A, commit unique, poussé). Voir
  "Point en cours / suivant" ci-dessus.
- **P7b** — arbitrage du site du paramètre requis (voir ci-dessus),
  enum `VpFallbackMode{erreurExplicite,projectionParallele}` en
  paramètre requis (sans défaut). Voie A (projection parallèle,
  `metresHauteur` seul, hypothèse axe caméra⊥mur documentée comme
  hypothèse). Voie B (erreur explicite, comportement observé rapporté).
  Rapport mesurable 4 presets × 2 modes + scène synthétique, sans
  arbitrer.
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
- **Un total `flutter analyze` conservé n'est pas une absence de
  changement** (Point 7b-3-ter/bis) : le retrait de `dart:ui` dans
  `vp_fallback_mode_test.dart` (un `unnecessary_import` en moins) et
  le décollement du pragma `avoid_print` par le reformatage clause 2
  (un `avoid_print` non couvert en plus) se sont soldés à 107→107,
  masquant les deux événements l'un derrière l'autre — seul le
  correctif du second a fait retomber le compte à 106.
- **Un `grep -c` par fichier est aveugle à un défaut d'adjacence**
  ligne-à-ligne entre un pragma `// ignore:` et le site qu'il doit
  couvrir (compte global identique, 9=9, que l'adjacence soit rompue
  ou non) — seul `flutter analyze` (qui applique la règle Dart réelle
  d'adjacence) le détecte. Une numérotation ou un motif de compte tapé
  de mémoire, plutôt que re-mesuré, est exactement ce qui a produit le
  couple `727,998`/`741,9966` mal attribué avant correction (Point
  7b-3-bis) — aucune généralisation de motif au-delà des cas
  effectivement sourcés n'est écrite ici sans grep dédié.
