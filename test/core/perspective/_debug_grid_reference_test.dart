// Script de diagnostic TEMPORAIRE — PAS commité ce tour. Produit UNE
// image : la photo haussmann.jpg brute + une grille de repérage 5%/10%
// (méthode citée dans persp_calib.dart, docstring de demoPresets :
// "grilles de repérage 1%/5%/10% superposées"), pour lire des
// pourcentages par pointage visuel avant de proposer un nouveau jeu de
// calibration. Ne dessine aucun filaire de calibration existant, aucun
// produit — juste la grille, pour ne rien présupposer.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('diagnostic (non commité) : grille de reperage 5%/10% sur haussmann.jpg', () async {
    final projectRoot = Directory.current.path;
    final photoPath = '$projectRoot/assets/demo_scenes/haussmann.jpg';
    final bytes = await File(photoPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final roomImage = frame.image;

    final srcW = roomImage.width.toDouble();
    final srcH = roomImage.height.toDouble();
    const canvasW = 1400.0;
    final canvasH = canvasW * srcH / srcW;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      roomImage,
      Rect.fromLTWH(0, 0, srcW, srcH),
      Rect.fromLTWH(0, 0, canvasW, canvasH),
      Paint(),
    );

    final minorPaint = Paint()
      ..color = const Color(0x40FFFFFF)
      ..strokeWidth = 1;
    final majorPaint = Paint()
      ..color = const Color(0xB000FFFF)
      ..strokeWidth = 1.5;

    for (var pct = 0; pct <= 100; pct += 5) {
      final x = canvasW * pct / 100.0;
      final isMajor = pct % 10 == 0;
      canvas.drawLine(Offset(x, 0), Offset(x, canvasH), isMajor ? majorPaint : minorPaint);
      if (isMajor) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$pct%',
            style: const TextStyle(
              color: Color(0xFF00FFFF),
              fontSize: 16,
              backgroundColor: Color(0xB0000000),
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(x + 2, 2));
      }
    }
    for (var pct = 0; pct <= 100; pct += 5) {
      final y = canvasH * pct / 100.0;
      final isMajor = pct % 10 == 0;
      canvas.drawLine(Offset(0, y), Offset(canvasW, y), isMajor ? majorPaint : minorPaint);
      if (isMajor) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$pct%',
            style: const TextStyle(
              color: Color(0xFF00FFFF),
              fontSize: 16,
              backgroundColor: Color(0xB0000000),
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(2, y + 2));
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(canvasW.round(), canvasH.round());
    final pngBytes = await encodePng(image);
    Directory('/tmp/diag_room_painter').createSync(recursive: true);
    File('/tmp/diag_room_painter/grid_reference.png').writeAsBytesSync(pngBytes);
    // ignore: avoid_print
    print('Ecrit: /tmp/diag_room_painter/grid_reference.png (${pngBytes.length} octets)');
  });
}
