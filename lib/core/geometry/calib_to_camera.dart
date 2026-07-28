/// Pont entre la calibration 2D utilisateur (`PerspCalib`, 8 points en
/// fraction d'image) et les primitives 3D autonomes de `geometry/`
/// (`Camera3D`, `Plane3`) — le module annoncé par la docstring de tête de
/// `camera.dart` ("livraison suivante").
///
/// ⚠️ Ce fichier est **Dart pur** : aucune dépendance UI (`dart:ui`,
/// `package:flutter/...`). Testable en isolation, sans widget. Il importe
/// `models/persp_calib.dart` (seul point d'entrée qui a le droit de faire ce
/// lien — `camera.dart`/`planes.dart`/`sweep.dart` restent volontairement
/// ignorants de `PerspCalib`, voir leur docstring de tête respective).
///
/// ## Ce que ce module NE fait PAS
///
/// [PerspCalib] ne contient **aucune information de profondeur/échelle
/// réelle** — seulement 8 points 2D (fractions d'image) qui délimitent un
/// rectangle "mur du fond" en perspective. Il n'existe donc pas de solution
/// unique pour la position 3D absolue du mur : ce module fait un choix
/// **explicite et documenté** (profondeur conventionnelle
/// [backWallDepthM], voir [buildCalibratedScene]) plutôt que de prétendre à
/// une reconstruction métrique exacte — cohérent avec l'usage actuel (rendu
/// visuel en perspective correcte, pas mesure physique de la pièce).
///
/// ## Méthode
///
/// 1. Les 4 coins du mur du fond ([PerspCalib.ceilL]/[ceilR]/[floorL]/
///    [floorR]), convertis de fractions d'image en pixels, servent à
///    estimer la focale caméra via [estimateFocalFromBackWallRectangle]
///    (méthode Caprile-Torre déjà existante dans `camera.dart` — **jamais
///    recalculée ici**).
/// 2. Une caméra canonique est construite à l'origine du monde, regardant
///    vers `-Z` ([Camera3D.lookingAt]) — un choix de repère arbitraire mais
///    cohérent (l'utilisateur ne fournit aucune position de caméra réelle).
/// 3. Les 4 coins du mur du fond sont **dé-projetés**
///    ([Camera3D.unproject]) à une profondeur conventionnelle
///    [backWallDepthM] — ce qui les place tous les 4 sur un même plan
///    frontal (perpendiculaire à l'axe optique), une approximation
///    raisonnable du "mur du fond" pour une photo dont ce mur est
///    approximativement face à la caméra (cas normal des photos de pièce
///    calibrées via [PerspCalib], voir ses presets `demoPresets`).
/// 4. Le plan plafond est horizontal (`normal = (0,1,0)`), à la hauteur
///    moyenne des deux coins plafond dé-projetés.
/// 5. Le plan mur du fond a pour normale `-camera.forward` (pointe vers la
///    caméra, donc vers l'intérieur de la pièce — cohérent avec la
///    convention `depthAxis` de `sweep.dart`/`CONVENTIONS.md` : x croissant
///    s'éloigne du mur en allant vers l'observateur) et passe par le
///    centroïde des 4 coins dé-projetés.
/// 6. Un point d'ancrage pour un trajet le long du mur du fond (typiquement
///    une corniche filante sous le plafond) est obtenu en projetant les
///    coins plafond dé-projetés sur la droite d'intersection
///    (mur∩plafond, [intersectPlanes]) — garantit par construction que le
///    trajet retourné est EXACTEMENT sur l'arête mur∩plafond (condition
///    requise par `_buildSegmentFrame` dans `sweep.dart`), pas seulement
///    approximativement.
library;

import 'package:vector_math/vector_math_64.dart';

import '../../models/persp_calib.dart';
import 'camera.dart';
import 'planes.dart';

/// Résultat de [buildCalibratedScene] : une scène 3D minimale (caméra +
/// plans mur du fond/plafond + arête mur∩plafond bornée aux coins
/// calibrés) suffisante pour appeler [sweepMoulure]
/// (`geometry/sweep.dart`) et projeter le maillage résultant à l'écran via
/// [camera].
class CalibratedScene {
  /// Caméra 3D dérivée de la calibration (position canonique à l'origine,
  /// regardant vers `-Z`, focale estimée par [estimateFocalFromBackWallRectangle]).
  final Camera3D camera;

  /// Plan du mur du fond, normale pointant vers l'intérieur de la pièce
  /// (vers la caméra) — utilisable directement comme `wallPlanes[i]` de
  /// [sweepMoulure].
  final Plane3 backWallPlane;

  /// Plan du plafond, horizontal — utilisable directement comme
  /// `ceilingPlane` de [sweepMoulure].
  final Plane3 ceilingPlane;

  /// Point 3D monde correspondant au coin `ceilL` de la calibration,
  /// **exactement sur l'arête mur∩plafond** (voir étape 6 de la docstring
  /// de tête de fichier) — extrémité gauche naturelle d'un trajet de
  /// corniche filant le long du mur du fond.
  final Vector3 ceilLOnEdge;

  /// Idem [ceilLOnEdge] pour le coin `ceilR` — extrémité droite naturelle.
  final Vector3 ceilROnEdge;

  /// Les 4 coins du mur du fond, dé-projetés à [backWallDepthM] — exposés
  /// pour debug/tests (transparence), pas nécessaires à un appel simple de
  /// [sweepMoulure] (qui n'a besoin que de [ceilLOnEdge]/[ceilROnEdge]/
  /// [backWallPlane]/[ceilingPlane]).
  final Vector3 ceilL3D;
  final Vector3 ceilR3D;
  final Vector3 floorL3D;
  final Vector3 floorR3D;

  /// Profondeur conventionnelle (mètres) utilisée pour la dé-projection —
  /// voir point 3 de la docstring de tête de fichier. Exposée pour
  /// transparence (ex. dimensionner un trajet de plinthe à la même
  /// profondeur que le mur du fond).
  final double backWallDepthM;

  const CalibratedScene({
    required this.camera,
    required this.backWallPlane,
    required this.ceilingPlane,
    required this.ceilLOnEdge,
    required this.ceilROnEdge,
    required this.ceilL3D,
    required this.ceilR3D,
    required this.floorL3D,
    required this.floorR3D,
    required this.backWallDepthM,
  });
}

/// Convertit un [CalibPoint] (fractions 0..1 d'image) en pixels, connaissant
/// les dimensions réelles de l'image ([imageWidthPx]/[imageHeightPx]).
Vector2 calibPointToPixels(
  CalibPoint p, {
  required double imageWidthPx,
  required double imageHeightPx,
}) {
  return Vector2(p.xPct * imageWidthPx, p.yPct * imageHeightPx);
}

/// Construit une [CalibratedScene] à partir d'une [PerspCalib] et des
/// dimensions de l'image source — voir la docstring de tête de fichier pour
/// la méthode complète.
///
/// [backWallDepthM] : profondeur conventionnelle (mètres) à laquelle les 4
/// coins du mur du fond sont placés dans le monde 3D — choix arbitraire
/// documenté (voir point 1 de la docstring de tête de fichier), sans effet
/// sur le RENDU final (une photo n'a pas d'échelle métrique absolue), mais
/// qui doit rester cohérent si plusieurs familles de produits (corniche +
/// plinthe + moulure) sont dessinées dans la même scène — toutes doivent
/// utiliser la même valeur pour ne pas se retrouver à des échelles
/// visuelles incohérentes entre elles. Défaut 3.0 m, raisonnable pour une
/// pièce standard.
///
/// Lance [ArgumentError] si le mur du fond et le plafond dérivés sont
/// (quasi) parallèles (configuration dégénérée — calibration invalide,
/// ex. les 4 coins du mur du fond seraient colinéaires) — jamais de NaN
/// silencieux, propagé directement depuis [intersectPlanes].
CalibratedScene buildCalibratedScene({
  required PerspCalib calib,
  required double imageWidthPx,
  required double imageHeightPx,
  double backWallDepthM = 3.0,
}) {
  final ceilLPx = calibPointToPixels(
    calib.ceilL,
    imageWidthPx: imageWidthPx,
    imageHeightPx: imageHeightPx,
  );
  final ceilRPx = calibPointToPixels(
    calib.ceilR,
    imageWidthPx: imageWidthPx,
    imageHeightPx: imageHeightPx,
  );
  final floorLPx = calibPointToPixels(
    calib.floorL,
    imageWidthPx: imageWidthPx,
    imageHeightPx: imageHeightPx,
  );
  final floorRPx = calibPointToPixels(
    calib.floorR,
    imageWidthPx: imageWidthPx,
    imageHeightPx: imageHeightPx,
  );

  final focal = estimateFocalFromBackWallRectangle(
    ceilL: ceilLPx,
    ceilR: ceilRPx,
    floorL: floorLPx,
    floorR: floorRPx,
    imageWidthPx: imageWidthPx,
    imageHeightPx: imageHeightPx,
  );

  final camera = Camera3D.lookingAt(
    eye: Vector3(0, 0, 0),
    target: Vector3(0, 0, -1),
    focalPx: focal.focalPx,
    principalPoint: focal.principalPoint,
  );

  final ceilL3D = camera.unproject(ceilLPx, backWallDepthM);
  final ceilR3D = camera.unproject(ceilRPx, backWallDepthM);
  final floorL3D = camera.unproject(floorLPx, backWallDepthM);
  final floorR3D = camera.unproject(floorRPx, backWallDepthM);

  final ceilingY = (ceilL3D.y + ceilR3D.y) / 2.0;
  final ceilingPlane = Plane3.fromPointAndNormal(
    Vector3(0, ceilingY, 0),
    Vector3(0, 1, 0),
  );

  final wallCentroid = (ceilL3D + ceilR3D + floorL3D + floorR3D) / 4.0;
  final wallNormal = -camera.forward;
  final backWallPlane = Plane3.fromPointAndNormal(wallCentroid, wallNormal);

  final edge = intersectPlanes(backWallPlane, ceilingPlane);
  if (edge.isDegenerate) {
    throw ArgumentError(
      'buildCalibratedScene: mur du fond et plafond dérivés sont (quasi) '
      'parallèles (${edge.message}) — calibration invalide (les 4 coins '
      'du mur du fond semblent colinéaires en pixels).',
    );
  }
  final line = edge.line!;

  Vector3 projectOntoLine(Vector3 p) {
    final t = (p - line.point).dot(line.direction);
    return line.point + line.direction * t;
  }

  final ceilLOnEdge = projectOntoLine(ceilL3D);
  final ceilROnEdge = projectOntoLine(ceilR3D);

  return CalibratedScene(
    camera: camera,
    backWallPlane: backWallPlane,
    ceilingPlane: ceilingPlane,
    ceilLOnEdge: ceilLOnEdge,
    ceilROnEdge: ceilROnEdge,
    ceilL3D: ceilL3D,
    ceilR3D: ceilR3D,
    floorL3D: floorL3D,
    floorR3D: floorR3D,
    backWallDepthM: backWallDepthM,
  );
}
