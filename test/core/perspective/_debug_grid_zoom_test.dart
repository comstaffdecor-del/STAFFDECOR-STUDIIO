// Script de diagnostic TEMPORAIRE — PAS commité ce tour. Produit 4 crops
// zoomés (coins haut-gauche, haut-droit, bas-gauche, bas-droit) de
// haussmann.jpg avec grille fine 2%/10%, pour pointer des repères
// précis avant de proposer un jeu de calibration. Complément du script
// _debug_grid_reference_test.dart (grille pleine image, labels illisibles
// en bord de cadre à cette résolution).
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> encodePng(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

const double kCanvasW = 1400.0;

Future<void> renderZoom(
  ui.Image roomImage,
  double canvasH,
  Rect cropCanvasRect,
  String label,
  String outPath,
) async {
  const zoomFactor = 3.0;
  final outW = cropCanvasRect.width * zoomFactor;
  final outH = cropCanvasRect.height * zoomFactor;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final srcW = roomImage.width.toDouble();
  final srcH = roomImage.height.toDouble();
  final scale = kCanvasW / srcW;
  // Rect en coordonnées image source correspondant au crop en coordonnées canvas.
  final srcRect = Rect.fromLTWH(
    cropCanvasRect.left / scale,
    cropCanvasRect.top / scale,
    cropCanvasRect.width / scale,
    cropCanvasRect.height / scale,
  );
  canvas.drawImageRect(roomImage, srcRect, Rect.fromLTWH(0, 0, outW, outH), Paint());

  final minorPaint = Paint()
    ..color = const Color(0x60FFFFFF)
    ..strokeWidth = 1;
  final majorPaint = Paint()
    ..color = const Color(0xE000FFFF)
    ..strokeWidth = 2;

  // Grille en % de la LARGEUR/HAUTEUR TOTALE du canvas 1400x(canvasH),
  // pas du crop — pour lire directement des xPct/yPct globaux.
  for (var pct = 0; pct <= 100; pct++) {
    final xGlobal = kCanvasW * pct / 100.0;
    if (xGlobal < cropCanvasRect.left || xGlobal > cropCanvasRect.right) continue;
    final xLocal = (xGlobal - cropCanvasRect.left) * zoomFactor;
    final isMajor = pct % 2 == 0;
    canvas.drawLine(Offset(xLocal, 0), Offset(xLocal, outH), isMajor ? majorPaint : minorPaint);
    if (pct % 2 == 0) {
      final tp = TextPainter(
        text: TextSpan(
          text: '$pct%',
          style: const TextStyle(color: Color(0xFF00FFFF), fontSize: 14, backgroundColor: Color(0xD0000000)),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(xLocal + 2, 2));
    }
  }
  for (var pct = 0; pct <= 100; pct++) {
    final yGlobal = canvasH * pct / 100.0;
    if (yGlobal < cropCanvasRect.top || yGlobal > cropCanvasRect.bottom) continue;
    final yLocal = (yGlobal - cropCanvasRect.top) * zoomFactor;
    final isMajor = pct % 2 == 0;
    canvas.drawLine(Offset(0, yLocal), Offset(outW, yLocal), isMajor ? majorPaint : minorPaint);
    if (pct % 2 == 0) {
      final tp = TextPainter(
        text: TextSpan(
          text: '$pct%',
          style: const TextStyle(color: Color(0xFF00FFFF), fontSize: 14, backgroundColor: Color(0xD0000000)),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(2, yLocal + 14));
    }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(outW.round(), outH.round());
  final bytes = await encodePng(image);
  File(outPath).writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('Ecrit ($label): $outPath (${bytes.length} octets, ${outW.round()}x${outH.round()})');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('diagnostic (non commité) : crops zoomes grille fine 2%% sur haussmann.jpg', () async {
    final projectRoot = Directory.current.path;
    final photoPath = '$projectRoot/assets/demo_scenes/haussmann.jpg';
    final bytes = await File(photoPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final roomImage = frame.image;

    final srcH = roomImage.height.toDouble();
    final srcW = roomImage.width.toDouble();
    final canvasH = kCanvasW * srcH / srcW;

    Directory('/tmp/diag_room_painter').createSync(recursive: true);

    // Zone plafond/mur du fond (mur miroir), x 0-70%, y 0-30% : couvre le
    // panneau lambrissé du fond avec le miroir et sa jonction plafond.
    await renderZoom(
      roomImage,
      canvasH,
      Rect.fromLTWH(0, 0, kCanvasW * 0.70, canvasH * 0.30),
      'plafond+mur-fond gauche',
      '/tmp/diag_room_painter/zoom_haut_gauche.png',
    );

    // Zone porte vitree droite (limite du mur du fond a droite), x 45-100%, y 0-30%.
    await renderZoom(
      roomImage,
      canvasH,
      Rect.fromLTWH(kCanvasW * 0.45, 0, kCanvasW * 0.55, canvasH * 0.30),
      'porte vitree droite + limite mur fond',
      '/tmp/diag_room_painter/zoom_haut_droit.png',
    );

    // Zone sol derriere canape, x 0-70%, y 55-90%.
    await renderZoom(
      roomImage,
      canvasH,
      Rect.fromLTWH(0, canvasH * 0.55, kCanvasW * 0.70, canvasH * 0.35),
      'sol derriere canape gauche',
      '/tmp/diag_room_painter/zoom_bas_gauche.png',
    );

    // Zone sol/porte vitree droite, x 45-100%, y 55-90%.
    await renderZoom(
      roomImage,
      canvasH,
      Rect.fromLTWH(kCanvasW * 0.45, canvasH * 0.55, kCanvasW * 0.55, canvasH * 0.35),
      'sol derriere canape / porte vitree droite',
      '/tmp/diag_room_painter/zoom_bas_droit.png',
    );
  });
}
