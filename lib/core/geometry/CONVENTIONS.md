# geometry/CONVENTIONS.md — Source unique des conventions géométriques

**Statut : source de vérité.** Tout fichier de `lib/core/geometry/` (et tout
code qui en dépend, notamment `sweep.dart`) DOIT renvoyer à ce document au
lieu de redéfinir/recalculer une convention localement. Aucune base
orthonormée, aucune matrice de passage ne doit être reconstruite "à la
main" dans un module individuel : la fonction [profileToWorld] ci-dessous
est **la seule** autorisée à faire cette conversion, appelée partout
ailleurs.

**Pourquoi ce document existe** : trois bugs de repère distincts ont été
découverts et corrigés pendant le développement du pipeline Python
(`solid2profile.py`, cf. `SPEC.md`) — chacun causé par une base 2D→3D
reconstruite indépendamment à un endroit différent du code, avec des
conventions subtilement incohérentes entre elles (rotation différente,
axes échangés). Le correctif a chaque fois été le même : **une seule
fonction, appelée une seule fois, dont le résultat est réutilisé partout**.
Ce document + [profileToWorld] appliquent la même discipline côté Dart,
avant qu'un bug analogue n'apparaisse dans `sweep.dart`.

## 1. Repère monde (Dart, `lib/core/geometry/`)

Convention déjà imposée par `camera.dart` et `planes.dart` (reprise ici
sans changement, pour que ce document soit la référence unique citée par
tous les fichiers) :

- **Main droite**, **X = droite**, **Y = haut**, **Z = vers la caméra**
  (la scène visible depuis une caméra qui "regarde vers la pièce" se
  trouve globalement à Z décroissant).
- **Unités : mètres.**
- **Origine** : au sol, au coin de la pièce (Y=0 = niveau du sol).
- Type Dart : `Vector3` (`package:vector_math/vector_math_64.dart`).

Ce repère est celui de `Camera3D.project`/`unproject` (`camera.dart`) et de
`Plane3`/`intersectPlanes` (`planes.dart`). `sweep.dart` produira son
maillage (sommets de la moulure extrudée) directement dans ce repère —
jamais dans un repère intermédiaire propre au module.

## 2. Repère profil 2D (pipeline Python, `assets/profiles/*.json`)

Convention déjà en vigueur dans `dxf2profile.py`/`solid2profile.py` et
`SPEC.md` (reprise ici, **vérifiée empiriquement** sur les fixtures
`TESTOK.dxf`/`TESTSOLIDE_L.stl` avant rédaction de ce document — voir
§2.3) :

- **Unités : millimètres** (`profil_mm` dans le JSON).
- **x = profondeur depuis le mur** : `x = 0` sur la face de pose mur
  (`face_pose_mur`), **croît** en s'éloignant du mur (vers l'intérieur de
  la pièce).
- **y = hauteur depuis le plafond** : `y = 0` sur la face de pose plafond
  (`face_pose_plafond`), **décroît** en descendant (donc, dans le JSON,
  les points natifs ont `y <= 0` ; la "hauteur depuis le plafond" au sens
  usager est `|y|`).
- **Sens horaire**, en repère mathématique standard (y vers le haut, pas
  le repère image y vers le bas) — c'est-à-dire aire signée **négative**
  (formule du lacet). Voir `dxf2profile.ensure_clockwise`.
- Type Dart (côté consommateur `sweep.dart`) : liste ordonnée de
  `Vector2(x_mm, y_mm)`, ou `Offset` si le point d'entrée est déjà côté
  Flutter — la fonction [profileToWorld] accepte les deux (voir signature).

### 2.1 bis. Le profil peut être CONCAVE — ne jamais le simplifier/convexifier

Pour un motif ornemental (`motif.type="variable"`, denticules, gorges),
`profil_mm` provient d'une **union** de coupes (`shapely.unary_union`,
voir `SPEC.md` §"Extension — pipeline 3D"), **pas** d'une enveloppe
convexe — décision explicitement corrigée en cours de développement
(l'enveloppe convexe effaçait les gorges concaves et détruisait le galbe
réel de la moulure). Conséquence pour `sweep.dart` : le polygone reçu dans
`profil_mm` DOIT être extrudé **exactement tel quel**, sommet par sommet,
dans l'ordre fourni — aucune étape de simplification, de lissage, ni de
`convex_hull`/enveloppe ne doit être appliquée côté Dart. Toute
"correction" du contour dans `sweep.dart` répéterait l'erreur déjà
corrigée côté Python, avec le même effet destructeur sur les motifs
concaves.

### 2.3 Vérification empirique (faite avant d'écrire ce document)

Rejouée sur `TESTSOLIDE_L.stl` (barre en L de référence, cf.
`test_solid2profile.py`) :

```
face_pose_mur.indices    = [11, 0]   (segment vertical x≈0)
face_pose_plafond.indices = [1, 2]   (segment horizontal y≈0)
profil_mm (12 sommets, extrait) :
  (0.0,  -0.04) (0.0, 0.0) (59.97, 0.0) (60.0, 0.0) (60.0, -19.99)
  (60.0, -20.0) (20.02, -20.0) (20.0, -20.0) (20.0, -79.97)
  (20.0, -80.0) (0.01, -80.0) (0.0, -80.0)
aire signée (formule du lacet, y-up) = -2400.0  -> horaire confirmé
```

Confirme : `x` démarre à 0 au mur et croît jusqu'à 60mm (profondeur de la
moulure) ; `y` démarre à 0 au plafond et descend jusqu'à -80mm (hauteur de
la moulure) ; le contour est bien horaire en repère math y-up. Toute
implémentation Dart qui consomme `profil_mm` doit respecter EXACTEMENT
cette convention (pas de retournement de signe implicite, pas de
réordonnancement des sommets).

## 3. Passage profil 2D → monde 3D : [profileToWorld]

**Une seule fonction, un seul endroit, appelée partout** — signature
prévue pour `sweep.dart` (livraison suivante) :

```dart
/// Convertit un point du profil 2D (x = profondeur mur en mm, y = hauteur
/// plafond en mm, voir §2 de CONVENTIONS.md) en un point du repère monde
/// (mètres, voir §1), sachant :
/// - [wallOrigin] : point 3D monde où x_profil=0 ET y_profil=0 coïncident
///   avec le mur/plafond réels (typiquement un point du bord supérieur
///   de la moulure posée, sur l'arête mur∩plafond) ;
/// - [depthAxis] : direction monde **unitaire** dans laquelle x_profil
///   croissant s'éloigne du mur (typiquement l'horizontale perpendiculaire
///   au mur, pointant vers l'intérieur de la pièce) ;
/// - [heightAxis] : direction monde **unitaire** dans laquelle y_profil
///   décroissant (donc plus négatif) descend depuis le plafond
///   (typiquement `-up` du monde, soit Y monde décroissant) ;
/// - [alongAxis] : direction monde **unitaire** de l'axe long de la barre
///   (le long de laquelle le profil est extrudé par sweep.dart) ;
/// - [alongOffsetM] : position le long de [alongAxis] (mètres), 0 à
///   l'origine de la barre.
///
/// Formule (unique, jamais recalculée ailleurs) :
///   world = wallOrigin
///         + (xProfilMm / 1000.0) * depthAxis
///         + (yProfilMm / 1000.0) * heightAxis   // yProfilMm est <= 0
///         + alongOffsetM * alongAxis
///
/// [depthAxis], [heightAxis], [alongAxis] doivent former une base
/// orthonormée directe (main droite) — non revérifié ici (à la charge de
/// l'appelant, voir `sweep.dart` pour la construction typique à partir
/// d'un `Plane3` mur + `Plane3` plafond via `intersectPlanes`).
Vector3 profileToWorld({
  required Vector3 wallOrigin,
  required Vector3 depthAxis,
  required Vector3 heightAxis,
  required Vector3 alongAxis,
  required double xProfilMm,
  required double yProfilMm,
  required double alongOffsetM,
}) {
  return wallOrigin
      + depthAxis * (xProfilMm / 1000.0)
      + heightAxis * (yProfilMm / 1000.0)
      + alongAxis * alongOffsetM;
}
```

Cette fonction sera implémentée dans `sweep.dart` (pas ici, pour éviter un
fichier "utilitaire fourre-tout" — mais sa signature et son contrat sont
fixés par ce document, pas par le fichier qui l'implémente). Tout code qui
a besoin de placer un point de profil dans le monde 3D appelle **cette**
fonction — jamais une base `(u, v)` reconstruite localement par produit
vectoriel, comme cela a été fait puis corrigé dans `solid2profile.py`
(voir `build_fixed_rotation`/bug height map, `SPEC.md`).

## 4. Résumé des bugs de repère déjà rencontrés (pour ne pas les répéter)

Cinq bugs distincts, tous dans `dxf2profile.py`/`solid2profile.py`, tous
de la même famille ("une hypothèse géométrique locale — repère, origine,
classification d'arête — appliquée de façon incomplète ou reconstruite
indépendamment à plusieurs endroits, incohérente avec la réalité du
maillage/contour") :

1. **Coupes non comparables entre elles** : `Path3D.to_2D()` appelé sans
   matrice explicite fait un `plane_fit` propre à chaque tranche →
   origine/rotation différentes d'une coupe à l'autre. Corrigé par
   `build_fixed_rotation(axis)`, calculée UNE fois, réutilisée pour
   toutes les coupes.
2. **Échantillonnage à 3 points fixes (25/50/75%)** : pas un bug de
   repère à proprement parler, mais un bug d'aliasing de phase — classé
   ici parce que la leçon est la même ("ne pas figer une hypothèse locale
   dans plusieurs endroits du code sans la faire dépendre d'une seule
   source de vérité"). Corrigé par un balayage dense.
3. **Height map désalignée** : `build_height_map` reconstruisait sa propre
   base `(u, v)` par produit vectoriel arbitraire, DIFFÉRENTE de celle
   utilisée par `section_polygon_at` pour produire les points 2D du
   profil (vérifié : `(u, v)` obtenus = `(row1, -row0)` de
   `fixed_rotation`, pas `(row0, row1)`) → les rayons de la height map
   étaient lancés au mauvais endroit du pourtour réel. Corrigé en
   réutilisant `fixed_rotation` (paramètre reçu, jamais recalculé).
4. **Origine d'axe = centroïde au lieu du vrai point de départ** :
   `find_long_axis()` retournait le centroïde ACP du maillage comme
   `origin`, alors que tout le reste du module (`sample_areas_along_axis`,
   `build_height_map`, la sélection min/max/médiane de
   `process_one_mesh`) calcule un offset dans `[0, length_mm]` **mesuré
   depuis `origin`**, en supposant implicitement que `origin` est
   l'extrémité de la barre. Le centroïde ACP n'est en général PAS au
   milieu géométrique exact de la projection sur l'axe long (mesh
   asymétrique) : vérifié sur `TESTSOLIDE_DENTICULES`, centroïde à
   proj = 0 mais projection réelle ∈ [-987.4, +1012.6] — donc tout
   offset > 1012.6 (la moitié des échantillons du balayage dense)
   tombait hors du maillage réel, produisant une height map à moitié
   nulle (moitié des lignes de l'image entièrement à zéro). Corrigé en
   redéfinissant `origin = centroid + proj.min() * axis` (le vrai point
   de départ de la barre le long de l'axe). Piège détecté visuellement
   (moitié de la height map rendue noire) AVANT présentation à
   l'utilisateur — les tests automatiques existants à ce moment-là ne le
   détectaient pas (assertions trop faibles : `arr.max() > 0` et
   `(arr > 0).sum() > 10` restent vraies même avec moitié de la barre non
   couverte). Un test de non-régression dédié
   (`test_height_map_couvre_toute_la_longueur_de_la_barre`) a depuis été
   ajouté pour vérifier explicitement un taux de couverture > 95 % sur
   toute la longueur, et l'absence de plage contiguë de lignes nulles.
5. **Détection mur/plafond incomplète, deux temps** : `detect_wall_and_
   ceiling_faces` ne collectait à l'origine que le PREMIER segment
   vertical/horizontal trouvé (2 sommets), au lieu de tous les sommets
   consécutifs colinéaires sous tolérance — vérifié sur
   `TESTSOLIDE_DENTICULES` : face plafond réelle sur 8 sommets (x de 0.04
   à 68.0mm), mais seul le segment [5,6] (x jusqu'à 31.52mm) était retenu
   → `projection_plafond_mm=31.48` au lieu de `68.0`. Corrigé par une
   collecte de "runs" d'arêtes consécutives de même classification.
   Second temps (après passage à l'union de coupes, bug lié) : unir
   plusieurs polygones introduit parfois une micro-arête de jonction
   (jitter de tessellation entre coupes, ex. dx=0, dy=0.0225mm) trop
   petite pour être classée franchement verticale OU horizontale par un
   test strict — elle cassait le run à tort (`projection_plafond_mm`
   retombé à 60.0 après le passage à l'union, avant d'être re-corrigé).
   Corrigé en rendant la classification d'arête permissive aux
   micro-arêtes (compatible avec un run en cours dès que la seule
   composante testée est sous tolérance, sans exiger que l'autre la
   dépasse) : une arête négligeable ne doit jamais interrompre un run,
   quel qu'il soit. Test de non-régression dédié :
   `test_projection_plafond_couvre_tous_les_sommets_colineaires`.

**Leçon générale (bugs 1, 3, 4 et 5)** : ne jamais laisser un module
recalculer sa propre origine/base locale à un autre endroit du code que
celui qui l'a définie la première fois — passer la valeur en paramètre
(ou l'importer d'une fonction unique), jamais la reconstruire par une
hypothèse géométrique indépendante (produit vectoriel arbitraire,
centroïde supposé être une extrémité, etc.).

**Conclusion appliquée à `sweep.dart`** : [profileToWorld] est écrite UNE
fois dans ce document, son contrat est fixé ici, et son implémentation
(dans `sweep.dart`) ne doit jamais être dupliquée/réinventée dans un autre
fichier de `geometry/`. Si un futur module a besoin de placer un point de
profil dans le monde, il importe et appelle cette fonction — il ne
reconstruit pas sa propre base locale. En particulier, `sweep.dart` devra
définir une seule et unique convention pour "le début de la barre" le
long de `alongAxis` (analogue à `origin` dans `find_long_axis`, bug #4
ci-dessus) et ne jamais la recalculer indépendamment dans une autre
fonction du fichier.
