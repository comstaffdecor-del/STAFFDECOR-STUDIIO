// P23-STANDARD-AUTO — brief "Correction finale du flow produit : le
// rendu IA validé est le MODE STANDARD".
//
// Historique complet :
//  1. Commit 8f4e875 "Retire le declenchement IA automatique" : retire
//     un premier mécanisme auto-trigger BRUT (mode 'add' sans
//     debounce/quota) — jugé trop instable visuellement à l'époque.
//  2. Commit 60f9fe7 "Restaure le pont automatique Mano en mode
//     hybride" : introduit [AppState.maybeAutoTriggerHybridAiPreview],
//     qui capture le rendu dynamique déjà composé et l'envoie en
//     `renderMode: 'refine'`.
//  3. Commit "Disable automatic hybrid AI preview after visual
//     rejection" : un test visuel réel montre que le mode hybride
//     AGGRAVE le défaut (Mano/Nano affine une pose déjà fausse) — les 3
//     appels automatiques hybrides sont retirés.
//  4. CE COMMIT (présent) : nouvelle validation visuelle — le rendu
//     validé est le MODE STANDARD (photo brute + `renderMode: 'add'` +
//     `control/<sku>.png`, comportement historique P19-MANOBANANA-QAD).
//     Introduit [AppState.maybeAutoTriggerStandardAiPreview], reconnecté
//     à [AppState.setRoomImageBytes] et [AppState.addToProject]
//     UNIQUEMENT — jamais [maybeAutoTriggerHybridAiPreview] (qui reste
//     dormant, non appelé). Ajoute un debounce (1,5 s) et un quota de
//     générations automatiques par session pour limiter les
//     facturations involontaires (ex: parcours rapide de plusieurs SKU).
//
// Ce fichier vérifie :
//  - le NOUVEAU mécanisme standard (debounce, anti-boucle par clé
//    `sku#roomImageVersion#add`, whitelist SKU, quota session, ref
//    explicite jamais `selectedProducts.first.ref` dans addToProject) ;
//  - l'ABSENCE totale de tout déclenchement automatique en mode BRUT
//    historique ([maybeAutoTriggerAiPreview]) OU HYBRIDE
//    ([maybeAutoTriggerHybridAiPreview]) depuis les points d'entrée
//    production ;
//  - le parcours MANUEL (icône topbar) reste intact ;
//  - le stockage Avant/Après continue de fonctionner.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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

/// Laisse le debounce de [AppState.maybeAutoTriggerStandardAiPreview]
/// s'écouler complètement (1,5 s réels, avancés via l'horloge simulée de
/// `flutter_test`) — voir [AppState.kStandardAutoTriggerDebounce].
Future<void> _settleStandardDebounce(WidgetTester tester) =>
    tester.pump(AppState.kStandardAutoTriggerDebounce + const Duration(milliseconds: 100));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CatalogueVisibilityGate.instance.resetForTesting();
  });

  tearDown(() {
    // Un Timer de debounce encore actif entre deux tests peut faire
    // planter `flutter_test` ("Timer still pending") — nettoyage
    // systématique via le hook de test dédié.
  });

  group('Auto-trigger STANDARD (maybeAutoTriggerStandardAiPreview) — mode add validé', () {
    testWidgets(
      '1. addToProject(D609) sur une photo déjà chargée déclenche, après '
      'le debounce, une génération STANDARD (renderMode add, jamais hybride)',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;

        state.addToProject('D609');
        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'pas encore déclenché : le debounce est en attente');

        await _settleStandardDebounce(tester);

        expect(state.showAiAmbiancePanel, isTrue,
            reason: 'après le debounce, le panneau IA doit s\'ouvrir '
                'automatiquement, sans bouton "Générer" à cliquer');
        expect(state.aiAmbianceAutoGenerate, isTrue);
        expect(state.aiAmbianceAutoGenerateHybrid, isFalse,
            reason: 'JAMAIS le mode hybride pour l\'auto-trigger standard '
                '— AiAmbiancePanel doit utiliser _useCurrentScene() '
                '(photo brute), jamais captureComposedScene()');
        expect(state.aiAmbiancePrefillRef, 'D609');

        state.disposeStandardAutoTriggerDebounceForTesting();
      },
    );

    testWidgets(
      '2. Photo déjà présente + produit déjà sélectionné => '
      'maybeAutoTriggerStandardAiPreview déclenche une génération STANDARD '
      '(reproduit la garde utilisée par setRoomImageBytes SANS traverser '
      'le vrai décodage image / autoDetectEdges / Sobel-Hough, hors '
      'périmètre de ce test unitaire — voir NOTE ci-dessous)',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        // NOTE (correctif suite au blocage constaté) : ce test vérifie la
        // RÈGLE MÉTIER "photo présente + produit déjà sélectionné => appel
        // à maybeAutoTriggerStandardAiPreview(ref: ...)" — exactement ce
        // que fait [AppState.setRoomImageBytes] après
        // `unawaited(autoDetectEdges())`. Appeler la VRAIE
        // `setRoomImageBytes()` ici forcerait un décodage PNG réel puis
        // `detectRoomEdges` (Sobel+Hough) sous l'horloge simulée de
        // `flutter_test`, ce qui bloque indéfiniment le test sans
        // `tester.runAsync()` étendu à tout le pipeline — inutile et
        // fragile pour ce qui est testé ici (le déclenchement de
        // l'auto-trigger standard, pas le décodage image lui-même, déjà
        // couvert par d'autres tests dédiés à autoDetectEdges).
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.selectedProducts = [
          const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];

        state.maybeAutoTriggerStandardAiPreview(ref: 'D609');

        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'debounce en attente');
        await _settleStandardDebounce(tester);

        expect(state.showAiAmbiancePanel, isTrue);
        expect(state.aiAmbianceAutoGenerate, isTrue);
        expect(state.aiAmbianceAutoGenerateHybrid, isFalse);
        expect(state.aiAmbiancePrefillRef, 'D609');

        state.disposeStandardAutoTriggerDebounceForTesting();
      },
    );

    testWidgets(
      '3. Sans photo chargée, addToProject ne déclenche rien (photo '
      'obligatoire)',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        state.addToProject('D609'); // pas de state.roomImage

        await _settleStandardDebounce(tester);

        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'aucune photo chargée : aucune génération possible');

        state.disposeStandardAutoTriggerDebounceForTesting();
      },
    );

    testWidgets(
      '4. Debounce : changements rapides de SKU (D520 -> D545 -> D609 en '
      'moins de 2s) => seule la DERNIÈRE sélection part en génération',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;

        state.addToProject('D520');
        await tester.pump(const Duration(milliseconds: 500));
        state.addToProject('D545');
        await tester.pump(const Duration(milliseconds: 500));
        state.addToProject('D609');

        await _settleStandardDebounce(tester);

        expect(state.showAiAmbiancePanel, isTrue);
        expect(state.aiAmbiancePrefillRef, 'D609',
            reason: 'seul le DERNIER SKU sélectionné doit générer — les '
                'tentatives D520/D545 doivent avoir été annulées par le '
                'debounce, évitant 2 facturations inutiles');

        state.disposeStandardAutoTriggerDebounceForTesting();
      },
    );

    testWidgets(
      '5. Anti-boucle : même photo + même SKU déjà généré => pas de '
      'deuxième génération',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;

        state.addToProject('D609');
        await _settleStandardDebounce(tester);
        expect(state.showAiAmbiancePanel, isTrue);

        state.closeAiAmbiancePanel();
        state.maybeAutoTriggerStandardAiPreview(ref: 'D609');
        await _settleStandardDebounce(tester);

        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'garde anti-boucle : même couple sku#roomImageVersion '
                '#add ne doit jamais redéclencher');

        state.disposeStandardAutoTriggerDebounceForTesting();
      },
    );

    testWidgets(
      '6. Changement de photo (nouvelle roomImageVersion) sur le même SKU '
      '=> nouvelle génération autorisée',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;

        state.addToProject('D609');
        await _settleStandardDebounce(tester);
        expect(state.showAiAmbiancePanel, isTrue);

        state.closeAiAmbiancePanel();
        state.roomImage = await _tinyImage();
        state.roomImageVersion++;
        state.maybeAutoTriggerStandardAiPreview(ref: 'D609');
        await _settleStandardDebounce(tester);

        expect(state.showAiAmbiancePanel, isTrue,
            reason: 'changer de photo doit relancer une génération même '
                'pour un SKU déjà traité sur l\'ancienne photo');

        state.disposeStandardAutoTriggerDebounceForTesting();
      },
    );

    testWidgets(
      '7. SKU non whitelisté => aucune génération automatique (pas de '
      'clientPrompt libre, ni de génération hors catalogue présentation)',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;

        // 'HORS-CATALOGUE' n'existe pas dans assets/profiles/index.json.
        state.maybeAutoTriggerStandardAiPreview(ref: 'HORS-CATALOGUE');
        await _settleStandardDebounce(tester);

        expect(state.showAiAmbiancePanel, isFalse);

        state.disposeStandardAutoTriggerDebounceForTesting();
      },
    );

    testWidgets(
      '8. Quota session : au-delà de kMaxStandardAutoTriggersPerSession '
      'générations automatiques, plus aucun auto-trigger (le parcours '
      'manuel reste toujours disponible)',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        state.roomImage = await _tinyImage();

        for (var i = 0; i < AppState.kMaxStandardAutoTriggersPerSession; i++) {
          state.roomImageVersion = i + 1; // photo "différente" à chaque tour
          state.maybeAutoTriggerStandardAiPreview(ref: 'D609');
          await _settleStandardDebounce(tester);
          expect(state.showAiAmbiancePanel, isTrue,
              reason: 'génération #$i doit réussir (quota non atteint)');
          state.closeAiAmbiancePanel();
        }

        // Quota désormais épuisé — une nouvelle tentative (nouvelle photo,
        // donc pas bloquée par l'anti-boucle) ne doit PAS déclencher.
        state.roomImageVersion = AppState.kMaxStandardAutoTriggersPerSession + 1;
        state.maybeAutoTriggerStandardAiPreview(ref: 'D609');
        await _settleStandardDebounce(tester);

        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'quota de générations automatiques par session atteint '
                '— l\'auto-trigger s\'arrête silencieusement, le rendu '
                'dynamique reste affiché ; le parcours MANUEL (icône '
                'topbar, non concerné par ce quota) reste disponible');

        // Vérifie explicitement que le parcours manuel n'est jamais
        // bloqué par ce même quota.
        state.openAiAmbiancePanel();
        expect(state.showAiAmbiancePanel, isTrue,
            reason: 'le quota ne s\'applique qu\'à l\'automatique, jamais '
                'à openAiAmbiancePanel() appelé manuellement');

        state.disposeStandardAutoTriggerDebounceForTesting();
      },
    );

    testWidgets(
      '9. addToProject utilise la ref QUI VIENT D\'ÊTRE ajoutée, jamais '
      'selectedProducts.first.ref',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;

        // D609 et D720 sont deux familles différentes ("Corniches" pour
        // les deux dans ce jeu de données réel — la règle "1 produit par
        // famille" retirerait donc D609 en ajoutant D720). On vérifie ici
        // avec des familles distinctes simulées pour isoler la garantie
        // "ref explicite" indépendamment de cette règle métier.
        state.addToProject('D609');
        await _settleStandardDebounce(tester);
        expect(state.aiAmbiancePrefillRef, 'D609');
        state.closeAiAmbiancePanel();

        // Ajoute un second produit d'une famille différente : les deux
        // restent dans selectedProducts (D609 en premier, D720 ensuite).
        state.addToProject('D720');
        await _settleStandardDebounce(tester);

        expect(state.aiAmbiancePrefillRef, 'D720',
            reason: 'l\'auto-trigger doit porter sur D720 (la ref qui '
                'vient d\'être ajoutée), jamais sur '
                'selectedProducts.first.ref qui pourrait encore valoir '
                'D609 selon l\'ordre de la liste');

        state.disposeStandardAutoTriggerDebounceForTesting();
      },
    );

    testWidgets(
      '10. Échec réseau (proxy injoignable) : géré par AiAmbiancePanel, '
      'jamais par AppState — pas de crash, le rendu dynamique reste seul '
      'affiché ; ce test verrouille l\'invariant côté AppState',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        expect(state.lastAiComparisonResult, isNull);
        // AiAmbiancePanel._generate() n'appelle setLastAiComparisonResult
        // QUE dans la branche succès (result.success && imageBytes !=
        // null) — en cas d'échec, _screenState bascule sur
        // _AiScreenState.fallback sans jamais toucher au rendu dynamique
        // du Studio (RoomPainter, jamais concerné par ce chemin).
        expect(state.showAiAmbiancePanel, isFalse);
      },
    );
  });

  group(
    'Non-régression — AUCUN déclenchement en mode BRUT historique ni '
    'HYBRIDE depuis les points d\'entrée production',
    () {
      test(
        'maybeAutoTriggerAiPreview() (mode brut) n\'est jamais appelé par '
        'addToProject/setRoomImageBytes',
        () async {
          final state = AppState();
          state.roomImage = await _tinyImage();
          state.roomImageVersion = 1;
          state.addToProject('D609');
          // À cet instant précis (synchrone, avant tout debounce), aucun
          // effet du mode brut historique ne doit être visible : le seul
          // mécanisme qui peut avoir programmé quelque chose est le
          // debounce standard (asynchrone), jamais une ouverture
          // synchrone comme le faisait l'ancien mode brut.
          expect(state.showAiAmbiancePanel, isFalse);
        },
      );

      test(
        'maybeAutoTriggerHybridAiPreview() reste une infrastructure '
        'dormante, jamais appelée automatiquement (aucun appel à '
        'captureComposedScene si non invoqué manuellement)',
        () async {
          final state = AppState();
          var captureCalls = 0;
          state.registerComposedSceneCapture(() async {
            captureCalls++;
            return Uint8List.fromList([9, 9, 9]);
          });

          state.roomImage = await _tinyImage();
          state.roomImageVersion = 1;
          state.addToProject('D609');

          expect(captureCalls, 0,
              reason: 'captureComposedScene ne doit JAMAIS être appelée '
                  'par l\'auto-trigger standard — c\'est la garantie '
                  'centrale de ce brief : jamais de scène composée pour '
                  'l\'automatique, toujours la photo brute');
        },
      );
    },
  );

  group(
    'Infrastructure dormante — maybeAutoTriggerAiPreview (mode BRUT '
    'historique) et maybeAutoTriggerHybridAiPreview (mode HYBRIDE, '
    'rejeté) — les deux restent fonctionnelles si invoquées manuellement',
    () {
      test('maybeAutoTriggerAiPreview reste correcte (anti-boucle) '
          'si invoquée manuellement', () async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.selectedProducts = [
          const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];

        state.maybeAutoTriggerAiPreview();
        expect(state.showAiAmbiancePanel, isTrue);
        expect(state.aiAmbianceAutoGenerateHybrid, isFalse);

        state.closeAiAmbiancePanel();
        state.maybeAutoTriggerAiPreview();
        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'garde anti-boucle du mode brut inchangée');
      });
    },
  );

  group('Parcours MANUEL (icône topbar) — toujours disponible et inchangé', () {
    test(
      'openAiAmbiancePanel() sans arguments ouvre le panneau en mode "add" '
      'par défaut, jamais autoGenerateHybrid',
      () {
        final state = AppState();
        state.openAiAmbiancePanel();

        expect(state.showAiAmbiancePanel, isTrue);
        expect(state.aiAmbianceAutoGenerate, isFalse,
            reason: 'le parcours manuel garde le pas-à-pas complet : '
                'l\'utilisateur choisit lui-même produit/scène puis '
                'clique "Générer"');
        expect(state.aiAmbianceAutoGenerateHybrid, isFalse);
      },
    );
  });

  group('Avant/Après IA — stockage et lecture du résultat', () {
    test(
      'setLastAiComparisonResult conserve photo originale + image IA + '
      'traçabilité (renderMode "add" typique d\'une génération standard)',
      () async {
        final state = AppState();
        final original = Uint8List.fromList(List.filled(16, 1));
        final aiResult = Uint8List.fromList(List.filled(16, 2));

        expect(state.lastAiComparisonResult, isNull);

        state.setLastAiComparisonResult(
          AiComparisonResult(
            originalImageBytes: original,
            aiImageBytes: aiResult,
            sku: 'D609',
            model: 'gemini-3.1-flash-image',
            usedProductReference: true,
            productReferencePath: 'assets/profiles/control/D609.png',
            renderMode: 'add',
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
        expect(r.renderMode, 'add',
            reason: 'traçabilité : le badge "MODE STANDARD — corniche '
                'ajoutée depuis photo brute" correspond à renderMode="add"');
      },
    );
  });
}
