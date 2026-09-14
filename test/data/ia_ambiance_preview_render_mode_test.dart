// P21-HYBRIDE (correction revue) — Test 1 du brief "sécurisation test
// hybride Nano Banana" : vérifie que le CLIENT envoie bien `renderMode`
// au proxy, et qu'en son ABSENCE explicite le comportement reste celui
// d'AVANT ce chantier ('add', jamais 'refine' par accident).
//
// N'appelle JAMAIS le vrai réseau/proxy/Gemini — utilise
// `package:http/testing.dart` → `MockClient` (même pattern déjà utilisé
// par `test/core/perspective/p12_http_room_plane_segmenter_contract_test.dart`
// dans ce repo) pour intercepter la requête HTTP et inspecter son corps
// JSON directement, sans dépendre du proxy réel ni du quota Gemini.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:staff_decor_studio/data/ia_ambiance_preview.dart';

void main() {
  // Image factice minimale (contenu arbitraire, jamais inspecté par
  // MockClient) — seul le corps JSON envoyé nous intéresse ici.
  final fakeScene = Uint8List.fromList(List.filled(16, 0xFF));

  http.Client mockClientCapturing(void Function(Map<String, dynamic> body) onBody) {
    return MockClient((request) async {
      final decoded = jsonDecode(request.body) as Map<String, dynamic>;
      onBody(decoded);
      return http.Response(
        jsonEncode({
          'ok': true,
          'provider': 'gemini',
          'mode': 'real',
          'model': 'gemini-3.1-flash-image',
          'sku': decoded['sku'],
          'renderMode': decoded['renderMode'] == 'refine' ? 'refine' : 'add',
          'imageBase64': base64Encode(Uint8List.fromList([1, 2, 3])),
          'mimeType': 'image/png',
          'usedProductReference': true,
          'productReferencePath': 'assets/profiles/control/D609.png',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  group('generateAiAmbiancePreview — renderMode envoyé au proxy', () {
    test(
      'Test 1 — SANS renderMode explicite, le client envoie "add" '
      '(comportement historique inchangé, jamais "refine" par défaut)',
      () async {
        Map<String, dynamic>? capturedBody;
        final client = mockClientCapturing((body) => capturedBody = body);

        final result = await generateAiAmbiancePreview(
          sceneImageBytes: fakeScene,
          ref: 'D609',
          nom: 'D609',
          famille: 'Corniches',
          // renderMode volontairement OMIS ici — on vérifie la valeur
          // par défaut du paramètre, pas une valeur passée explicitement.
          httpClient: client,
        );

        expect(capturedBody, isNotNull,
            reason: 'la requête HTTP doit avoir été effectivement envoyée');
        expect(capturedBody!['renderMode'], 'add',
            reason: 'sans renderMode explicite, le client doit envoyer '
                '"add" — jamais "refine" par accident, jamais absent '
                '(le proxy retomberait aussi sur "add" mais le contrat '
                'client doit rester explicite et vérifiable).');

        expect(result.success, isTrue);
        expect(result.renderMode, 'add',
            reason: 'le renderMode renvoyé par le proxy (mocké ici) doit '
                'être fidèlement reporté dans AiPreviewResult.renderMode.');
      },
    );

    test(
      'renderMode="refine" explicite est bien transmis tel quel au proxy',
      () async {
        Map<String, dynamic>? capturedBody;
        final client = mockClientCapturing((body) => capturedBody = body);

        final result = await generateAiAmbiancePreview(
          sceneImageBytes: fakeScene,
          ref: 'D609',
          nom: 'D609',
          famille: 'Corniches',
          renderMode: 'refine',
          httpClient: client,
        );

        expect(capturedBody!['renderMode'], 'refine');
        expect(result.renderMode, 'refine');
      },
    );
  });
}
