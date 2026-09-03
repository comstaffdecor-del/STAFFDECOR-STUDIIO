// P9a — harnais de mesure (permanent, PAS un *_tmp_*) : écart entre la
// calibration détectée automatiquement (`detectRoomEdges`,
// `lib/core/perspective/edge_detect.dart`) et la calibration de vérité
// terrain (`PerspCalib.forDemoScene`, `lib/models/persp_calib.dart`,
// calée à la main — vérité terrain CONVENTIONNELLE, pas une mesure
// indépendante) sur les 4 photos de scènes démo
// (`assets/demo_scenes/<key>.jpg`).
//
// Aucun `expect` qui échoue : ce fichier est un instrument de mesure,
// pas un test de non-régression — il doit rester vert quel que soit le
// résultat mesuré. Voir docs/ETAT.md (section P9a) pour la formule de
// conversion et son origine.
//
// Espace de coordonnées : `detectRoomEdges` retourne un `PerspCalib` en
// `xPct`/`yPct` (fraction 0-1 de l'image source, voir
// `edge_detect.dart` fonction `norm`) — exactement le même espace que
// les presets démo (`persp_calib.dart`, docstring : "en pourcentage,
// xPct/yPct de l'image source"). La conversion px utilisée ci-dessous
// reproduit `CalibCanvasPoints.fromCalib` (`calib_canvas.dart`) dans sa
// branche `imgDraw == null` : `Offset(p.xPct * w, p.yPct * h)` — c'est
// la seule conversion légitime trouvée dans le dépôt pour comparer les
// deux calibrations sur une géométrie canvas commune ; elle n'est pas
// inventée pour ce harnais.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/calib_canvas.dart';
import 'package:staff_decor_studio/core/perspective/edge_detect.dart';
import 'package:staff_decor_studio/core/perspective/persp_geometry.dart'
    as pg;
import 'package:staff_decor_studio/models/persp_calib.dart';
import 'dart:ui' as ui;

const double kCanvasW = 1400.0;
const double kCanvasH = 975.0;

const List<String> kPresetKeys = [
  'haussmann',
  'moderne',
  'provencal',
  'scandinave',
];

Future<ui.Image> _decodeImageFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Reproduction exacte de `CalibCanvasPoints.fromCalib` (branche
/// `imgDraw == null`) : `Offset(p.xPct * w, p.yPct * h)` — voir
/// `lib/core/perspective/calib_canvas.dart:38-46`.
CalibCanvasPoints _toCanvasNoLetterbox(PerspCalib calib) {
  return CalibCanvasPoints.fromCalib(
    calib,
    imgDraw: null,
    w: kCanvasW,
    h: kCanvasH,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('P9a : écart detectRoomEdges vs presets sur les 4 scènes démo', () async {
    for (final key in kPresetKeys) {
      final imgPath = 'assets/demo_scenes/$key.jpg';
      final file = File(imgPath);
      if (!file.existsSync()) {
        // ignore: avoid_print
        print('[p9a] preset=$key image introuvable path=$imgPath');
        continue;
      }

      final image = await _decodeImageFile(imgPath);
      final detected = await detectRoomEdges(image);
      image.dispose();

      if (detected == null) {
        // ignore: avoid_print
        print(
          '[p9a] preset=$key conf=null d_ceilL=null d_ceilR=null '
          'd_floorL=null d_floorR=null d_max=null',
        );
        continue;
      }

      final truth = PerspCalib.forDemoScene(key);
      final detectedCanvas = _toCanvasNoLetterbox(detected.calib);
      final truthCanvas = _toCanvasNoLetterbox(truth);

      final dCeilL = pg.dist(detectedCanvas.ceilL, truthCanvas.ceilL);
      final dCeilR = pg.dist(detectedCanvas.ceilR, truthCanvas.ceilR);
      final dFloorL = pg.dist(detectedCanvas.floorL, truthCanvas.floorL);
      final dFloorR = pg.dist(detectedCanvas.floorR, truthCanvas.floorR);
      final dMax = [dCeilL, dCeilR, dFloorL, dFloorR].reduce(
        (a, b) => a > b ? a : b,
      );

      // ignore: avoid_print
      print(
        '[p9a] preset=$key conf=${detected.confidence.toStringAsFixed(4)} '
        'd_ceilL=${dCeilL.toStringAsFixed(4)} '
        'd_ceilR=${dCeilR.toStringAsFixed(4)} '
        'd_floorL=${dFloorL.toStringAsFixed(4)} '
        'd_floorR=${dFloorR.toStringAsFixed(4)} '
        'd_max=${dMax.toStringAsFixed(4)}',
      );
    }
    // Aucun expect : instrument de mesure, jamais de rouge par
    // construction.
    expect(true, isTrue);
  });
}
