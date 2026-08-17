// Script de diagnostic TEMPORAIRE — PAS commité ce tour. Zoom cible sur
// la base du canapé (pieds metalliques fins), pour reperer visuellement
// les intervalles entre pieds ou le parquet est visible en fines tranches,
// avant mesure par ecart-type de luminance (meme critere que pour la
// gorge moulurée).
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
  double zoomFactor,
  String label,
  String outPath,
) async {
  final outW = cropCanvasRect.width * zoomFactor;
  final outH = cropCanvasRect.height * zoomFactor;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  final srcW = roomImage.width.toDouble();
  final scale = kCanvasW / srcW;
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

  test('diagnostic (non commité) : zoom base du canape (pieds/sol)', () async {
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

    // Base du canape pleine largeur du mur du fond retenu (x 10%-56%),
    // bande y 58%-84% : couvre l'assise basse, les pieds, et le sol
    // visible en dessous si les pieds sont assez fins/espaces.
    await renderZoom(
      roomImage,
      canvasH,
      Rect.fromLTWH(kCanvasW * 0.10, canvasH * 0.58, kCanvasW * 0.46, canvasH * 0.26),
      3.0,
      'base canape pleine largeur mur du fond',
      '/tmp/diag_room_painter/zoom_base_canape.png',
    );
  });
}
