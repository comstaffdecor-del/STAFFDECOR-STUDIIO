// Script de diagnostic TEMPORAIRE, AUCUN rendu -- question unique :
// la focale focalPx=2488.888... observee dans tous les diagnostics
// precedents (_debug_ceil_edge_depth_test.dart, commit 35d758f, etc.)
// provient-elle du calcul geometrique (Caprile-Torre,
// FocaleOrigine.calculee) ou du repli 35mm-equivalent
// (FocaleOrigine.defaut) -- ce dernier attendu si les 4 points de
// calibration du preset haussmann ont des aretes verticales
// (ceilL-floorL, ceilR-floorR) strictement paralleles en pixels
// (memes x), ce qui rend v2 = null via lineIntersect2D.
//
// Aucun arrondi cosmetique. Ne modifie AUCUN fichier de production.
// Sera supprime apres usage.
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:staff_decor_studio/core/geometry/calib_to_camera.dart';
import 'package:staff_decor_studio/core/geometry/camera.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

String v2s(vm.Vector2? v) => v == null ? 'null' : '(${v.x}, ${v.y})';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FocalEstimationResult.origine + v1/v2 pour le preset haussmann', () async {
    const imgW = 2560.0;
    const imgH = 1783.0;
    final calib = PerspCalib.forDemoScene('haussmann');

    final ceilLPx = calibPointToPixels(calib.ceilL, imageWidthPx: imgW, imageHeightPx: imgH);
    final ceilRPx = calibPointToPixels(calib.ceilR, imageWidthPx: imgW, imageHeightPx: imgH);
    final floorLPx = calibPointToPixels(calib.floorL, imageWidthPx: imgW, imageHeightPx: imgH);
    final floorRPx = calibPointToPixels(calib.floorR, imageWidthPx: imgW, imageHeightPx: imgH);

    // ignore: avoid_print
    print('ceilLPx  = $ceilLPx');
    // ignore: avoid_print
    print('ceilRPx  = $ceilRPx');
    // ignore: avoid_print
    print('floorLPx = $floorLPx');
    // ignore: avoid_print
    print('floorRPx = $floorRPx');
    // ignore: avoid_print
    print('ceilLPx.x == floorLPx.x : ${ceilLPx.x == floorLPx.x}');
    // ignore: avoid_print
    print('ceilRPx.x == floorRPx.x : ${ceilRPx.x == floorRPx.x}');

    final result = estimateFocalFromBackWallRectangle(
      ceilL: ceilLPx,
      ceilR: ceilRPx,
      floorL: floorLPx,
      floorR: floorRPx,
      imageWidthPx: imgW,
      imageHeightPx: imgH,
    );

    // ignore: avoid_print
    print('=== FocalEstimationResult (preset haussmann) ===');
    // ignore: avoid_print
    print('origine  = ${result.origine}');
    // ignore: avoid_print
    print('focalPx  = ${result.focalPx}');
    // ignore: avoid_print
    print('v1       = ${v2s(result.v1)}');
    // ignore: avoid_print
    print('v2       = ${v2s(result.v2)}');

    final defaultVal = defaultFocalPx35mmEquivalent(imgW);
    // ignore: avoid_print
    print('defaultFocalPx35mmEquivalent($imgW) = $defaultVal');
    // ignore: avoid_print
    print('result.focalPx == defaultFocalPx35mmEquivalent : ${result.focalPx == defaultVal}');

    expect(result.origine, FocaleOrigine.defaut);
    expect(result.v2, isNull);
  });
}
