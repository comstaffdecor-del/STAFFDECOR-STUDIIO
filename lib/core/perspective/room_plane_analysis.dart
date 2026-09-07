/// P11 — analyse neutre d'un [RoomPlaneMaskResult] : orchestre
/// l'extraction des deux frontières (plafond/mur, mur/sol) via
/// `plane_boundary_extractor.dart` et produit un score de qualité, des
/// sous-scores, et les raisons pour lesquelles une validation manuelle
/// serait nécessaire.
///
/// Fichier NEUTRE : ce sont exactement les fonctions `analyseLabelMap`
/// et `_fitScore` demandées par le brief P11 ("déplacer hors du fake"),
/// écrites ici dès le départ (il n'existe pas encore de fake dans ce
/// dépôt à cette étape de la construction — ce fichier est créé AVANT
/// `fake_room_plane_segmenter.dart`, justement pour que ce dernier
/// puisse l'importer sans jamais que l'inverse se produise).
///
/// Règle stricte : aucun fichier de `lib/` ne doit importer
/// `fake_room_plane_segmenter.dart`. Ce fichier-ci ne l'importe pas et
/// n'a aucune dépendance vers lui.
library;

import 'plane_boundary_extractor.dart';
import 'room_plane_segmenter.dart';

/// Résultat complet de l'analyse d'un masque de segmentation : les deux
/// frontières extraites (si possible), le score de qualité global, le
/// détail par sous-critère, et l'indication explicite de nécessité
/// d'une validation manuelle.
///
/// Volontairement, AUCUNE clé/champ "confidence" n'existe ici ni dans
/// [debugJson] — ce concept est celui de l'ancien `edge_detect.dart` et
/// est explicitement remplacé par le triplet qualityScore /
/// qualitySubScores / manualRequired(+Reasons).
class RoomPlaneAnalysisResult {
  /// Frontière plafond -> mur, `null` si non calculable (masque
  /// plafond ou mur absent).
  final PlaneBoundaryResult? ceilingWallBoundary;

  /// Frontière mur -> sol, `null` si non calculable (masque mur ou sol
  /// absent).
  final PlaneBoundaryResult? wallFloorBoundary;

  /// Score global dans `[0, 1]`, moyenne des [qualitySubScores]. `0.0`
  /// si aucun sous-score n'a pu être calculé (aucune frontière
  /// disponible).
  final double qualityScore;

  /// Détail du score par sous-critère (ex: `ceilingWallFit`,
  /// `wallFloorFit`, `ceilingWallDensity`, `wallFloorDensity`).
  final Map<String, double> qualitySubScores;

  /// `true` si au moins une des conditions suivantes est vraie : un
  /// masque de classe attendu est manquant, une frontière n'a pas pu
  /// être extraite, ou une frontière a été extraite mais sans coin net
  /// détecté (repli sur `globalLine`, donc pas de position xL/xR
  /// fiable — voir [manualRequiredReasons]).
  final bool manualRequired;

  /// Raisons textuelles machine-lisibles justifiant [manualRequired]
  /// (liste vide si `manualRequired == false`).
  final List<String> manualRequiredReasons;

  /// Représentation debug entièrement dépourvue de la clé
  /// `"confidence"`.
  final Map<String, dynamic> debugJson;

  const RoomPlaneAnalysisResult({
    required this.ceilingWallBoundary,
    required this.wallFloorBoundary,
    required this.qualityScore,
    required this.qualitySubScores,
    required this.manualRequired,
    required this.manualRequiredReasons,
    required this.debugJson,
  });
}

/// Score de qualité d'un fit `(0..1)`, calculé comme un R² classique :
/// `1 - SSE(modele)/SST(moyenne)`, clampé à `[0, 1]` (un modèle pire
/// que la moyenne constante est simplement noté 0, pas négatif — un
/// score de qualité n'a pas de sens en-dessous de 0 ici).
///
/// [yAt] est la fonction de prédiction du modèle testé — typiquement
/// `PlaneBoundaryResult.yAt` (qui utilise les segments left/middle/
/// right si détectés, sinon `globalLine`), appliquée aux [samples]
/// mêmes ayant servi à construire ce modèle (métrique de fit, pas de
/// généralisation — usage volontairement simple, cohérent avec le rôle
/// de sonde de mesure de ce module, pas de prétention de qualité IA).
double _fitScore(
  List<BoundarySample> samples,
  double Function(double xPct) yAt,
) {
  if (samples.length < 2) return 0.0;

  var meanY = 0.0;
  for (final s in samples) {
    meanY += s.yPct;
  }
  meanY /= samples.length;

  var sse = 0.0;
  var sst = 0.0;
  for (final s in samples) {
    final pred = yAt(s.xPct);
    final residual = s.yPct - pred;
    sse += residual * residual;
    final centered = s.yPct - meanY;
    sst += centered * centered;
  }

  if (sst < 1e-9) {
    // Nuage quasi-constant (pas de variance à expliquer) : un fit
    // quasi-parfait (sse quasi-nulle) est noté 1.0, sinon 0.0.
    return sse < 1e-9 ? 1.0 : 0.0;
  }

  final r2 = 1.0 - sse / sst;
  return r2.clamp(0.0, 1.0);
}

/// Analyse un [RoomPlaneMaskResult] complet : vérifie la présence des 3
/// classes attendues (ceiling/wall/floor), extrait les deux frontières
/// via [extractPlaneBoundary], calcule le score de qualité et détecte
/// les cas nécessitant une validation manuelle.
///
/// [cornerSearchMargin]/[minSeg] sont transmis tels quels à
/// [extractPlaneBoundary] pour les deux frontières (mêmes valeurs par
/// défaut que `plane_boundary_extractor.dart`).
RoomPlaneAnalysisResult analyseLabelMap(
  RoomPlaneMaskResult mask, {
  double cornerSearchMargin = kDefaultCornerSearchMargin,
  int minSeg = kDefaultMinSeg,
}) {
  final reasons = <String>[];

  final hasCeiling = mask.hasAny(RoomPlaneClass.ceiling);
  final hasWall = mask.hasAny(RoomPlaneClass.wall);
  final hasFloor = mask.hasAny(RoomPlaneClass.floor);

  if (!hasCeiling) reasons.add('mask_missing_ceiling');
  if (!hasWall) reasons.add('mask_missing_wall');
  if (!hasFloor) reasons.add('mask_missing_floor');

  PlaneBoundaryResult? ceilingWall;
  PlaneBoundaryResult? wallFloor;

  if (hasCeiling && hasWall) {
    ceilingWall = extractPlaneBoundary(
      mask,
      above: RoomPlaneClass.ceiling,
      below: RoomPlaneClass.wall,
      cornerSearchMargin: cornerSearchMargin,
      minSeg: minSeg,
    );
  } else {
    reasons.add('boundary_ceiling_wall_unavailable');
  }

  if (hasWall && hasFloor) {
    wallFloor = extractPlaneBoundary(
      mask,
      above: RoomPlaneClass.wall,
      below: RoomPlaneClass.floor,
      cornerSearchMargin: cornerSearchMargin,
      minSeg: minSeg,
    );
  } else {
    reasons.add('boundary_wall_floor_unavailable');
  }

  // Frontière extraite mais sans coin net détecté : repli sur
  // globalLine, donc pas de position xL/xR fiable (correspond au "si
  // fallback x" du brief P11).
  if (ceilingWall != null && ceilingWall.corners == null) {
    reasons.add('ceiling_wall_fallback_no_corners');
  }
  if (wallFloor != null && wallFloor.corners == null) {
    reasons.add('wall_floor_fallback_no_corners');
  }

  final subScores = <String, double>{};
  if (ceilingWall != null) {
    subScores['ceilingWallFit'] = _fitScore(
      ceilingWall.samples,
      ceilingWall.yAt,
    );
    subScores['ceilingWallDensity'] = mask.width == 0
        ? 0.0
        : (ceilingWall.samples.length / mask.width).clamp(0.0, 1.0);
  }
  if (wallFloor != null) {
    subScores['wallFloorFit'] = _fitScore(wallFloor.samples, wallFloor.yAt);
    subScores['wallFloorDensity'] = mask.width == 0
        ? 0.0
        : (wallFloor.samples.length / mask.width).clamp(0.0, 1.0);
  }

  final qualityScore = subScores.isEmpty
      ? 0.0
      : subScores.values.reduce((a, b) => a + b) / subScores.length;

  final manualRequired = reasons.isNotEmpty;

  final debugJson = <String, dynamic>{
    'hasCeiling': hasCeiling,
    'hasWall': hasWall,
    'hasFloor': hasFloor,
    'qualityScore': qualityScore,
    'qualitySubScores': subScores,
    'manualRequired': manualRequired,
    'manualRequiredReasons': reasons,
    'ceilingWallCorners': ceilingWall?.corners,
    'wallFloorCorners': wallFloor?.corners,
  };

  return RoomPlaneAnalysisResult(
    ceilingWallBoundary: ceilingWall,
    wallFloorBoundary: wallFloor,
    qualityScore: qualityScore,
    qualitySubScores: subScores,
    manualRequired: manualRequired,
    manualRequiredReasons: reasons,
    debugJson: debugJson,
  );
}
