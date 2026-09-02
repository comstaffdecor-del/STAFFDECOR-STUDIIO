# ÉTAT DU PROJET — staff_decor_studio / moteur de perspective (VP)

Reconstruit depuis `git log` + contenu réel des tests. Format imposé :
chiffres + chemins de logs, sans prose.

## Errata mutation (SHA `9eaac52`)

`9eaac52` est poussé — jamais d'`--amend`/`rebase` sur lui. Cinq
corrections, identifiées PENDANT ce tour, sont donc consignées ici
plutôt que réécrites dans l'historique.

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
  (ligne ~753, l'assertion de signe, sans toucher au calcul `signed`) :
  reste du fichier vert (`+40` avant, `+39` sans l'assertion neutralisée
  — isolable, aucun couplage collatéral).
- **Étage B** — inverser la valeur attendue du signe (côté test) :
  rouge sur les 4 presets, message de COMPARAISON DE VALEUR
  (`Expected: <1.0> / Actual: <-1.0>`), pas une exception — le mode
  d'échec est bien une assertion, pas un crash.
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
(`grep -n -A1 "ignore: avoid_print" test/core/perspective/vp_frac_degenere_test.dart`)
confirme que les 7 pragmas actifs (lignes 149, 234, 746, 897, 1138,
1240, 1300 — lignes déplacées par l'édition du collecteur, voir plus
bas) sont chacun immédiatement suivis d'un `print()` réel ; l'orphelin
retracté au Point 6bis a donc bien été traité, aucun pragma mort.
`flutter analyze` (5 `avoid_print` non couverts par un `ignore`, lignes
402/456/505/598) reste identique à la baseline, préexistant, hors
périmètre.

**Rejeu Étage C, preuve versionnée** : capture intégrale dans
`docs/logs/errata_mutation_rouge.txt`
(`flutter test test/core/perspective/vp_frac_degenere_test.dart
--reporter expanded`, exit code 1) — **un seul test rouge** (`+27 -1`),
message unique listant les **4 écarts** (haussmann, moderne,
provençal, scandinave) dans l'ordre naturel d'itération des clés,
chacun avec l'`Offset` obtenu et attendu. Valeurs lues dans le log, pas
prédites : haussmann `Offset(728.0, 185.3)` vs attendu
`Offset(728.0, 750.8)` ; moderne `Offset(700.0, 170.6)` vs
`Offset(700.0, 624.0)` ; provençal `Offset(700.0, 226.1)` vs
`Offset(700.0, 720.9)` ; scandinave `Offset(700.0, 213.8)` vs
`Offset(700.0, 670.0)`. Écart avec la prédiction initiale de ce tour :
provençal avait été annoncé à 226,1 (arrondi) — la mesure du log
confirme 226,1 à la précision affichée (le log n'affiche pas plus de
décimales ici) ; scandinave n'avait au départ aucune trace vérifiée
avant ce rejeu — le log ci-dessus en constitue la première preuve
versionnée. `totalPointsVerifies` est resté à 44 dans cette exécution
rouge (pas de `Expected: <44> Actual: <40>`) : l'incrément
inconditionnel (variante (i)) n'a pas été affecté par le collecteur.
Restauration ensuite : `git checkout lib/core/perspective/vanishing_point.dart`,
`git diff --stat lib/` vide, `flutter test
test/core/perspective/vp_frac_degenere_test.dart` → `+40: All tests
passed!`.

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
