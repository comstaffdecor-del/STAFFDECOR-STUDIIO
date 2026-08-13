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

- **`prodProfiles['D720']` décrit comme « 222×258 mm » (contenu initial
  de la section 5, tel que committé en `387f9a1`)** : c'était faux. Ces
  `w`/`h` sont des pixels d'une image de coupe (confirmé par l'en-tête du
  générateur `prod-profiles.js` et par l'absence totale du PNG source),
  pas des millimètres — la comparaison à `bbox_mm` (STEP, en mm) qui en
  découlait n'a donc jamais été une comparaison homogène. Détail complet
  en section 5 ci-dessous, qui réécrit intégralement cette partie.

- **Concordance à 0,0 mm sur le produit `1000` prise pour une validation
  générale de la mesure géométrique** : cette concordance valide
  uniquement la chaîne d'extraction DXF (`dxf2profile.py`), pas la chaîne
  STEP (`step2profile.py`) qui a produit `D705`/`D718`/`D720` — les deux
  voies sont des implémentations distinctes, sans recoupement l'une avec
  l'autre. Détail en section 5.

- **Arbitrage « la table PDF fait foi » (commit `5580799`)** : portait sur
  une source (`prodProfiles`) dépourvue de toute dimension métrique — cet
  arbitrage ne peut donc pas être maintenu tel quel. Reformulé en section
  5 comme une répartition des rôles entre sources, plutôt qu'un choix
  entre sources concurrentes.

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

## 5. Répartition des rôles entre les sources (D720 et le catalogue corniches)

**RÉTRACTATION EXPLICITE — ces lignes annulent le contenu de la version
initiale de cette section, telle que committée en `387f9a1`.** Cette
version affirmait « PDF → w 222, h 258 mm » : c'était faux. Le résumé
court de cette rétractation (et des deux autres qui en découlent) est
aussi consigné en section 3 ci-dessus, dans la liste des conclusions
annulées. Le détail complet est développé ici, dans la section réécrite
intégralement ci-après.

- **STEP, `assets/profiles/D720.json`** (relu intégralement à la
  rédaction initiale de ce document) : champ `bbox_mm = {w: 199.145, h:
  202.87}` ; recalcul indépendant à partir des 25 sommets de `profil_mm`
  (min/max des coordonnées x et y) : extent x = 199,1447 mm, extent y =
  202,8698 mm, ratio x/y = 0,9816379766727231 (≈ 0,9816). Les deux
  sources (champ `bbox_mm` déclaré dans le JSON et recalcul direct depuis
  `profil_mm`) concordent. **Unité désormais vérifiée** (pas seulement
  documentée comme convention) : `assets/step/D720.stp` déclare
  `SI_UNIT(.MILLI.,.METRE.)` dans son en-tête (confirmé par `grep -io
  "SI_UNIT([^)]*)" assets/step/D720.stp`, identique sur `D705.stp` et
  `D718.stp`) ; `tools/dxf_pipeline/step2profile.py` lit cette unité via
  `Interface_Static.CVal_s("xstep.cascade.unit")` après un `ReadFile()`
  réel (lignes 285-286) plutôt que de la présumer — sa docstring (lignes
  47-62) documente explicitement `ERREUR_UNITES` (profil vide) comme
  seule issue si l'unité résolue n'est ni reconnue ni couverte par
  `units_override.csv`, jamais une supposition silencieuse. Le champ
  `source` écrit dans `D720.json` (et dans `D705.json`/`D718.json`) le
  confirme : `{'fichier': 'D720.stp', 'insunits': None, 'unite_retenue':
  'mm', 'origine_unite': 'step_header', 'methode': 'section_step'}` —
  `insunits: None` prouve que le repli `units_override.csv` n'a même pas
  été consulté, l'en-tête STEP ayant suffi. En-tête du fichier source :
  généré par « Delcam plc STEP library », daté du 06/11/2017 — un export
  CAO industriel d'origine, pas une reconstruction faite pour ce projet.

- **`prodProfiles['D720']`, `lib/data/prod_profiles_data.dart`, ligne
  225** : `ProdProfile(w: 222, h: 258, r: 0.86)`. **Ces `w`/`h` sont des
  pixels d'image de coupe, pas des millimètres** — confirmé en remontant
  au générateur du fichier, trouvé hors du dépôt Flutter
  (`/home/user/staff-decor-sources/webapp/public/static/js/
  prod-profiles.js`, absent de toute copie versionnée avec historique
  git — ce dépôt source n'a lui-même aucun commit). Son en-tête dit
  explicitement : « 283 produits : dimensions du PNG profil pour calcul
  du ratio d'aspect [...] Image accessible via /static/profiles/
  {ref}.png ». Le PNG en question (qui mesurerait 222×258 px si l'unité
  est bien le pixel) est introuvable : le répertoire `/static/profiles/`
  référencé n'existe dans aucune copie disponible du dépôt source (0
  fichier `.png` au total dans `staff-decor-sources`), et les seuls PNG
  portant le nom `D720`/`D718`/`D705` présents dans ce dépôt Flutter
  (`assets/profiles/control/*.png`) font tous exactement 885×888 px —
  taille identique sur les trois, donc un rendu de contrôle généré par le
  pipeline `dxf_pipeline`, pas le PNG de coupe source. La seule grandeur
  que cette table est censée fournir (le ratio `r = w/h`) est donc, elle
  aussi, un ratio de pixels d'image, pas un ratio de cotes physiques.

- **Proportion implicite des coefficients en dur** de
  `StripThickness.corniceDefault` (`lib/core/perspective/
  cornice_plinth_painter.dart`, lignes 81-85, relu à la rédaction de ce
  document) : `faceMurFond: pH * 0.055`, `faceHorizFond: pH * 0.140`,
  `faceMurLat: pH * 0.080`, `faceHorizLat: pH * 0.200`. Rapport
  `0.055 / 0.140 = 0,3928571...` (≈ 0,39) — sans lien avec les deux
  sources précédentes.

**Reformulation de l'arbitrage du 5580799 (« la table PDF fait foi »)** :
cet arbitrage portait sur une source qui ne contient aucune dimension
métrique — il ne peut donc pas être maintenu tel quel. Ce n'est plus un
conflit à trois sources à trancher, mais une répartition des rôles,
établie par lecture directe (pas par arbitrage) :
  - `prodProfiles` (table PDF) : écartée pour toute question d'échelle —
    ne contient que des pixels d'image, aucune mm.
  - `catalogue.csv` (tarif papier, `tools/dxf_pipeline/catalogue.csv`,
    1596 lignes) : reste autoritaire pour les longueurs de barre et les
    prix (`longueur_barre_mm` renseigné sur 338/1596 lignes,
    `prix_ht`/`prix_ttc` sur la quasi-totalité) — mais **muet sur la
    section des 153 lignes désignées « corniche »** : `cote1_mm` n'y est
    renseigné que sur 2/153 lignes (`D107`, cas atypique « équerre à
    éclairage » avec cote dans son libellé ; `D650L`, dont le champ
    capturé est en réalité une longueur de barre, pas une section), et
    aucune des trois références pilotes de ce fil (`D705`, `D718`,
    `D720`) n'en fait partie — leurs colonnes `cote1_mm`/`cote2_mm`/
    `hauteur_mm`/`diametre_mm` sont toutes vides sur leur ligne
    catalogue. Sur l'ensemble du tarif, `cote1_mm` n'est renseigné que
    sur 300/1596 lignes au total.
  - **STEP (`assets/step/*.stp`, `assets/profiles/*.json` produits par
    `step2profile.py`) : unique source de section pour la famille
    corniche**, son unité étant désormais vérifiée par lecture d'en-tête
    (voir ci-dessus) plutôt que présumée par convention. Disponibilité :
    **3 fichiers `.stp`** (`D705`, `D718`, `D720`) pour **8 profils JSON**
    au total dans `assets/profiles/` — les 5 autres (`0900`, `1000`,
    `1005`, `1145c`, `20-54`) proviennent d'une voie DXF distincte
    (`tools/dxf_pipeline/dxf2profile.py`, champ `source.origine_unite:
    'header'`, pas `'step_header'` — deux chaînes d'extraction séparées,
    ne pas confondre).

**Validation métrique obtenue, et sa portée exacte** : le seul
recoupement chiffré disponible entre une cote catalogue et une bbox
mesurée porte sur le SKU `1000` (`Pilastre cannelé 23 x 250 cm`, ligne 59
de `catalogue.csv` : `cote1_mm=230.0` en clair) contre `bbox_mm.w=230.0`
de `assets/profiles/1000.json` — écart de 0,0 mm, sans circularité
(vérifié en lisant `tools/dxf_pipeline/inject_cote_catalogue.py`,
fonction `build_cote_catalogue_mm` : `dims[field] = float(catalogue_row.
get(field))`, aucune lecture de `bbox_mm`/`profil_mm` dans cette
fonction). **Ce recoupement valide la chaîne d'extraction DXF, PAS la
chaîne STEP** : `1000.json` provient de `dxf2profile.py` (voie DXF), pas
de `step2profile.py` (voie STEP, celle qui a produit `D705`/`D718`/
`D720`). Les deux chaînes sont des implémentations distinctes ; aucun
recoupement métrique catalogue-vs-géométrie n'existe à ce jour pour la
voie STEP, et — le tarif étant muet sur la section des corniches — aucun
ne pourra être obtenu depuis cette source pour `D705`/`D718`/`D720`.

**Vraisemblance, marquée comme telle et non comme mesure** : la section
et le prix au mètre linéaire croissent ensemble sur les trois corniches
pilotes — `D705` (bbox ≈101 mm, 19,34 €/ml), `D718` (bbox ≈153 mm, 34,95
€/ml), `D720` (bbox ≈199 mm, 37,67 €/ml), valeurs lues dans
`catalogue.csv` et `assets/profiles/*.json`. Cette progression conjointe
serait improbable si l'une des trois bbox était grossièrement aberrante ;
elle exclut une erreur d'un facteur 10 (confusion cm/mm) ou 25,4
(confusion pouce/mm) mais pas un facteur fin (ex. 1,1) — ce n'est pas une
mesure, seulement un indice de vraisemblance.

**Recherche d'anomalies dans la voie DXF** : 4 des 5 profils DXF
(`0900`, `1005`, `1145c`, `20-54`) portent `statut: "ERREUR_SELECTION"`
et une géométrie vide (`profil_mm`: 0 point, `bbox_mm: {w:0, h:0}`) —
seul `1000` a un statut `OK` sur cette voie. Aucun `ERREUR_SELECTION` sur
la voie STEP : les trois profils `D705`/`D718`/`D720` ont tous `statut:
"OK"`. Ce déséquilibre concerne la robustesse de la sélection de face sur
la voie DXF, pas la voie STEP — mais il réduit d'autant l'échantillon
DXF disponible pour tout recoupement futur (1 cas exploitable sur 5).

---

## 6. Point de branchement

Relation dimensionnelle du moteur 2D (`VanishingPoint.pH`, hauteur de
perspective en pixels canvas) à une grandeur métrique réelle :
`pxParMetre = pH / metresHauteur`. Cette relation n'est **pas
implémentée** dans le code actuel — elle est formulée ici comme le point
de branchement identifié, pas comme un fait du code.

> **Mise à jour (voir footer « Statut »)** : cette affirmation ne vaut
> plus que pour la famille PLINTHE. Pour la famille CORNICHE, la relation
> est désormais implémentée (`lib/core/perspective/strip_px_from_dims.dart`,
> `pxParMm`) et branchée dans `room_painter.dart` (case `'Corniches'`, via
> `corniceFor` de `cornice_plinth_painter.dart`), mais UNIQUEMENT pour les
> 8 références couvertes par `assets/profiles/*.json` — les 275 autres
> références de corniche, ainsi que la totalité de la famille plinthe,
> continuent de dépendre exclusivement des coefficients en dur
> `StripThickness.corniceDefault(pH)`/`.plintheDefault(pH)` décrits plus
> haut dans ce document. Le reste de cette section (métrique produit
> hors 8 refs couvertes, plinthe, décisions en attente) reste
> intégralement valide.

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
- **Validité du plan de coupe choisi sur les profils STEP de la famille
  corniche** (`D705`/`D718`/`D720`) : l'unité de ces fichiers est
  désormais vérifiée (section 5), mais rien ne garantit que le plan de
  coupe retenu par `step2profile.py` pour extraire `profil_mm` correspond
  bien à la section transversale que la pièce physique présenterait à la
  découpe. Cette question est distincte de la question d'unité et n'est
  **pas recoupable depuis le tarif** : la famille pour laquelle une
  validation serait utile (corniche) est précisément celle dont le
  catalogue ne donne aucune cote de section (voir section 5, 2/153 lignes
  cotées, aucune des trois pilotes). Elle ne pourra être tranchée que par
  comparaison directe à une pièce réelle.

---

**Statut** : document rédigé le 2026-08-10 (date système du sandbox à la
rédaction), couvrant l'historique jusqu'au commit `5580799` inclus
(dernier commit du dépôt à cette date, vérifié par `git log --oneline -1`
→ `5580799 diag(focal): confirme FocaleOrigine.defaut ...`). Aucun code,
test ou rendu n'a été exécuté pour la rédaction de ce document — seules
des commandes de lecture (`git show`, `git log`, `grep`, lecture directe
de fichiers) ont été utilisées.

**Mise à jour du 2026-08-13** (date système du sandbox à la rédaction de
cette mise à jour) : câblage de la conversion métrique mm→px dans le
peintre pour la famille CORNICHE (voir note ajoutée en section 6) —
troisième et dernier commit d'une séquence de trois (`StripThickness
.fromPx` seul, puis `ProfileDimsCache`, puis ce câblage). Couvre
l'historique jusqu'au commit de ce câblage inclus (premier de la séquence
à changer quelque chose de visible à l'écran : voir section 6 pour le
périmètre exact — 8 références sur 283, corniche seule, plinthe
inchangée). Hash de ce commit : `7440195` (rédigé après coup — l'entrée
initiale renvoyait au `git log --oneline -1` faute de connaître le hash
avant l'écriture de son propre commit ; corrigé ici par une modification
distincte, sans reword du commit `7440195` lui-même, pour ne pas rouvrir
un commit déjà clos). `flutter analyze` propre et suite de tests
`flutter test` (98 tests, tout le dépôt) intégralement verte au moment de
cette mise à jour.

**Mise à jour du 2026-08-13 (sonde `--force-with-lease`)** : trace
empirique du comportement de `--force-with-lease=<refname>:<expect>`
quand `<refname>` ne correspond pas à la ref réellement poussée, obtenue
sur **git version 2.39.5** (le comportement autour des refs non listées
et de l'interaction avec `push.default` a connu des ajustements selon
les versions — cette trace n'est réutilisable qu'avec cette réserve de
version explicite).

Protocole : branche jetable poussée une première fois (tip A), puis
divergence RÉELLE créée localement par `git reset --hard <parent
commun>` suivi d'un nouveau commit (tip B, frère de A, PAS descendant —
vérifié par `git merge-base --is-ancestor A HEAD` qui échoue). Trois
pushs tentés sur cette même divergence :

1. Push nu, sans force ni bail → `! [rejected] (non-fast-forward)`.
2. Push avec `--force-with-lease="main:<sha-de-main>"` (nom de ref
   délibérément erroné — la ref poussée est la branche jetable, pas
   `main`) → `! [rejected] (non-fast-forward)`, PAS `(stale info)`.
3. Push avec `--force-with-lease="<branche-jetable>:<tip-A-reel>"` (nom
   et SHA corrects) → `+ A...B (forced update)`.

Point de méthode capital sur le résultat 2, à ne pas mal résumer : le
SHA fourni pour `main` (`be72a82`) était lui-même périmé par rapport au
`main` distant réel (`4557f46`) au moment du test. Si le bail nommé
`main` avait été évalué, le rejet aurait porté la mention `(stale
info)`, pas `(non-fast-forward)`. Il ne l'a pas portée. La conclusion
correcte est donc double, et les deux moitiés sont nécessaires : (a) le
bail nommé sur une ref non poussée par cette commande n'est pas
seulement inopérant, il est **inerte** — il n'est pas évalué du tout ;
(b) la ref réellement poussée retombe sur la règle fast-forward
ordinaire du transport git, indépendamment de tout bail présent dans la
commande. C'est la conjonction de (a) et (b), pas (a) seul, qui donne le
mode de défaillance sûr : dire seulement « le bail mal nommé ne force
pas » laisserait croire à un rôle protecteur du bail alors qu'il n'a
joué aucun rôle, protecteur ou autre.

Nettoyage : les deux branches jetables utilisées (une pour la première
série de tests, invalidée après coup car elle ne produisait que des
fast-forwards déguisés ; une seconde pour la divergence réelle
ci-dessus) ont été supprimées localement et sur le remote après chaque
série. Aucune trace résiduelle sur `main`.

---

**Mise à jour du 2026-08-12** (date système du sandbox à la rédaction de
cette mise à jour) : correction de la section 5, qui affirmait à tort
trois choses (voir rétractations ajoutées en section 3 et réécriture
complète en section 5) — couvre l'historique jusqu'au commit `387f9a1`
inclus (dernier commit du dépôt avant celui de cette mise à jour, vérifié
par `git log --oneline -1` → `387f9a1 docs: etat des deux lignees de
rendu (2D livree / 3D non branchee) et question d'echelle`). Aucun code,
test ou rendu n'a été exécuté pour cette mise à jour — seules des
commandes de lecture ont été utilisées, plus une mise à jour de ce
fichier de documentation lui-même.
