// Script de diagnostic TEMPORAIRE, AUCUN rendu -- question unique : l'origine
// du profil (croix bleue de l'overlay) et le depart du trajet (premier point
// de la polyligne rouge) designent-ils le MEME point 3D ? Aucun arrondi
// cosmetique sur les ecarts (toStringAsFixed(9) reserve a l'AFFICHAGE, pas
// au calcul -- les differences sont calculees sur les valeurs double brutes).
//
// API reelle utilisee (pas de nom invente) :
//   - Camera3D.project(Vector3) -> ProjectionResult { pixel: Vector2,
//     depthCam: double, isInFrontOfCamera: bool } (camera.dart).
//   - MoulureProfile.pointsMm (pas .points), ceilingIndices, wallIndices.
//   - computeCrossSectionRings(...) -> List<List<Vector3>> (sweep.dart).
//   - Le "trajet" du test overlay est `pathMeters` (List<Vector3>), pas un
//     type `pathPoints3D` distinct.
//
// Ne modifie AUCUN fichier de production. Sera supprime apres usage.
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

String v3(vm.Vector3 v) =>
    '(${v.x.toStringAsFixed(9)}, ${v.y.toStringAsFixed(9)}, ${v.z.toStringAsFixed(9)})';
String v2(vm.Vector2 v) =>
    '(${v.x.toStringAsFixed(4)}, ${v.y.toStringAsFixed(4)})';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'origine profil (croix bleue) vs depart trajet (polyligne rouge) -- '
    'meme point 3D ?',
    () async {
      const eps = 1e-9;
      const imgW = 2560.0;
      const imgH = 1783.0;
      final calib = PerspCalib.forDemoScene('haussmann');
      final scene = buildCalibratedScene(calib: calib, imageWidthPx: imgW, imageHeightPx: imgH);
      final camera = scene.camera;

      final projectRoot = Directory.current.path;
      final jsonStr = await File('$projectRoot/assets/profiles/D720.json').readAsString();
      final profileJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      final profile = loadProfileFromJson(profileJson);

      // ── Trajet, identique aux tests overlay/whitebg : depart = ceilLOnEdge. ──
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

      // ── A. Origine PARAMETRIQUE du balayage (u=0) : c'est la valeur
      // passee en tete de pathMeters, wallOrigin de _buildSegmentFrame
      // pour le premier segment. ──
      print('=== A. ORIGINE PARAMETRIQUE DU BALAYAGE (u=0, wallOrigin) ===');
      final aW = scene.ceilLOnEdge;
      final aP = camera.project(aW);
      print('A.world  = ${v3(aW)}');
      print('A.pixel  = ${v2(aP.pixel)}   depthCam=${aP.depthCam.toStringAsFixed(9)}');
      print('A.devant = ${aP.isInFrontOfCamera}');

      // ── B. Sommet portant la croix bleue de l'overlay -- EXACT sommet
      // utilise dans _debug_overlay_render_test.dart/_debug_whitebg_overlay_test.dart :
      // ring[0][profile.ceilingIndices.first]. ──
      print('=== B. SOMMET PORTANT LA CROIX BLEUE (ring[0][ceilingIndices.first]) ===');
      final blueVertexIndex = profile.ceilingIndices.first;
      final bW = ringsExposed.first[blueVertexIndex];
      final bP = camera.project(bW);
      print('B.ceilingIndices (tous)     = ${profile.ceilingIndices}');
      print('B.indexRing0 (utilise)      = $blueVertexIndex');
      print(
        'B.profil2D (pointsMm[idx])  = '
        '(${profile.pointsMm[blueVertexIndex].x}, ${profile.pointsMm[blueVertexIndex].y})  // mm',
      );
      print('B.world  = ${v3(bW)}');
      print('B.pixel  = ${v2(bP.pixel)}   depthCam=${bP.depthCam.toStringAsFixed(9)}');

      // ── C. Premier point de la polyligne rouge -- pathMeters.first,
      // strictement (pas de recalcul indépendant). ──
      print('=== C. PREMIER POINT DE LA POLYLIGNE ROUGE (pathMeters.first) ===');
      final cW = pathMeters.first;
      final cP = camera.project(cW);
      print('C.world  = ${v3(cW)}');
      print('C.pixel  = ${v2(cP.pixel)}   depthCam=${cP.depthCam.toStringAsFixed(9)}');
      print('C.nbPoints trajet = ${pathMeters.length}');

      // ── D. Ecarts -- valeurs double brutes, aucun arrondi avant calcul. ──
      print('=== D. ECARTS (aucun arrondi cosmetique sur le calcul) ===');
      final aMinusCWorld = aW - cW;
      final aMinusBWorld = aW - bW;
      print('A-C world  = ${v3(aMinusCWorld)}   |.|=${aMinusCWorld.length}');
      print('A-B world  = ${v3(aMinusBWorld)}   |.|=${aMinusBWorld.length}');
      print('A-C pixel  dx=${aP.pixel.x - cP.pixel.x}  dy=${aP.pixel.y - cP.pixel.y}');
      print('A-B pixel  dx=${aP.pixel.x - bP.pixel.x}  dy=${aP.pixel.y - bP.pixel.y}');
      print('B-C pixel  dx=${bP.pixel.x - cP.pixel.x}  dy=${bP.pixel.y - cP.pixel.y}');

      // ── E. Echelle locale px -> mm, a la profondeur de A. ──
      print('=== E. ECHELLE LOCALE (pour convertir px -> mm) ===');
      print('focalPx = ${camera.focalPx}');
      final pxPerMm = camera.focalPx / (aP.depthCam * 1000.0);
      print('px/mm a la profondeur de A = $pxPerMm');
      print(
        'B-C en mm : dx=${(bP.pixel.x - cP.pixel.x) / pxPerMm}  '
        'dy=${(bP.pixel.y - cP.pixel.y) / pxPerMm}',
      );

      // ── F. Controle : A est-il sur l'arete plafond/mur (wallOrigin.y) ? ──
      print('=== F. CONTROLE : A est-il sur l\'arete plafond/mur ? ===');
      final wallOriginY = scene.ceilLOnEdge.y;
      print(
        'A.y vs wallOrigin.y : ${aW.y} vs $wallOriginY  '
        'egal=${(aW.y - wallOriginY).abs() < eps}',
      );

      expect(aP.isInFrontOfCamera, isTrue);
    },
  );
}
