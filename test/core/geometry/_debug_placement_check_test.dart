// Script de diagnostic TEMPORAIRE (Point 3, doute utilisateur sur le
// placement du mesh) -- ne modifie AUCUN fichier de production, sera
// supprime apres usage. Imprime en brut : les 4 points de calibration
// (px), les equations des plans mur/plafond, coordonnees 3D debut/fin du
// trajet, leurs projections 2D, focalPx, et un controle d'echelle
// independant (hauteur apparente attendue vs mesuree).
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

  test('diagnostic brut placement D720/haussmann', () async {
    const imgW = 2560.0;
    const imgH = 1783.0;
    final calib = PerspCalib.forDemoScene('haussmann');

    // ── 1. Points de calibration bruts (fraction + px) ──
    print('=== 1. POINTS DE CALIBRATION (haussmann preset) ===');
    for (final entry in <String, dynamic>{
      'ceilL': calib.ceilL,
      'ceilR': calib.ceilR,
      'floorL': calib.floorL,
      'floorR': calib.floorR,
      'wallTL': calib.wallTL,
      'wallTR': calib.wallTR,
      'wallBL': calib.wallBL,
      'wallBR': calib.wallBR,
    }.entries) {
      final cp = entry.value;
      final px = calibPointToPixels(cp, imageWidthPx: imgW, imageHeightPx: imgH);
      print('${entry.key}: frac=(${cp.xPct},${cp.yPct})  px=(${px.x},${px.y})');
    }

    final scene = buildCalibratedScene(calib: calib, imageWidthPx: imgW, imageHeightPx: imgH);

    print('');
    print('=== 2. CAMERA ===');
    print('focalPx = ${scene.camera.focalPx}');
    print('principalPoint = ${scene.camera.principalPoint}');
    print('position = ${scene.camera.position}');
    print('right = ${scene.camera.right}');
    print('up = ${scene.camera.up}');
    print('back = ${scene.camera.back}');
    print('backWallDepthM = ${scene.backWallDepthM}');

    print('');
    print('=== 3. PLANS ===');
    print('backWallPlane: normal=${scene.backWallPlane.normal} constant=${scene.backWallPlane.constant}');
    print('  equation: ${scene.backWallPlane.normal.x}*x + ${scene.backWallPlane.normal.y}*y + ${scene.backWallPlane.normal.z}*z + ${scene.backWallPlane.constant} = 0');
    print('ceilingPlane: normal=${scene.ceilingPlane.normal} constant=${scene.ceilingPlane.constant}');
    print('  equation: ${scene.ceilingPlane.normal.x}*x + ${scene.ceilingPlane.normal.y}*y + ${scene.ceilingPlane.normal.z}*z + ${scene.ceilingPlane.constant} = 0');

    print('');
    print('=== 4. COINS MUR DU FOND DEPROJETES (3D) ===');
    print('ceilL3D = ${scene.ceilL3D}');
    print('ceilR3D = ${scene.ceilR3D}');
    print('floorL3D = ${scene.floorL3D}');
    print('floorR3D = ${scene.floorR3D}');

    print('');
    print('=== 5. TRAJET (arete mur∩plafond, bornee) ===');
    print('ceilLOnEdge (debut trajet) = ${scene.ceilLOnEdge}');
    print('ceilROnEdge (fin trajet)   = ${scene.ceilROnEdge}');
    final projStart = scene.camera.project(scene.ceilLOnEdge);
    final projEnd = scene.camera.project(scene.ceilROnEdge);
    print('projection ceilLOnEdge -> pixel = ${projStart.pixel}  depthCam=${projStart.depthCam}');
    print('projection ceilROnEdge -> pixel = ${projEnd.pixel}  depthCam=${projEnd.depthCam}');

    // ── 6. Comparaison avec les points de calibration ceilL/ceilR bruts ──
    final ceilLPx = calibPointToPixels(calib.ceilL, imageWidthPx: imgW, imageHeightPx: imgH);
    final ceilRPx = calibPointToPixels(calib.ceilR, imageWidthPx: imgW, imageHeightPx: imgH);
    print('');
    print('=== 6. ECART projection(ceilLOnEdge) vs calib.ceilL (px cliques) ===');
    print('calib.ceilL px = $ceilLPx   vs   projection = ${projStart.pixel}   ecart = ${(projStart.pixel - ceilLPx).length} px');
    print('calib.ceilR px = $ceilRPx   vs   projection = ${projEnd.pixel}   ecart = ${(projEnd.pixel - ceilRPx).length} px');

    // ── 7. Profil D720 + origine du profil (point 0,0 du profil = wallOrigin du 1er segment) ──
    final jsonStr = await File('${Directory.current.path}/assets/profiles/D720.json').readAsString();
    final profileJson = jsonDecode(jsonStr) as Map<String, dynamic>;
    final profile = loadProfileFromJson(profileJson);
    final bboxHMm = (profileJson['bbox_mm']['h'] as num).toDouble();

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

    final mesh = sweepMoulure(
      profile: profile,
      pathMeters: pathMeters,
      wallPlanes: wallPlanes,
      ceilingPlane: scene.ceilingPlane,
    );

    print('');
    print('=== 7. ORIGINE DU PROFIL (point xProfil=0,yProfil=0 du 1er anneau) ===');
    // Le sommet d'indice ceilingIndices[0] du 1er anneau doit etre tres
    // proche de wallOrigin=ceilLOnEdge (a la tolerance pose 0.1mm).
    final ringsExposed = computeCrossSectionRings(
      profile: profile,
      pathMeters: pathMeters,
      wallPlanes: wallPlanes,
      ceilingPlane: scene.ceilingPlane,
    );
    final firstRing = ringsExposed.first;
    final ceilIdx0 = profile.ceilingIndices.first;
    final wallIdx0 = profile.wallIndices.first;
    print('profile.ceilingIndices = ${profile.ceilingIndices} -> point profil = ${profile.pointsMm[ceilIdx0]}');
    print('profile.wallIndices = ${profile.wallIndices} -> point profil = ${profile.pointsMm[wallIdx0]}');
    print('ring[0][ceilIdx0] (monde 3D, mm origine plafond) = ${firstRing[ceilIdx0]}');
    print('ceilLOnEdge (attendu proche) = ${scene.ceilLOnEdge}');
    print('ecart = ${(firstRing[ceilIdx0] - scene.ceilLOnEdge).length * 1000} mm');
    final projOrigin = scene.camera.project(firstRing[ceilIdx0]);
    print('projection origine profil -> pixel = ${projOrigin.pixel}');

    // ── 8. Bounding box de TOUT le mesh en pixels (pas juste la fenetre 40cm) ──
    print('');
    print('=== 8. BBOX PIXEL DU MESH ENTIER (tous sommets, pas de fenetre) ===');
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final proj = scene.camera.project(mesh.positionAt(i));
      if (proj.pixel.x < minX) minX = proj.pixel.x;
      if (proj.pixel.x > maxX) maxX = proj.pixel.x;
      if (proj.pixel.y < minY) minY = proj.pixel.y;
      if (proj.pixel.y > maxY) maxY = proj.pixel.y;
    }
    print('mesh bbox px : x=[$minX, $maxX]  y=[$minY, $maxY]');
    print('mesh bbox px hauteur = ${maxY - minY} px   largeur = ${maxX - minX} px');
    print('(pour reference, image = ${imgW}x$imgH px, donc y%image = [${minY/imgH*100}, ${maxY/imgH*100}] %)');

    // ── 9. Controle d'echelle independant ──
    print('');
    print('=== 9. CONTROLE ECHELLE INDEPENDANT ===');
    final zAtStart = -(scene.camera.rotationCameraToWorld.transposed()
            .transformed(scene.ceilLOnEdge - scene.camera.position))
        .z; // depthCam
    final hPxExpected = scene.camera.focalPx * (bboxHMm / 1000.0) / zAtStart;
    print('bboxHMm (hauteur reelle corniche) = $bboxHMm mm');
    print('z (depthCam) au debut du trajet = $zAtStart m');
    print('h_px attendu = focalPx * (h_m/z) = ${scene.camera.focalPx} * (${bboxHMm/1000.0}/$zAtStart) = $hPxExpected px');
    print('h_px MESURE (bbox pixel du mesh, etape 8) = ${maxY - minY} px');
    print('ratio attendu/mesure = ${hPxExpected / (maxY - minY)}');
  });
}
