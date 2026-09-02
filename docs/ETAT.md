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
vaut 1,081 sur haussmann et se situe entre 0,98 et 1,21 sur les quatre
calibrations livrées — tout seuil inférieur à 0,98 se déclenche donc
sur les quatre à la fois. Une garde a priori calibrée naïvement bloque
l'application entière au lieu de filtrer les cas dégénérés.

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

**Point 8 : ne rien commencer sans accord explicite utilisateur.**

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
