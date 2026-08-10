// Script de diagnostic TEMPORAIRE (Point unique du tour : localiser
// l'erreur de placement). Vue d'ensemble AVEC la photo haussmann.jpg,
// overlay : trajet de balayage projete (polyligne rouge 2px), les 4
// points de calibration ceilL/ceilR/floorL/floorR (croix vertes
// numerotees), et le point d'origine du profil x=0,y=0 (croix bleue).
// Ne modifie AUCUN fichier de production. Sera supprime apres usage.
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

void drawCross(ui.Canvas canvas, ui.Offset center, ui.Color color, {double size = 22, double strokeWidth = 4}) {
  final paint = ui.Paint()
    ..color = color
    ..strokeWidth = strokeWidth
    ..style = ui.PaintingStyle.stroke;
  canvas.drawLine(ui.Offset(center.dx - size, center.dy), ui.Offset(center.dx + size, center.dy), paint);
  canvas.drawLine(ui.Offset(center.dx, center.dy - size), ui.Offset(center.dx, center.dy + size), paint);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('overlay trajet + calibration + origine profil sur haussmann.jpg', () async {
    final projectRoot = Directory.current.path;
    final photoPath = '$projectRoot/assets/demo_scenes/haussmann.jpg';
    final photo = await decodeImageFile(photoPath);
    final imgW = photo.width.toDouble();
    final imgH = photo.height.toDouble();

    final calib = PerspCalib.forDemoScene('haussmann');
    final scene = buildCalibratedScene(calib: calib, imageWidthPx: imgW, imageHeightPx: imgH);

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

    // ⚠️ CORRECTIF (ce tour) : voir _debug_whitebg_overlay_test.dart pour
    // la preuve complète (_debug_origin_vs_path_test.dart, commit 8ba3cef)
    // -- l'ancien calcul `ringsExposed.first[profile.ceilingIndices.first]`
    // pointait sur le sommet d'indice 3 (profil=(112.79,0.0)mm), pas sur
    // l'origine du balayage. L'origine définitionnelle est
    // `pathMeters.first` == `wallOrigin` du premier segment.
    final profileOrigin3D = pathMeters.first;

    final lightDirWorld = vm.Vector3(0.5, 0.7, 0.7);
    const ambient = 0.20;

    // ── Composition : photo + mesh + overlay ──
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      photo,
      ui.Rect.fromLTWH(0, 0, imgW, imgH),
      ui.Rect.fromLTWH(0, 0, imgW, imgH),
      ui.Paint(),
    );
    paintMeshOnCanvas(
      canvas,
      mesh,
      scene.camera,
      baseColor: const ui.Color(0xFFEDEAE4),
      lightDirWorld: lightDirWorld,
      ambient: ambient,
    );

    // 1. Trajet de balayage projete -- polyligne ROUGE 2px (ceilLOnEdge -> ceilROnEdge)
    final pStart = scene.camera.project(scene.ceilLOnEdge).pixel;
    final pEnd = scene.camera.project(scene.ceilROnEdge).pixel;
    canvas.drawLine(
      ui.Offset(pStart.x, pStart.y),
      ui.Offset(pEnd.x, pEnd.y),
      ui.Paint()
        ..color = const ui.Color(0xFFFF0000)
        ..strokeWidth = 2.0,
    );

    // 2. Les 4 points de calibration -- croix VERTES numerotees
    final calibPoints = <String, dynamic>{
      '1.ceilL': calib.ceilL,
      '2.ceilR': calib.ceilR,
      '3.floorL': calib.floorL,
      '4.floorR': calib.floorR,
    };
    final textPainterEntries = <MapEntry<String, ui.Offset>>[];
    for (final entry in calibPoints.entries) {
      final cp = entry.value;
      final px = calibPointToPixels(cp, imageWidthPx: imgW, imageHeightPx: imgH);
      final offset = ui.Offset(px.x, px.y);
      drawCross(canvas, offset, const ui.Color(0xFF00FF00), size: 26, strokeWidth: 5);
      textPainterEntries.add(MapEntry(entry.key, offset));
    }

    // 3. Origine du profil (x=0,y=0) -- croix BLEUE
    final originPx = scene.camera.project(profileOrigin3D).pixel;
    drawCross(canvas, ui.Offset(originPx.x, originPx.y), const ui.Color(0xFF0000FF), size: 26, strokeWidth: 5);

    final picture = recorder.endRecording();
    final fullImage = await picture.toImage(imgW.round(), imgH.round());

    // Labels numeriques (dessines dans une 2e passe car ui.Canvas texte
    // necessite un ParagraphBuilder -- simplifie ici en cercles numerotes
    // deja integres au nom de la croix, pas de police chargee pour ce
    // diagnostic rapide).
    final pngBytesFull = await encodePng(fullImage);
    const outPathFull = '/tmp/step2profile_pilot_test/debug_overlay_full.png';
    final outFileFull = File(outPathFull);
    await outFileFull.parent.create(recursive: true);
    await outFileFull.writeAsBytes(pngBytesFull);

    // Version redimensionnee pour affichage (1400px de large)
    const displayW = 1400.0;
    final scale = displayW / imgW;
    final displayH = imgH * scale;
    final dispRecorder = ui.PictureRecorder();
    final dispCanvas = ui.Canvas(dispRecorder);
    dispCanvas.drawImageRect(
      fullImage,
      ui.Rect.fromLTWH(0, 0, imgW, imgH),
      ui.Rect.fromLTWH(0, 0, displayW, displayH),
      ui.Paint(),
    );
    final dispPicture = dispRecorder.endRecording();
    final dispImage = await dispPicture.toImage(displayW.round(), displayH.round());
    final pngBytesDisp = await encodePng(dispImage);
    const outPathDisp = '/tmp/step2profile_pilot_test/debug_overlay_display.png';
    final outFileDisp = File(outPathDisp);
    await outFileDisp.writeAsBytes(pngBytesDisp);

    // ignore: avoid_print
    print('=== OVERLAY -- coordonnees pixel des elements dessines ===');
    // ignore: avoid_print
    print('Trajet (rouge) : debut=$pStart fin=$pEnd');
    for (final e in textPainterEntries) {
      // ignore: avoid_print
      print('Calib (vert) $e');
    }
    // ignore: avoid_print
    print('Origine profil (bleu) : $originPx  (3D=$profileOrigin3D)');

    // ── Comparaison au "filet" y≈175 -- REFERENCE INFORMELLE/NON VERIFIEE ──
    // (releve visuel de crops anterieurs, PAS une mesure a sortie de
    // commande -- ne doit jamais etre presente comme une valeur "retenue").
    const filetYInformalRef = 175.0;
    final offsetLeft = filetYInformalRef - pStart.y;
    final offsetRight = filetYInformalRef - pEnd.y;
    final delta = offsetRight - offsetLeft;
    // ignore: avoid_print
    print('=== ECART vs filet y=$filetYInformalRef (REFERENCE INFORMELLE, non mesuree par commande -- a ne pas retenir comme valeur finale) ===');
    // ignore: avoid_print
    print('Extremite GAUCHE (pres ceilL, x=${pStart.x}) : trajet.y=${pStart.y}  ecart=$offsetLeft px');
    // ignore: avoid_print
    print('Extremite DROITE (pres ceilR, x=${pEnd.x}) : trajet.y=${pEnd.y}  ecart=$offsetRight px');
    // ignore: avoid_print
    print('Delta (droite - gauche) = $delta px');
    if (delta.abs() < 1e-6) {
      // ignore: avoid_print
      print('=> ECART CONSTANT sur toute la longueur (pas d\'ouverture) : ceilL et ceilR contribuent de facon identique.');
    } else {
      // ignore: avoid_print
      print('=> ECART NON CONSTANT, ouverture de ${delta.abs()} px vers ${delta > 0 ? "la droite (ceilR seul en cause probable)" : "la gauche (ceilL seul en cause probable)"}.');
    }

    // ignore: avoid_print
    print('PNG plein format ecrit: $outPathFull (${pngBytesFull.length} octets)');
    // ignore: avoid_print
    print('PNG affichage ecrit: $outPathDisp (${pngBytesDisp.length} octets)');

    expect(await outFileFull.exists(), isTrue);
  });
}
