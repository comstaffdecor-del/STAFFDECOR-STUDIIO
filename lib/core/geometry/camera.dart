/// Caméra pinhole 3D autonome — projection perspective et calibration de
/// focale par points de fuite orthogonaux.
///
/// ⚠️ Ce fichier est **Dart pur** : aucune dépendance UI (`dart:ui`,
/// `package:flutter/...`). Testable en isolation, sans widget.
///
/// ⚠️ Ce fichier NE dépend PAS de `PerspCalib` (`lib/models/persp_calib.dart`)
/// — c'est une décision d'architecture explicite : [Camera3D] et les
/// fonctions de calibration ci-dessous sont génériques et autonomes. Le pont
/// entre les 8 points `PerspCalib` (fractions d'image) et ces primitives
/// géométriques sera fait par un module séparé (`geometry/calib_to_camera.dart`,
/// livraison suivante), qui convertira les `CalibPoint` en `Vector2` pixels
/// avant d'appeler [estimateFocalFromBackWallRectangle] et de construire un
/// [Camera3D]. Aucune modification de `PerspCalib` n'est faite ni nécessaire.
///
/// ## Convention géométrique (imposée, valable pour tout `geometry/`)
///
/// - **Repère monde** : main droite, **X = droite**, **Y = haut**,
///   **Z = vers la caméra** (donc la scène visible depuis une caméra qui
///   "regarde vers la pièce" se trouve globalement à Z décroissant).
/// - **Unités** : mètres.
/// - **Origine** : au sol, au coin de la pièce (Y=0 = niveau du sol).
/// - **Repère caméra (local)** : même convention main droite. L'axe Z
///   caméra pointe vers l'arrière de la caméra (vers l'observateur qui la
///   tiendrait), donc tout point *visible* (devant l'objectif) a une
///   coordonnée Z **négative** dans le repère caméra — convention standard
///   type OpenGL. La "profondeur" `depthCam` utilisée dans ce fichier est
///   définie comme `depthCam = -z_cam`, donc **positive** pour tout point
///   devant la caméra.
/// - **Repère image (pixels)** : origine en haut-à-gauche, **X vers la
///   droite, Y vers le bas** (convention écran standard — cohérent avec
///   `CalibPoint.yPct` de `PerspCalib`, où `yPct` croît du haut vers le bas
///   de l'image). Un flip de signe sur l'axe Y est donc appliqué entre le
///   repère caméra (Y haut) et le repère image (Y bas) — voir [Camera3D.project].
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:exif_reader/exif_reader.dart';
import 'package:vector_math/vector_math_64.dart';

/// Intersection de deux droites 2D (a→b) et (c→d), en coordonnées
/// **pixels image** (pas de lien avec le repère monde).
///
/// Retourne `null` si les droites sont parallèles (ou quasi-parallèles,
/// sous le seuil [epsilon] sur le déterminant) — jamais un point à
/// coordonnées infinies/NaN.
Vector2? lineIntersect2D(
  Vector2 a,
  Vector2 b,
  Vector2 c,
  Vector2 d, {
  double epsilon = 1e-9,
}) {
  final d1x = b.x - a.x, d1y = b.y - a.y;
  final d2x = d.x - c.x, d2y = d.y - c.y;
  final denom = d1x * d2y - d1y * d2x;
  if (denom.abs() < epsilon) return null;
  final t = ((c.x - a.x) * d2y - (c.y - a.y) * d2x) / denom;
  return Vector2(a.x + t * d1x, a.y + t * d1y);
}

/// Résultat d'une projection 3D → 2D par [Camera3D.project].
///
/// [depthCam] est la profondeur du point dans le repère caméra local
/// (positive = devant l'objectif). [isInFrontOfCamera] est `false` si le
/// point est derrière ou exactement dans le plan de la caméra
/// (`depthCam <= 0`) — dans ce cas [pixel] est un repli explicite (le point
/// principal), **jamais NaN/Infinity**.
class ProjectionResult {
  final Vector2 pixel;
  final double depthCam;
  final bool isInFrontOfCamera;

  const ProjectionResult({
    required this.pixel,
    required this.depthCam,
    required this.isInFrontOfCamera,
  });

  @override
  String toString() =>
      'ProjectionResult(pixel: $pixel, depthCam: $depthCam, '
      'isInFrontOfCamera: $isInFrontOfCamera)';
}

/// Caméra pinhole 3D : position + orientation + focale + point principal.
///
/// Autonome : ne dépend d'aucune calibration image (`PerspCalib`). Se
/// construit soit directement (position + matrice de rotation), soit via
/// [Camera3D.lookingAt] (construction "regarde vers", pratique pour les
/// tests et les scènes synthétiques).
class Camera3D {
  /// Position de la caméra dans le repère monde (mètres).
  final Vector3 position;

  /// Matrice de rotation **caméra → monde** : ses colonnes sont les axes
  /// locaux de la caméra (right, up, back) exprimés en coordonnées monde.
  /// Doit être orthonormée (rotation pure) — non revérifié à la
  /// construction, à la charge de l'appelant (ou de [Camera3D.lookingAt]
  /// qui garantit l'orthonormalité par construction).
  final Matrix3 rotationCameraToWorld;

  /// Focale exprimée en pixels (distance focale / taille de pixel), pas en
  /// mm physiques — cohérent avec [estimateFocalFromBackWallRectangle] qui
  /// calcule directement une focale en pixels à partir de points image.
  final double focalPx;

  /// Point principal (en pixels), typiquement proche du centre de l'image.
  final Vector2 principalPoint;

  const Camera3D({
    required this.position,
    required this.rotationCameraToWorld,
    required this.focalPx,
    required this.principalPoint,
  });

  /// Axe "droite" de la caméra, exprimé en coordonnées monde.
  Vector3 get right => Vector3(
    rotationCameraToWorld.storage[0],
    rotationCameraToWorld.storage[1],
    rotationCameraToWorld.storage[2],
  );

  /// Axe "haut" de la caméra, exprimé en coordonnées monde.
  Vector3 get up => Vector3(
    rotationCameraToWorld.storage[3],
    rotationCameraToWorld.storage[4],
    rotationCameraToWorld.storage[5],
  );

  /// Axe "arrière" de la caméra (pointe loin de la scène, vers
  /// l'observateur), exprimé en coordonnées monde.
  Vector3 get back => Vector3(
    rotationCameraToWorld.storage[6],
    rotationCameraToWorld.storage[7],
    rotationCameraToWorld.storage[8],
  );

  /// Direction de visée de la caméra (vers la scène), exprimée en
  /// coordonnées monde. `forward = -back`.
  Vector3 get forward => -back;

  /// Construit une caméra "regardant vers" [target] depuis [eye], selon la
  /// convention lookAt standard (main droite) :
  /// `back = normalize(eye - target)`, `right = normalize(cross(worldUp,
  /// back))`, `up = cross(back, right)`. [worldUp] par défaut = axe Y monde
  /// (`(0,1,0)`), cohérent avec la convention "Y vers le haut" imposée.
  ///
  /// Lance [ArgumentError] si [eye] == [target] (direction de visée
  /// indéfinie) ou si [worldUp] est colinéaire à `eye - target` (caméra
  /// visant exactement selon l'axe up — pose indéfinie). Aucun NaN produit
  /// silencieusement.
  factory Camera3D.lookingAt({
    required Vector3 eye,
    required Vector3 target,
    Vector3? worldUp,
    required double focalPx,
    required Vector2 principalPoint,
  }) {
    final up0 = worldUp ?? Vector3(0, 1, 0);
    final backRaw = eye - target;
    if (backRaw.length2 < 1e-18) {
      throw ArgumentError(
        'Camera3D.lookingAt: eye et target sont confondus, '
        'direction de visée indéfinie.',
      );
    }
    final back = backRaw.normalized();
    final rightRaw = up0.cross(back);
    if (rightRaw.length2 < 1e-18) {
      throw ArgumentError(
        'Camera3D.lookingAt: worldUp est colinéaire à la direction de '
        'visée (eye→target) — pose caméra indéfinie.',
      );
    }
    final right = rightRaw.normalized();
    final up = back.cross(right); // déjà unitaire (back, right orthonormés)
    return Camera3D(
      position: Vector3.copy(eye),
      rotationCameraToWorld: Matrix3.columns(right, up, back),
      focalPx: focalPx,
      principalPoint: principalPoint,
    );
  }

  /// Projette un point 3D monde vers l'image (pixels).
  ///
  /// Si le point est derrière ou dans le plan de la caméra
  /// (`depthCam <= 0`), retourne un [ProjectionResult] avec
  /// `isInFrontOfCamera = false` et `pixel = principalPoint` (repli
  /// explicite) — jamais de division par zéro / NaN.
  ProjectionResult project(Vector3 worldPoint) {
    final rel = worldPoint - position;
    final pCam = rotationCameraToWorld.transposed().transformed(rel);
    final depthCam = -pCam.z;

    if (depthCam == 0) {
      return ProjectionResult(
        pixel: principalPoint.clone(),
        depthCam: 0,
        isInFrontOfCamera: false,
      );
    }

    final xNdc = focalPx * pCam.x / depthCam;
    final yNdc = focalPx * pCam.y / depthCam;
    final pixel = Vector2(
      principalPoint.x + xNdc,
      principalPoint.y - yNdc, // flip : Y caméra haut -> Y image bas
    );
    return ProjectionResult(
      pixel: pixel,
      depthCam: depthCam,
      isInFrontOfCamera: depthCam > 0,
    );
  }

  /// Dé-projette un pixel image vers un point 3D monde, connaissant sa
  /// profondeur caméra [depthCam] (positive = devant l'objectif).
  ///
  /// Inverse mathématique exacte de [project] : pour tout point monde `p`,
  /// `unproject(project(p).pixel, project(p).depthCam) == p` (à la
  /// précision flottante près).
  Vector3 unproject(Vector2 pixel, double depthCam) {
    final xNdc = pixel.x - principalPoint.x;
    final yNdc = principalPoint.y - pixel.y; // inverse du flip de [project]
    final pCam = Vector3(
      xNdc * depthCam / focalPx,
      yNdc * depthCam / focalPx,
      -depthCam,
    );
    return rotationCameraToWorld.transformed(pCam) + position;
  }
}

/// Origine de la focale retenue au final (par [resolveFocal], qui applique
/// la priorité EXIF > calcul géométrique > défaut).
enum FocaleOrigine {
  /// Focale lue depuis les métadonnées EXIF de la photo (FocalLength +
  /// FocalLengthIn35mmFilm, ou FocalLength + FocalPlaneXResolution).
  /// **Prioritaire** sur le calcul géométrique quand disponible : gratuite,
  /// et bien plus fiable que 4 clics utilisateur sur les coins du mur.
  exif,

  /// Focale effectivement calculée par intersection des points de fuite
  /// orthogonaux du mur du fond (méthode Caprile-Torre).
  calculee,

  /// Cas dégénéré (VP à l'infini, ou produit scalaire non négatif, et pas
  /// d'EXIF disponible) : focale de repli, équivalent 35 mm sur capteur
  /// plein format.
  defaut,
}

/// Résultat de [estimateFocalFromBackWallRectangle].
///
/// [v1] / [v2] sont les points de fuite horizontal/vertical du mur du fond
/// quand ils ont pu être calculés géométriquement (même si le résultat final
/// est [FocaleOrigine.defaut] parce que leur produit scalaire ne validait
/// pas le cas non-dégénéré) — exposés pour transparence/debug, jamais
/// cachés. `null` uniquement quand l'intersection de droites elle-même est
/// impossible (droites parallèles, mur strictement frontal).
class FocalEstimationResult {
  final double focalPx;
  final FocaleOrigine origine;
  final Vector2 principalPoint;
  final Vector2? v1;
  final Vector2? v2;

  const FocalEstimationResult({
    required this.focalPx,
    required this.origine,
    required this.principalPoint,
    this.v1,
    this.v2,
  });

  @override
  String toString() =>
      'FocalEstimationResult(focalPx: $focalPx, origine: $origine, '
      'principalPoint: $principalPoint, v1: $v1, v2: $v2)';
}

/// Focale équivalente 35 mm (35 mm de focale sur un capteur plein format,
/// largeur de référence 36 mm), convertie en pixels pour une image de
/// largeur [imageWidthPx]. Utilisée comme repli explicite quand la focale
/// ne peut pas être calculée géométriquement.
double defaultFocalPx35mmEquivalent(
  double imageWidthPx, {
  double focaleMm = 35.0,
}) {
  const largeurCapteurMm = 36.0; // plein format, référence "équivalent 35mm"
  return imageWidthPx * (focaleMm / largeurCapteurMm);
}

/// Calcule la focale (en pixels) d'une caméra à partir des 4 coins d'un
/// rectangle réel connu vu en perspective (typiquement le mur du fond
/// d'une pièce) — méthode des deux points de fuite orthogonaux
/// (Caprile–Torre) :
///
/// 1. Le rectangle [ceilL]-[ceilR]-[floorL]-[floorR] a deux paires de
///    côtés parallèles dans le monde réel. Leurs images convergent (sauf
///    cas frontal) vers deux points de fuite :
///    - `v1` (horizontal) = intersection des droites (ceilL→ceilR) et
///      (floorL→floorR) — les deux côtés horizontaux du rectangle.
///    - `v2` (vertical) = intersection des droites (ceilL→floorL) et
///      (ceilR→floorR) — les deux côtés verticaux du rectangle.
/// 2. `c` = point principal (centre image par défaut : `(imageWidthPx/2,
///    imageHeightPx/2)`).
/// 3. `f = sqrt(-(v1-c)·(v2-c))`, **valide seulement si le produit
///    scalaire `(v1-c)·(v2-c)` est strictement négatif** (condition
///    d'orthogonalité des deux directions de visée vers v1/v2 dans
///    l'espace caméra).
///
/// **Cas dégénérés — jamais de bricolage, jamais de NaN** : si `v1` ou
/// `v2` n'existe pas (droites parallèles → mur vu de face selon cet axe),
/// ou si le produit scalaire n'est pas strictement négatif, la fonction
/// retourne explicitement [FocaleOrigine.defaut] avec
/// [defaultFocalPx35mmEquivalent] comme focale de repli. `v1`/`v2` restent
/// exposés dans le résultat quand ils ont pu être calculés (transparence),
/// `null` sinon.
FocalEstimationResult estimateFocalFromBackWallRectangle({
  required Vector2 ceilL,
  required Vector2 ceilR,
  required Vector2 floorL,
  required Vector2 floorR,
  required double imageWidthPx,
  required double imageHeightPx,
}) {
  final principalPoint = Vector2(imageWidthPx / 2, imageHeightPx / 2);

  final v1 = lineIntersect2D(ceilL, ceilR, floorL, floorR);
  final v2 = lineIntersect2D(ceilL, floorL, ceilR, floorR);

  if (v1 == null || v2 == null) {
    return FocalEstimationResult(
      focalPx: defaultFocalPx35mmEquivalent(imageWidthPx),
      origine: FocaleOrigine.defaut,
      principalPoint: principalPoint,
      v1: v1,
      v2: v2,
    );
  }

  final dot = (v1 - principalPoint).dot(v2 - principalPoint);
  if (dot >= 0) {
    return FocalEstimationResult(
      focalPx: defaultFocalPx35mmEquivalent(imageWidthPx),
      origine: FocaleOrigine.defaut,
      principalPoint: principalPoint,
      v1: v1,
      v2: v2,
    );
  }

  final focalPx = math.sqrt(-dot);
  return FocalEstimationResult(
    focalPx: focalPx,
    origine: FocaleOrigine.calculee,
    principalPoint: principalPoint,
    v1: v1,
    v2: v2,
  );
}

/// Focale lue depuis les métadonnées EXIF d'une photo — **gratuite, et
/// bien plus fiable qu'une estimation géométrique à partir de 4 clics
/// utilisateur** sur les coins du mur du fond. À utiliser en priorité 1
/// quand disponible ; le calcul géométrique
/// ([estimateFocalFromBackWallRectangle]) et la focale par défaut
/// ([defaultFocalPx35mmEquivalent]) ne sont que des replis successifs.
///
/// Deux méthodes de calcul, dans cet ordre de préférence :
/// 1. `FocalLengthIn35mmFilm` (equivalent 35mm déjà normalisé par
///    l'appareil/le téléphone) → converti en pixels via
///    [defaultFocalPx35mmEquivalent] appliqué à la focale équivalente
///    réelle (au lieu de la constante 35mm de repli).
/// 2. `FocalLength` (mm réels) + `FocalPlaneXResolution` (pixels par unité
///    [FocalPlaneResolutionUnit], typiquement pouces ou cm) → focale en
///    pixels = `focalLengthMm * (focalPlaneXResolution / unitToMm)`.
///
/// Retourne `null` si aucun tag EXIF utilisable n'est présent, ou si les
/// tags trouvés ne permettent pas un calcul cohérent (division par zéro,
/// valeurs nulles/négatives) — **jamais de NaN silencieux**, l'appelant
/// doit alors retomber sur [estimateFocalFromBackWallRectangle] puis
/// [defaultFocalPx35mmEquivalent].
Future<FocalEstimationResult?> readFocalFromExif(
  Uint8List imageBytes, {
  required double imageWidthPx,
  required double imageHeightPx,
}) async {
  final principalPoint = Vector2(imageWidthPx / 2, imageHeightPx / 2);

  ExifData exif;
  try {
    exif = await readExifFromBytes(imageBytes);
  } catch (_) {
    // Fichier non-image, EXIF corrompu, etc. — repli explicite, pas de
    // propagation d'exception vers l'appelant pour ce cas non-bloquant.
    return null;
  }

  if (exif.tags.isEmpty) return null;

  // Méthode 1 : FocalLengthIn35mmFilm — la plus fiable, déjà normalisée.
  final focal35Tag = exif.tags['EXIF FocalLengthIn35mmFilm'];
  if (focal35Tag != null) {
    final values = focal35Tag.values.toList();
    if (values.isNotEmpty) {
      final focal35Mm = (values.first as num).toDouble();
      if (focal35Mm > 0) {
        return FocalEstimationResult(
          focalPx: defaultFocalPx35mmEquivalent(
            imageWidthPx,
            focaleMm: focal35Mm,
          ),
          origine: FocaleOrigine.exif,
          principalPoint: principalPoint,
        );
      }
    }
  }

  // Méthode 2 : FocalLength (mm réels) + FocalPlaneXResolution (px par
  // unité) — nécessite de connaître l'unité (FocalPlaneResolutionUnit :
  // 2 = pouces, 3 = centimètres ; défaut EXIF = pouces si absent).
  final focalLengthTag = exif.tags['EXIF FocalLength'];
  final focalPlaneXResTag = exif.tags['EXIF FocalPlaneXResolution'];
  if (focalLengthTag != null && focalPlaneXResTag != null) {
    final focalLengthValues = focalLengthTag.values.toList();
    final resValues = focalPlaneXResTag.values.toList();
    if (focalLengthValues.isNotEmpty && resValues.isNotEmpty) {
      final focalLengthMm = _ratioOrNumToDouble(focalLengthValues.first);
      final resPxPerUnit = _ratioOrNumToDouble(resValues.first);

      if (focalLengthMm != null &&
          resPxPerUnit != null &&
          focalLengthMm > 0 &&
          resPxPerUnit > 0) {
        final unitTag = exif.tags['EXIF FocalPlaneResolutionUnit'];
        // 2 = pouces (défaut EXIF), 3 = centimètres.
        final unitCode = unitTag != null
            ? unitTag.values.toList().firstOrNull as int? ?? 2
            : 2;
        final mmPerUnit = unitCode == 3 ? 10.0 : 25.4;
        final resPxPerMm = resPxPerUnit / mmPerUnit;
        final focalPx = focalLengthMm * resPxPerMm;
        if (focalPx.isFinite && focalPx > 0) {
          return FocalEstimationResult(
            focalPx: focalPx,
            origine: FocaleOrigine.exif,
            principalPoint: principalPoint,
          );
        }
      }
    }
  }

  return null;
}

/// Convertit une valeur EXIF (`Ratio` ou `num`) en `double`, ou `null` si
/// le type n'est pas géré / la valeur est invalide. Ne lance jamais.
double? _ratioOrNumToDouble(dynamic value) {
  if (value is num) return value.toDouble();
  try {
    // `Ratio` (exif_reader) : duck-typing volontaire pour ne pas importer
    // le type interne — expose `numerator`/`denominator` (int).
    final num_ = (value as dynamic).numerator as int;
    final den = (value as dynamic).denominator as int;
    if (den == 0) return null;
    return num_ / den;
  } catch (_) {
    return null;
  }
}

/// Résout la focale à utiliser en appliquant l'ordre de priorité imposé :
/// **EXIF > calcul géométrique (points de fuite) > défaut (35mm-équivalent)**.
///
/// [imageBytes] : octets bruts de la photo importée par l'utilisateur (pour
/// tenter la lecture EXIF). `null` si l'image n'a pas (ou plus) ses octets
/// originaux disponibles (ex. image déjà décodée) — dans ce cas on saute
/// directement au calcul géométrique.
/// [ceilL]/[ceilR]/[floorL]/[floorR] : les 4 coins du mur du fond, en
/// pixels, pour le repli géométrique.
Future<FocalEstimationResult> resolveFocal({
  Uint8List? imageBytes,
  required Vector2 ceilL,
  required Vector2 ceilR,
  required Vector2 floorL,
  required Vector2 floorR,
  required double imageWidthPx,
  required double imageHeightPx,
}) async {
  if (imageBytes != null) {
    final fromExif = await readFocalFromExif(
      imageBytes,
      imageWidthPx: imageWidthPx,
      imageHeightPx: imageHeightPx,
    );
    if (fromExif != null) return fromExif;
  }

  return estimateFocalFromBackWallRectangle(
    ceilL: ceilL,
    ceilR: ceilR,
    floorL: floorL,
    floorR: floorR,
    imageWidthPx: imageWidthPx,
    imageHeightPx: imageHeightPx,
  );
}
