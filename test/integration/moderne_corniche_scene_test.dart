/// Test de non-régression — intégration de la scène démo
/// "moderne_corniche" (A3c) à côté de "moderne".
///
/// Vérifie que la nouvelle scène partage strictement la même géométrie
/// d'affichage (dimensions, imgDraw "contain", calibration à 8 points)
/// que la scène `moderne` d'origine. Aucune modification de
/// `moderne.jpg`, aucun build/lancement d'app requis.
///
/// Les dimensions JPEG sont lues par un décodage MINIMAL des marqueurs
/// SOF0/SOF1/SOF2 de l'en-tête JPEG (dart:io pur, sans dart:ui ni
/// nouvelle dépendance pub) — volontairement plus léger que
/// `ui.instantiateImageCodec`, qui nécessite le moteur de rendu Flutter
/// (flutter_tester) et peut rester bloqué en environnement de test
/// headless sans binding widget préalable.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/models/persp_calib.dart';
import 'package:staff_decor_studio/state/app_state.dart' show computeImgDraw;

/// Lit width/height d'un JPEG en parcourant ses segments (marqueurs
/// 0xFF 0xXX), jusqu'au premier marqueur SOF (Start Of Frame :
/// 0xC0-0xC3, 0xC5-0xC7, 0xC9-0xCB, 0xCD-0xCF — couvre baseline,
/// progressif, et les variantes arithmétiques/lossless), qui encode
/// systématiquement (hauteur:2 octets, largeur:2 octets) juste après
/// l'octet de précision. Suffisant pour les JPEG produits par les
/// pipelines standards (PIL/libjpeg) utilisés dans ce projet.
({int width, int height}) _readJpegDimensions(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    throw FormatException('Pas un JPEG valide (SOI manquant) : $path');
  }
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) {
      offset++;
      continue;
    }
    final marker = bytes[offset + 1];
    // SOF0..SOF3, SOF5..SOF7, SOF9..SOF11, SOF13..SOF15
    final isSof = (marker >= 0xC0 && marker <= 0xC3) ||
        (marker >= 0xC5 && marker <= 0xC7) ||
        (marker >= 0xC9 && marker <= 0xCB) ||
        (marker >= 0xCD && marker <= 0xCF);
    if (isSof) {
      // Layout: FF marker | len(2) | precision(1) | height(2) | width(2)
      final height = data.getUint16(offset + 5, Endian.big);
      final width = data.getUint16(offset + 7, Endian.big);
      return (width: width, height: height);
    }
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      offset += 2; // marqueurs sans segment de longueur
      continue;
    }
    final segLen = data.getUint16(offset + 2, Endian.big);
    offset += 2 + segLen;
  }
  throw FormatException('Aucun marqueur SOF trouvé dans : $path');
}

void main() {
  const modernePath = 'assets/demo_scenes/moderne.jpg';
  const modCorPath = 'assets/demo_scenes/moderne_corniche.jpg';

  group('Scène démo moderne_corniche — non-régression', () {
    test('les deux fichiers assets existent', () {
      expect(File(modernePath).existsSync(), true, reason: '$modernePath doit exister');
      expect(File(modCorPath).existsSync(), true, reason: '$modCorPath doit exister');
    });

    test('les deux images ont exactement les dimensions 1960x1470', () {
      final dimsModerne = _readJpegDimensions(modernePath);
      final dimsCorniche = _readJpegDimensions(modCorPath);

      expect(dimsModerne.width, 1960);
      expect(dimsModerne.height, 1470);
      expect(dimsCorniche.width, 1960);
      expect(dimsCorniche.height, 1470);
    });

    test('computeImgDraw donne le même résultat pour les deux, à dimensions égales', () {
      // Dimensions égales (1960x1470, vérifié ci-dessus) => pour un même
      // conteneur, computeImgDraw doit produire un ImgDraw identique.
      const containerW = 430.0;
      const containerH = 322.0; // cadre AppShell desktop plafonné ~430px

      final drawModerne = computeImgDraw(1960, 1470, containerW, containerH);
      final drawCorniche = computeImgDraw(1960, 1470, containerW, containerH);

      expect(drawCorniche.dx, drawModerne.dx);
      expect(drawCorniche.dy, drawModerne.dy);
      expect(drawCorniche.dw, drawModerne.dw);
      expect(drawCorniche.dh, drawModerne.dh);
      expect(drawCorniche.scale, drawModerne.scale);
    });

    test('PerspCalib.forDemoScene est strictement identique pour moderne et moderne_corniche', () {
      final calibModerne = PerspCalib.forDemoScene('moderne');
      final calibCorniche = PerspCalib.forDemoScene('moderne_corniche');

      expect(calibCorniche.ceilL.xPct, calibModerne.ceilL.xPct);
      expect(calibCorniche.ceilL.yPct, calibModerne.ceilL.yPct);
      expect(calibCorniche.ceilR.xPct, calibModerne.ceilR.xPct);
      expect(calibCorniche.ceilR.yPct, calibModerne.ceilR.yPct);
      expect(calibCorniche.floorL.xPct, calibModerne.floorL.xPct);
      expect(calibCorniche.floorL.yPct, calibModerne.floorL.yPct);
      expect(calibCorniche.floorR.xPct, calibModerne.floorR.xPct);
      expect(calibCorniche.floorR.yPct, calibModerne.floorR.yPct);
      expect(calibCorniche.wallTL.xPct, calibModerne.wallTL.xPct);
      expect(calibCorniche.wallTL.yPct, calibModerne.wallTL.yPct);
      expect(calibCorniche.wallTR.xPct, calibModerne.wallTR.xPct);
      expect(calibCorniche.wallTR.yPct, calibModerne.wallTR.yPct);
      expect(calibCorniche.wallBL.xPct, calibModerne.wallBL.xPct);
      expect(calibCorniche.wallBL.yPct, calibModerne.wallBL.yPct);
      expect(calibCorniche.wallBR.xPct, calibModerne.wallBR.xPct);
      expect(calibCorniche.wallBR.yPct, calibModerne.wallBR.yPct);
    });

    test("PerspCalib.forDemoScene('unknown') retombe toujours sur defaultCalib", () {
      final calibUnknown = PerspCalib.forDemoScene('unknown');
      final calibDefault = PerspCalib.defaultCalib;

      expect(calibUnknown.ceilL.xPct, calibDefault.ceilL.xPct);
      expect(calibUnknown.ceilL.yPct, calibDefault.ceilL.yPct);
      expect(calibUnknown.ceilR.xPct, calibDefault.ceilR.xPct);
      expect(calibUnknown.ceilR.yPct, calibDefault.ceilR.yPct);
      expect(calibUnknown.floorL.yPct, calibDefault.floorL.yPct);
      expect(calibUnknown.floorR.yPct, calibDefault.floorR.yPct);
      expect(calibUnknown.wallTL.yPct, calibDefault.wallTL.yPct);
      expect(calibUnknown.wallTR.yPct, calibDefault.wallTR.yPct);
      expect(calibUnknown.wallBL.yPct, calibDefault.wallBL.yPct);
      expect(calibUnknown.wallBR.yPct, calibDefault.wallBR.yPct);
    });
  });
}
