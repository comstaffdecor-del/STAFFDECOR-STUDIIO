/// P11 — conversion d'un [RoomPlaneAnalysisResult] (sortie de
/// `room_plane_analysis.dart`) vers un [PerspCalib] (8 points
/// `CalibPoint(xPct:, yPct:)`, format consommé par le moteur de
/// perspective existant, `lib/models/persp_calib.dart` — INCHANGÉ,
/// jamais modifié par P11).
///
/// Règle stricte du brief : jamais d'auto-apply si `manualRequired`.
/// Concrètement, [perspCalibFromDetection] retourne un
/// [PerspCalibDetectionResult] dont le champ [PerspCalibDetectionResult.calib]
/// est `null` dès que `manualRequired` est vrai — impossible pour un
/// appelant d'obtenir accidentellement un [PerspCalib] "détecté" dans ce
/// cas ; il doit alors explicitement se rabattre sur
/// [PerspCalibDetectionResult.fallback] (= [PerspFallbackDefaults.value]
/// = [PerspCalib.defaultCalib]) et/ou solliciter une calibration
/// manuelle.
library;

import '../../models/persp_calib.dart';
import 'room_plane_analysis.dart';

/// Point d'accès unique vers la calibration de repli — lit
/// explicitement [PerspCalib.defaultCalib] (ceilL/ceilR = 0.200/0.150
/// et 0.800/0.150, floorL/floorR = 0.200/0.850 et 0.800/0.850, etc.),
/// AUCUNE valeur inventée ici.
class PerspFallbackDefaults {
  const PerspFallbackDefaults._();

  /// Toujours égal à `PerspCalib.defaultCalib` — pas de duplication de
  /// valeurs, une seule source de vérité (`lib/models/persp_calib.dart`).
  static PerspCalib get value => PerspCalib.defaultCalib;
}

/// Résultat de la tentative de conversion segmentation -> PerspCalib.
class PerspCalibDetectionResult {
  /// `PerspCalib` détecté à partir de la segmentation, ou `null` si
  /// [manualRequired] est vrai (voir règle "jamais d'auto-apply" en
  /// tête de fichier) — un appelant NE DOIT PAS utiliser ce champ sans
  /// avoir vérifié [manualRequired] au préalable.
  final PerspCalib? calib;

  /// `true` si la détection n'est pas jugée suffisamment fiable pour
  /// être appliquée automatiquement (repris de
  /// [RoomPlaneAnalysisResult.manualRequired], éventuellement complété
  /// si une frontière est absente).
  final bool manualRequired;

  /// Raisons machine-lisibles (voir
  /// [RoomPlaneAnalysisResult.manualRequiredReasons]).
  final List<String> manualRequiredReasons;

  /// Calibration de repli à utiliser à la place de [calib] lorsque
  /// [manualRequired] est vrai — toujours [PerspFallbackDefaults.value].
  final PerspCalib fallback;

  const PerspCalibDetectionResult({
    required this.calib,
    required this.manualRequired,
    required this.manualRequiredReasons,
    required this.fallback,
  });
}

/// Convertit [analysis] (résultat de `analyseLabelMap`) en
/// [PerspCalibDetectionResult].
///
/// Construction des 8 points quand les deux frontières ET leurs coins
/// sont disponibles (`manualRequired == false`) :
///   - `ceilL`/`ceilR` : positions des 2 coins de la frontière
///     plafond/mur (`ceilingWallBoundary.corners`), hauteur via
///     `ceilingWallBoundary.yAt(x)`.
///   - `floorL`/`floorR` : positions des 2 coins de la frontière
///     mur/sol (`wallFloorBoundary.corners`), hauteur via
///     `wallFloorBoundary.yAt(x)`.
///   - `wallTL`/`wallTR` : bords gauche/droit (xPct=0/1) de la
///     frontière plafond/mur.
///   - `wallBL`/`wallBR` : bords gauche/droit (xPct=0/1) de la
///     frontière mur/sol.
///
/// Dès que l'une des deux frontières est absente, ou que l'une d'elles
/// n'a pas de coins détectés (repli sur `globalLine` — pas de position
/// xL/xR fiable), [manualRequired] est forcé à `true` et [calib] est
/// `null` (jamais d'auto-apply, voir docstring de tête de fichier).
PerspCalibDetectionResult perspCalibFromDetection(
  RoomPlaneAnalysisResult analysis,
) {
  final reasons = <String>[...analysis.manualRequiredReasons];

  final ceilingWall = analysis.ceilingWallBoundary;
  final wallFloor = analysis.wallFloorBoundary;

  final ceilingWallHasCorners = ceilingWall?.corners != null;
  final wallFloorHasCorners = wallFloor?.corners != null;

  final canAutoApply =
      !analysis.manualRequired &&
      ceilingWall != null &&
      wallFloor != null &&
      ceilingWallHasCorners &&
      wallFloorHasCorners;

  if (!canAutoApply) {
    if (ceilingWall == null &&
        !reasons.contains('boundary_ceiling_wall_unavailable')) {
      reasons.add('boundary_ceiling_wall_unavailable');
    }
    if (wallFloor == null &&
        !reasons.contains('boundary_wall_floor_unavailable')) {
      reasons.add('boundary_wall_floor_unavailable');
    }
    if (ceilingWall != null &&
        !ceilingWallHasCorners &&
        !reasons.contains('ceiling_wall_fallback_no_corners')) {
      reasons.add('ceiling_wall_fallback_no_corners');
    }
    if (wallFloor != null &&
        !wallFloorHasCorners &&
        !reasons.contains('wall_floor_fallback_no_corners')) {
      reasons.add('wall_floor_fallback_no_corners');
    }
    return PerspCalibDetectionResult(
      calib: null,
      manualRequired: true,
      manualRequiredReasons: reasons,
      fallback: PerspFallbackDefaults.value,
    );
  }

  final cwCorners = ceilingWall.corners!;
  final wfCorners = wallFloor.corners!;

  final ceilL = CalibPoint(
    xPct: cwCorners[0],
    yPct: ceilingWall.yAt(cwCorners[0]),
  );
  final ceilR = CalibPoint(
    xPct: cwCorners[1],
    yPct: ceilingWall.yAt(cwCorners[1]),
  );
  final floorL = CalibPoint(
    xPct: wfCorners[0],
    yPct: wallFloor.yAt(wfCorners[0]),
  );
  final floorR = CalibPoint(
    xPct: wfCorners[1],
    yPct: wallFloor.yAt(wfCorners[1]),
  );

  final wallTL = CalibPoint(xPct: 0.0, yPct: ceilingWall.yAt(0.0));
  final wallTR = CalibPoint(xPct: 1.0, yPct: ceilingWall.yAt(1.0));
  final wallBL = CalibPoint(xPct: 0.0, yPct: wallFloor.yAt(0.0));
  final wallBR = CalibPoint(xPct: 1.0, yPct: wallFloor.yAt(1.0));

  final calib = PerspCalib(
    ceilL: ceilL,
    ceilR: ceilR,
    floorL: floorL,
    floorR: floorR,
    wallTL: wallTL,
    wallTR: wallTR,
    wallBL: wallBL,
    wallBR: wallBR,
  );

  return PerspCalibDetectionResult(
    calib: calib,
    manualRequired: false,
    manualRequiredReasons: const [],
    fallback: PerspFallbackDefaults.value,
  );
}
