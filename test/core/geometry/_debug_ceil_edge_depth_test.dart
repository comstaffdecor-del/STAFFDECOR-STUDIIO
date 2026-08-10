// Script de diagnostic TEMPORAIRE, AUCUN rendu -- question unique :
// ceilLOnEdge et ceilROnEdge (les deux extremites 3D de l'arete
// mur/plafond reconstruite par buildCalibratedScene) sont-ils a la MEME
// profondeur camera (depthCam) ? Si oui, c'est cette contrainte
// geometrique elle-meme (et non un bug) qui impose pStart.y == pEnd.y
// dans le rendu overlay -- ce qui expliquerait l'ecart CONSTANT observe
// dans _debug_overlay_render_test.dart (commit 76727cf) independamment
// de toute question de calibration ceilL/ceilR.
//
// Aucun arrondi cosmetique sur les calculs (v3/v2 ne servent qu'a
// l'AFFICHAGE, repris tels quels de _debug_origin_vs_path_test.dart).
//
// Ne modifie AUCUN fichier de production. Sera supprime apres usage.
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:staff_decor_studio/core/geometry/calib_to_camera.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

String v3(vm.Vector3 v) =>
    '(${v.x.toStringAsFixed(9)}, ${v.y.toStringAsFixed(9)}, ${v.z.toStringAsFixed(9)})';
String v2(vm.Vector2 v) => '(${v.x.toStringAsFixed(4)}, ${v.y.toStringAsFixed(4)})';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ceilLOnEdge vs ceilROnEdge -- meme profondeur camera (depthCam) ?', () async {
    const imgW = 2560.0;
    const imgH = 1783.0;
    final calib = PerspCalib.forDemoScene('haussmann');
    final scene = buildCalibratedScene(calib: calib, imageWidthPx: imgW, imageHeightPx: imgH);
    final camera = scene.camera;

    final L = scene.ceilLOnEdge;
    final R = scene.ceilROnEdge;
    final pL = camera.project(L);
    final pR = camera.project(R);

    // ignore: avoid_print
    print('ceilLOnEdge.world = ${v3(L)}');
    // ignore: avoid_print
    print('ceilROnEdge.world = ${v3(R)}');
    // ignore: avoid_print
    print('L.depthCam = ${pL.depthCam}');
    // ignore: avoid_print
    print('R.depthCam = ${pR.depthCam}');
    // ignore: avoid_print
    print('dz world      = ${R.z - L.z}');
    // ignore: avoid_print
    print('d(depthCam)   = ${pR.depthCam - pL.depthCam}');
    // ignore: avoid_print
    print('z egaux (==)  = ${L.z == R.z}');
    // ignore: avoid_print
    print('L.pixel = ${v2(pL.pixel)}   R.pixel = ${v2(pR.pixel)}');
    // ignore: avoid_print
    print('dy pixel = ${pR.pixel.y - pL.pixel.y}');

    // Contexte : d'ou viennent ces deux points (CalibPoint n'a pas de
    // toString exploitable -- xPct/yPct affiches explicitement).
    // ignore: avoid_print
    print(
      'calib ceilL frac = (xPct=${calib.ceilL.xPct}, yPct=${calib.ceilL.yPct})'
      '   calib ceilR frac = (xPct=${calib.ceilR.xPct}, yPct=${calib.ceilR.yPct})',
    );
    // ignore: avoid_print
    print('longueur arete 3D = ${(R - L).length} m');

    expect(pL.isInFrontOfCamera, isTrue);
    expect(pR.isInFrontOfCamera, isTrue);
  });
}
