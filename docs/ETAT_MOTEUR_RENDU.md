# État du moteur de rendu — Staff Décor Studio

**Objet de ce document** : consigner, à un instant donné, la coexistence de
deux lignées de code géométrique dans ce projet — une lignée 2D livrée et
branchée à l'écran, une lignée 3D rigoureuse mais jamais appelée en dehors
des tests — et la question d'échelle qui en découle. Rédigé pour être
relisible sans contexte de session : chaque chiffre cité renvoie soit à un
hash de commit (`git show <hash>`), soit à un chemin de fichier lu
directement dans le dépôt au moment de la rédaction. Toute valeur sans
source de ce type est marquée explicitement **« estimation non
vérifiée »**.

---

## 1. Les deux lignées et leur déconnexion

Le dépôt contient deux ensembles de code géométrique indépendants, qui ne
s'appellent jamais l'un l'autre.

**Lignée 2D, livrée et branchée à l'écran** : `lib/core/perspective/`
(`room_painter.dart`, `vanishing_point.dart`, `cornice_plinth_painter.dart`,
`profile_strip.dart`, `ratio_lookup.dart`, `calib_canvas.dart`,
`persp_geometry.dart`). `RoomPainter` (`lib/core/perspective/room_painter.dart`)
importe explicitement `calib_canvas.dart`, `vanishing_point.dart`,
`cornice_plinth_painter.dart`, `moulure_painter.dart`,
`other_families_painter.dart`, `product_texture_cache.dart`,
`ratio_lookup.dart` (liste d'imports lue directement dans le fichier,
lignes 18-28) — et n'importe ni `camera.dart` ni `calib_to_camera.dart`.
C'est ce `RoomPainter` qui est le moteur réellement utilisé par
`studio_screen.dart` (chemin d'import réel de la photo confirmé par lecture
de ce fichier : `ImagePicker().pickImage` → `readAsBytes()` →
`state.setRoomImageBytes(bytes, ...)`).

`VanishingPoint` (`lib/core/perspective/vanishing_point.dart`) est un
modèle purement 2D : ses seuls champs sont `vp`, `fTL`, `fTR`, `fBL`,
`fBR`, tous de type `Offset` ; il n'y a dans ce fichier ni focale, ni
profondeur, ni type `Vector3`. Sa docstring (lignes 1-18 du fichier)
énonce explicitement qu'il remplace trois anciens moteurs de perspective
incompatibles (bandes plates sans perspective, VP heuristique
approximatif, VP à pourcentages fixes dans `comparateur.js`) et qu'il est
« l'UNIQUE source de vérité désormais », consommé identiquement par
Studio et Comparateur — c'est la correction identifiée dans le fil comme
« Bug #5 ».

**Lignée 3D, rigoureuse, jamais appelée hors tests** :
`lib/core/geometry/` (`camera.dart`, `calib_to_camera.dart`, `sweep.dart`).
Recherche exhaustive (`grep -rn "resolveFocal|readFocalFromExif|
buildCalibratedScene|sweepMoulure|MoulureProfile|computeCrossSectionRings"
lib/`) : toutes les occurrences trouvées sont soit la définition de ces
fonctions/classes dans `lib/core/geometry/*.dart` lui-même, soit des
mentions dans les docstrings/commentaires de `CONVENTIONS.md`. Aucun
fichier hors de `lib/core/geometry/` ne les appelle. Recherche
complémentaire (`grep -rln "core/geometry" lib/ --include="*.dart" | grep
-v "^lib/core/geometry/"`) : aucun résultat — aucun fichier de `lib/` en
dehors du dossier `geometry/` lui-même n'importe quoi que ce soit de ce
module. Cette lignée n'est consommée que par `test/core/geometry/*.dart`.

**Ce n'est pas une régression.** Bug #5 (trois moteurs 2D incompatibles)
est bien clos : `VanishingPoint` est aujourd'hui la source unique côté 2D,
comme sa docstring le revendique et comme le confirme la lecture de
`room_painter.dart`. Ce qui existe est **deux ensembles parallèles** : un
moteur 2D non-métrique livré, et un moteur 3D métrique rigoureux mais
non-branché — pas un moteur cassé qui en remplacerait un autre.

---

## 2. Acquis validés

- **Bug 1 — signe de `heightAxis`** : `_downFromCeiling()` retournait
  `heightAxis.y = -1.0`, ce qui, combiné à `yProfilMm ≤ 0`
  (`CONVENTIONS.md` §2), produisait une double négation plaçant tout le
  mesh ~20 cm au-dessus du plafond réel. Test rouge : commit `e0908fa`
  (message : « Expected: a numeric value within <0.000001> of
  <0.683655311607143> / Actual: <1.089394911607143> »). Correctif : commit
  `85bb204`, renommage en `_upFromCeiling()` et inversion du signe
  retourné ; régression complète confirmée dans ce même commit :
  « flutter test test/core/geometry/ → +58: All tests passed! ». Invariant
  écrit dans `lib/core/geometry/CONVENTIONS.md` §3 (docstring de
  `profileToWorld`) et §3bis (section dédiée « INVARIANT DUR — signe de
  `heightAxis` »), les deux sections confirmées présentes par lecture
  directe du fichier à la rédaction de ce document.

- **Ancrage de la croix bleue** : commit `f6dbef1`. La croix « origine du
  profil » était dessinée sur
  `ringsExposed.first[profile.ceilingIndices.first]` au lieu de
  `pathMeters.first` (== `wallOrigin`) ; écart mesuré dans ce commit :
  exactement 112,7888 mm en Z monde, correspondant à la coordonnée x du
  sommet d'indice 3 de `D720.json` — donc un mauvais sommet désigné, pas
  une dérive numérique. Correctif appliqué aux deux scripts d'overlay
  concernés ; sortie brute du commit : « flutter test
  test/core/geometry/ : 61/61 passed ».

- **Origine `(0,0)` du profil = point virtuel hors matière** : confirmé
  dans le même commit `f6dbef1` par lecture complète des 25 sommets de
  `assets/profiles/D720.json` — aucun sommet exact à `(0,0)` dans
  `profil_mm`. Relevé à cette occasion : `wallIndices = [1, 2]`,
  `ceilingIndices = [3, 4]`, `pointsMm[1] = (0.0, -202.8698)` (sur la face
  mur), `pointsMm[3] = (112.7888, 0.0)` (sur la face plafond) — un
  intervalle de ~112,79 mm sépare le bord intérieur de la face de pose mur
  du début de la face de pose plafond. Confirmé conforme au comportement
  attendu d'une corniche à dos creux (sommets 2 et 3 reliés par une
  diagonale de fermeture du contour, pas par un chemin le long des faces
  de pose) — pas une anomalie.

---

## 3. Rétractations

Cette section liste, à dessein, les conclusions provisoires de ce fil qui
ont été explicitement annulées ou vidées de leur portée pratique — pour
qu'une relecture rapide de l'historique des commits ne s'y laisse pas
prendre.

- **Conclusion de `76727cf` sur ceilL/ceilR** : ce commit mesurait un
  écart constant de 18,9875 px entre le trajet rouge et un « filet »
  informel repéré à y≈175 (référence non vérifiée par commande, issue
  d'une inspection visuelle de crops antérieure), et concluait que ceilL
  et ceilR contribuent de façon identique à cet écart (delta droite−gauche
  = 0,0 px). Le commit `35d758f` a montré que ce `dy = 0` est **garanti
  par construction** : `ceilLOnEdge` et `ceilROnEdge` sont tous deux
  projetés par `buildCalibratedScene`/`projectOntoLine` sur la même droite
  d'intersection mur∩plafond, à la même profondeur caméra
  (`L.z == R.z == -3.0`, égalité bit-à-bit confirmée dans ce commit) —
  quelle que soit la calibration source. La conclusion géométrique de
  `76727cf` reste vraie en elle-même, mais **sans portée pratique** pour
  distinguer une erreur sur ceilL d'une erreur sur ceilR. Rétractation
  écrite explicitement dans le message du commit `5580799`.

- **Pente d'arête prétendument inversée** : hypothèse formulée dans une
  session antérieure à ce document, démentie par inspection de crops
  (mentionnée comme telle dans le message du commit `f6dbef1`, sans
  qu'un commit dédié à cette rétractation n'existe — traçable uniquement
  par la mention dans `f6dbef1`).

- **Ratio 1,18 (bbox vs hauteur)** : mentionné dans des sessions
  antérieures à ce fil comme indicateur de calibration ; retiré
  explicitement de la liste des indicateurs dans le commit `5580799`, au
  motif qu'il compare une bbox à une hauteur pure en utilisant une focale
  et une profondeur postulées par défaut (`FocaleOrigine.defaut`,
  `backWallDepthM` non surchargé — voir section 4) et ne valide donc rien.

- **EXIF** : proposé comme piste dans ce fil, puis retiré par l'utilisateur
  lui-même comme redondant — la lecture EXIF est **déjà implémentée**
  dans `resolveFocal` (`lib/core/geometry/camera.dart`, ligne 495 pour la
  signature de la fonction), avec l'ordre de priorité documenté en ligne
  487 : « EXIF > calcul géométrique (points de fuite) > défaut
  (35mm-équivalent) ». Le point réellement bloquant n'est pas l'absence de
  ce mécanisme mais le fait que `resolveFocal` — comme tout le reste de
  `lib/core/geometry/` — n'est appelé par aucun code de `lib/` (voir
  section 1). Vérifié par ailleurs sur la photo de démonstration
  `assets/demo_scenes/haussmann.jpg` (dump EXIF via Python/PIL, sortie
  brute de cette session) : 0 tag EXIF à tout niveau IFD, métadonnées
  JFIF uniquement — cette photo précise n'aurait de toute façon pas pu
  fournir de focale par EXIF.

---

## 4. Échelle

`focalPx = 2488.8888888888887` observé dans tous les diagnostics de ce
fil (`_debug_ceil_edge_depth_test.dart`, commit `35d758f` ; confirmé dans
le commit `5580799`) est le **repli 35 mm-équivalent**, pas un calcul
géométrique. Preuve apportée dans le commit `5580799` : pour le preset
`haussmann` de `lib/models/persp_calib.dart`, les arêtes verticales
ceilL–floorL et ceilR–floorR ont des `xPct` strictement identiques en haut
et en bas (`0.12`/`0.12` et `0.88`/`0.88` — préconisé par le preset
lui-même, valeurs lues dans `persp_calib.dart`), donc rigoureusement
parallèles en pixels ; `lineIntersect2D` retourne alors `v2 = null` pour
ce couple de droites, ce qui fait tomber `estimateFocalFromBackWallRectangle`
dans sa branche de repli. Sortie brute du commit `5580799` :
`origine = FocaleOrigine.defaut`, `v2 = null`,
`result.focalPx == defaultFocalPx35mmEquivalent(2560.0)` → `true`
(`2488.8888888888887 == 2560 * 35 / 36`).

`backWallDepthM = 3.0` : valeur par défaut du paramètre de
`buildCalibratedScene` (`lib/core/geometry/calib_to_camera.dart`, ligne
151). Recherche exhaustive de tout site d'appel qui la surcharge
(`grep -rn "backWallDepthM" lib/ test/`, ré-exécutée à la rédaction de ce
document) : les seules occurrences hors définition/docstring sont son
usage interne dans `calib_to_camera.dart` (lignes 190-193, 233) et un
`print` dans un script de debug (`test/core/geometry/
_debug_placement_check_test.dart`, ligne 65) qui l'affiche mais ne la
modifie pas. **Jamais surchargée nulle part dans le dépôt** — confirmé
initialement dans le commit `35d758f`, ré-confirmé pour ce document.

Longueur d'arête `2,345142857142857 m` : sortie brute du commit
`35d758f` (« longueur arete 3D = 2.345142857142857 m »). Ce nombre est le
produit arithmétique de `focalPx` (repli 35 mm) et `backWallDepthM = 3.0`
(convention non surchargée) appliqués aux fractions de calibration du
preset `haussmann` — **pas une mesure issue de la photo**.

Conclusion de cette section : la simplification (focale par défaut,
profondeur conventionnelle) était assumée et documentée dans
`calib_to_camera.dart` — sa docstring énonce explicitement (lecture
directe du fichier, lignes 19 et 133) qu'elle fait « un choix explicite et
documenté » plutôt que de prétendre à une reconstruction métrique exacte,
suffisant pour un « rendu visuel en perspective correcte, pas une mesure
physique de la pièce ». Cette hypothèse cesse d'être neutre depuis que des
profils STEP métriques réels (ex. `D720.json`, 202,87 mm de hauteur réelle
— voir section 5) entrent dans la scène : le rapport corniche/mur dépend
alors entièrement d'une échelle postulée, non mesurée.

---

## 5. Trois descriptions concurrentes de D720

- **STEP, `assets/profiles/D720.json`** (relu intégralement à la
  rédaction de ce document) : champ `bbox_mm = {w: 199.145, h: 202.87}` ;
  recalcul indépendant à partir des 25 sommets de `profil_mm` (min/max
  des coordonnées x et y) : extent x = 199,1447 mm, extent y = 202,8698 mm,
  ratio x/y = 0,9816379766727231 (≈ 0,9816). Les deux sources (champ
  `bbox_mm` déclaré dans le JSON et recalcul direct depuis `profil_mm`)
  concordent.

- **`prodProfiles['D720']`, `lib/data/prod_profiles_data.dart`, ligne 225** :
  `ProdProfile(w: 222, h: 258, r: 0.86)` — valeurs issues de pixels de PNG
  de coupe extraits de PDF (catalogue GED), selon la docstring de
  `lib/core/perspective/ratio_lookup.dart` (lignes 1-6 : « 283 entrées
  extraites des PDF GED »).

- **Proportion implicite des coefficients en dur** de
  `StripThickness.corniceDefault` (`lib/core/perspective/
  cornice_plinth_painter.dart`, lignes 81-85, relu à la rédaction de ce
  document) : `faceMurFond: pH * 0.055`, `faceHorizFond: pH * 0.140`,
  `faceMurLat: pH * 0.080`, `faceHorizLat: pH * 0.200`. Rapport
  `0.055 / 0.140 = 0,3928571...` (≈ 0,39) — sans lien avec les deux
  sources précédentes.

L'écart entre la première source (ratio 0,9816) et la seconde
(0,86) est de l'ordre de 14 % — signalé sans être investigué plus avant
dans ce fil. Si la table PDF a été mesurée avec marges (hypothèse non
vérifiée), les 283 entrées de `prodProfiles` seraient potentiellement
concernées, pas seulement D720 — cette hypothèse n'a fait l'objet
d'aucune vérification par commande dans ce fil et doit être traitée comme
**estimation non vérifiée**.

---

## 6. Point de branchement

Relation dimensionnelle du moteur 2D (`VanishingPoint.pH`, hauteur de
perspective en pixels canvas) à une grandeur métrique réelle :
`pxParMetre = pH / metresHauteur`. Cette relation n'est **pas
implémentée** dans le code actuel — elle est formulée ici comme le point
de branchement identifié, pas comme un fait du code.

`metresHauteur` : champ de `lib/state/app_state.dart`, ligne 81
(`double metresHauteur = 2.5;`), lu et écrit par ailleurs aux lignes 585,
606, 769, 800, 837, 901-902 de ce même fichier. Saisi par l'utilisateur
via `TextEditingController` dans `lib/widgets/studio/metres_panel.dart`
(ligne 33 : `_hauteur = TextEditingController(text: _fmt(s.metresHauteur))`)
et appliqué via `applyMetres()`. Persisté dans
`lib/models/saved_project.dart` (lignes 36, 50, 65, 84 — sérialisation
JSON avec repli par défaut à `2.5`). Consommé aujourd'hui par le seul
`lib/core/chiffrage.dart` (ligne 197 : paramètre `metresHauteur` ; ligne
207 : `surface = ((perimetre * metresHauteur) - surfaceOuv).clamp(...)`)
— un calcul de surface pour le chiffrage, sans lien avec le rendu visuel.

`pxPerCm` : champ déclaré dans `lib/state/app_state.dart`, ligne 72
(`double? pxPerCm;`). Recherche de tout autre site de lecture/écriture
dans `lib/` : aucun résultat au-delà de cette déclaration — champ orphelin.

Recherche complémentaire (`grep -rn "metresHauteur|pxPerCm"
lib/core/perspective/`) : aucune occurrence — confirmé qu'aucun lien
n'existe aujourd'hui entre ce champ métrique et le moteur de rendu 2D.

**Estimation non vérifiée, jamais sortie par une commande, formulée de
tête dans une session antérieure à ce document** : à une hauteur sous
plafond `metresHauteur = 2,5 m`, les deux faces de la corniche se
tromperaient en sens opposés — facteur d'environ 0,7× pour `faceMurFond`
et environ 1,76× pour `faceHorizFond`. Ces deux facteurs ne sont
accompagnés d'aucun calcul reproductible dans ce fil (aucun test, aucun
script, aucune sortie de commande ne les établit) — ils doivent être
traités comme de simples pistes à vérifier, pas comme des valeurs
retenues.

---

## 7. Décisions en attente

Questions ouvertes, sans réponse à la date de rédaction de ce document :

- Faut-il rendre la saisie d'une hauteur réelle (ou d'une autre dimension
  de référence dans la pièce) **obligatoire avant tout rendu** avec
  produit, ou bien assumer et afficher explicitement dans l'interface que
  le rendu reste indicatif/non-métrique tant qu'aucune dimension réelle
  n'a été saisie ?
- Quelle source de dimension produit doit faire foi — le STEP
  (`assets/profiles/*.json`, réputé le plus précis mais couvrant un
  nombre de références inconnu à ce jour) ou la table `prodProfiles`
  (283 entrées, couverture large mais origine PDF-pixels potentiellement
  biaisée par des marges, voir section 5) ?
- Une scène de démonstration à arête nue (sans ornementation autour de
  l'arête mur/plafond) est-elle toujours nécessaire pour les diagnostics
  de calibration ? `haussmann.jpg` a été jugé inadapté à cet usage car sa
  corniche existante, très ornée, masque l'arête réelle.
- Bug 2 (calibration ceilR/ceilL) reste **en pause**, explicitement en
  aval de la question d'échelle traitée en section 4 : toute nouvelle
  mesure sur ceilR ou ceilL ne pourra rien prouver de plus tant que la
  question de l'échelle (source de la focale, de la profondeur, du point
  de branchement métrique) n'est pas tranchée en amont.

---

**Statut** : document rédigé le 2026-08-10 (date système du sandbox à la
rédaction), couvrant l'historique jusqu'au commit `5580799` inclus
(dernier commit du dépôt à cette date, vérifié par `git log --oneline -1`
→ `5580799 diag(focal): confirme FocaleOrigine.defaut ...`). Aucun code,
test ou rendu n'a été exécuté pour la rédaction de ce document — seules
des commandes de lecture (`git show`, `git log`, `grep`, lecture directe
de fichiers) ont été utilisées.
