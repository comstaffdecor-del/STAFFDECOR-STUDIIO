// Script de diagnostic TEMPORAIRE — PAS commité ce tour. "Banc d'essai" :
// les points de calibration sont des PARAMETRES LOCAUX de ce script (des
// PerspCalib construits ici, jamais lus depuis
// lib/models/persp_calib.dart), pour permettre d'itérer visuellement sur
// un jeu de valeurs AVANT d'en écrire aucune dans le préréglage réel.
//
// Reprend de _debug_room_painter_real_render_test.dart la même technique
// de rendu (PictureRecorder/toByteData PNG, fond blanc) et le même trace
// filaire (quad mur du fond en rouge, aretes laterales en bleu, croix
// verte au point de fuite, coins numérotés 1-4) — mais avec `calib`
// injecté en paramètre au lieu de PerspCalib.forDemoScene('haussmann').
//
// Un seul jeu de valeurs testé ce tour ("candidat n°1"), issu de mesures
// pixel objectives (numpy, citées dans la réponse) sur assets/demo_scenes
// /haussmann.jpg — PAS d'une lecture visuelle approximative de grille.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/calib_canvas.dart';
import 'package:staff_decor_studio/core/perspective/room_painter.dart';
import 'package:staff_decor_studio/core/perspective/vanishing_point.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

const double kCanvasW = 1400.0;

Future<Uint8List> encodePng(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
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

Future<void> renderWireframeCandidate({
  required ui.Image roomImage,
  required ImgDraw imgDraw,
  required PerspCalib calib,
  required Size size,
  required String outPath,
  required String candidateLabel,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFFFFFFFF));

  final noProductPainter = RoomPainter(
    roomImage: roomImage,
    imgDraw: imgDraw,
    calib: calib,
    selectedProducts: const [],
    prodPositions: const {},
    metresHauteur: 2.5,
  );
  noProductPainter.paint(canvas, size);

  final cp = CalibCanvasPoints.fromCalib(calib, imgDraw: imgDraw, w: size.width, h: size.height);
  final vp = VanishingPoint.compute(fTL: cp.ceilL, fTR: cp.ceilR, fBL: cp.floorL, fBR: cp.floorR);

  final fondPath = Path()
    ..moveTo(cp.ceilL.dx, cp.ceilL.dy)
    ..lineTo(cp.ceilR.dx, cp.ceilR.dy)
    ..lineTo(cp.floorR.dx, cp.floorR.dy)
    ..lineTo(cp.floorL.dx, cp.floorL.dy)
    ..close();
  canvas.drawPath(
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
  canvas.drawLine(cp.ceilL, cp.wallTL, latPaint);
  canvas.drawLine(cp.ceilR, cp.wallTR, latPaint);
  canvas.drawLine(cp.floorL, cp.wallBL, latPaint);
  canvas.drawLine(cp.floorR, cp.wallBR, latPaint);

  drawCross(canvas, vp.vp, const Color(0xFF00CC00));

  // ⚠️ CORRECTION ce tour (itération moderne) : les labels texte '1'..'4'
  // et le titre candidateLabel s'affichaient en glyphes "tofu"
  // (rectangles noir/blanc) dans l'environnement `flutter test` headless
  // (pas de police système chargée) — masquant precisement la ligne
  // plafond/mur (ceilL/ceilR) qu'il fallait inspecter. Remplacés par de
  // simples points pleins (pas de texte, pas de dépendance police), et le
  // titre déplacé en bas de canevas, hors de la zone d'évaluation.
  void dot(Offset p, Color c) => canvas.drawCircle(p, 7, Paint()..color = c);
  dot(cp.ceilL, const Color(0xFFFF0000));
  dot(cp.ceilR, const Color(0xFFFF0000));
  dot(cp.floorR, const Color(0xFFFF0000));
  dot(cp.floorL, const Color(0xFFFF0000));

  drawLabel(canvas, candidateLabel, Offset(20, size.height - 34), const Color(0xFF000000));

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  final bytes = await encodePng(image);
  File(outPath).writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('Ecrit ($candidateLabel): $outPath (${bytes.length} octets)');
  // ignore: avoid_print
  print(
    '  ceilL=(${cp.ceilL.dx.toStringAsFixed(1)},${cp.ceilL.dy.toStringAsFixed(1)}) '
    'ceilR=(${cp.ceilR.dx.toStringAsFixed(1)},${cp.ceilR.dy.toStringAsFixed(1)}) '
    'floorL=(${cp.floorL.dx.toStringAsFixed(1)},${cp.floorL.dy.toStringAsFixed(1)}) '
    'floorR=(${cp.floorR.dx.toStringAsFixed(1)},${cp.floorR.dy.toStringAsFixed(1)})',
  );
  // ignore: avoid_print
  print('  vp=(${vp.vp.dx.toStringAsFixed(1)},${vp.vp.dy.toStringAsFixed(1)})  pH=${vp.pH.toStringAsFixed(1)}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('banc d\'essai (non commité) : candidat n°1 de calibration haussmann', () async {
    final projectRoot = Directory.current.path;
    final photoPath = '$projectRoot/assets/demo_scenes/haussmann.jpg';
    final bytes = await File(photoPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final roomImage = frame.image;

    final srcW = roomImage.width.toDouble();
    final srcH = roomImage.height.toDouble();
    final canvasH = kCanvasW * srcH / srcW;
    final size = Size(kCanvasW, canvasH);
    final imgDraw = ImgDraw(dx: 0, dy: 0, dw: kCanvasW, dh: canvasH, scale: kCanvasW / srcW);

    Directory('/tmp/diag_room_painter').createSync(recursive: true);

    // ── CANDIDAT n°1 ──
    // Bornes latérales du mur du fond (lambris à miroir ENTRE les deux
    // portes vitrées) : mesurées par analyse pixel objective (numpy,
    // écart-type de luminance colonne par colonne, seuil de saut de
    // texture) sur haussmann.jpg — valeurs citées dans la réponse :
    //   bord gauche (porte -> lambris)  : x ≈ 14%
    //   bord droit  (lambris -> 2e porte): x ≈ 53%
    // Ligne plafond (bas de la gorge moulurée) : mesurée de la même
    // façon, écart-type de luminance par ligne sur bandes de mur propre :
    //   x=16-22% (près bord gauche) -> y ≈ 6.39%
    //   x=46-52% (près bord droit)  -> y ≈ 6.45%
    //   quasi identiques -> ligne plafond quasi horizontale ici (mesure,
    //   pas supposition).
    // Ligne sol : NON mesurée par pixel — la jonction réelle sol/mur est
    // OCCULTÉE par le canapé sur toute la largeur du mur du fond visible.
    // Valeur ci-dessous = ESTIMATION DE PREMIER JET (non mesurée),
    // explicitement signalée comme telle, à corriger par l'itération
    // visuelle demandée.
    const candidate1 = PerspCalib(
      ceilL: CalibPoint(xPct: 0.14, yPct: 0.064),
      ceilR: CalibPoint(xPct: 0.53, yPct: 0.065),
      floorL: CalibPoint(xPct: 0.14, yPct: 0.75), // ESTIMATION non mesurée
      floorR: CalibPoint(xPct: 0.53, yPct: 0.75), // ESTIMATION non mesurée
      wallTL: CalibPoint(xPct: 0.00, yPct: 0.08),
      wallTR: CalibPoint(xPct: 1.00, yPct: 0.08),
      wallBL: CalibPoint(xPct: 0.00, yPct: 0.92),
      wallBR: CalibPoint(xPct: 1.00, yPct: 0.92),
    );

    await renderWireframeCandidate(
      roomImage: roomImage,
      imgDraw: imgDraw,
      calib: candidate1,
      size: size,
      outPath: '/tmp/diag_room_painter/wireframe_candidat1.png',
      candidateLabel: 'CANDIDAT 1',
    );
  });

  test('banc d\'essai (non commité) : moderne.jpg — itération 1', () async {
    final projectRoot = Directory.current.path;
    final photoPath = '$projectRoot/assets/demo_scenes/moderne.jpg';
    final bytes = await File(photoPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final roomImage = frame.image;

    // Canvas RÉEL de la scène (1400x975), letterboxing RÉEL calculé au
    // point 2 de ce tour via la formule exacte de computeImgDraw
    // (lib/state/app_state.dart) : scale=min(1400/1960, 975/1470)=0.66327,
    // dw=1960*0.66327=1300.00, dh=1470*0.66327=975.00,
    // dx=(1400-1300)/2=50.00, dy=(975-975)/2=0.00 — PAS le raccourci
    // dx=0,dy=0 du candidat haussmann : la logique de letterboxing est ici
    // délibérément exercée (Réserve 2).
    const size = Size(1400.0, 975.0);
    const imgDraw = ImgDraw(dx: 50.0, dy: 0.0, dw: 1300.0, dh: 975.0, scale: 0.66327);

    Directory('/tmp/diag_room_painter').createSync(recursive: true);

    // ── ITERATION 1 — placée à l'œil sur assets/demo_scenes/moderne.jpg,
    // à partir de la reconnaissance de ce tour :
    //   - ligne plafond/mur mesurée (gradient luminance, zones de mur
    //     propres hors poutres/fenêtres) : y≈2.7-2.9% → arrondi 0.028.
    //   - bornes latérales du mur du fond estimées à l'œil sur la grille :
    //     gauche x≈6% (après la poutre en biais visible en haut-gauche),
    //     droite x≈88% (avant le rideau qui débute vers x≈89-90%).
    //   - ligne sol NON mesurée : jonction sol/mur occultée par canapé +
    //     fauteuils + table basse sur toute la largeur → ESTIMATION.
    const candidateModerneIt1 = PerspCalib(
      ceilL: CalibPoint(xPct: 0.06, yPct: 0.028),
      ceilR: CalibPoint(xPct: 0.88, yPct: 0.028),
      floorL: CalibPoint(xPct: 0.06, yPct: 0.90), // ESTIMATION non mesurée
      floorR: CalibPoint(xPct: 0.88, yPct: 0.90), // ESTIMATION non mesurée
      wallTL: CalibPoint(xPct: 0.00, yPct: 0.02),
      wallTR: CalibPoint(xPct: 1.00, yPct: 0.02),
      wallBL: CalibPoint(xPct: 0.00, yPct: 0.95),
      wallBR: CalibPoint(xPct: 1.00, yPct: 0.95),
    );

    await renderWireframeCandidate(
      roomImage: roomImage,
      imgDraw: imgDraw,
      calib: candidateModerneIt1,
      size: size,
      outPath: '/tmp/diag_room_painter/wireframe_moderne_it1.png',
      candidateLabel: 'MODERNE - ITERATION 1',
    );
  });
}
