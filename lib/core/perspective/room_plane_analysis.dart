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

  /// P12-quater — marge (xPct) au-delà de laquelle un coin détecté
  /// évalué hors du domaine observé déclenche un rejet
  /// (`*_extrapolated_left`/`*_extrapolated_right`). `null` (défaut) =
  /// domaine purement DIAGNOSTIQUE : aucun rejet sur ce critère, seul
  /// `extrapolationSweep` (dans [debugJson]) est peuplé. Voir brief :
  /// "on lira la table avant de câbler le moindre rejet sur
  /// extrapolation".
  double? extrapolationMarginXPct,
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
    // P12-ter : plafond jamais occulté -> dernier pixel de la classe
    // supérieure (ceiling) est fiable. Mode explicite (voir brief :
    // "la configuration doit exposer ce choix explicitement").
    ceilingWall = extractPlaneBoundary(
      mask,
      above: RoomPlaneClass.ceiling,
      below: RoomPlaneClass.wall,
      cornerSearchMargin: cornerSearchMargin,
      minSeg: minSeg,
      sampleMode: BoundarySampleMode.lastOfUpper,
    );
  } else {
    reasons.add('boundary_ceiling_wall_unavailable');
  }

  if (hasWall && hasFloor) {
    // P12-ter : plinthe quasi-systématiquement occultée par du
    // mobilier (classé unknown) -> le dernier pixel wall mesure le
    // sommet du meuble, pas la plinthe. On prend le premier pixel de
    // la classe inférieure (floor) en remontant depuis le bas de la
    // colonne.
    wallFloor = extractPlaneBoundary(
      mask,
      above: RoomPlaneClass.wall,
      below: RoomPlaneClass.floor,
      cornerSearchMargin: cornerSearchMargin,
      minSeg: minSeg,
      sampleMode: BoundarySampleMode.firstOfLower,
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

  // --- P12-quater : plausibilité (bloquant, sans seuil réglable) ---
  Map<String, BoundaryEval> evalsOf(PlaneBoundaryResult b, double margin) {
    final out = <String, BoundaryEval>{'edgeL': b.evalAt(0.0, margin: margin)};
    final c = b.corners;
    if (c != null) {
      out['cornerL'] = b.evalAt(c[0], margin: margin);
      out['cornerR'] = b.evalAt(c[1], margin: margin);
    }
    out['edgeR'] = b.evalAt(1.0, margin: margin);
    return out;
  }

  final cwEvals = ceilingWall == null ? null : evalsOf(ceilingWall, 0.0);
  final wfEvals = wallFloor == null ? null : evalsOf(wallFloor, 0.0);

  if (cwEvals != null && cwEvals.values.any((e) => e.yOutOfBounds)) {
    reasons.add('ceiling_wall_y_out_of_bounds');
  }
  if (wfEvals != null && wfEvals.values.any((e) => e.yOutOfBounds)) {
    reasons.add('wall_floor_y_out_of_bounds');
  }

  // Croisement / inversion : le sol doit rester STRICTEMENT sous le
  // plafond sur tout le domaine commun observé.
  if (ceilingWall != null && wallFloor != null) {
    final lo = [ceilingWall.minSampleXPct, wallFloor.minSampleXPct]
        .reduce((a, b) => a > b ? a : b);
    final hi = [ceilingWall.maxSampleXPct, wallFloor.maxSampleXPct]
        .reduce((a, b) => a < b ? a : b);
    if (lo.isNaN || hi.isNaN || hi <= lo) {
      reasons.add('boundaries_no_common_domain');
    } else {
      var crossed = false;
      for (var k = 0; k <= 20; k++) {
        final x = lo + (hi - lo) * k / 20.0;
        if (wallFloor.yAt(x) <= ceilingWall.yAt(x)) crossed = true;
      }
      if (crossed) reasons.add('boundaries_crossed');
    }
  }

  // --- P12-quater : domaine / extrapolation (DIAGNOSTIC seul si
  // extrapolationMarginXPct == null) ---
  final sweep = <String, dynamic>{};
  for (final m in kExtrapolationMarginSweep) {
    final flagged = <String>[];
    for (final entry in [
      if (ceilingWall != null) ('ceiling_wall', evalsOf(ceilingWall, m)),
      if (wallFloor != null) ('wall_floor', evalsOf(wallFloor, m)),
    ]) {
      entry.$2.forEach((name, e) {
        if (e.extrapolatedLeft) flagged.add('${entry.$1}.$name.left');
        if (e.extrapolatedRight) flagged.add('${entry.$1}.$name.right');
      });
    }
    sweep[m.toStringAsFixed(2)] = flagged;
  }

  final margin = extrapolationMarginXPct;
  if (margin != null) {
    for (final entry in [
      if (ceilingWall != null) ('ceiling_wall', evalsOf(ceilingWall, margin)),
      if (wallFloor != null) ('wall_floor', evalsOf(wallFloor, margin)),
    ]) {
      for (final name in const ['cornerL', 'cornerR']) {
        final e = entry.$2[name];
        if (e == null) continue;
        if (e.extrapolatedLeft) reasons.add('${entry.$1}_extrapolated_left');
        if (e.extrapolatedRight) reasons.add('${entry.$1}_extrapolated_right');
      }
    }
  }

  // Déduplication : plusieurs points peuvent déclencher la même raison.
  final uniqueReasons = reasons.toSet().toList();

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

  final manualRequired = uniqueReasons.isNotEmpty;

  final debugJson = <String, dynamic>{
    'hasCeiling': hasCeiling,
    'hasWall': hasWall,
    'hasFloor': hasFloor,
    'qualityScore': qualityScore,
    'qualitySubScores': subScores,
    'manualRequired': manualRequired,
    'manualRequiredReasons': uniqueReasons,
    'ceilingWallCorners': ceilingWall?.corners,
    'wallFloorCorners': wallFloor?.corners,
    'ceilingWallSampleDomain': ceilingWall == null
        ? null
        : [ceilingWall.minSampleXPct, ceilingWall.maxSampleXPct],
    'wallFloorSampleDomain': wallFloor == null
        ? null
        : [wallFloor.minSampleXPct, wallFloor.maxSampleXPct],
    'ceilingWallEvals': cwEvals?.map((k, v) => MapEntry(k, v.toJson())),
    'wallFloorEvals': wfEvals?.map((k, v) => MapEntry(k, v.toJson())),
    'extrapolationSweep': sweep,
    'extrapolationMarginXPct': extrapolationMarginXPct,
  };

  return RoomPlaneAnalysisResult(
    ceilingWallBoundary: ceilingWall,
    wallFloorBoundary: wallFloor,
    qualityScore: qualityScore,
    qualitySubScores: subScores,
    manualRequired: manualRequired,
    manualRequiredReasons: uniqueReasons,
    debugJson: debugJson,
  );
}
