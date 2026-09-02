// Script de diagnostic TEMPORAIRE — PAS commité ce tour (consigne
// explicite, tour de MESURE uniquement : aucune correction lib/, aucun
// commit, aucune sonde git, aucun refactor, aucun fichier nouveau).
//
// Instrumente le script existant (inchangé dans son principe depuis sa
// première version) pour répondre à UNE seule question avant de toucher
// au rendu : le filaire de calibration se pose-t-il sur les arêtes
// réelles de la photo, ou non ? Deux issues opposées, deux corrections
// opposées — d'où l'exigence de mesurer avant de choisir.
//
// Reprend de test/core/geometry/_debug_whitebg_overlay_test.dart
// (0deed35) UNIQUEMENT la technique de capture PNG (PictureRecorder,
// toByteData(ImageByteFormat.png), fond blanc) — rien de ses entrées
// (caméra/sweep/profil), déjà écarté au tour précédent.
//
// ⚠️ AVERTISSEMENT DE FIDÉLITÉ — à lire avant d'interpréter le bloc 4 :
// `paintCorniceSet`/`paintPlintheSet` (cornice_plinth_painter.dart)
// n'exposent PAS leurs points d'onglet intermédiaires (ongletL/ongletR,
// variables locales privées à la fonction). Pour imprimer "les quatre
// sommets du quadrilatère effectivement passés au tracé" sans modifier
// lib/, ce script RÉPLIQUE ce calcul en dehors de la fonction, avec les
// MÊMES primitives PUBLIQUES (perpDown/perpUp/lineIntersect/dist,
// persp_geometry.dart) et une copie du seuil et de la formule PRIVÉS
// `_cornerSharpness`/`_kFlatCornerThreshold` (cornice_plinth_painter.dart
// lignes 50-58 et 62, recopiées ici à l'identique, citées explicitement).
// Cette réplication n'est PAS un appel direct à la fonction réelle : sa
// fidélité repose sur la correspondance textuelle avec le code source
// cité, pas sur une garantie d'exécution partagée. Les blocs 1, 2 et 3
// n'ont PAS ce problème : ce sont des appels DIRECTS aux mêmes fonctions
// PUBLIQUES (`CalibCanvasPoints.fromCalib`, `VanishingPoint.compute`)
// que `RoomPainter.paint()` appelle en interne (room_painter.dart lignes
// 136-143), avec les mêmes arguments (même calib, même imgDraw, même
// size) — les valeurs imprimées sont donc numériquement identiques à ce
// que `RoomPainter.paint()` calcule réellement, par déterminisme pur.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/calib_canvas.dart';
import 'package:staff_decor_studio/core/perspective/cornice_plinth_painter.dart';
import 'package:staff_decor_studio/core/perspective/persp_geometry.dart';
import 'package:staff_decor_studio/core/perspective/profile_dims_cache.dart';
import 'package:staff_decor_studio/core/perspective/room_painter.dart';
import 'package:staff_decor_studio/core/perspective/strip_px_from_dims.dart';
import 'package:staff_decor_studio/core/perspective/vanishing_point.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';
import 'package:staff_decor_studio/models/project_item.dart';

const double kCanvasW = 1400.0;

Future<Uint8List> encodePng(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// Réplique EXACTE (recopiée, citée) de `_cornerSharpness`
/// (cornice_plinth_painter.dart lignes 50-58) — fonction privée, non
/// exportée, donc non appelable directement depuis ce fichier de test.
double replicatedCornerSharpness(Offset a, Offset b, Offset c) {
  final v1x = b.dx - a.dx, v1y = b.dy - a.dy;
  final v2x = c.dx - b.dx, v2y = c.dy - b.dy;
  final l1 = dist(a, b), l2 = dist(b, c);
  if (l1 < 0.001 || l2 < 0.001) return 0.0;
  final cross = (v1x * v2y - v1y * v2x).abs();
  return cross / (l1 * l2);
}

/// Réplique du seuil `_kFlatCornerThreshold` (cornice_plinth_painter.dart
/// ligne 62).
const double kFlatCornerThresholdReplicated = 0.12;

String boundsStatus(Offset p, double w, double h) {
  final xOut = p.dx < 0 || p.dx > w;
  final yOut = p.dy < 0 || p.dy > h;
  if (!xOut && !yOut) {
    return 'DANS les bornes [0,${w.round()}]x[0,${h.round()}]';
  }
  final parts = <String>[];
  if (xOut) {
    final over = p.dx < 0 ? -p.dx : p.dx - w;
    parts.add('x hors bornes de ${over.toStringAsFixed(1)}px');
  }
  if (yOut) {
    final over = p.dy < 0 ? -p.dy : p.dy - h;
    parts.add('y hors bornes de ${over.toStringAsFixed(1)}px');
  }
  return 'HORS BORNES (${parts.join(', ')})';
}

void printPoint(String label, Offset p, double w, double h) {
  // ignore: avoid_print
  print(
    '  $label: (${p.dx.toStringAsFixed(2)}, ${p.dy.toStringAsFixed(2)}) — ${boundsStatus(p, w, h)}',
  );
}

Future<void> waitForProfileDims(String ref) async {
  if (ProfileDimsCache.instance.getIfLoaded(ref) != null ||
      ProfileDimsCache.instance.hasFailed(ref)) {
    return;
  }
  final completer = Completer<void>();
  void cb() {
    if (ProfileDimsCache.instance.getIfLoaded(ref) != null ||
        ProfileDimsCache.instance.hasFailed(ref)) {
      if (!completer.isCompleted) completer.complete();
    }
  }

  ProfileDimsCache.instance.addListener(cb);
  ProfileDimsCache.instance.ensureLoading(ref);
  await completer.future.timeout(const Duration(seconds: 5));
  ProfileDimsCache.instance.removeListener(cb);
}

Future<void> renderAndSave(RoomPainter painter, Size size, String outPath) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.width, size.height),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  final bytes = await encodePng(image);
  File(outPath).writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('Ecrit: $outPath (${bytes.length} octets, ${size.width.round()}x${size.height.round()})');
}

void drawCross(Canvas canvas, Offset center, Color color, {double size = 22, double strokeWidth = 4}) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = strokeWidth
    ..style = PaintingStyle.stroke;
  canvas.drawLine(Offset(center.dx - size, center.dy), Offset(center.dx + size, center.dy), paint);
  canvas.drawLine(Offset(center.dx, center.dy - size), Offset(center.dx, center.dy + size), paint);
}

void drawLabel(Canvas canvas, String text, Offset pos, Color color) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: 30,
        fontWeight: FontWeight.bold,
        backgroundColor: const Color(0xFFFFFFFF),
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  tp.layout();
  tp.paint(canvas, pos);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'diagnostic (non commité) : imprime imgDraw/calib/VP/quads reels + filaire seul',
    () async {
      final projectRoot = Directory.current.path;
      final photoPath = '$projectRoot/assets/demo_scenes/haussmann.jpg';
      final photoFile = File(photoPath);
      expect(photoFile.existsSync(), isTrue, reason: 'Scene demo reelle introuvable: $photoPath');

      final bytes = await photoFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final roomImage = frame.image;

      final srcW = roomImage.width.toDouble();
      final srcH = roomImage.height.toDouble();
      // ignore: avoid_print
      print('Photo haussmann.jpg decodee: ${srcW.round()}x${srcH.round()}');

      const canvasW = kCanvasW;
      final canvasH = canvasW * srcH / srcW;
      final size = Size(canvasW, canvasH);
      final imgDraw = ImgDraw(dx: 0, dy: 0, dw: canvasW, dh: canvasH, scale: canvasW / srcW);

      final calib = PerspCalib.forDemoScene('haussmann');
      expect(
        identical(calib, PerspCalib.demoPresets['haussmann']),
        isTrue,
        reason: "PerspCalib.forDemoScene('haussmann') doit renvoyer l'entree demoPresets reelle.",
      );

      const metresHauteur = 2.5;

      // ── BLOC 1 : imgDraw ──
      // ignore: avoid_print
      print('\n=== BLOC 1 : imgDraw ===');
      // ignore: avoid_print
      print(
        '  dx=${imgDraw.dx.toStringAsFixed(2)}  dy=${imgDraw.dy.toStringAsFixed(2)}  '
        'dw=${imgDraw.dw.toStringAsFixed(2)}  dh=${imgDraw.dh.toStringAsFixed(2)}  '
        'scale=${imgDraw.scale.toStringAsFixed(6)}',
      );

      // ── Appel PUBLIC direct, identique room_painter.dart:136 ──
      final cp = CalibCanvasPoints.fromCalib(calib, imgDraw: imgDraw, w: size.width, h: size.height);

      // ── BLOC 2 : les 4 coins du mur du fond (coords canvas) ──
      // ignore: avoid_print
      print('\n=== BLOC 2 : mur du fond (CalibCanvasPoints.fromCalib) ===');
      printPoint('ceilL', cp.ceilL, size.width, size.height);
      printPoint('ceilR', cp.ceilR, size.width, size.height);
      printPoint('floorL', cp.floorL, size.width, size.height);
      printPoint('floorR', cp.floorR, size.width, size.height);

      // ── Appel PUBLIC direct, identique room_painter.dart:137-142 ──
      final vp = VanishingPoint.compute(
        fTL: cp.ceilL,
        fTR: cp.ceilR,
        fBL: cp.floorL,
        fBR: cp.floorR,
        wallTL: cp.wallTL,
        wallTR: cp.wallTR,
        wallBL: cp.wallBL,
        wallBR: cp.wallBR,
        fallbackMode: VpFallbackMode.repliHistoriqueCoupleBas,
      );
      final pH = vp.pH;

      // ── BLOC 3 : point de fuite ──
      // ignore: avoid_print
      print('\n=== BLOC 3 : point de fuite (VanishingPoint.compute) ===');
      printPoint('vp', vp.vp, size.width, size.height);
      // ignore: avoid_print
      print('  (pour reference, non demande explicitement) pH = ${pH.toStringAsFixed(2)}');

      ProfileDimsCache.instance.resetForTesting();

      // ── Corniche D720 : th reel via corniceFor (appel PUBLIC, identique
      //    room_painter.dart:208-225). ──
      await waitForProfileDims('D720');
      final d720Dims = ProfileDimsCache.instance.getIfLoaded('D720');
      expect(d720Dims, isNotNull, reason: 'D720 doit resoudre avant capture.');
      final stripPx = stripPxFromDims(
        pH: pH,
        metresHauteur: metresHauteur,
        retombeeMm: d720Dims!.retombeeMm,
        projectionMm: d720Dims.projectionMm,
      );
      final thCornice = corniceFor(stripPx, pH);

      // ── REPLICATION (voir avertissement en tete de fichier) du calcul
      //    d'onglet du segment FOND de paintCorniceSet
      //    (cornice_plinth_painter.dart lignes 156-210). ──
      final corniceFTL = cp.ceilL, corniceFTR = cp.ceilR;
      final corniceWallTL = cp.wallTL, corniceWallTR = cp.wallTR;
      final corniceHasLatG = dist(corniceFTL, corniceWallTL) > 8;
      final corniceHasLatD = dist(corniceWallTR, corniceFTR) > 8;
      final corniceDpFond = perpDown(corniceFTL, corniceFTR, thCornice.faceMurFond);
      final corniceFTLbF = corniceFTL + corniceDpFond;
      final corniceFTRbF = corniceFTR + corniceDpFond;
      var corniceOngletL = corniceFTLbF;
      var corniceOngletR = corniceFTRbF;
      if (corniceHasLatG) {
        final sharp = replicatedCornerSharpness(corniceWallTL, corniceFTL, corniceFTR);
        final isFlat = sharp < kFlatCornerThresholdReplicated;
        final latThick = isFlat ? thCornice.faceMurFond : thCornice.faceMurLat;
        final dpLatG = perpDown(corniceWallTL, corniceFTL, latThick);
        final fTLbG = corniceFTL + dpLatG;
        final wallTLb = corniceWallTL + dpLatG;
        corniceOngletL = !isFlat
            ? (lineIntersect(wallTLb, fTLbG, corniceFTLbF, corniceFTRbF) ?? corniceFTLbF)
            : corniceFTLbF;
      }
      if (corniceHasLatD) {
        final sharp = replicatedCornerSharpness(corniceFTL, corniceFTR, corniceWallTR);
        final isFlat = sharp < kFlatCornerThresholdReplicated;
        final latThick = isFlat ? thCornice.faceMurFond : thCornice.faceMurLat;
        final dpLatD = perpDown(corniceFTR, corniceWallTR, latThick);
        final fTRbD = corniceFTR + dpLatD;
        final wallTRb = corniceWallTR + dpLatD;
        corniceOngletR = !isFlat
            ? (lineIntersect(corniceFTLbF, corniceFTRbF, fTRbD, wallTRb) ?? corniceFTRbF)
            : corniceFTRbF;
      }

      // ── Plinthe PLIN08 : th = plintheDefault (appel PUBLIC, identique
      //    room_painter.dart:239). ──
      final thPlinthe = StripThickness.plintheDefault(pH);
      final plintheFBL = cp.floorL, plintheFBR = cp.floorR;
      final plintheWallBL = cp.wallBL, plintheWallBR = cp.wallBR;
      final plintheHasLatG = dist(plintheFBL, plintheWallBL) > 8;
      final plintheHasLatD = dist(plintheWallBR, plintheFBR) > 8;
      final plintheUpFond = perpUp(plintheFBL, plintheFBR, thPlinthe.faceMurFond);
      final plintheFBLtF = plintheFBL + plintheUpFond;
      final plintheFBRtF = plintheFBR + plintheUpFond;
      var plintheOngletL = plintheFBLtF;
      var plintheOngletR = plintheFBRtF;
      if (plintheHasLatG) {
        final sharp = replicatedCornerSharpness(plintheWallBL, plintheFBL, plintheFBR);
        final isFlat = sharp < kFlatCornerThresholdReplicated;
        final latThick = isFlat ? thPlinthe.faceMurFond : thPlinthe.faceMurLat;
        final upLatG = perpUp(plintheWallBL, plintheFBL, latThick);
        final fBLtG = plintheFBL + upLatG;
        final wallBLt = plintheWallBL + upLatG;
        plintheOngletL = !isFlat
            ? (lineIntersect(wallBLt, fBLtG, plintheFBLtF, plintheFBRtF) ?? plintheFBLtF)
            : plintheFBLtF;
      }
      if (plintheHasLatD) {
        final sharp = replicatedCornerSharpness(plintheFBL, plintheFBR, plintheWallBR);
        final isFlat = sharp < kFlatCornerThresholdReplicated;
        final latThick = isFlat ? thPlinthe.faceMurFond : thPlinthe.faceMurLat;
        final upLatD = perpUp(plintheFBR, plintheWallBR, latThick);
        final fBRtD = plintheFBR + upLatD;
        final wallBRt = plintheWallBR + upLatD;
        plintheOngletR = !isFlat
            ? (lineIntersect(plintheFBLtF, plintheFBRtF, fBRtD, wallBRt) ?? plintheFBRtF)
            : plintheFBRtF;
      }

      // ── BLOC 4 : quadrilateres FOND effectivement passes a
      //    _drawCorniceStrip/_drawPlinthStrip (voir avertissement de
      //    fidelite en tete de fichier — REPLICATION pour ongletL/R). ──
      // ignore: avoid_print
      print(
        '\n=== BLOC 4 : quadrilatere corniche (segment FOND, ordre topA,topB,botA,botB) ===\n'
        '  [REPLICATION du calcul d\'onglet — voir avertissement en tete de fichier]',
      );
      printPoint('topA (=fTL=ceilL)', corniceFTL, size.width, size.height);
      printPoint('topB (=fTR=ceilR)', corniceFTR, size.width, size.height);
      printPoint('botA (=ongletL)', corniceOngletL, size.width, size.height);
      printPoint('botB (=ongletR)', corniceOngletR, size.width, size.height);

      // ignore: avoid_print
      print(
        '\n=== BLOC 4 (suite) : quadrilatere plinthe (segment FOND, ordre topA,topB,botA,botB) ===\n'
        '  [REPLICATION du calcul d\'onglet — voir avertissement en tete de fichier]',
      );
      printPoint('topA (=ongletL)', plintheOngletL, size.width, size.height);
      printPoint('topB (=ongletR)', plintheOngletR, size.width, size.height);
      printPoint('botA (=fBL=floorL)', plintheFBL, size.width, size.height);
      printPoint('botB (=fBR=floorR)', plintheFBR, size.width, size.height);

      Directory('/tmp/diag_room_painter').createSync(recursive: true);

      // ── Rendus produit (INCHANGES dans leur principe — RoomPainter.paint()
      //    reel, recalcule en interne cp/vp/th de facon deterministe et
      //    identique aux blocs imprimes ci-dessus). ──
      const corniceItem = ProjectItem(ref: 'D720', famille: 'Corniches', qte: 2.0, unite: 'ml');
      final corniceePainter = RoomPainter(
        roomImage: roomImage,
        imgDraw: imgDraw,
        calib: calib,
        selectedProducts: const [corniceItem],
        prodPositions: const {},
        metresHauteur: metresHauteur,
      );
      await renderAndSave(corniceePainter, size, '/tmp/diag_room_painter/cornice_d720.png');

      const plintheItem = ProjectItem(ref: 'PLIN08', famille: 'Plinthes', qte: 2.0, unite: 'ml');
      final plinthePainter = RoomPainter(
        roomImage: roomImage,
        imgDraw: imgDraw,
        calib: calib,
        selectedProducts: const [plintheItem],
        prodPositions: const {},
        metresHauteur: metresHauteur,
      );
      await renderAndSave(plinthePainter, size, '/tmp/diag_room_painter/plinthe_plin08.png');

      // ── Image supplementaire UNIQUE : filaire de calibration seul, sans
      //    aucun produit. Photo dessinee via RoomPainter reel avec
      //    selectedProducts vide (room_painter.dart:133 -> return avant
      //    tout produit, chemin PUBLIC reel, pas de reimplementation du
      //    drawImageRect). Aucun produit => aucune texture en jeu => la
      //    consigne "repli de texture en gris plat" n'a aucun terrain
      //    d'application dans cette image precise (constat neutre, pas
      //    une omission). ──
      final wireframeRecorder = ui.PictureRecorder();
      final wireframeCanvas = Canvas(wireframeRecorder);
      wireframeCanvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      final noProductPainter = RoomPainter(
        roomImage: roomImage,
        imgDraw: imgDraw,
        calib: calib,
        selectedProducts: const [],
        prodPositions: const {},
        metresHauteur: metresHauteur,
      );
      noProductPainter.paint(wireframeCanvas, size);

      // Quadrilatere mur du fond : numerotation arbitraire mais explicite
      // 1=ceilL, 2=ceilR, 3=floorR, 4=floorL (sens horaire depuis le coin
      // haut-gauche) — choix documente ici, pas implicite.
      final fondPath = Path()
        ..moveTo(cp.ceilL.dx, cp.ceilL.dy)
        ..lineTo(cp.ceilR.dx, cp.ceilR.dy)
        ..lineTo(cp.floorR.dx, cp.floorR.dy)
        ..lineTo(cp.floorL.dx, cp.floorL.dy)
        ..close();
      wireframeCanvas.drawPath(
        fondPath,
        Paint()
          ..color = const Color(0xFFFF0000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );

      final latPaint = Paint()
        ..color = const Color(0xFF0000FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      wireframeCanvas.drawLine(cp.ceilL, cp.wallTL, latPaint);
      wireframeCanvas.drawLine(cp.ceilR, cp.wallTR, latPaint);
      wireframeCanvas.drawLine(cp.floorL, cp.wallBL, latPaint);
      wireframeCanvas.drawLine(cp.floorR, cp.wallBR, latPaint);

      drawCross(wireframeCanvas, vp.vp, const Color(0xFF00CC00));

      drawLabel(wireframeCanvas, '1', cp.ceilL + const Offset(8, -34), const Color(0xFFFF0000));
      drawLabel(wireframeCanvas, '2', cp.ceilR + const Offset(8, -34), const Color(0xFFFF0000));
      drawLabel(wireframeCanvas, '3', cp.floorR + const Offset(8, 4), const Color(0xFFFF0000));
      drawLabel(wireframeCanvas, '4', cp.floorL + const Offset(8, 4), const Color(0xFFFF0000));

      final wireframePicture = wireframeRecorder.endRecording();
      final wireframeImage = await wireframePicture.toImage(
        size.width.round(),
        size.height.round(),
      );
      final wireframeBytes = await encodePng(wireframeImage);
      File('/tmp/diag_room_painter/wireframe_haussmann.png').writeAsBytesSync(wireframeBytes);
      // ignore: avoid_print
      print(
        '\nEcrit: /tmp/diag_room_painter/wireframe_haussmann.png '
        '(${wireframeBytes.length} octets, ${size.width.round()}x${size.height.round()})',
      );
    },
  );
}
