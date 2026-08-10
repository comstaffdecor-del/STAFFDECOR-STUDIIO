// Script de diagnostic TEMPORAIRE (Point unique du tour : lever le doute
// "les denticules citées appartiennent-elles a la photo ou au mesh ?").
// Rend EXACTEMENT la meme scene (meme camera, meme profil D720, meme
// lumiere (0.5,0.7,0.7)/ambient=0.20, meme trajet subdivise 50mm, meme
// fenetre de crop 400mm centree) que
// `render_d720_haussmann_dualview_test.dart`, mais sur fond BLANC UNI au
// lieu de haussmann.jpg -- mesh seul. Ne modifie AUCUN fichier de
// production. Sera supprime apres usage.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rend D720 sur fond BLANC (pas de photo) -- meme camera/profil/lumiere/crop', () async {
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

    final mesh = sweepMoulure(
      profile: profile,
      pathMeters: pathMeters,
      wallPlanes: wallPlanes,
      ceilingPlane: scene.ceilingPlane,
    );

    final lightDirWorld = vm.Vector3(0.5, 0.7, 0.7);
    const ambient = 0.20;

    // ── Vue d'ensemble sur fond BLANC (pas de drawImageRect de la photo) ──
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
    final overviewPicture = overviewRecorder.endRecording();
    final overviewImage = await overviewPicture.toImage(imgW.round(), imgH.round());

    // ── Meme fenetre de crop 400mm centree que le test dispute ──
    final totalLengthMm = (scene.ceilROnEdge - scene.ceilLOnEdge).length * 1000.0;
    final uCenterMm = totalLengthMm / 2.0;
    const halfWindowMm = 200.0;
    final uMinMm = uCenterMm - halfWindowMm;
    final uMaxMm = uCenterMm + halfWindowMm;

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
      ui.Paint()..color = const ui.Color(0xFFCCCCCC)..style = ui.PaintingStyle.stroke..strokeWidth = 1,
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

    const outPath = '/tmp/step2profile_pilot_test/debug_whitebg_d720.png';
    final outFile = File(outPath);
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(pngBytes);

    // ignore: avoid_print
    print('PNG fond blanc ecrit: $outPath (${pngBytes.length} octets)');
    // ignore: avoid_print
    print('mesh bbox complet (tous sommets) : x=[$minX,$maxX] y=[$minY,$maxY] (dans le crop window 400mm: $minX..$maxX)');
    expect(await outFile.exists(), isTrue);
  });
}
