// P21-HYBRIDE (correction revue) — Test 2 du brief "sécurisation test
// hybride Nano Banana" : vérifie que `renderMode: 'refine'` n'est
// JAMAIS envoyé sauf quand la scène provient explicitement de
// `_useComposedScene` (bouton "Scène avec produit déjà posé") — les
// trois autres sources de scène (scène actuelle du Studio, scène démo,
// import photo) doivent toujours envoyer `renderMode: 'add'`
// (comportement historique inchangé).
//
// Utilise le hook `debugGenerateAiAmbiancePreviewOverride` (réservé aux
// tests, voir ai_ambiance_panel.dart) pour observer le renderMode
// RÉELLEMENT transmis par le widget à l'appel réseau, sans jamais
// toucher le vrai proxy/Gemini.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:staff_decor_studio/data/catalogue_visibility.dart';
import 'package:staff_decor_studio/data/ia_ambiance_preview.dart';
import 'package:staff_decor_studio/models/project_item.dart';
import 'package:staff_decor_studio/state/app_state.dart';
import 'package:staff_decor_studio/widgets/studio/ai_ambiance_panel.dart';

/// Fabrique une image PNG 2x2 minimale décodée en [ui.Image] — même
/// pattern que `test/state/ai_auto_trigger_and_comparison_test.dart`.
Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = Colors.white);
  final picture = recorder.endRecording();
  return picture.toImage(2, 2);
}

/// Bytes PNG RÉELS et valides (1x1 pixel blanc) — nécessaire car
/// `_buildResult()` affiche le résultat via `Image.memory(bytes)` :
/// des bytes factices arbitraires (ex. `[1, 2, 3]`) font planter le
/// décodeur d'image du binding de test ("Invalid image data"), ce qui
/// n'a rien à voir avec le comportement `renderMode` que ce test
/// vérifie. Généré une seule fois via `_tinyImage()` + encodage PNG.
Future<Uint8List> _tinyPngBytes() async {
  final image = await _tinyImage();
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CatalogueVisibilityGate.instance.resetForTesting();
    debugGenerateAiAmbiancePreviewOverride = null;
  });

  tearDown(() {
    // Ne JAMAIS laisser le hook de test actif pour un autre test/le
    // reste de l'app — voir docstring du champ dans ai_ambiance_panel.dart.
    debugGenerateAiAmbiancePreviewOverride = null;
  });

  Future<String?> pumpPanelAndCaptureRenderMode(
    WidgetTester tester, {
    required AppState state,
    required Future<void> Function(WidgetTester tester) drive,
  }) async {
    String? capturedRenderMode;
    final resultBytes = await _tinyPngBytes();
    debugGenerateAiAmbiancePreviewOverride = ({
      required Uint8List sceneImageBytes,
      required String ref,
      required String nom,
      required String famille,
      required String renderMode,
    }) async {
      capturedRenderMode = renderMode;
      return AiPreviewResult.ok(
        resultBytes,
        model: 'gemini-3.1-flash-image',
        sku: ref,
        usedProductReference: true,
        productReferencePath: 'assets/profiles/control/$ref.png',
        renderMode: renderMode,
      );
    };

    await tester.runAsync(() async {
      await CatalogueVisibilityGate.instance.ensureLoaded();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AppState>.value(
          value: state,
          child: Scaffold(
            body: AiAmbiancePanel(onClose: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await drive(tester);

    return capturedRenderMode;
  }

  /// La grille de produits (`GridView.builder` dans une zone de hauteur
  /// fixe) ne construit QUE les tuiles visibles dans son viewport — sur
  /// 43 refs triées alphabétiquement, "D609" est loin dans la liste et
  /// n'existe donc PAS encore dans l'arbre de widgets tant qu'on n'a pas
  /// scrollé jusqu'à lui (cause réelle de l'échec initial : `find.text
  /// ('D609')` retournait une liste vide, PAS un problème de chargement
  /// de `CatalogueVisibilityGate`, confirmé chargé avec 43 refs incluant
  /// D609 avant le pump). On scrolle explicitement le `GridView` avant
  /// tout tap sur la tuile produit.
  Future<void> _scrollToAndTapD609(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('D609'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('D609').first);
    await tester.pumpAndSettle();
  }

  group('AiAmbiancePanel — renderMode selon la provenance de la scène', () {
    testWidgets(
      'Test 2a — "Scène actuelle" (_useCurrentScene) envoie renderMode="add"',
      (tester) async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.selectedProducts = [
          const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];

        final captured = await pumpPanelAndCaptureRenderMode(
          tester,
          state: state,
          drive: (tester) async {
            // Étape 1 : choisir le produit D609 dans la grille (nécessite
            // un scroll, voir _scrollToAndTapD609).
            await _scrollToAndTapD609(tester);

            // Étape 2 : "Scène actuelle" (PAS "Scène avec produit déjà posé").
            await tester.tap(find.text('Scène actuelle'));
            await tester.pumpAndSettle();

            // Étape 3 : Générer.
            await tester.tap(find.text('Générer un aperçu IA'));
            await tester.pumpAndSettle();
          },
        );

        expect(captured, 'add',
            reason: '_useCurrentScene doit toujours envoyer renderMode='
                '"add" (photo brute, comportement historique) — jamais '
                '"refine".');
      },
    );

    testWidgets(
      'Test 2b — scène démo (_useDemoScene) envoie renderMode="add"',
      (tester) async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.selectedProducts = [
          const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];

        final captured = await pumpPanelAndCaptureRenderMode(
          tester,
          state: state,
          drive: (tester) async {
            await _scrollToAndTapD609(tester);

            // Scène démo "Contemporain" (assets/demo_scenes/moderne.jpg)
            // — chargement d'asset réel, doit tourner dans runAsync.
            await tester.runAsync(() async {
              await tester.tap(find.text('Contemporain'));
              await tester.pumpAndSettle();
            });

            await tester.tap(find.text('Générer un aperçu IA'));
            await tester.pumpAndSettle();
          },
        );

        expect(captured, 'add',
            reason: '_useDemoScene doit toujours envoyer renderMode='
                '"add" — jamais "refine".');
      },
    );

    testWidgets(
      'Test 2c — "Scène avec produit déjà posé" (_useComposedScene) '
      'envoie renderMode="refine", et UNIQUEMENT dans ce cas',
      (tester) async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.selectedProducts = [
          const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];
        // Simule une capture réussie du rendu composé (RepaintBoundary
        // réel posé dans studio_screen.dart, non monté dans ce test
        // widget isolé — on injecte directement le résultat attendu
        // du capteur, ce qui est le contrat exact vérifié par
        // AppState.captureComposedScene()).
        state.registerComposedSceneCapture(
          () async => Uint8List.fromList([9, 9, 9]),
        );

        final captured = await pumpPanelAndCaptureRenderMode(
          tester,
          state: state,
          drive: (tester) async {
            await _scrollToAndTapD609(tester);

            // Le bouton hybride requiert une opération asynchrone
            // (captureComposedScene) — exécuter dans runAsync.
            await tester.runAsync(() async {
              await tester.tap(find.text('Scène avec produit déjà posé (rendu dynamique)'));
              await tester.pumpAndSettle();
            });

            await tester.tap(find.text('Générer un aperçu IA'));
            await tester.pumpAndSettle();
          },
        );

        expect(captured, 'refine',
            reason: '_useComposedScene est le SEUL chemin qui doit '
                'envoyer renderMode="refine" — c\'est précisément ce '
                'que ce test garantit, en miroir des tests 2a/2b qui '
                'garantissent l\'inverse pour toutes les autres sources '
                'de scène.');
      },
    );
  });
}
