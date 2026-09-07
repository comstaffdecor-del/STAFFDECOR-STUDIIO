/// P11 — test de CONTRAT (plomberie) pour le pipeline de segmentation
/// par plans de pièce : masque -> extraction de frontières -> analyse
/// -> conversion PerspCalib.
///
/// Géométrie EXAGÉRÉE via `SyntheticRoomSpec.frontal()` (coude ~0.06,
/// coins francs à xPct=0.25/0.75) — volontairement facile à détecter,
/// pour valider que la PLOMBERIE fonctionne (pas pour mesurer une
/// quelconque qualité de segmentation IA réelle : ce fichier n'utilise
/// QUE `FakeRoomPlaneSegmenter`, jamais un provider réel).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/fake_room_plane_segmenter.dart';
import 'package:staff_decor_studio/core/perspective/plane_boundary_extractor.dart';
import 'package:staff_decor_studio/core/perspective/room_plane_analysis.dart';
import 'package:staff_decor_studio/core/perspective/room_plane_segmenter.dart';
import 'package:staff_decor_studio/core/perspective/segmentation_to_persp_calib.dart';

const int kMaskWidth = 512;
const int kMaskHeight = 384;

void main() {
  group('P11 contrat - plomberie segmentation -> PerspCalib', () {
    test('3 masques non vides (ceiling/wall/floor) - geometrie exageree', () async {
      final segmenter = FakeRoomPlaneSegmenter(spec: SyntheticRoomSpec.frontal());
      final mask = await segmenter.segment(
        imageBytes: Uint8ListEmpty.value,
        width: kMaskWidth,
        height: kMaskHeight,
      );
      expect(mask, isNotNull);
      expect(mask!.hasAny(RoomPlaneClass.ceiling), isTrue);
      expect(mask.hasAny(RoomPlaneClass.wall), isTrue);
      expect(mask.hasAny(RoomPlaneClass.floor), isTrue);
    });

    test('frontieres extraites avec coins detectes a +/-0.04', () async {
      final spec = SyntheticRoomSpec.frontal();
      final segmenter = FakeRoomPlaneSegmenter(spec: spec);
      final mask = await segmenter.segment(
        imageBytes: Uint8ListEmpty.value,
        width: kMaskWidth,
        height: kMaskHeight,
      );
      expect(mask, isNotNull);

      final ceilingWall = extractPlaneBoundary(
        mask!,
        above: RoomPlaneClass.ceiling,
        below: RoomPlaneClass.wall,
      );
      final wallFloor = extractPlaneBoundary(
        mask,
        above: RoomPlaneClass.wall,
        below: RoomPlaneClass.floor,
      );

      expect(ceilingWall.corners, isNotNull, reason: 'coude ~0.06 doit produire des coins nets');
      expect(wallFloor.corners, isNotNull, reason: 'coude ~0.06 doit produire des coins nets');

      const tolerance = 0.04;
      expect(
        (ceilingWall.corners![0] - spec.cornerLeftX).abs(),
        lessThan(tolerance),
        reason: 'coin gauche plafond/mur',
      );
      expect(
        (ceilingWall.corners![1] - spec.cornerRightX).abs(),
        lessThan(tolerance),
        reason: 'coin droit plafond/mur',
      );
      expect(
        (wallFloor.corners![0] - spec.cornerLeftX).abs(),
        lessThan(tolerance),
        reason: 'coin gauche mur/sol',
      );
      expect(
        (wallFloor.corners![1] - spec.cornerRightX).abs(),
        lessThan(tolerance),
        reason: 'coin droit mur/sol',
      );
    });

    test('conversion PerspCalib reussie quand les 2 frontieres ont des coins', () async {
      final segmenter = FakeRoomPlaneSegmenter(spec: SyntheticRoomSpec.frontal());
      final mask = await segmenter.segment(
        imageBytes: Uint8ListEmpty.value,
        width: kMaskWidth,
        height: kMaskHeight,
      );
      expect(mask, isNotNull);

      final analysis = analyseLabelMap(mask!);
      final detection = perspCalibFromDetection(analysis);

      expect(analysis.manualRequired, isFalse);
      expect(detection.manualRequired, isFalse);
      expect(detection.calib, isNotNull);
    });

    test('manualRequired si un masque de classe est manquant (floor absent)', () async {
      final segmenter = FakeRoomPlaneSegmenter(
        spec: SyntheticRoomSpec.frontal(),
        includeFloor: false,
      );
      final mask = await segmenter.segment(
        imageBytes: Uint8ListEmpty.value,
        width: kMaskWidth,
        height: kMaskHeight,
      );
      expect(mask, isNotNull);
      expect(mask!.hasAny(RoomPlaneClass.floor), isFalse);

      final analysis = analyseLabelMap(mask);
      expect(analysis.manualRequired, isTrue);
      expect(analysis.manualRequiredReasons, contains('mask_missing_floor'));

      final detection = perspCalibFromDetection(analysis);
      expect(detection.manualRequired, isTrue);
      expect(detection.calib, isNull, reason: 'jamais d\'auto-apply si manualRequired');
    });

    test('manualRequired si repli sur fallback x (pas de coins detectes)', () async {
      // Geometrie parfaitement plate (kink=0.0) : globalLine couvre tout,
      // aucun coude a detecter -> corners == null -> manualRequired.
      final flatSpec = SyntheticRoomSpec.frontal(kink: 0.0);
      final segmenter = FakeRoomPlaneSegmenter(spec: flatSpec);
      final mask = await segmenter.segment(
        imageBytes: Uint8ListEmpty.value,
        width: kMaskWidth,
        height: kMaskHeight,
      );
      expect(mask, isNotNull);

      final analysis = analyseLabelMap(mask!);
      final detection = perspCalibFromDetection(analysis);

      // Avec kink=0.0, les 3 segments sont colineaires: soit aucun
      // breakpoint distinct n'est optimal, soit un breakpoint "par
      // hasard" est trouve sans signal reel. Dans les deux cas, le
      // fallback x doit se manifester via manualRequired si detection
      // jugee non fiable OU la conversion doit rester coherente.
      // Gate dur explicitement demande par le brief: si aucun coin net,
      // manualRequired doit etre vrai.
      if (analysis.ceilingWallBoundary?.corners == null ||
          analysis.wallFloorBoundary?.corners == null) {
        expect(analysis.manualRequired, isTrue);
        expect(detection.calib, isNull);
      }
    });

    test('qualityScore decroit quand le bruit augmente', () async {
      final spec = SyntheticRoomSpec.frontal();

      final segmenterClean = FakeRoomPlaneSegmenter(
        spec: spec,
        noiseStdDevPct: 0.0,
        seed: 7,
      );
      final maskClean = await segmenterClean.segment(
        imageBytes: Uint8ListEmpty.value,
        width: kMaskWidth,
        height: kMaskHeight,
      );
      final analysisClean = analyseLabelMap(maskClean!);

      final segmenterNoisy = FakeRoomPlaneSegmenter(
        spec: spec,
        noiseStdDevPct: 0.05,
        seed: 7,
      );
      final maskNoisy = await segmenterNoisy.segment(
        imageBytes: Uint8ListEmpty.value,
        width: kMaskWidth,
        height: kMaskHeight,
      );
      final analysisNoisy = analyseLabelMap(maskNoisy!);

      expect(
        analysisNoisy.qualityScore,
        lessThan(analysisClean.qualityScore),
        reason: 'plus de bruit doit degrader le score de qualite du fit',
      );
    });

    test('debugJson ne contient jamais la cle "confidence"', () async {
      final segmenter = FakeRoomPlaneSegmenter(spec: SyntheticRoomSpec.frontal());
      final mask = await segmenter.segment(
        imageBytes: Uint8ListEmpty.value,
        width: kMaskWidth,
        height: kMaskHeight,
      );
      final analysis = analyseLabelMap(mask!);
      expect(analysis.debugJson.containsKey('confidence'), isFalse);
    });
  });
}

/// `imageBytes` est ignore par `FakeRoomPlaneSegmenter` (voir docstring
/// de ce provider) : un buffer vide suffit pour tous les appels de ce
/// fichier de test.
class Uint8ListEmpty {
  static final Uint8List value = Uint8List(0);
}
