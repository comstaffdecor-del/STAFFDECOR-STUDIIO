// ══════════════════════════════════════════════════════════════════════
// P14 — rendu rapide D720 v3 (calibration manuelle mur-miroir, PAS le
// preset large 0.12-0.88 réfuté en P14-E) — UNE image, pas de test P14-E
// complet, pas d'axes, pas de doc.
//
// Calibration manuelle imposée (mesurée à la main sur haussmann.jpg,
// bornée au pan de mur-miroir réellement visible) :
//   ceilL (0.16, 0.090)   ceilR (0.56, 0.088)
//   floorL(0.16, 0.685)   floorR(0.56, 0.686)
//   wallT*/wallB* alignés dessus (non lus par buildCalibratedScene —
//   estimateFocalFromBackWallRectangle n'utilise que ceilL/R/floorL/R).
//
// N'ajoute PAS ce calib à PerspCalib.demoPresets (valeurs locales au test
// uniquement). Ne modifie NI sweep.dart NI camera.dart NI
// calib_to_camera.dart NI mesh_painter.dart.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:staff_decor_studio/core/geometry/calib_to_camera.dart';
import 'package:staff_decor_studio/core/geometry/camera.dart';
import 'package:staff_decor_studio/core/geometry/sweep.dart';
import 'package:staff_decor_studio/core/perspective/mesh_painter.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

const double roomHeightMInjectable = 2.5;

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

int _bottomIdxOf(MoulureProfile p) {
  var bottomIdx = 0;
  var minY = p.pointsMm[0].y;
  for (var i = 1; i < p.pointsMm.length; i++) {
    if (p.pointsMm[i].y < minY) {
      minY = p.pointsMm[i].y;
      bottomIdx = i;
    }
  }
  return bottomIdx;
}

Future<ui.Image> decodeImageFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<Uint8List> encodePng(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

void paintMeshWireframe(
  ui.Canvas canvas,
  Mesh mesh,
  Camera3D camera, {
  ui.Color color = const ui.Color(0xFF00C800),
  double strokeWidth = 1.0,
}) {
  final vertexCount = mesh.vertexCount;
  if (vertexCount == 0) return;
  final screenPos = List<ui.Offset>.filled(vertexCount, ui.Offset.zero);
  for (var i = 0; i < vertexCount; i++) {
    final proj = camera.project(mesh.positionAt(i));
    screenPos[i] = ui.Offset(proj.pixel.x, proj.pixel.y);
  }
  final paint = ui.Paint()
    ..color = color
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = strokeWidth;
  final triangleCount = mesh.triangleCount;
  for (var t = 0; t < triangleCount; t++) {
    final i0 = mesh.indices[t * 3];
    final i1 = mesh.indices[t * 3 + 1];
    final i2 = mesh.indices[t * 3 + 2];
    final path = ui.Path()
      ..moveTo(screenPos[i0].dx, screenPos[i0].dy)
      ..lineTo(screenPos[i1].dx, screenPos[i1].dy)
      ..lineTo(screenPos[i2].dx, screenPos[i2].dy)
      ..close();
    canvas.drawPath(path, paint);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'P14 fast v3 — D720 sur calibration manuelle mur-miroir '
    '(ceilL/R+floorL/R resserrés, H2 tranché) — image seule, pas de test '
    'P14-E complet',
    () async {
      final projectRoot = Directory.current.path;
      const sku = 'D720';
      const sceneKey = 'haussmann';
      final photoPath = '$projectRoot/assets/demo_scenes/$sceneKey.jpg';
      final photo = await decodeImageFile(photoPath);
      final photoW = photo.width.toDouble();
      final photoH = photo.height.toDouble();

      // ── Calibration manuelle imposée (mur-miroir, PAS le preset large). ──
      const calibManualV3 = PerspCalib(
        ceilL: CalibPoint(xPct: 0.16, yPct: 0.090),
        ceilR: CalibPoint(xPct: 0.56, yPct: 0.088),
        floorL: CalibPoint(xPct: 0.16, yPct: 0.685),
        floorR: CalibPoint(xPct: 0.56, yPct: 0.686),
        wallTL: CalibPoint(xPct: 0.16, yPct: 0.090),
        wallTR: CalibPoint(xPct: 0.56, yPct: 0.088),
        wallBL: CalibPoint(xPct: 0.16, yPct: 0.685),
        wallBR: CalibPoint(xPct: 0.56, yPct: 0.686),
      );

      final jsonStr = await File('$projectRoot/assets/profiles/$sku.json').readAsString();
      final profileJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      final bboxHMm = (profileJson['bbox_mm']['h'] as num).toDouble();
      final baseProfile = loadProfileFromJson(profileJson);

      // ── Scène — roomHeightM=2.5 (même choix que P14-D). ──
      final scene = buildCalibratedScene(
        calib: calibManualV3,
        imageWidthPx: photoW,
        imageHeightPx: photoH,
        roomHeightM: roomHeightMInjectable,
      );

      // ── Diagnostic focale (mur quasi frontal -> v2 vertical dégénéré
      //    attendu -> repli 35mm-équivalent automatique de
      //    estimateFocalFromBackWallRectangle, PAS un bricolage ajouté
      //    ici). Reproduit le calcul par LECTURE, sans toucher les 4
      //    points de calib, juste pour savoir si le repli a été pris. ──
      final ceilLPx = calibPointToPixels(calibManualV3.ceilL, imageWidthPx: photoW, imageHeightPx: photoH);
      final ceilRPx = calibPointToPixels(calibManualV3.ceilR, imageWidthPx: photoW, imageHeightPx: photoH);
      final floorLPx = calibPointToPixels(calibManualV3.floorL, imageWidthPx: photoW, imageHeightPx: photoH);
      final floorRPx = calibPointToPixels(calibManualV3.floorR, imageWidthPx: photoW, imageHeightPx: photoH);
      final focalDiag = estimateFocalFromBackWallRectangle(
        ceilL: ceilLPx,
        ceilR: ceilRPx,
        floorL: floorLPx,
        floorR: floorRPx,
        imageWidthPx: photoW,
        imageHeightPx: photoH,
      );
      final focalPx = scene.camera.focalPx;
      expect(focalPx, closeTo(focalDiag.focalPx, 1e-9));

      final focaleAbsurde = focalDiag.origine == FocaleOrigine.defaut;
      // Mur quasi frontal (v2 vertical dégénéré attendu, v1 horizontal
      // très excentré) -> repli 35mm-équivalent attendu, PAS un bug de ce
      // test : on le SIGNALE, on NE RETOUCHE PAS les points de calib.
      expect(
        focaleAbsurde,
        isTrue,
        reason: 'Attendu : mur mur-miroir quasi frontal -> v2 dégénéré -> '
            'repli 35mm-équivalent. Si ce test échoue, la focale a été '
            'calculée géométriquement (v1/v2 valides) — à re-vérifier, '
            'mais NE PAS retoucher les points sans le signaler.',
      );

      // ── Trajet + mesh (source unique : la scène corrigée). ──
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
      final midRingIndex = pathMeters.length ~/ 2;

      final mesh = sweepMoulure(
        profile: baseProfile,
        pathMeters: pathMeters,
        wallPlanes: wallPlanes,
        ceilingPlane: scene.ceilingPlane,
      );

      // ── Hauteur mesh mesurée (ring du milieu). ──
      final rings = computeCrossSectionRings(
        profile: baseProfile,
        pathMeters: pathMeters,
        wallPlanes: wallPlanes,
        ceilingPlane: scene.ceilingPlane,
      );
      final ring = rings[midRingIndex];
      final topPx = scene.camera.project(ring[baseProfile.ceilingIndices.first]).pixel;
      final bottomPx = scene.camera.project(ring[_bottomIdxOf(baseProfile)]).pixel;
      final hauteurMeshMesureePx = (bottomPx.y - topPx.y).abs();

      // ── Bornes x du mesh projeté (tous sommets, tous anneaux). ──
      var minXPx = double.infinity;
      var maxXPx = -double.infinity;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final px = scene.camera.project(mesh.positionAt(i)).pixel;
        if (px.x < minXPx) minXPx = px.x;
        if (px.x > maxXPx) maxXPx = px.x;
      }
      final minXFrac = minXPx / photoW;
      final maxXFrac = maxXPx / photoW;

      // ── Critère (brief) : hauteur 112-131px, borné x∈[0.16,0.56]. ──
      expect(
        hauteurMeshMesureePx,
        inInclusiveRange(60.0, 200.0),
        reason: 'Hauteur mesh hors plage large de sécurité — voir .txt '
            'pour la valeur exacte rapportée (le critère strict '
            '112-131px est jugé dans le rapport, pas bloquant ici pour '
            'ne pas cacher un résultat inattendu derrière un échec de '
            'test).',
      );
      expect(minXFrac, greaterThan(-0.05));
      expect(maxXFrac, lessThan(1.05));

      // ── Capture MATIÈRE (blanc cassé, Lambert). ──
      const offWhite = ui.Color(0xFFF2EEE4);
      final light = vm.Vector3(-0.4, 0.6, 0.7).normalized();
      const ambient = 0.55;
      final recorderMatiere = ui.PictureRecorder();
      final canvasMatiere = ui.Canvas(recorderMatiere);
      canvasMatiere.drawImageRect(
        photo,
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Paint(),
      );
      paintMeshOnCanvas(
        canvasMatiere,
        mesh,
        scene.camera,
        baseColor: offWhite,
        lightDirWorld: light,
        ambient: ambient,
      );
      final pictureMatiere = recorderMatiere.endRecording();
      final imageMatiere = await pictureMatiere.toImage(photo.width, photo.height);
      final pngMatiere = await encodePng(imageMatiere);
      const outPngAfterPath = '/tmp/p14_fast_d720_after_v3.png';
      await File(outPngAfterPath).writeAsBytes(pngMatiere);
      expect(await File(outPngAfterPath).exists(), isTrue);

      // ── Capture WIREFRAME. ──
      final recorderWire = ui.PictureRecorder();
      final canvasWire = ui.Canvas(recorderWire);
      canvasWire.drawImageRect(
        photo,
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Paint(),
      );
      paintMeshWireframe(canvasWire, mesh, scene.camera);
      final pictureWire = recorderWire.endRecording();
      final imageWire = await pictureWire.toImage(photo.width, photo.height);
      final pngWire = await encodePng(imageWire);
      const outPngWirePath = '/tmp/p14_fast_d720_wire_v3.png';
      await File(outPngWirePath).writeAsBytes(pngWire);
      expect(await File(outPngWirePath).exists(), isTrue);

      // ── Rapport texte (6 lignes utiles + focale signalée si absurde). ──
      final report = StringBuffer();
      report.writeln('P14 fast v3 — D720 / calib manuelle mur-miroir (0.16-0.56)');
      report.writeln('focalPx = ${focalPx.toStringAsFixed(4)} px'
          '${focaleAbsurde ? ' [REPLI 35mm-EQUIV — v1 très excentré (mur quasi frontal), v2 vertical dégénéré, PAS retouché]' : ''}');
      report.writeln('backWallDepthM = ${scene.backWallDepthM.toStringAsFixed(6)} m (derive de roomHeightM=$roomHeightMInjectable)');
      report.writeln('hSceneM = ${roomHeightMInjectable.toStringAsFixed(3)} m (par construction, roomHeightM impose)');
      report.writeln('hauteur mesh mesuree = ${hauteurMeshMesureePx.toStringAsFixed(2)} px (bboxHMm=$bboxHMm)');
      report.writeln('bornes x mesh = [${minXFrac.toStringAsFixed(4)}, ${maxXFrac.toStringAsFixed(4)}] (attendu ~[0.16,0.56])');
      report.writeln('Defauts restants : ${focaleAbsurde ? 'focale = repli 35mm-equiv (mur quasi frontal, VP horizontal a x≈${(focalDiag.v1!.x / photoW).toStringAsFixed(2)} hors-cadre) -- plausible mais NON mesuree geometriquement ; ' : ''}pas de verification automatique de galbe/materiau, jugement visuel requis sur le PNG.');

      const outTxtPath = '/tmp/p14_fast_d720_after_v3.txt';
      await File(outTxtPath).writeAsString(report.toString());
      expect(await File(outTxtPath).exists(), isTrue);

      // ignore: avoid_print
      print(report.toString());
    },
  );
}
