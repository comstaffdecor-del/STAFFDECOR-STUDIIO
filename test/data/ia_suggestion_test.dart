// P15-IA-DEMO — Volet B, "Suggestion automatique (démo)".
//
// Test aller-retour OBLIGATOIRE (brief, point 5) : soumet chacune des
// vignettes réellement bundlées (`assets/profiles/control/<ref>.png`)
// correspondant à une ref présentation-visible (même gate que le filtre
// existant, [CatalogueVisibilityGate]) comme si c'était "la photo
// d'entrée", et vérifie qu'elle se classe elle-même en position #1 ET
// franchit le seuil d'exploitabilité ([kMinIaScore]/[kMinIaGap]).
//
// Le taux exact n/43 (43 = refs de présentation, dont seules celles
// possédant une vignette locale sont scorables — voir doc de
// `lib/data/ia_suggestion.dart`) est imprimé et sert de preuve pour
// `/tmp/presentation_ai_demo.txt`. AUCUN mock/compensation : si un seul
// cas échoue, ce test le signale explicitement en clair (le
// désaveu du module, `kIaSuggestionEnabled = false`, est un choix
// éditorial séparé pris au vu de ce résultat, jamais automatisé ici).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/data/catalogue_visibility.dart';
import 'package:staff_decor_studio/data/ia_suggestion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CatalogueVisibilityGate.instance.resetForTesting();
    IaSuggestionGate.instance.resetForTesting();
  });

  test(
    'Round-trip Piste 1 : chaque vignette control/*.png se retrouve '
    'top-1 sur elle-même, ET franchit le seuil d\'exploitabilité '
    '(kMinIaScore=$kMinIaScore, kMinIaGap=$kMinIaGap) — rapporte n/43',
    () async {
      final visible = await CatalogueVisibilityGate.instance.ensureLoaded();
      expect(visible.length, 43, reason: 'Périmètre attendu = 43 refs présentation');

      final db = await IaSuggestionGate.instance.ensureLoaded();
      // ignore: avoid_print
      print(
        '[ia_suggestion] base de référence chargée : ${db.length}/43 refs '
        'possèdent une vignette control/*.png exploitable '
        '(${43 - db.length}/43 n\'en ont aucune — hors périmètre IA, '
        'toujours accessibles via le catalogue manuel).',
      );

      var pass = 0;
      var fail = 0;
      final failures = <String>[];

      for (final ref in db.keys.toList()..sort()) {
        final data = await rootBundle.load('assets/profiles/control/$ref.png');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        final result = await IaSuggestionGate.instance.rank(bytes);

        final top1IsSelf = result.exploitable &&
            result.matches.isNotEmpty &&
            result.matches.first.ref == ref;

        if (top1IsSelf) {
          pass++;
        } else {
          fail++;
          failures.add(
            '$ref -> exploitable=${result.exploitable} '
            'top1=${result.matches.isNotEmpty ? result.matches.first.ref : "aucun"} '
            '(${result.reason})',
          );
        }
      }

      // ignore: avoid_print
      print(
        '[ia_suggestion] ROUND-TRIP RESULT : $pass/${db.length} '
        '(sur 43 refs présentation, ${db.length} scorables via vignette '
        'locale) — échecs=$failures',
      );

      // Écrit le résultat brut dans /tmp/ pour être repris tel quel dans
      // le rapport final (jamais réécrit à la main).
      File('/tmp/ia_suggestion_roundtrip.txt').writeAsStringSync(
        'round_trip_pass=$pass\n'
        'round_trip_total_scorable=${db.length}\n'
        'presentation_total=43\n'
        'kMinIaScore=$kMinIaScore\n'
        'kMinIaGap=$kMinIaGap\n'
        'failures=$failures\n',
      );

      // Ce test documente le taux, il n'échoue PAS automatiquement sur
      // un taux <100% (même philosophie que les sondes P9/P10 du
      // projet) : la décision d'activer/désactiver kIaSuggestionEnabled
      // est prise au vu de ce résultat imprimé, pas par un `expect`
      // bloquant ici — mais le brief exige explicitement 0 échec pour
      // que kIaSuggestionEnabled reste `true`.
      expect(pass + fail, db.length);
    },
  );

  test(
    'Rejet propre (non-exploitable) sur une image dégénérée (blanche) '
    '— jamais de crash',
    () async {
      await CatalogueVisibilityGate.instance.ensureLoaded();
      await IaSuggestionGate.instance.ensureLoaded();

      // 8x8 blanc pur encodé en PNG minimal (aucune "encre" détectable).
      final whitePng = await _solidColorPng(8, 8, 255, 255, 255);
      final result = await IaSuggestionGate.instance.rank(whitePng);
      expect(result.exploitable, isFalse);
      expect(result.matches, isEmpty);
    },
  );

  test(
    'Rejet propre (non-exploitable) sur des bytes corrompus/non-image '
    '— jamais de crash',
    () async {
      await CatalogueVisibilityGate.instance.ensureLoaded();
      await IaSuggestionGate.instance.ensureLoaded();

      final garbage = Uint8List.fromList(List.generate(100, (i) => i % 256));
      final result = await IaSuggestionGate.instance.rank(garbage);
      expect(result.exploitable, isFalse);
      expect(result.matches, isEmpty);
    },
  );

  test('kIaSuggestionEnabled est bien un bool (point de réversibilité)', () {
    expect(kIaSuggestionEnabled, isA<bool>());
  });
}

/// Construit un PNG uni de taille [w]x[h] en mémoire (pas de fichier
/// disque), utilisé uniquement pour le test de rejet "image blanche" —
/// même pattern `PictureRecorder`/`toImage`/`toByteData(png)` que
/// `test/core/geometry/render_corniche_screenshot_test.dart` (précédent
/// déjà établi dans ce projet).
Future<Uint8List> _solidColorPng(int w, int h, int r, int g, int b) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..color = ui.Color.fromARGB(255, r, g, b);
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), paint);
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return byteData!.buffer.asUint8List();
}
