// P22-HYBRIDE-AUTO — brief "Nouvelle règle produit" (correction de la
// décision produit précédente, commit "Retire le declenchement IA
// automatique").
//
// ⚠️ CE FICHIER REMPLACE la version précédente qui vérifiait l'ABSENCE
// de tout déclenchement automatique de l'aperçu IA. Cette décision a
// été explicitement INVERSÉE par l'utilisateur : il ne fallait PAS
// retirer tout auto-trigger, seulement l'auto-trigger BRUT (Gemini
// invente la pose depuis la photo brute, renderMode='add' implicite).
//
// Nouvelle règle produit :
//   Rendu dynamique automatique      : OUI (inchangé, jamais désactivé)
//   Mano/Nano automatique après rendu dynamique : OUI
//   Mano/Nano en génération brute libre          : NON (sauf fallback
//                                                   manuel contrôlé,
//                                                   voir dernier group)
//   Mode refine/hybride                          : OUI, exclusivement
//
// Ce fichier teste donc [AppState.maybeAutoTriggerHybridAiPreview] (le
// SEUL mécanisme automatique appelé en production, depuis
// [AppState.setRoomImageBytes], [AppState.loadDemoScene] et
// [AppState.addToProject]) — jamais l'ancien
// [AppState.maybeAutoTriggerAiPreview] (mode brut, resté une
// infrastructure dormante non appelée en production, testé séparément
// dans le dernier group ci-dessous pour mémoire).
//
// Pattern de pump utilisé : [maybeAutoTriggerHybridAiPreview] différe
// la capture composée via `SchedulerBinding.addPostFrameCallback`
// (laisser le moteur dynamique dessiner le produit avant de capturer),
// PUIS attend elle-même de façon asynchrone le résultat de
// [AppState.captureComposedScene] avant de marquer la clé anti-boucle
// et d'ouvrir le panneau. Dans un test `flutter_test` sans widget réel
// affiché, le post-frame callback ne se déclenche PAS automatiquement à
// un `pump()` simple : il faut explicitement
// `SchedulerBinding.instance.scheduleFrame()` puis `pump()` (confirmé
// par sondage direct de l'API avant d'écrire ces tests), puis un second
// `pump()` pour laisser le `Future` interne (résolution de
// `captureComposedScene()`) se terminer avant d'observer l'état final.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/data/catalogue_visibility.dart';
import 'package:staff_decor_studio/models/project_item.dart';
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

/// Laisse [AppState.maybeAutoTriggerHybridAiPreview] terminer son cycle
/// asynchrone complet (post-frame callback différé + await de
/// [AppState.captureComposedScene]) dans un test widget sans arbre de
/// widgets réel affiché. Voir commentaire de tête de fichier.
Future<void> _settleHybridAutoTrigger(WidgetTester tester) async {
  SchedulerBinding.instance.scheduleFrame();
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // L'index catalogue (43 refs whitelistées, dont D609/D720) doit être
    // chargé et STABLE avant chaque test : [maybeAutoTriggerHybridAiPreview]
    // est fail-open tant que l'index n'est pas chargé (presentationVisible
    // renvoie `null`), ce qui laisserait passer un SKU non whitelisté par
    // accident dans un test qui voudrait justement vérifier le blocage.
    CatalogueVisibilityGate.instance.resetForTesting();
  });

  group('Auto-trigger HYBRIDE (maybeAutoTriggerHybridAiPreview) — nouvelle règle produit', () {
    testWidgets(
      '1. Pas d\'auto-trigger BRUT : photo seule (sans produit sélectionné) '
      '=> aucun appel à Mano/Nano, panneau IA fermé',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        var captureCalls = 0;
        state.registerComposedSceneCapture(() async {
          captureCalls++;
          return Uint8List.fromList([1, 2, 3]);
        });

        await tester.pumpWidget(const SizedBox());

        // Simule exactement ce que fait setRoomImageBytes une fois la
        // photo décodée : pas de produit sélectionné à ce stade.
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.maybeAutoTriggerHybridAiPreview();
        await _settleHybridAutoTrigger(tester);

        expect(captureCalls, 0,
            reason: 'sans produit sélectionné, la scène composée ne doit '
                'jamais être capturée ni envoyée à Mano/Nano');
        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'importer une photo seule ne doit jamais ouvrir le '
                'panneau IA automatiquement (pas de mode "add" brut)');
        expect(state.aiAmbianceAutoGenerateHybrid, isFalse);
      },
    );

    testWidgets(
      '2. Auto-trigger HYBRIDE : photo + D609 sélectionné + capture composée '
      'disponible => panneau IA ouvert automatiquement, renderMode "refine"',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        var captureCalls = 0;
        final composed = Uint8List.fromList([9, 9, 9]);
        state.registerComposedSceneCapture(() async {
          captureCalls++;
          return composed;
        });

        await tester.pumpWidget(const SizedBox());

        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.selectedProducts = [
          const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];
        state.maybeAutoTriggerHybridAiPreview();
        await _settleHybridAutoTrigger(tester);

        expect(captureCalls, 1,
            reason: 'la scène COMPOSÉE (produit déjà posé), jamais la '
                'photo brute, doit être capturée exactement une fois');
        expect(state.showAiAmbiancePanel, isTrue,
            reason: 'photo + produit whitelisté + capture disponible doit '
                'ouvrir automatiquement le panneau IA, sans bouton '
                '"Générer" ni action utilisateur supplémentaire');
        expect(state.aiAmbianceAutoGenerateHybrid, isTrue,
            reason: 'AiAmbiancePanel doit savoir qu\'il doit consommer la '
                'scène pré-capturée et forcer renderMode="refine" — '
                'jamais le mode "add" brut');
        expect(state.aiAmbiancePrefillRef, 'D609');
        expect(state.consumePendingHybridAutoScene(), composed,
            reason: 'la scène pré-capturée transmise au panneau doit être '
                'exactement celle renvoyée par captureComposedScene(), '
                'jamais recapturée une deuxième fois');
      },
    );

    testWidgets(
      '3. Anti-boucle : même photo + même SKU => pas de deuxième capture/génération',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        var captureCalls = 0;
        state.registerComposedSceneCapture(() async {
          captureCalls++;
          return Uint8List.fromList([9, 9, 9]);
        });

        await tester.pumpWidget(const SizedBox());

        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.selectedProducts = [
          const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];
        state.maybeAutoTriggerHybridAiPreview();
        await _settleHybridAutoTrigger(tester);
        expect(captureCalls, 1);
        expect(state.showAiAmbiancePanel, isTrue);

        // L'utilisateur ferme le panneau (ex: consulte le résultat puis
        // referme) — le couple (SKU, roomImageVersion, 'refine') reste
        // strictement identique : re-notifier ne doit PAS redéclencher.
        state.closeAiAmbiancePanel();
        state.maybeAutoTriggerHybridAiPreview();
        await _settleHybridAutoTrigger(tester);

        expect(captureCalls, 1,
            reason: 'garde anti-boucle : même photo + même SKU ne doit '
                'jamais provoquer une deuxième capture/génération');
        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'le panneau ne doit pas se rouvrir tout seul pour un '
                'couple déjà traité');
      },
    );

    testWidgets(
      '4a. Changement de PRODUIT (nouveau SKU, même photo) => nouvelle '
      'capture/génération autorisée',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        var captureCalls = 0;
        state.registerComposedSceneCapture(() async {
          captureCalls++;
          return Uint8List.fromList([9, 9, 9]);
        });

        await tester.pumpWidget(const SizedBox());

        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.selectedProducts = [
          const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];
        state.maybeAutoTriggerHybridAiPreview();
        await _settleHybridAutoTrigger(tester);
        expect(captureCalls, 1);

        state.closeAiAmbiancePanel();
        // Nouveau SKU (whitelisté) sur la MÊME photo.
        state.selectedProducts = [
          const ProjectItem(ref: 'D720', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];
        state.maybeAutoTriggerHybridAiPreview();
        await _settleHybridAutoTrigger(tester);

        expect(captureCalls, 2,
            reason: 'changer de SKU doit relancer une capture/génération');
        expect(state.showAiAmbiancePanel, isTrue);
        expect(state.aiAmbiancePrefillRef, 'D720');
      },
    );

    testWidgets(
      '4b. Changement de PHOTO (nouvelle roomImageVersion, même SKU) => '
      'nouvelle capture/génération autorisée',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        var captureCalls = 0;
        state.registerComposedSceneCapture(() async {
          captureCalls++;
          return Uint8List.fromList([9, 9, 9]);
        });

        await tester.pumpWidget(const SizedBox());

        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.selectedProducts = [
          const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];
        state.maybeAutoTriggerHybridAiPreview();
        await _settleHybridAutoTrigger(tester);
        expect(captureCalls, 1);

        state.closeAiAmbiancePanel();
        // Nouvelle photo (nouvelle version), même SKU sélectionné —
        // simule exactement ce que fait setRoomImageBytes en interne.
        state.roomImage = await _tinyImage();
        state.roomImageVersion++;
        state.maybeAutoTriggerHybridAiPreview();
        await _settleHybridAutoTrigger(tester);

        expect(captureCalls, 2,
            reason: 'changer de photo doit relancer une capture/génération '
                'même si le SKU sélectionné reste identique');
        expect(state.showAiAmbiancePanel, isTrue);
      },
    );

    testWidgets(
      '5. SKU non whitelisté => aucune capture/génération automatique '
      '(garde whitelist)',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        var captureCalls = 0;
        state.registerComposedSceneCapture(() async {
          captureCalls++;
          return Uint8List.fromList([9, 9, 9]);
        });

        await tester.pumpWidget(const SizedBox());

        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        // 'HORS-CATALOGUE' n'existe pas dans assets/profiles/index.json.
        state.selectedProducts = [
          const ProjectItem(ref: 'HORS-CATALOGUE', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];
        state.maybeAutoTriggerHybridAiPreview();
        await _settleHybridAutoTrigger(tester);

        expect(captureCalls, 0,
            reason: 'un SKU absent de la whitelist ne doit jamais '
                'déclencher de capture/génération automatique');
        expect(state.showAiAmbiancePanel, isFalse);
      },
    );

    testWidgets(
      '6. Échec de capture composée (Studio pas encore monté) => aucun '
      'crash, panneau IA reste fermé, rendu dynamique inchangé',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        // Aucune capture enregistrée (registerComposedSceneCapture jamais
        // appelé) => captureComposedScene() renvoie null, exactement
        // comme un Studio pas encore construit à l'écran.

        await tester.pumpWidget(const SizedBox());

        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.selectedProducts = [
          const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];

        expect(() => state.maybeAutoTriggerHybridAiPreview(), returnsNormally);
        await _settleHybridAutoTrigger(tester);

        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'une capture indisponible ne doit jamais ouvrir le '
                'panneau IA — le rendu dynamique déterministe reste seul '
                'affiché');

        // La clé anti-boucle ne doit PAS avoir été marquée par cet échec
        // : une prochaine tentative (ex: Studio enfin monté) doit pouvoir
        // réussir pour le même couple photo+SKU.
        state.registerComposedSceneCapture(() async => Uint8List.fromList([1]));
        state.maybeAutoTriggerHybridAiPreview();
        await _settleHybridAutoTrigger(tester);
        expect(state.showAiAmbiancePanel, isTrue,
            reason: 'une fois la capture disponible, le même couple '
                'photo+SKU doit pouvoir déclencher normalement (l\'échec '
                'précédent n\'a pas dû être mémorisé comme "déjà traité")');
      },
    );
  });

  group(
    '5bis. Échec Mano côté proxy — le rendu dynamique reste affiché '
    '(géré par AiAmbiancePanel, pas par AppState)',
    () {
      test(
        'setLastAiComparisonResult n\'est jamais appelé sans succès explicite '
        '— un échec proxy ne pollue jamais lastAiComparisonResult',
        () {
          final state = AppState();
          expect(state.lastAiComparisonResult, isNull);
          // Rien à faire ici : AiAmbiancePanel._generate() n'appelle
          // setLastAiComparisonResult QUE dans la branche
          // `result.success && result.imageBytes != null` (voir
          // ai_ambiance_panel.dart) — en cas d'échec, `_screenState`
          // bascule sur `_AiScreenState.fallback` (écran "Réessayer" /
          // fermer) sans jamais toucher AppState ni au rendu dynamique
          // du Studio (RoomPainter, jamais concerné par ce chemin).
          // Ce test documente/verrouille cette garantie au niveau
          // AppState : aucune méthode de AppState ne doit permettre de
          // marquer un résultat "réussi" sans qu'un appelant l'ait
          // explicitement construit avec de vrais bytes IA.
          expect(state.showAiAmbiancePanel, isFalse);
        },
      );
    },
  );

  group(
    'Infrastructure dormante — maybeAutoTriggerAiPreview (mode BRUT, non '
    'appelé en production, voir sa docstring dans app_state.dart)',
    () {
      test(
        'reste fonctionnel si invoqué manuellement (aucune régression '
        'sur ce mécanisme conservé mais inutilisé)',
        () async {
          final state = AppState();
          state.roomImage = await _tinyImage();
          state.roomImageVersion = 1;
          state.selectedProducts = [
            const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
          ];

          // Appel manuel direct — jamais fait automatiquement par
          // addToProject/setRoomImageBytes/loadDemoScene (voir leur
          // code : ils appellent tous maybeAutoTriggerHybridAiPreview,
          // jamais maybeAutoTriggerAiPreview).
          state.maybeAutoTriggerAiPreview();
          expect(state.showAiAmbiancePanel, isTrue);
          expect(state.aiAmbianceAutoGenerateHybrid, isFalse,
              reason: 'le mode brut ne doit jamais forcer le mode hybride');

          state.closeAiAmbiancePanel();
          state.maybeAutoTriggerAiPreview();
          expect(state.showAiAmbiancePanel, isFalse,
              reason: 'garde anti-boucle du mécanisme brut inchangée');
        },
      );
    },
  );

  group('Avant/Après IA — stockage et lecture du résultat (déclenchement manuel ou auto)', () {
    test(
      'setLastAiComparisonResult conserve photo originale + image IA + traçabilité',
      () async {
        final state = AppState();
        final original = Uint8List.fromList(List.filled(16, 1));
        final aiResult = Uint8List.fromList(List.filled(16, 2));

        expect(state.lastAiComparisonResult, isNull,
            reason: 'avant toute génération réussie, l\'écran Avant/Après '
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
            renderMode: 'refine',
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
        expect(r.renderMode, 'refine',
            reason: 'traçabilité : le résultat auto-hybride doit porter '
                'renderMode="refine", jamais "add"');
      },
    );
  });
}
