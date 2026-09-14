// Test de NON-RÉGRESSION — DÉCISION PRODUIT (retour utilisateur : "le
// rendu IA automatique n'est pas acceptable visuellement — la corniche
// est trop artificielle et pas assez professionnelle").
//
// Historique : une passe précédente (P20-AUTO) avait câblé un
// déclenchement AUTOMATIQUE de l'aperçu IA (Gemini/Nano Banana) dès
// qu'une photo était importée et qu'un produit était sélectionné, sans
// action utilisateur. Ce comportement a été explicitement RETIRÉ (voir
// commentaires dans app_state.dart : setRoomImageBytes, loadDemoScene,
// addToProject) car Gemini reste instable d'une génération à l'autre —
// un rendu automatique imposé peut dégrader l'image de marque.
//
// Ce fichier de test a été RÉÉCRIT pour vérifier l'inverse de ce qu'il
// vérifiait avant : que le Studio n'ouvre JAMAIS le panneau IA tout
// seul, quelles que soient les actions de l'utilisateur (import photo,
// scène démo, sélection produit). Le mécanisme `maybeAutoTriggerAiPreview`
// reste présent dans AppState (infrastructure dormante, documentée) mais
// n'est plus appelé nulle part dans lib/ — seul un appel manuel explicite
// (comme fait ici) peut encore l'invoquer, ce que ce test utilise
// justement pour prouver que la garde anti-boucle reste correcte SI ce
// chantier est un jour rouvert.
//
// Reste inchangé et toujours vérifié : le stockage du résultat IA dans
// AppState pour l'écran Avant/Après (Comparateur, mode "Aperçu IA"),
// qui continue de fonctionner pour un déclenchement MANUEL de l'IA
// (icône topbar Studio), lui non retiré.
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

  group('Non-régression — pas de rendu IA automatique (décision produit)', () {
    test(
      'importer une photo (roomImage chargé) n\'ouvre PAS le panneau IA tout seul',
      () async {
        final state = AppState();
        expect(state.showAiAmbiancePanel, isFalse);

        // Simule le résultat d'un import photo (setRoomImageBytes charge
        // roomImage puis, historiquement, appelait maybeAutoTriggerAiPreview
        // — cet appel a été retiré, on vérifie donc l'ABSENCE d'effet).
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;

        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'le simple chargement d\'une photo ne doit jamais '
                'ouvrir le panneau IA automatiquement');
      },
    );

    test(
      'sélectionner un produit (D609) n\'ouvre PAS le panneau IA tout seul',
      () async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;

        // addToProject() n'appelle plus maybeAutoTriggerAiPreview().
        state.addToProject('D609');

        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'sélectionner un produit doit uniquement mettre à '
                'jour le rendu dynamique déterministe (RoomPainter), '
                'jamais déclencher Gemini automatiquement');
        expect(state.aiAmbianceAutoGenerate, isFalse);
        expect(state.aiAmbiancePrefillRef, isNull);
      },
    );

    test(
      'importer une photo PUIS sélectionner un produit reste sans effet sur l\'IA',
      () async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.addToProject('D609');
        state.addToProject('D720');

        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'aucune combinaison photo + produit ne doit ouvrir '
                'le panneau IA sans action manuelle explicite');
      },
    );

    test(
      'seul un appel manuel explicite à openAiAmbiancePanel ouvre le panneau IA',
      () {
        final state = AppState();
        // C'est ce qu'appelle l'icône topbar "Aperçu d'ambiance IA" du
        // Studio (studio_screen.dart, onAiAmbiance: state.openAiAmbiancePanel),
        // SANS prefill ni autoGenerate — parcours manuel pas-à-pas conservé.
        state.openAiAmbiancePanel();

        expect(state.showAiAmbiancePanel, isTrue);
        expect(state.aiAmbianceAutoGenerate, isFalse,
            reason: 'le déclenchement manuel depuis la topbar ne doit '
                'jamais lancer de génération automatique — l\'utilisateur '
                'choisit lui-même produit/scène puis clique "Générer"');
      },
    );
  });

  group(
    'Infrastructure dormante — maybeAutoTriggerAiPreview (non appelée en '
    'production, conservée pour un futur chantier qualité IA validé séparément)',
    () {
      test('la garde anti-boucle reste correcte si invoquée manuellement',
          () async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.addToProject('D609');
        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'confirme qu\'addToProject n\'appelle plus le trigger');

        // Appel manuel direct (comme le ferait un futur chantier qualité
        // IA, hors périmètre de ce test) — vérifie que le mécanisme lui-
        // même reste fonctionnel et sûr s'il est un jour reconnecté.
        state.maybeAutoTriggerAiPreview();
        expect(state.showAiAmbiancePanel, isTrue);

        state.closeAiAmbiancePanel();
        state.maybeAutoTriggerAiPreview();
        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'garde anti-boucle : pas de re-déclenchement pour le '
                'même couple (sku, scène)');
      });
    },
  );

  group('Avant/Après IA — stockage et lecture du résultat (déclenchement manuel)', () {
    test(
      'setLastAiComparisonResult conserve photo originale + image IA + traçabilité',
      () async {
        final state = AppState();
        final original = Uint8List.fromList(List.filled(16, 1));
        final aiResult = Uint8List.fromList(List.filled(16, 2));

        expect(state.lastAiComparisonResult, isNull,
            reason: 'avant toute génération manuelle, l\'écran Avant/Après '
                'doit afficher "Générez d\'abord un aperçu IA depuis le '
                'Studio."');

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
        expect(r!.originalImageBytes, original);
        expect(r.aiImageBytes, aiResult);
        expect(r.sku, 'D609');
        expect(r.model, 'gemini-3.1-flash-image');
        expect(r.usedProductReference, isTrue);
        expect(r.productReferencePath, 'assets/profiles/control/D609.png');
      },
    );
  });
}
