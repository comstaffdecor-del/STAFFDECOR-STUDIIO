// Test P20-AUTO / Avant-Après IA — vérifie, SANS aucun appel réseau réel,
// le câblage logique demandé par le brief :
//
//   1) import photo (roomImage chargé) + sélection produit (D609)
//      => maybeAutoTriggerAiPreview() ouvre le panneau IA en mode
//         auto-generate, avec le bon prefillRef ;
//   2) la garde anti-boucle empêche un second déclenchement pour le
//      MÊME couple (sku, roomImageVersion) tant que rien ne change ;
//   3) un changement de scène (nouvelle image) OU de produit sélectionné
//      autorise un nouveau déclenchement ;
//   4) après une génération IA réussie, AppState.lastAiComparisonResult
//      contient bien {photo originale, image IA, sku, model,
//      usedProductReference, productReferencePath} — c'est cette donnée
//      que l'écran Avant/Après ("Aperçu IA") lit pour afficher
//      avant/après SANS jamais relancer Gemini.
//
// Ce test ne remplace PAS la validation visuelle manuelle du parcours
// complet sur le lien 8083 (import réel, clic Avant/Après, lecture de
// l'image affichée à l'écran) — il prouve seulement que la logique
// d'état (AppState) qui alimente cet écran est correctement câblée,
// de façon reproductible et automatisée.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/state/app_state.dart';

/// Fabrique une image PNG 2x2 minimale décodée en [ui.Image] — suffisant
/// pour peupler [AppState.roomImage] sans dépendre d'assets réels.
Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = Colors.white);
  final picture = recorder.endRecording();
  return picture.toImage(2, 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P20-AUTO — déclenchement automatique aperçu IA', () {
    test(
      'import photo + sélection produit ouvre le panneau IA en mode auto-generate',
      () async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;

        expect(state.showAiAmbiancePanel, isFalse);

        state.addToProject('D609');

        expect(state.showAiAmbiancePanel, isTrue,
            reason: 'la sélection produit doit ouvrir automatiquement le '
                'panneau IA, sans action manuelle');
        expect(state.aiAmbiancePrefillRef, 'D609');
        expect(state.aiAmbianceAutoGenerate, isTrue,
            reason: 'la génération doit démarrer seule, jamais via un '
                'bouton');
      },
    );

    test(
      'garde anti-boucle : ne redéclenche pas pour le même couple (sku, scène)',
      () async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.addToProject('D609');
        expect(state.showAiAmbiancePanel, isTrue);

        // L'utilisateur ferme le panneau (ex: consulte le devis) —
        // sans changement de photo ni de produit.
        state.closeAiAmbiancePanel();
        expect(state.showAiAmbiancePanel, isFalse);

        // Un notifyListeners quelconque (ex: saisie de métrés) ne doit
        // JAMAIS rouvrir le panneau IA pour ce même couple déjà généré.
        state.maybeAutoTriggerAiPreview();
        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'aucune re-génération en boucle pour un couple '
                '(sku, scène) déjà déclenché');
      },
    );

    test(
      'un changement de scène (nouvelle photo) autorise un nouveau déclenchement',
      () async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.addToProject('D609');
        state.closeAiAmbiancePanel();

        // Nouvelle photo importée => nouvelle version de scène.
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 2;
        state.maybeAutoTriggerAiPreview();

        expect(state.showAiAmbiancePanel, isTrue,
            reason: 'un changement de photo doit relancer un aperçu IA '
                'pour le produit déjà sélectionné');
        expect(state.aiAmbiancePrefillRef, 'D609');
      },
    );

    test(
      'un changement de produit sélectionné autorise un nouveau déclenchement',
      () async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.addToProject('D609');
        state.closeAiAmbiancePanel();

        // Autre produit sélectionné (même scène) — la clé anti-boucle
        // inclut le sku, donc le déclenchement doit repartir.
        state.addToProject('D720');
        expect(state.showAiAmbiancePanel, isTrue);
        expect(state.aiAmbiancePrefillRef, 'D720');
      },
    );

    test(
      'aucune génération concurrente : pas de déclenchement si une génération est déjà en cours',
      () async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.setAiAmbianceGenerating(true);

        state.addToProject('D609');

        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'ne jamais superposer une génération par-dessus une '
                'autre déjà en cours');
      },
    );

    test('rien ne se déclenche sans photo chargée', () {
      final state = AppState();
      state.addToProject('D609');
      expect(state.showAiAmbiancePanel, isFalse);
    });
  });

  group('Avant/Après IA — stockage et lecture du résultat', () {
    test(
      'setLastAiComparisonResult conserve photo originale + image IA + traçabilité',
      () async {
        final state = AppState();
        final original = Uint8List.fromList(List.filled(16, 1));
        final aiResult = Uint8List.fromList(List.filled(16, 2));

        expect(state.lastAiComparisonResult, isNull,
            reason: 'avant toute génération, l\'écran Avant/Après doit '
                'afficher le message "Générez d\'abord un aperçu IA '
                'depuis le Studio."');

        state.setLastAiComparisonResult(
          AiComparisonResult(
            originalImageBytes: original,
            aiImageBytes: aiResult,
            sku: 'D609',
            model: 'gemini-3.1-flash-image',
            usedProductReference: true,
            productReferencePath: 'assets/profiles/control/D609.png',
          ),
        );

        final r = state.lastAiComparisonResult;
        expect(r, isNotNull);
        expect(r!.originalImageBytes, original,
            reason: 'le "AVANT" doit être la vraie photo envoyée au '
                'proxy, pas une image reconstruite');
        expect(r.aiImageBytes, aiResult,
            reason: 'le "APRÈS" doit être l\'image Gemini réellement '
                'reçue, jamais un mock');
        expect(r.sku, 'D609');
        expect(r.model, 'gemini-3.1-flash-image',
            reason: 'preuve que le modèle non-lite a bien été utilisé');
        expect(r.usedProductReference, isTrue,
            reason: 'preuve que control/D609.png a bien servi de '
                'référence visuelle produit');
        expect(r.productReferencePath, 'assets/profiles/control/D609.png');
      },
    );
  });
}
