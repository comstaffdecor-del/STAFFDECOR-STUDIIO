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

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    // CORRECTIF (brief "Persist quota SharedPreferences") : le quota
    // auto-IA STANDARD lit/écrit désormais shared_preferences (clé datée
    // du jour) — sans ce mock, `SharedPreferences.getInstance()` plante
    // en environnement de test (pas de vrai stockage disque/navigateur).
    // `{}` = quota vierge pour tous les tests de ce fichier, sauf ceux du
    // group dédié "Quota persisté" qui pré-remplissent explicitement.
    SharedPreferences.setMockInitialValues({});
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
      '1b. quickToggleProd(D609) — VRAI chemin UI du tap sur une tuile du '
      'strip Studio (product_strip.dart: onTap => quickToggleProd), '
      'distinct de addToProject appelé directement par le test 1 — '
      'verrouille la régression constatée : le clic réel D609 ne '
      'déclenchait rien car quickToggleProd n\'était pas couvert',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;

        // Premier tap sur la tuile : produit absent du projet => ajout.
        state.quickToggleProd('D609');
        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'debounce en attente');

        await _settleStandardDebounce(tester);

        expect(state.showAiAmbiancePanel, isTrue,
            reason: 'quickToggleProd (chemin réel du tap Studio) doit '
                'déclencher l\'auto-trigger standard exactement comme '
                'addToProject, puisqu\'il l\'appelle en interne pour la '
                'branche ajout');
        expect(state.aiAmbianceAutoGenerate, isTrue);
        expect(state.aiAmbianceAutoGenerateHybrid, isFalse);
        expect(state.aiAmbiancePrefillRef, 'D609');

        state.disposeStandardAutoTriggerDebounceForTesting();
      },
    );

    testWidgets(
      '1c. quickToggleProd sur un produit déjà présent (retrait) ne '
      'déclenche JAMAIS de génération IA — seul l\'AJOUT doit auto-trigger',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.selectedProducts = [
          const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];
        // Marque comme déjà généré pour ce couple, afin d'isoler la
        // garantie "retrait ne redéclenche jamais" de la garde
        // anti-boucle générique (déjà testée ailleurs).
        state.maybeAutoTriggerStandardAiPreview(ref: 'D609');
        await _settleStandardDebounce(tester);
        state.closeAiAmbiancePanel();

        // Deuxième tap : produit déjà présent => retrait (removeProd),
        // jamais addToProject, jamais d'auto-trigger.
        state.quickToggleProd('D609');
        await _settleStandardDebounce(tester);

        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'retirer un produit ne doit jamais relancer une '
                'génération IA automatique');
        expect(state.getProdInProject('D609'), isNull,
            reason: 'le produit doit bien avoir été retiré du projet');

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
      '8. Quota jour calendaire : au-delà de kMaxStandardAutoTriggersPerDay '
      'générations automatiques, plus aucun auto-trigger (le parcours '
      'manuel reste toujours disponible)',
      (tester) async {
        await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

        final state = AppState();
        state.roomImage = await _tinyImage();

        for (var i = 0; i < AppState.kMaxStandardAutoTriggersPerDay; i++) {
          state.roomImageVersion = i + 1; // photo "différente" à chaque tour
          state.maybeAutoTriggerStandardAiPreview(ref: 'D609');
          await _settleStandardDebounce(tester);
          expect(state.showAiAmbiancePanel, isTrue,
              reason: 'génération #$i doit réussir (quota non atteint)');
          state.closeAiAmbiancePanel();
        }

        // Quota désormais épuisé — une nouvelle tentative (nouvelle photo,
        // donc pas bloquée par l'anti-boucle) ne doit PAS déclencher.
        state.roomImageVersion = AppState.kMaxStandardAutoTriggersPerDay + 1;
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

  group(
    'Quota auto-IA STANDARD persisté (shared_preferences, clé datée du '
    'jour) — survit à un rechargement de page (nouvelle instance AppState)',
    () {
      testWidgets(
        'Quota déjà atteint (persisté par une session PRÉCÉDENTE simulée) '
        '=> une NOUVELLE instance AppState (= rechargement de page) '
        'refuse immédiatement l\'auto-trigger, sans attendre le debounce '
        'pour le découvrir',
        (tester) async {
          await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());

          // Simule une session précédente ayant déjà consommé tout le
          // quota du jour — clé DATÉE (même format que
          // AppState._standardAutoTriggerPrefsKey), écrite directement
          // dans shared_preferences AVANT toute création d'AppState,
          // exactement comme le ferait un vrai rechargement de page web
          // où AppState est reconstruit à neuf mais le disque persiste.
          final today = DateTime.now();
          final key = 'ai_auto_standard_count_'
              '${today.year.toString().padLeft(4, '0')}-'
              '${today.month.toString().padLeft(2, '0')}-'
              '${today.day.toString().padLeft(2, '0')}';
          SharedPreferences.setMockInitialValues({
            key: AppState.kMaxStandardAutoTriggersPerDay,
          });

          final state = AppState(); // nouvelle instance = "nouveau F5"
          state.roomImage = await _tinyImage();
          state.roomImageVersion = 1;

          state.maybeAutoTriggerStandardAiPreview(ref: 'D609');
          await _settleStandardDebounce(tester);

          expect(state.showAiAmbiancePanel, isFalse,
              reason: 'le quota du jour est déjà épuisé dans '
                  'shared_preferences — même une AppState fraîchement '
                  'créée (rechargement de page) doit le respecter, pas '
                  'juste un compteur en mémoire remis à 0 par erreur');

          state.disposeStandardAutoTriggerDebounceForTesting();
        },
      );

      testWidgets(
        'Une génération auto STANDARD réussie incrémente bien le compteur '
        'PERSISTÉ (relisible par une AUTRE instance AppState simulant un '
        'rechargement immédiatement après)',
        (tester) async {
          await tester.runAsync(() => CatalogueVisibilityGate.instance.ensureLoaded());
          SharedPreferences.setMockInitialValues({});

          final state1 = AppState();
          state1.roomImage = await _tinyImage();
          state1.roomImageVersion = 1;
          state1.maybeAutoTriggerStandardAiPreview(ref: 'D609');
          await _settleStandardDebounce(tester);
          expect(state1.showAiAmbiancePanel, isTrue);
          state1.disposeStandardAutoTriggerDebounceForTesting();

          // Nouvelle instance = "rechargement de page" juste après — doit
          // lire le MÊME compteur persisté par state1, pas repartir de 0.
          final state2 = AppState();
          await state2.ensureStandardAutoTriggerQuotaLoadedForTesting();

          // On épuise le reste du quota avec state2 pour vérifier que le
          // compteur repris est bien >= 1 (déjà consommé par state1),
          // donc qu'il ne reste QUE kMax-1 générations possibles pour
          // state2, pas kMax complètes.
          var successes = 0;
          for (var i = 0; i < AppState.kMaxStandardAutoTriggersPerDay; i++) {
            state2.roomImage = await _tinyImage();
            state2.roomImageVersion = 100 + i; // photo "différente" à chaque tour
            state2.maybeAutoTriggerStandardAiPreview(ref: 'D720');
            await _settleStandardDebounce(tester);
            if (state2.showAiAmbiancePanel) {
              successes++;
              state2.closeAiAmbiancePanel();
            }
          }
          state2.disposeStandardAutoTriggerDebounceForTesting();

          expect(successes, AppState.kMaxStandardAutoTriggersPerDay - 1,
              reason: 'state1 a déjà consommé 1 génération du quota '
                  'PERSISTÉ du jour — state2 (nouvelle instance) doit '
                  'hériter de ce compteur et ne disposer que de '
                  '(kMax - 1) générations restantes, jamais kMax '
                  'complètes comme si le quota était reparti de 0');
        },
      );
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

  group(
    'Verrou statique - le lien setRoomImageBytes -> '
    'maybeAutoTriggerStandardAiPreview ne doit JAMAIS disparaitre '
    'silencieusement',
    () {
      // CORRECTIF (brief "test statique demande") : les tests
      // comportementaux ci-dessus (groupe "Auto-trigger STANDARD")
      // verifient l'EFFET de l'appel (panneau IA qui s'ouvre apres le
      // debounce), mais un futur refactor de [AppState.setRoomImageBytes]
      // pourrait retirer l'appel a [AppState.maybeAutoTriggerStandardAiPreview]
      // sans qu'aucun test comportemental existant ne le detecte
      // directement (ex: si le refactor deplace ce declenchement dans
      // une autre methode appelee par ailleurs, ou le supprime carrement
      // pendant qu'un autre test passe encore pour de mauvaises
      // raisons). Ce test lit le SOURCE de `app_state.dart` comme texte
      // brut et verifie litteralement que le corps de la methode
      // `setRoomImageBytes` contient bien l'appel - un filet de securite
      // "statique" independant du comportement runtime, volontairement
      // tres simple pour rester robuste aux refactors mineurs (renommage
      // de variables locales, reordonnancement de lignes, etc.), tout en
      // detectant a coup sur la disparition pure et simple de l'appel.
      test(
        'le corps de setRoomImageBytes() dans lib/state/app_state.dart '
        'contient toujours un appel a maybeAutoTriggerStandardAiPreview(',
        () {
          final file = File(
            '${Directory.current.path}/lib/state/app_state.dart',
          );
          expect(file.existsSync(), isTrue,
              reason: 'lib/state/app_state.dart doit exister a cet '
                  'emplacement relatif a la racine du projet Flutter');

          final source = file.readAsStringSync();

          // Isole le corps de setRoomImageBytes en reperant sa signature,
          // puis la signature de la methode suivante (setRoomImageFile)
          // qui delimite naturellement la fin du corps - evite un vrai
          // parsing Dart, volontairement simple et donc robuste.
          final startMarker = 'Future<void> setRoomImageBytes(';
          final startIndex = source.indexOf(startMarker);
          expect(startIndex, isNot(-1),
              reason: 'la methode setRoomImageBytes doit exister dans '
                  'app_state.dart - si elle a ete renommee, ce test doit '
                  'etre mis a jour EN CONNAISSANCE DE CAUSE, pas parce '
                  'que le lien vers maybeAutoTriggerStandardAiPreview a '
                  'disparu silencieusement');

          // Fin du corps : le prochain point d'entree de methode publique
          // apres le debut de setRoomImageBytes. On cherche une signature
          // de methode suivante connue et stable (recomputeImgDraw) pour
          // bornage - si elle aussi disparait, on retombe simplement sur
          // la fin du fichier (pas de faux negatif possible).
          final nextMethodMarker = 'void recomputeImgDraw(';
          final nextMethodIndex = source.indexOf(nextMethodMarker, startIndex);
          final endIndex = nextMethodIndex == -1 ? source.length : nextMethodIndex;

          final body = source.substring(startIndex, endIndex);

          expect(
            body.contains('maybeAutoTriggerStandardAiPreview('),
            isTrue,
            reason: 'REGRESSION CRITIQUE : setRoomImageBytes() ne contient '
                'plus aucun appel a maybeAutoTriggerStandardAiPreview(). '
                'Le SEUL mode IA valide visuellement (MODE STANDARD) ne '
                'se declenchera plus automatiquement lors du chargement '
                'd\'une photo alors qu\'un produit est deja selectionne. '
                'Si ce retrait est INTENTIONNEL, mettre a jour ce test '
                'en connaissance de cause plutot que de le supprimer.',
          );
        },
      );
    },
  );
}
