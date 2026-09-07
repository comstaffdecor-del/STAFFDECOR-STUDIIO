/// P11 — provider `RoomPlaneSegmenter` déterministe basé sur une
/// géométrie SYNTHÉTIQUE ([SyntheticRoomSpec]), utilisé exclusivement
/// par les tests (contrat A et sonde B) — jamais dans le pipeline de
/// production.
///
/// ⚠️ Ce fichier ne contient AUCUN concept `sideRise` (absent dès la
/// première version de ce fichier neuf de ce dépôt — rien à supprimer,
/// juste à ne jamais introduire).
///
/// ⚠️ AVERTISSEMENT EXPLICITE (répété dans les tests qui l'utilisent) :
/// ce provider ne mesure JAMAIS la qualité d'une IA de segmentation
/// réelle. Il valide uniquement la PLOMBERIE (masque -> RLE ->
/// extraction de frontières -> PerspCalib), avec une géométrie connue
/// à l'avance.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/persp_calib.dart';
import 'room_plane_analysis.dart';
import 'room_plane_segmenter.dart';

double _lerp(double x0, double y0, double x1, double y1, double x) {
  if ((x1 - x0).abs() < 1e-12) return y0;
  final t = (x - x0) / (x1 - x0);
  return y0 + t * (y1 - y0);
}

/// Géométrie synthétique à 3 segments (mur latéral gauche / mur du
/// fond / mur latéral droit) pour les DEUX frontières (plafond/mur et
/// mur/sol), exprimée en fractions `xPct`/`yPct` — même format que
/// [PerspCalib].
///
/// Les 2 coins (`cornerLeftX`/`cornerRightX`) sont PARTAGÉS entre les
/// deux frontières (cohérent avec les presets réels, où
/// `ceilL.xPct == floorL.xPct` et `ceilR.xPct == floorR.xPct` dans les
/// 4 scènes démo de `PerspCalib.demoPresets`).
class SyntheticRoomSpec {
  final double ceilYLeft;
  final double ceilYRight;
  final double ceilYAtCornerLeft;
  final double ceilYAtCornerRight;
  final double floorYLeft;
  final double floorYRight;
  final double floorYAtCornerLeft;
  final double floorYAtCornerRight;
  final double cornerLeftX;
  final double cornerRightX;

  const SyntheticRoomSpec({
    required this.ceilYLeft,
    required this.ceilYRight,
    required this.ceilYAtCornerLeft,
    required this.ceilYAtCornerRight,
    required this.floorYLeft,
    required this.floorYRight,
    required this.floorYAtCornerLeft,
    required this.floorYAtCornerRight,
    required this.cornerLeftX,
    required this.cornerRightX,
  });

  /// Dérive la géométrie synthétique directement des 8 points d'un
  /// [PerspCalib] RÉEL (preset démo via `PerspCalib.forDemoScene`, ou
  /// [PerspCalib.defaultCalib]) — AUCUNE valeur inventée ici, une
  /// simple reprojection champ à champ :
  ///   `ceilYLeft = wallTL.yPct`, `ceilYRight = wallTR.yPct`,
  ///   `ceilYAtCornerLeft = ceilL.yPct`, `ceilYAtCornerRight = ceilR.yPct`,
  ///   `floorYLeft = wallBL.yPct`, `floorYRight = wallBR.yPct`,
  ///   `floorYAtCornerLeft = floorL.yPct`, `floorYAtCornerRight = floorR.yPct`,
  ///   `cornerLeftX = ceilL.xPct`, `cornerRightX = ceilR.xPct`.
  ///
  /// C'est cette factory (pas [frontal]) qui produit la géométrie
  /// RÉELLE (coude d'amplitude ~0.010 sur 10% de largeur pour les
  /// presets démo) utilisée par le test de sonde B — sa détectabilité
  /// par l'algorithme de `plane_boundary_extractor.dart` est
  /// précisément l'inconnue mesurée par ce test, pas une garantie.
  factory SyntheticRoomSpec.fromPreset(PerspCalib calib) => SyntheticRoomSpec(
    ceilYLeft: calib.wallTL.yPct,
    ceilYRight: calib.wallTR.yPct,
    ceilYAtCornerLeft: calib.ceilL.yPct,
    ceilYAtCornerRight: calib.ceilR.yPct,
    floorYLeft: calib.wallBL.yPct,
    floorYRight: calib.wallBR.yPct,
    floorYAtCornerLeft: calib.floorL.yPct,
    floorYAtCornerRight: calib.floorR.yPct,
    cornerLeftX: calib.ceilL.xPct,
    cornerRightX: calib.ceilR.xPct,
  );

  /// Géométrie EXAGÉRÉE (coude ~0.06 en yPct sur chaque frontière),
  /// coins francs à `xPct = 0.25`/`0.75` — réservée aux TESTS UNITAIRES
  /// (test de contrat A) : sert à vérifier que la plomberie fonctionne
  /// quand le signal géométrique est net, PAS à mesurer la
  /// détectabilité de la géométrie réelle (voir [fromPreset] pour
  /// cela, seule factory utilisée par le test de sonde B).
  factory SyntheticRoomSpec.frontal({double kink = 0.06}) {
    const ceilBase = 0.15;
    const floorBase = 0.85;
    return SyntheticRoomSpec(
      ceilYLeft: ceilBase,
      ceilYRight: ceilBase,
      ceilYAtCornerLeft: ceilBase - kink,
      ceilYAtCornerRight: ceilBase - kink,
      floorYLeft: floorBase,
      floorYRight: floorBase,
      floorYAtCornerLeft: floorBase + kink,
      floorYAtCornerRight: floorBase + kink,
      cornerLeftX: 0.25,
      cornerRightX: 0.75,
    );
  }

  /// Hauteur (yPct) de la frontière plafond/mur à l'abscisse [xPct],
  /// interpolée linéairement par segment (gauche/milieu/droite).
  double ceilYAt(double xPct) {
    if (xPct <= cornerLeftX) {
      return _lerp(0.0, ceilYLeft, cornerLeftX, ceilYAtCornerLeft, xPct);
    }
    if (xPct >= cornerRightX) {
      return _lerp(cornerRightX, ceilYAtCornerRight, 1.0, ceilYRight, xPct);
    }
    return _lerp(
      cornerLeftX,
      ceilYAtCornerLeft,
      cornerRightX,
      ceilYAtCornerRight,
      xPct,
    );
  }

  /// Hauteur (yPct) de la frontière mur/sol à l'abscisse [xPct],
  /// interpolée linéairement par segment (gauche/milieu/droite).
  double floorYAt(double xPct) {
    if (xPct <= cornerLeftX) {
      return _lerp(0.0, floorYLeft, cornerLeftX, floorYAtCornerLeft, xPct);
    }
    if (xPct >= cornerRightX) {
      return _lerp(cornerRightX, floorYAtCornerRight, 1.0, floorYRight, xPct);
    }
    return _lerp(
      cornerLeftX,
      floorYAtCornerLeft,
      cornerRightX,
      floorYAtCornerRight,
      xPct,
    );
  }
}

/// Provider `RoomPlaneSegmenter` déterministe : ignore entièrement
/// [imageBytes] (aucune analyse d'image réelle — c'est un FAKE) et
/// génère un masque directement à partir de [spec], à la résolution
/// [width]x[height] demandée.
///
/// [includeCeiling]/[includeWall]/[includeFloor] : permet de simuler un
/// masque avec une classe manquante (test de contrat A :
/// `manualRequired` si masque manquant).
///
/// [noiseStdDevPct] : bruit gaussien (écart-type en fraction yPct)
/// ajouté indépendamment à chaque colonne pour chacune des deux
/// frontières — sert à vérifier que `qualityScore` décroît quand le
/// bruit augmente (test de contrat A). `0.0` = géométrie exacte, sans
/// bruit.
class FakeRoomPlaneSegmenter implements RoomPlaneSegmenter {
  final SyntheticRoomSpec spec;
  final bool includeCeiling;
  final bool includeWall;
  final bool includeFloor;
  final double noiseStdDevPct;
  final int seed;

  FakeRoomPlaneSegmenter({
    required this.spec,
    this.includeCeiling = true,
    this.includeWall = true,
    this.includeFloor = true,
    this.noiseStdDevPct = 0.0,
    this.seed = 0,
  });

  @override
  Future<RoomPlaneMaskResult?> segment({
    required Uint8List imageBytes,
    required int width,
    required int height,
  }) async {
    final rng = math.Random(seed);
    final flat = Uint8List(width * height);

    for (var x = 0; x < width; x++) {
      final xPct = (x + 0.5) / width;
      var ceilY = spec.ceilYAt(xPct);
      var floorY = spec.floorYAt(xPct);

      if (noiseStdDevPct > 0) {
        ceilY += _gaussian(rng) * noiseStdDevPct;
        floorY += _gaussian(rng) * noiseStdDevPct;
      }
      ceilY = ceilY.clamp(0.0, 1.0);
      floorY = floorY.clamp(0.0, 1.0);
      if (floorY < ceilY) {
        final tmp = floorY;
        floorY = ceilY;
        ceilY = tmp;
      }

      final ceilRow = (ceilY * height).round().clamp(0, height);
      final floorRow = (floorY * height).round().clamp(0, height);

      for (var y = 0; y < height; y++) {
        RoomPlaneClass cls;
        if (y < ceilRow) {
          cls = includeCeiling
              ? RoomPlaneClass.ceiling
              : RoomPlaneClass.unknown;
        } else if (y < floorRow) {
          cls = includeWall ? RoomPlaneClass.wall : RoomPlaneClass.unknown;
        } else {
          cls = includeFloor ? RoomPlaneClass.floor : RoomPlaneClass.unknown;
        }
        flat[y * width + x] = cls.index;
      }
    }

    return RoomPlaneMaskResult(
      width: width,
      height: height,
      rle: _encodeRle(flat),
      providerName: 'fake',
    );
  }

  /// Bruit gaussien standard (Box-Muller) — utilisé uniquement pour
  /// simuler l'imprécision d'un vrai masque de segmentation IA, jamais
  /// pour produire une valeur "de qualité IA" (voir avertissement de
  /// tête de fichier).
  double _gaussian(math.Random rng) {
    final u1 = rng.nextDouble().clamp(1e-9, 1.0);
    final u2 = rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  List<List<int>> _encodeRle(Uint8List flat) {
    final rle = <List<int>>[];
    if (flat.isEmpty) return rle;
    var curClass = flat[0];
    var runLen = 1;
    for (var i = 1; i < flat.length; i++) {
      if (flat[i] == curClass) {
        runLen++;
      } else {
        rle.add([curClass, runLen]);
        curClass = flat[i];
        runLen = 1;
      }
    }
    rle.add([curClass, runLen]);
    return rle;
  }

  /// Aide de debug/vérification réservée aux tests — analyse un masque
  /// produit par ce provider via `analyseLabelMap` (justifie l'import
  /// de `room_plane_analysis.dart` dans ce fichier : le fake s'appuie
  /// sur le module neutre pour son auto-vérification, jamais
  /// l'inverse).
  static RoomPlaneAnalysisResult debugSelfAnalysis(RoomPlaneMaskResult mask) {
    return analyseLabelMap(mask);
  }
}
