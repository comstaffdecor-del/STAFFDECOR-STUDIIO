// Script de diagnostic TEMPORAIRE -- vérifie point par point (PAS bbox
// globale) où se trouve chaque sommet du PREMIER anneau (u=0, ring[0]) du
// profil D720, en pixel ET en monde, pour expliquer pourquoi la bbox
// globale de la fenêtre [0,400mm] a un minY (103.7px) plus petit que la
// croix bleue (origine profil, y=127.3px) -- effet de perspective attendu
// (points plus profonds dans la piece, plus proches camera) ou régression.
// Ne modifie AUCUN fichier de production. Sera supprimé après usage.
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

  test('diagnostic brut : sommets du ring[0] (u=0) -- pixel + monde', () async {
    const imgW = 2560.0;
    const imgH = 1783.0;
    final calib = PerspCalib.forDemoScene('haussmann');
    final scene = buildCalibratedScene(calib: calib, imageWidthPx: imgW, imageHeightPx: imgH);

    final projectRoot = Directory.current.path;
    final jsonStr = await File('$projectRoot/assets/profiles/D720.json').readAsString();
    final profileJson = jsonDecode(jsonStr) as Map<String, dynamic>;
    final profile = loadProfileFromJson(profileJson);

    const pathSubdivisionStepMm = 50.0;
    final edgeVec = scene.ceilROnEdge - scene.ceilLOnEdge;
    final edgeLengthM = edgeVec.length;
    final edgeDir = edgeVec.normalized();
    final subdivisionCount = (edgeLengthM * 1000.0 / pathSubdivisionStepMm).ceil();
    final pathMeters = <vm.Vector3>[
      for (var i = 0; i <= subdivisionCount; i++)
        scene.ceilLOnEdge + edgeDir * (edgeLengthM * i / subdivisionCount),
    ];
    final wallPlanes = List.filled(pathMeters.length - 1, scene.backWallPlane);

    final ringsExposed = computeCrossSectionRings(
      profile: profile,
      pathMeters: pathMeters,
      wallPlanes: wallPlanes,
      ceilingPlane: scene.ceilingPlane,
    );

    print('=== RING[0] (u=0, debut du trajet, cote ceilL) -- ${profile.pointsMm.length} sommets ===');
    print('wallOrigin (ceilLOnEdge) = ${scene.ceilLOnEdge}');
    print('wallOrigin.y (monde) = ${scene.ceilLOnEdge.y}');
    print('');

    final ring0 = ringsExposed.first;
    double minPixelY = double.infinity;
    int minPixelYIdx = -1;
    for (var j = 0; j < profile.pointsMm.length; j++) {
      final profilPt = profile.pointsMm[j];
      final world3D = ring0[j];
      final proj = scene.camera.project(world3D);
      final isCeil = profile.ceilingIndices.contains(j);
      final isWall = profile.wallIndices.contains(j);
      final tag = isCeil ? ' [CEIL]' : (isWall ? ' [WALL]' : '');
      print(
        'j=$j profilMm=(${profilPt.x.toStringAsFixed(2)},${profilPt.y.toStringAsFixed(2)}) '
        'world=(${world3D.x.toStringAsFixed(4)},${world3D.y.toStringAsFixed(4)},${world3D.z.toStringAsFixed(4)}) '
        'world.y-wallOrigin.y=${(world3D.y - scene.ceilLOnEdge.y).toStringAsFixed(4)} '
        'pixel=(${proj.pixel.x.toStringAsFixed(1)},${proj.pixel.y.toStringAsFixed(1)}) '
        'depthCam=${proj.depthCam.toStringAsFixed(4)}$tag',
      );
      if (proj.pixel.y < minPixelY) {
        minPixelY = proj.pixel.y;
        minPixelYIdx = j;
      }
    }
    print('');
    print(
      '=== Sommet au pixel Y MINIMUM (le plus haut a l\'ecran) du ring[0] : '
      'j=$minPixelYIdx, pixelY=$minPixelY ===',
    );
    final worldMin = ring0[minPixelYIdx];
    print('world.y de ce sommet = ${worldMin.y}   vs wallOrigin.y = ${scene.ceilLOnEdge.y}');
    print(
      'Ce sommet est-il PHYSIQUEMENT au-dessus du plafond (world.y > wallOrigin.y) ? '
      '${worldMin.y > scene.ceilLOnEdge.y}',
    );

    // Comparaison : ring a mi-chemin de la fenetre [0,400mm] et ring a la fin,
    // pour verifier si le minY pixel de la bbox globale (400mm) vient d'un
    // ring different de ring[0].
    print('');
    print('=== Comparaison bbox pixel Y min PAR ANNEAU (u croissant, pas 50mm) ===');
    for (var r = 0; r < ringsExposed.length && r < 9; r++) {
      final ring = ringsExposed[r];
      double localMinY = double.infinity;
      int localMinYIdx = -1;
      for (var j = 0; j < ring.length; j++) {
        final proj = scene.camera.project(ring[j]);
        if (proj.pixel.y < localMinY) {
          localMinY = proj.pixel.y;
          localMinYIdx = j;
        }
      }
      final uMm = r * pathSubdivisionStepMm;
      print('ring[$r] (u=${uMm}mm) : minPixelY=$localMinY (j=$localMinYIdx)');
    }

    expect(minPixelYIdx, isNotNull);
  });
}
