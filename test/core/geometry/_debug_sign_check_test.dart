import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:staff_decor_studio/core/geometry/calib_to_camera.dart';
import 'package:staff_decor_studio/core/geometry/sweep.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

MoulureProfile loadProfileFromJson(Map<String, dynamic> json) {
  final rawPts = (json['profil_mm'] as List)
      .map((p) => vm.Vector2((p[0] as num).toDouble(), (p[1] as num).toDouble()))
      .toList();
  var pts = rawPts;
  if (rawPts.length > 1 && rawPts.first.distanceTo(rawPts.last) < 1e-6) {
    pts = rawPts.sublist(0, rawPts.length - 1);
  }
  final wallIdx = (json['face_pose_mur']['indices'] as List).map((i) => i as int).toList();
  final ceilIdx = (json['face_pose_plafond']['indices'] as List).map((i) => i as int).toList();
  return MoulureProfile(pointsMm: pts, wallIndices: wallIdx, ceilingIndices: ceilIdx);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('signe heightAxis - point bas du profil (mur, y=-202.87mm)', () async {
    const imgW = 2560.0; const imgH = 1783.0;
    final calib = PerspCalib.forDemoScene('haussmann');
    final scene = buildCalibratedScene(calib: calib, imageWidthPx: imgW, imageHeightPx: imgH);
    final jsonStr = await File('${Directory.current.path}/assets/profiles/D720.json').readAsString();
    final profileJson = jsonDecode(jsonStr) as Map<String, dynamic>;
    final profile = loadProfileFromJson(profileJson);

    final pathMeters = [scene.ceilLOnEdge, scene.ceilROnEdge];
    final wallPlanes = [scene.backWallPlane];
    final rings = computeCrossSectionRings(
      profile: profile, pathMeters: pathMeters, wallPlanes: wallPlanes, ceilingPlane: scene.ceilingPlane,
    );
    final ring0 = rings[0];

    print('=== Points profil bruts (index: x_mm, y_mm) ===');
    for (var i = 0; i < profile.pointsMm.length; i++) {
      print('  idx $i: ${profile.pointsMm[i]}');
    }
    print('');
    print('wallOrigin attendu = ceilLOnEdge = ${scene.ceilLOnEdge}  (Y monde = ${scene.ceilLOnEdge.y})');
    print('');
    print('=== Point profil idx=1 (x=0,y=-202.8698 -- COIN BAS DU MUR, wallIndices[0]) ===');
    print('  point monde 3D = ${ring0[1]}');
    print('  Y monde = ${ring0[1].y}');
    print('  delta Y vs wallOrigin.y = ${ring0[1].y - scene.ceilLOnEdge.y}  (mm = ${(ring0[1].y - scene.ceilLOnEdge.y)*1000})');
    print('  -> attendu (si correct) : descend donc Y monde < wallOrigin.y (delta NEGATIF ~ -0.203m)');
    print('  -> si Y monde > wallOrigin.y (delta POSITIF) : le mesh MONTE au lieu de descendre -> BUG');
    print('');
    final proj = scene.camera.project(ring0[1]);
    print('  projection pixel = ${proj.pixel}');
    final projOrigin = scene.camera.project(scene.ceilLOnEdge);
    print('  projection ceilLOnEdge (plafond) pixel = ${projOrigin.pixel}');
    print('  -> en image, Y croit vers le BAS. Si le point bas du mur a un Y-pixel INFERIEUR');
    print('     a celui du plafond, ca veut dire visuellement "plus haut que le plafond" -> BUG');
  });
}
