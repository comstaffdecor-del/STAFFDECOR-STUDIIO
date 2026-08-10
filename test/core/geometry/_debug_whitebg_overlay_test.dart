// Script de diagnostic TEMPORAIRE (retour à l'étape convenue : PNG fond
// blanc, seul livrable de ce tour). Rend EXACTEMENT la même scène (même
// caméra, même profil D720, même calibration haussmann, même trajet
// subdivisé 50mm, même fenêtre de crop 400mm centrée, même éclairage
// ambient=0.20 / directionnelle (0.5,0.7,0.7) déjà validée aux commits
// df10997/36ed322) que les tests précédents, mais :
//   - fond BLANC uni (pas de drawImageRect de haussmann.jpg) ;
//   - overlay conservé tel quel par-dessus le mesh : polyligne ROUGE 2px
//     du trajet de balayage (ceilLOnEdge -> ceilROnEdge), croix BLEUE à
//     l'origine du profil (xProfil=0, yProfil=0), croix VERTES numérotées
//     aux 4 points de calibration ceilL/ceilR/floorL/floorR (inchangées).
//
// Question posée (les deux seules) :
//   1. Les denticules disparaissent-elles du crop ×4 sur fond blanc ?
//   2. La bande grise (mesh) est-elle sous la croix bleue ?
//
// Ne modifie AUCUN fichier de production. Sera supprimé après usage.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:staff_decor_studio/core/geometry/calib_to_camera.dart';
import 'package:staff_decor_studio/core/geometry/sweep.dart';
import 'package:staff_decor_studio/core/perspective/mesh_painter.dart';
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

Future<Uint8List> encodePng(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

void drawCross(
  ui.Canvas canvas,
  ui.Offset center,
  ui.Color color, {
  double size = 22,
  double strokeWidth = 4,
}) {
  final paint = ui.Paint()
    ..color = color
    ..strokeWidth = strokeWidth
    ..style = ui.PaintingStyle.stroke;
  canvas.drawLine(
    ui.Offset(center.dx - size, center.dy),
    ui.Offset(center.dx + size, center.dy),
    paint,
  );
  canvas.drawLine(
    ui.Offset(center.dx, center.dy - size),
    ui.Offset(center.dx, center.dy + size),
    paint,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'rend D720 sur fond BLANC + overlay (trajet rouge, origine bleue, '
    'calib verte) -- même caméra/profil/lumière/crop que les tests photo',
    () async {
      const imgW = 2560.0;
      const imgH = 1783.0;
      final calib = PerspCalib.forDemoScene('haussmann');
      final scene = buildCalibratedScene(
        calib: calib,
        imageWidthPx: imgW,
        imageHeightPx: imgH,
      );

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

      final mesh = sweepMoulure(
        profile: profile,
        pathMeters: pathMeters,
        wallPlanes: wallPlanes,
        ceilingPlane: scene.ceilingPlane,
      );

      // ⚠️ CORRECTIF (ce tour) : la croix bleue "origine du profil" était
      // dessinée sur `ringsExposed.first[profile.ceilingIndices.first]`
      // (sommet d'indice 3 pour D720, profil=(112.79,0.0)mm) -- PAS
      // l'origine du balayage. Prouvé par _debug_origin_vs_path_test.dart
      // (commit 8ba3cef) : écart exact de 112.7888mm en Z monde,
      // correspondant bit à bit à `profile.pointsMm[3].x`. L'origine
      // définitionnelle du balayage (xProfil=0, yProfil=0 conceptuel) est
      // `pathMeters.first` == `wallOrigin` du premier segment
      // (`_buildSegmentFrame`, sweep.dart) -- c'est CE point, et lui seul,
      // qui doit porter la croix bleue, sans dépendre d'un indice de
      // sommet du profil (voir CONVENTIONS.md §3 : wallOrigin est le point
      // où xProfil=0 ET yProfil=0 coïncident avec l'arête réelle).
      final profileOrigin3D = pathMeters.first;

      // ── Question de fond demandée : existe-t-il un sommet à (0,0) dans
      // profil_mm ? Six lignes brutes, aucune interprétation ici. ──
      // ignore: avoid_print
      print('=== SIX PREMIERS POINTS DU PROFIL (pointsMm[0..5]) ===');
      // ignore: avoid_print
      print('wallIndices = ${profile.wallIndices}');
      // ignore: avoid_print
      print('ceilingIndices = ${profile.ceilingIndices}');
      for (var i = 0; i < 6; i++) {
        // ignore: avoid_print
        print('pointsMm[$i] = (${profile.pointsMm[i].x}, ${profile.pointsMm[i].y})');
      }

      final lightDirWorld = vm.Vector3(0.5, 0.7, 0.7);
      const ambient = 0.20;

      // ── Canvas plein format, fond BLANC + mesh + overlay ──
      final overviewRecorder = ui.PictureRecorder();
      final overviewCanvas = ui.Canvas(overviewRecorder);
      overviewCanvas.drawRect(
        ui.Rect.fromLTWH(0, 0, imgW, imgH),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      paintMeshOnCanvas(
        overviewCanvas,
        mesh,
        scene.camera,
        baseColor: const ui.Color(0xFFEDEAE4),
        lightDirWorld: lightDirWorld,
        ambient: ambient,
      );

      // 1. Trajet de balayage projeté -- polyligne ROUGE 2px.
      final pStart = scene.camera.project(scene.ceilLOnEdge).pixel;
      final pEnd = scene.camera.project(scene.ceilROnEdge).pixel;
      overviewCanvas.drawLine(
        ui.Offset(pStart.x, pStart.y),
        ui.Offset(pEnd.x, pEnd.y),
        ui.Paint()
          ..color = const ui.Color(0xFFFF0000)
          ..strokeWidth = 2.0,
      );

      // 2. Les 4 points de calibration -- croix VERTES, inchangées.
      final calibPoints = <String, CalibPoint>{
        '1.ceilL': calib.ceilL,
        '2.ceilR': calib.ceilR,
        '3.floorL': calib.floorL,
        '4.floorR': calib.floorR,
      };
      final greenCrossesPx = <String, ui.Offset>{};
      for (final entry in calibPoints.entries) {
        final px = calibPointToPixels(entry.value, imageWidthPx: imgW, imageHeightPx: imgH);
        final offset = ui.Offset(px.x, px.y);
        drawCross(overviewCanvas, offset, const ui.Color(0xFF00FF00), size: 26, strokeWidth: 5);
        greenCrossesPx[entry.key] = offset;
      }

      // 3. Origine du profil (x=0,y=0) -- croix BLEUE.
      final originPx = scene.camera.project(profileOrigin3D).pixel;
      final originOffset = ui.Offset(originPx.x, originPx.y);
      drawCross(overviewCanvas, originOffset, const ui.Color(0xFF0000FF), size: 26, strokeWidth: 5);

      final overviewPicture = overviewRecorder.endRecording();
      final overviewImage = await overviewPicture.toImage(imgW.round(), imgH.round());

      // ── Fenêtre de crop RECENTRÉE sur l'ORIGINE DU PROFIL (u≈0, côté
      // ceilL/croix bleue) -- PAS le centre du trajet comme dans les tests
      // précédents. Choix délibéré : la question posée ce tour porte sur
      // la relation bande-mesh / croix bleue, qui est au début du trajet,
      // pas au milieu. Fenêtre [0, 400]mm depuis le départ. ──
      const uMinMm = 0.0;
      const uMaxMm = 400.0;

      double minX = double.infinity, maxX = -double.infinity;
      double minY = double.infinity, maxY = -double.infinity;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final u = mesh.uvAt(i).x;
        if (u < uMinMm || u > uMaxMm) continue;
        final proj = scene.camera.project(mesh.positionAt(i));
        if (proj.pixel.x < minX) minX = proj.pixel.x;
        if (proj.pixel.x > maxX) maxX = proj.pixel.x;
        if (proj.pixel.y < minY) minY = proj.pixel.y;
        if (proj.pixel.y > maxY) maxY = proj.pixel.y;
      }

      final bboxPxW = maxX - minX;
      final bboxPxH = maxY - minY;
      final marginX = bboxPxW * 0.15;
      final marginYAbove = bboxPxH * 0.5;
      final marginYBelow = bboxPxH * 1.1;
      final cropLeft = (minX - marginX).clamp(0.0, imgW);
      final cropRight = (maxX + marginX).clamp(0.0, imgW);
      final cropTop = (minY - marginYAbove).clamp(0.0, imgH);
      final cropBottom = (maxY + marginYBelow).clamp(0.0, imgH);
      final cropW = cropRight - cropLeft;
      final cropH = cropBottom - cropTop;

      const zoomFactor = 4.0;
      final cropCanvasW = cropW * zoomFactor;
      final cropCanvasH = cropH * zoomFactor;
      final cropRecorder = ui.PictureRecorder();
      final cropCanvas = ui.Canvas(cropRecorder);
      cropCanvas.drawImageRect(
        overviewImage,
        ui.Rect.fromLTWH(cropLeft, cropTop, cropW, cropH),
        ui.Rect.fromLTWH(0, 0, cropCanvasW, cropCanvasH),
        ui.Paint(),
      );
      final cropPicture = cropRecorder.endRecording();
      final cropImage = await cropPicture.toImage(cropCanvasW.round(), cropCanvasH.round());

      // Coordonnées de la croix bleue DANS le panneau crop (avant mise à
      // l'échelle d'affichage finale) -- ce que l'oeil voit réellement
      // agrandi ×4 dans le PNG.
      final originInCropCanvas = ui.Offset(
        (originOffset.dx - cropLeft) * zoomFactor,
        (originOffset.dy - cropTop) * zoomFactor,
      );
      final originInsideCropWindow =
          originOffset.dx >= cropLeft &&
          originOffset.dx <= cropRight &&
          originOffset.dy >= cropTop &&
          originOffset.dy <= cropBottom;

      // ── Composition finale : vue d'ensemble + crop x4, fond blanc ──
      const displayW = 1400.0;
      final overviewScale = displayW / imgW;
      final overviewDisplayH = imgH * overviewScale;
      final cropDisplayScale = (displayW / cropCanvasW).clamp(0.0, 1.0);
      final cropDisplayH = cropCanvasH * cropDisplayScale;
      const pad = 16.0;
      const labelH = 30.0;
      final totalW = displayW + pad * 2;
      final totalH = pad + labelH + overviewDisplayH + pad + labelH + cropDisplayH + pad;

      final finalRecorder = ui.PictureRecorder();
      final finalCanvas = ui.Canvas(finalRecorder);
      finalCanvas.drawRect(
        ui.Rect.fromLTWH(0, 0, totalW, totalH),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      var cursorY = pad + labelH;
      finalCanvas.save();
      finalCanvas.translate(pad, cursorY);
      finalCanvas.scale(overviewScale, overviewScale);
      finalCanvas.drawImageRect(
        overviewImage,
        ui.Rect.fromLTWH(0, 0, imgW, imgH),
        ui.Rect.fromLTWH(0, 0, imgW, imgH),
        ui.Paint(),
      );
      finalCanvas.restore();
      finalCanvas.drawRect(
        ui.Rect.fromLTWH(pad, cursorY, displayW, overviewDisplayH),
        ui.Paint()
          ..color = const ui.Color(0xFFCCCCCC)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      cursorY += overviewDisplayH + pad + labelH;
      finalCanvas.save();
      finalCanvas.translate(pad, cursorY);
      finalCanvas.scale(cropDisplayScale, cropDisplayScale);
      finalCanvas.drawImageRect(
        cropImage,
        ui.Rect.fromLTWH(0, 0, cropCanvasW, cropCanvasH),
        ui.Rect.fromLTWH(0, 0, cropCanvasW, cropCanvasH),
        ui.Paint(),
      );
      finalCanvas.restore();

      final finalPicture = finalRecorder.endRecording();
      final finalImage = await finalPicture.toImage(totalW.round(), totalH.round());
      final pngBytes = await encodePng(finalImage);

      const outPath = '/tmp/step2profile_pilot_test/debug_whitebg_overlay_d720.png';
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(pngBytes);

      // ignore: avoid_print
      print('=== PNG FOND BLANC + OVERLAY -- sortie brute ===');
      // ignore: avoid_print
      print('Chemin : $outPath (${pngBytes.length} octets)');
      // ignore: avoid_print
      print('Dimensions PNG final : ${totalW.round()}x${totalH.round()} px');
      // ignore: avoid_print
      print(
        'Bande (bbox mesh dans fenetre u=[$uMinMm,$uMaxMm]mm) : '
        'x=[$minX,$maxX] y=[$minY,$maxY] px (image pleine 2560x1783)',
      );
      // ignore: avoid_print
      print('Bande hauteur px (maxY-minY) = $bboxPxH px');
      // ignore: avoid_print
      print('Bande largeur px (maxX-minX) = $bboxPxW px');
      // ignore: avoid_print
      print('Croix BLEUE (origine profil) px image pleine = $originOffset');
      // ignore: avoid_print
      print(
        'Croix BLEUE dans le panneau crop (avant echelle affichage, '
        'zoom x4) = $originInCropCanvas',
      );
      // ignore: avoid_print
      print('Croix BLEUE a l\'interieur de la fenetre de crop ? $originInsideCropWindow');
      // ignore: avoid_print
      print(
        'Fenetre de crop (px image pleine) : x=[$cropLeft,$cropRight] '
        'y=[$cropTop,$cropBottom]',
      );
      for (final e in greenCrossesPx.entries) {
        // ignore: avoid_print
        print('Croix VERTE ${e.key} px image pleine = ${e.value}');
      }
      // ignore: avoid_print
      print('Trajet ROUGE : debut=$pStart fin=$pEnd');

      expect(await outFile.exists(), isTrue);
    },
  );
}
