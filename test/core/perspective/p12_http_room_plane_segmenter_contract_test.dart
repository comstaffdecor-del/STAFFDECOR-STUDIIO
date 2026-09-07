/// P12 — tests de CONTRAT (plomberie réseau) pour
/// `HttpRoomPlaneSegmenter` / `decodeRoomPlaneMaskJson`, via
/// `package:http/testing.dart` (`MockClient`) rejouant des réponses
/// capturées — AUCUN réseau réel, AUCUN backend FastAPI requis pour
/// faire tourner ce fichier.
///
/// Couvre les 5 invariants de `docs/P12_BACKEND_CONTRACT.md`, avec le
/// bon type d'exception attendu par cas :
///   1. labels desordonnes/incorrects  -> RoomPlaneContractViolationException
///   2. dimensions divergentes (P12-1) -> RoomPlaneContractViolationException
///   3. somme(runLength) != width*height -> ArgumentError (constructeur
///      de RoomPlaneMaskResult)
///   4. classIndex hors bornes [0,3]     -> ArgumentError (idem)
///   5. RLE bien forme, parcours ligne-major -> succès (cas nominal,
///      vérifié positivement, pas seulement par absence d'erreur)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:staff_decor_studio/core/perspective/http_room_plane_segmenter.dart';
import 'package:staff_decor_studio/core/perspective/room_plane_segmenter.dart';

const int kW = 4;
const int kH = 4;

/// Réponse JSON canonique (contrat nominal) : masque 4x4, 16 pixels,
/// toutes classes representees, RLE bien forme.
Map<String, dynamic> _validBody({int width = kW, int height = kH}) => {
  'width': width,
  'height': height,
  'labels': ['unknown', 'ceiling', 'wall', 'floor'],
  'rle': [
    [0, 4], // 4 unknown
    [1, 4], // 4 ceiling
    [2, 4], // 4 wall
    [3, 4], // 4 floor
  ],
};

http.Client _mockClientReturning(
  int statusCode,
  Object? jsonBody, {
  bool asRawString = false,
}) {
  return MockClient((request) async {
    final body = asRawString ? jsonBody as String : jsonEncode(jsonBody);
    return http.Response(body, statusCode);
  });
}

/// Le contenu de l'image n'est jamais inspecté par `MockClient` dans
/// ces tests (le handler ignore le corps de la requête), un buffer
/// vide suffit.
final Uint8List _fakeImageBytes = Uint8List(0);

void main() {
  group('P12 contrat reseau - HttpRoomPlaneSegmenter / decodeRoomPlaneMaskJson', () {
    test('1. cas nominal: reponse valide -> RoomPlaneMaskResult correct', () async {
      final client = _mockClientReturning(200, _validBody());
      final segmenter = HttpRoomPlaneSegmenter(
        endpoint: Uri.parse('http://localhost:9999/segment'),
        client: client,
      );

      final mask = await segmenter.segment(
        imageBytes: _fakeImageBytes,
        width: kW,
        height: kH,
      );

      expect(mask, isNotNull);
      expect(mask!.width, kW);
      expect(mask.height, kH);
      expect(mask.providerName, 'http');
      // Parcours ligne-major, RLE [[0,4],[1,4],[2,4],[3,4]] sur 4x4:
      // ligne 0 (indices 0-3) = unknown, ligne 1 (4-7) = ceiling,
      // ligne 2 (8-11) = wall, ligne 3 (12-15) = floor.
      expect(mask.classAt(0, 0), RoomPlaneClass.unknown);
      expect(mask.classAt(3, 0), RoomPlaneClass.unknown);
      expect(mask.classAt(0, 1), RoomPlaneClass.ceiling);
      expect(mask.classAt(0, 2), RoomPlaneClass.wall);
      expect(mask.classAt(0, 3), RoomPlaneClass.floor);
      expect(mask.hasAny(RoomPlaneClass.wall), isTrue);
      expect(mask.hasAny(RoomPlaneClass.floor), isTrue);
      expect(mask.countOf(RoomPlaneClass.floor), 4);
    });

    test('2. labels desordonnes -> RoomPlaneContractViolationException', () async {
      final body = _validBody();
      body['labels'] = ['unknown', 'wall', 'ceiling', 'floor']; // wall/ceiling inverses
      final client = _mockClientReturning(200, body);
      final segmenter = HttpRoomPlaneSegmenter(
        endpoint: Uri.parse('http://localhost:9999/segment'),
        client: client,
      );

      expect(
        () => segmenter.segment(
          imageBytes: _fakeImageBytes,
          width: kW,
          height: kH,
        ),
        throwsA(isA<RoomPlaneContractViolationException>()),
      );
    });

    test('2b. labels incomplets (modele Pascal VOC sans ceiling/floor) -> RoomPlaneContractViolationException', () async {
      final body = _validBody();
      body['labels'] = ['unknown', 'wall']; // Pascal VOC-like, incomplet
      final client = _mockClientReturning(200, body);
      final segmenter = HttpRoomPlaneSegmenter(
        endpoint: Uri.parse('http://localhost:9999/segment'),
        client: client,
      );

      expect(
        () => segmenter.segment(
          imageBytes: _fakeImageBytes,
          width: kW,
          height: kH,
        ),
        throwsA(isA<RoomPlaneContractViolationException>()),
      );
    });

    test('3. dimensions divergentes (P12-1) -> RoomPlaneContractViolationException', () async {
      // Backend renvoie 2x2 (4 pixels) alors que le client demande 4x4.
      final body = {
        'width': 2,
        'height': 2,
        'labels': ['unknown', 'ceiling', 'wall', 'floor'],
        'rle': [
          [0, 4],
        ],
      };
      final client = _mockClientReturning(200, body);
      final segmenter = HttpRoomPlaneSegmenter(
        endpoint: Uri.parse('http://localhost:9999/segment'),
        client: client,
      );

      expect(
        () => segmenter.segment(
          imageBytes: _fakeImageBytes,
          width: kW,
          height: kH,
        ),
        throwsA(isA<RoomPlaneContractViolationException>()),
      );
    });

    test('4. somme(runLength) != width*height -> ArgumentError', () async {
      final body = _validBody();
      body['rle'] = [
        [0, 4],
        [1, 4],
        [2, 4],
        [3, 3], // total = 15 != 16
      ];
      final client = _mockClientReturning(200, body);
      final segmenter = HttpRoomPlaneSegmenter(
        endpoint: Uri.parse('http://localhost:9999/segment'),
        client: client,
      );

      expect(
        () => segmenter.segment(
          imageBytes: _fakeImageBytes,
          width: kW,
          height: kH,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('5. classIndex hors bornes -> ArgumentError', () async {
      final body = _validBody();
      body['rle'] = [
        [0, 4],
        [1, 4],
        [2, 4],
        [4, 4], // classIndex 4 hors bornes [0,3]
      ];
      final client = _mockClientReturning(200, body);
      final segmenter = HttpRoomPlaneSegmenter(
        endpoint: Uri.parse('http://localhost:9999/segment'),
        client: client,
      );

      expect(
        () => segmenter.segment(
          imageBytes: _fakeImageBytes,
          width: kW,
          height: kH,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('6. HTTP != 200 -> RoomPlaneContractViolationException', () async {
      final client = _mockClientReturning(500, 'internal error', asRawString: true);
      final segmenter = HttpRoomPlaneSegmenter(
        endpoint: Uri.parse('http://localhost:9999/segment'),
        client: client,
      );

      expect(
        () => segmenter.segment(
          imageBytes: _fakeImageBytes,
          width: kW,
          height: kH,
        ),
        throwsA(isA<RoomPlaneContractViolationException>()),
      );
    });

    test('7. reponse non-JSON -> RoomPlaneContractViolationException', () async {
      final client = _mockClientReturning(200, 'ceci n\'est pas du json', asRawString: true);
      final segmenter = HttpRoomPlaneSegmenter(
        endpoint: Uri.parse('http://localhost:9999/segment'),
        client: client,
      );

      expect(
        () => segmenter.segment(
          imageBytes: _fakeImageBytes,
          width: kW,
          height: kH,
        ),
        throwsA(isA<RoomPlaneContractViolationException>()),
      );
    });

    test('8. element RLE non numerique -> RoomPlaneContractViolationException', () async {
      final body = _validBody();
      body['rle'] = [
        ['not_a_number', 16],
      ];
      final client = _mockClientReturning(200, body);
      final segmenter = HttpRoomPlaneSegmenter(
        endpoint: Uri.parse('http://localhost:9999/segment'),
        client: client,
      );

      expect(
        () => segmenter.segment(
          imageBytes: _fakeImageBytes,
          width: kW,
          height: kH,
        ),
        throwsA(isA<RoomPlaneContractViolationException>()),
      );
    });
  });

  group('P12 contrat - decodeRoomPlaneMaskJson (unitaire, sans reseau)', () {
    test('expectedWidth/expectedHeight null: aucune verification de dimension (retro-compat P11)', () {
      final body = {
        'width': 2,
        'height': 2,
        'labels': ['unknown', 'ceiling', 'wall', 'floor'],
        'rle': [
          [0, 4],
        ],
      };
      final mask = decodeRoomPlaneMaskJson(body);
      expect(mask.width, 2);
      expect(mask.height, 2);
    });

    test('expectedWidth/expectedHeight fournis et corrects: succes', () {
      final body = _validBody();
      final mask = decodeRoomPlaneMaskJson(
        body,
        expectedWidth: kW,
        expectedHeight: kH,
      );
      expect(mask.width, kW);
      expect(mask.height, kH);
    });
  });
}
