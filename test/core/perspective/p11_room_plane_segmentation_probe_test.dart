/// P11 — SONDE (mesure, pas preuve de qualite IA) : geometrie REELLE
/// des 4 scenes demo (`PerspCalib.demoPresets`), via
/// `SyntheticRoomSpec.fromPreset(PerspCalib.forDemoScene(name))`.
///
/// ============================================================
/// AVERTISSEMENT EXPLICITE : provider FAKE (`FakeRoomPlaneSegmenter`).
/// Ce test valide la PLOMBERIE du pipeline (masque -> extraction de
/// frontieres -> erreurs signees), PAS la qualite d'une segmentation
/// IA reelle (aucun modele, aucune image reelle n'est utilise ici).
/// ============================================================
///
/// Masque genere a 512x384 (resolution de travail du pipeline).
/// `sceneSizes` ci-dessous sert UNIQUEMENT a documenter les dimensions
/// des photos sources reelles dans les fichiers de sortie — n'affecte
/// PAS la resolution du masque synthetique (toujours 512x384).
///
/// Portes dures : UNIQUEMENT sur ceilL/ceilR/floorL/floorR (erreur
/// signee de hauteur yPct a l'abscisse xPct CONNUE du vrai coin du
/// preset, |err| < 0.02).
/// AUCUNE porte sur xL/xR (erreur de position x du coin DETECTE) : le
/// coude reel des presets ne fait que ~0.010 d'amplitude en yPct sur
/// ~10% de largeur — sa detectabilite par l'algorithme de
/// `plane_boundary_extractor.dart` est precisement l'inconnue mesuree
/// ici, pas une garantie. Si non detecte -> manualRequired, jamais un
/// echec de test.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/fake_room_plane_segmenter.dart';
import 'package:staff_decor_studio/core/perspective/room_plane_analysis.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

const int kMaskWidth = 512;
const int kMaskHeight = 384;
const double kHardGateThreshold = 0.02;

/// Dimensions des photos sources reelles (`assets/demo_scenes/*.jpg`) —
/// UNIQUEMENT pour documentation dans la sortie JSON/texte, jamais
/// utilisees pour generer le masque synthetique (toujours 512x384, voir
/// docstring de tete de fichier).
const Map<String, List<int>> sceneSizes = {
  'haussmann': [2560, 1783],
  'moderne': [1960, 1470],
  'provencal': [2560, 1707],
  'scandinave': [1920, 1088],
};

const List<String> kScenes = ['haussmann', 'moderne', 'provencal', 'scandinave'];

class SceneProbeResult {
  final String scene;
  final double? ceilL;
  final double? ceilR;
  final double? floorL;
  final double? floorR;
  final double? xL;
  final double? xR;
  final double qualityScore;
  final Map<String, double> qualitySubScores;
  final bool manualRequired;
  final List<String> manualRequiredReasons;

  const SceneProbeResult({
    required this.scene,
    required this.ceilL,
    required this.ceilR,
    required this.floorL,
    required this.floorR,
    required this.xL,
    required this.xR,
    required this.qualityScore,
    required this.qualitySubScores,
    required this.manualRequired,
    required this.manualRequiredReasons,
  });

  Map<String, dynamic> toJson() => {
    'provider': 'FAKE',
    'scene': scene,
    'sourceImageSize': {
      'width': sceneSizes[scene]![0],
      'height': sceneSizes[scene]![1],
    },
    'maskSize': {'width': kMaskWidth, 'height': kMaskHeight},
    'errors': {'ceilL': ceilL, 'ceilR': ceilR, 'floorL': floorL, 'floorR': floorR, 'xL': xL, 'xR': xR},
    'qualityScore': qualityScore,
    'qualitySubScores': qualitySubScores,
    'manualRequired': manualRequired,
    'manualRequiredReasons': manualRequiredReasons,
  };
}

/// Exécute la sonde pour une [scene] donnée : génère le masque
/// synthétique via [FakeRoomPlaneSegmenter] + `SyntheticRoomSpec.fromPreset`,
/// extrait les 2 frontières via `analyseLabelMap`, puis calcule les 6
/// erreurs signées par comparaison directe aux 8 points du VRAI preset
/// (`PerspCalib.forDemoScene(scene)`).
Future<SceneProbeResult> _runProbe(String scene) async {
  final truth = PerspCalib.forDemoScene(scene);
  final spec = SyntheticRoomSpec.fromPreset(truth);

  final segmenter = FakeRoomPlaneSegmenter(spec: spec);
  final mask = await segmenter.segment(
    imageBytes: Uint8List(0),
    width: kMaskWidth,
    height: kMaskHeight,
  );
  expect(mask, isNotNull, reason: 'scene $scene: masque doit toujours etre genere par le fake');

  final analysis = analyseLabelMap(mask!);

  final ceilingWall = analysis.ceilingWallBoundary;
  final wallFloor = analysis.wallFloorBoundary;

  // ceilL/ceilR/floorL/floorR : erreur signee de hauteur (yAt) a
  // l'abscisse CONNUE (verite terrain) du coin correspondant — yAt est
  // toujours defini (segments si corners detectes, sinon globalLine),
  // donc ces 4 erreurs sont mesurables independamment du succes de la
  // detection de coin (c'est precisement pourquoi elles portent les
  // portes dures, contrairement a xL/xR).
  final ceilL = ceilingWall != null
      ? ceilingWall.yAt(truth.ceilL.xPct) - truth.ceilL.yPct
      : null;
  final ceilR = ceilingWall != null
      ? ceilingWall.yAt(truth.ceilR.xPct) - truth.ceilR.yPct
      : null;
  final floorL = wallFloor != null
      ? wallFloor.yAt(truth.floorL.xPct) - truth.floorL.yPct
      : null;
  final floorR = wallFloor != null
      ? wallFloor.yAt(truth.floorR.xPct) - truth.floorR.yPct
      : null;

  // xL/xR : erreur signee de POSITION du coin DETECTE (corners[0]/[1])
  // vs la position x connue du vrai coin. null si aucun coin n'a ete
  // detecte sur AUCUNE des 2 frontieres (repli global sans coude net)
  // -> mesure non disponible, jamais un echec (voir docstring).
  final detectedCorners = ceilingWall?.corners ?? wallFloor?.corners;
  final xL = detectedCorners != null ? detectedCorners[0] - truth.ceilL.xPct : null;
  final xR = detectedCorners != null ? detectedCorners[1] - truth.ceilR.xPct : null;

  final reasons = [...analysis.manualRequiredReasons];
  if (detectedCorners == null && !reasons.contains('corner_position_undetected')) {
    reasons.add('corner_position_undetected');
  }

  return SceneProbeResult(
    scene: scene,
    ceilL: ceilL,
    ceilR: ceilR,
    floorL: floorL,
    floorR: floorR,
    xL: xL,
    xR: xR,
    qualityScore: analysis.qualityScore,
    qualitySubScores: analysis.qualitySubScores,
    manualRequired: analysis.manualRequired || detectedCorners == null,
    manualRequiredReasons: reasons,
  );
}

String _fmtErr(double? v) => v == null ? 'N/A (manualRequired)' : v.toStringAsFixed(4);

void main() {
  group('P11 sonde - geometrie reelle des 4 scenes demo (provider FAKE)', () {
    final results = <String, SceneProbeResult>{};

    for (final scene in kScenes) {
      test('scene $scene: erreurs signees ceilL/ceilR/floorL/floorR < 0.02 (xL/xR non gates)', () async {
        final result = await _runProbe(scene);
        results[scene] = result;

        // Ecriture immediate du JSON par scene (pas d'attente de fin de
        // groupe - chaque test est independant).
        final jsonFile = File('/tmp/p11_segmentation_$scene.json');
        jsonFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(result.toJson()),
        );

        // Portes dures : UNIQUEMENT ceilL/ceilR/floorL/floorR.
        expect(result.ceilL, isNotNull, reason: 'scene $scene: frontiere plafond/mur doit etre extractible');
        expect(result.ceilR, isNotNull, reason: 'scene $scene: frontiere plafond/mur doit etre extractible');
        expect(result.floorL, isNotNull, reason: 'scene $scene: frontiere mur/sol doit etre extractible');
        expect(result.floorR, isNotNull, reason: 'scene $scene: frontiere mur/sol doit etre extractible');

        expect(result.ceilL!.abs(), lessThan(kHardGateThreshold), reason: 'scene $scene: ceilL');
        expect(result.ceilR!.abs(), lessThan(kHardGateThreshold), reason: 'scene $scene: ceilR');
        expect(result.floorL!.abs(), lessThan(kHardGateThreshold), reason: 'scene $scene: floorL');
        expect(result.floorR!.abs(), lessThan(kHardGateThreshold), reason: 'scene $scene: floorR');

        // AUCUNE porte sur xL/xR (voir docstring) : simplement journalise.
        // ignore: avoid_print
        print(
          'scene $scene: xL=${_fmtErr(result.xL)} xR=${_fmtErr(result.xR)} '
          '(informatif, pas de gate) manualRequired=${result.manualRequired}',
        );
      });
    }

    tearDownAll(() {
      final buffer = StringBuffer();
      buffer.writeln('provider FAKE, valide la plomberie, PAS la qualite IA');
      buffer.writeln('=' * 70);
      buffer.writeln(
        'Geometrie synthetique derivee des VRAIS 8 points PerspCalib.demoPresets '
        '(SyntheticRoomSpec.fromPreset), masque 512x384. '
        'Portes dures uniquement sur ceilL/ceilR/floorL/floorR (|err| < 0.02). '
        'xL/xR = mesure informative (detectabilite du coude reel, ~0.010 '
        "d'amplitude sur ~10% de largeur), AUCUNE porte, manualRequired accepte.",
      );
      buffer.writeln('');
      for (final scene in kScenes) {
        final r = results[scene];
        if (r == null) {
          buffer.writeln('scene $scene: (test non execute)');
          continue;
        }
        buffer.writeln('--- scene: $scene ---');
        buffer.writeln('  sourceImageSize: ${sceneSizes[scene]![0]}x${sceneSizes[scene]![1]} (documentation seule, masque toujours 512x384)');
        buffer.writeln('  ceilL  = ${_fmtErr(r.ceilL)}   (gate dur < ${kHardGateThreshold.toStringAsFixed(2)})');
        buffer.writeln('  ceilR  = ${_fmtErr(r.ceilR)}   (gate dur < ${kHardGateThreshold.toStringAsFixed(2)})');
        buffer.writeln('  floorL = ${_fmtErr(r.floorL)}   (gate dur < ${kHardGateThreshold.toStringAsFixed(2)})');
        buffer.writeln('  floorR = ${_fmtErr(r.floorR)}   (gate dur < ${kHardGateThreshold.toStringAsFixed(2)})');
        buffer.writeln('  xL     = ${_fmtErr(r.xL)}   (AUCUNE gate - informatif)');
        buffer.writeln('  xR     = ${_fmtErr(r.xR)}   (AUCUNE gate - informatif)');
        buffer.writeln('  qualityScore = ${r.qualityScore.toStringAsFixed(4)}');
        buffer.writeln('  qualitySubScores = ${r.qualitySubScores}');
        buffer.writeln('  manualRequired = ${r.manualRequired}');
        buffer.writeln('  manualRequiredReasons = ${r.manualRequiredReasons}');
        buffer.writeln('');
      }
      File('/tmp/p11_segmentation.txt').writeAsStringSync(buffer.toString());
    });
  });
}
