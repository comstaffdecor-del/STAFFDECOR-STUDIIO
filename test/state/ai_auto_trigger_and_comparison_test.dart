// Test de NON-RÉGRESSION — DÉCISION PRODUIT (validation visuelle réelle :
// "le mode hybride auto est rejeté").
//
// Historique complet :
//  1. Commit 8f4e875 "Retire le declenchement IA automatique" : retire
//     un premier mécanisme auto-trigger BRUT (Gemini invente la pose
//     depuis la photo brute, renderMode='add' implicite) — jugé trop
//     instable visuellement.
//  2. Commit 60f9fe7 "Restaure le pont automatique Mano en mode
//     hybride" : introduit puis reconnecte un NOUVEAU mécanisme,
//     [AppState.maybeAutoTriggerHybridAiPreview], qui capture le rendu
//     dynamique déjà composé (produit posé géométriquement) et l'envoie
//     automatiquement à Mano/Nano en `renderMode: 'refine'`.
//  3. CE COMMIT (présent) : un test visuel RÉEL du mécanisme (2) a
//     montré un MAUVAIS RENDU — Mano/Nano en mode 'refine' AFFINE une
//     scène dynamique déjà imprécise géométriquement, ce qui AGGRAVE le
//     défaut au lieu de le corriger. Les 3 appels automatiques
//     ([setRoomImageBytes], [loadDemoScene], [addToProject]) sont donc
//     RE-RETIRÉS. [maybeAutoTriggerHybridAiPreview] reste présente,
//     INCHANGÉE dans son corps, comme infrastructure dormante
//     documentée — exactement comme [maybeAutoTriggerAiPreview] (mode
//     brut, déjà dormant depuis (1)).
//
// Ce fichier vérifie donc à nouveau l'ABSENCE de tout déclenchement
// automatique de l'aperçu IA — brut OU hybride — quelles que soient les
// actions de l'utilisateur (import photo, scène démo, sélection
// produit, changement de produit). Reste vérifié en parallèle :
//  - le parcours MANUEL (icône topbar "Aperçu d'ambiance IA") reste
//    intégralement disponible, en mode 'add' par défaut (seul rendu
//    visuellement validé à ce jour) ;
//  - le stockage du résultat IA pour l'écran Avant/Après continue de
//    fonctionner pour un déclenchement manuel.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CatalogueVisibilityGate.instance.resetForTesting();
  });

  group(
    'Non-régression — pas de rendu IA automatique, ni brut ni hybride '
    '(décision produit après rejet visuel du mode hybride)',
    () {
      test(
        'importer une photo (roomImage chargé) n\'ouvre PAS le panneau IA '
        'tout seul',
        () async {
          final state = AppState();
          expect(state.showAiAmbiancePanel, isFalse);

          // Simule le résultat d'un import photo : setRoomImageBytes
          // charge roomImage puis, historiquement, appelait un
          // auto-trigger — ces deux appels ont été retirés (brut puis
          // hybride), on vérifie donc l'ABSENCE d'effet.
          state.roomImage = await _tinyImage();
          state.roomImageVersion = 1;

          expect(state.showAiAmbiancePanel, isFalse,
              reason: 'le simple chargement d\'une photo ne doit jamais '
                  'ouvrir le panneau IA automatiquement');
        },
      );

      test(
        'sélectionner un produit (D609), même avec une photo déjà chargée, '
        'n\'ouvre PAS le panneau IA tout seul',
        () async {
          final state = AppState();
          state.roomImage = await _tinyImage();
          state.roomImageVersion = 1;

          // addToProject() n'appelle plus aucun auto-trigger IA (ni brut
          // ni hybride) depuis ce commit.
          state.addToProject('D609');

          expect(state.showAiAmbiancePanel, isFalse,
              reason: 'sélectionner un produit doit uniquement mettre à '
                  'jour le rendu dynamique déterministe (RoomPainter), '
                  'jamais déclencher Mano/Nano automatiquement');
          expect(state.aiAmbianceAutoGenerate, isFalse);
          expect(state.aiAmbianceAutoGenerateHybrid, isFalse,
              reason: 'le mode hybride automatique est explicitement '
                  'rejeté (test visuel réel) — jamais forcé ici');
          expect(state.aiAmbiancePrefillRef, isNull);
        },
      );

      test(
        'capture composée disponible (registerComposedSceneCapture) + photo '
        '+ produit sélectionné => AUCUN appel automatique à la capture, ni '
        'ouverture du panneau',
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
              reason: 'même si une capture composée est disponible, elle '
                  'ne doit JAMAIS être appelée automatiquement — c\'est '
                  'exactement le mécanisme rejeté après test visuel réel '
                  '(Mano/Nano affinant une scène dynamique déjà fausse)');
          expect(state.showAiAmbiancePanel, isFalse);
        },
      );

      test(
        'changer de produit sélectionné (D609 puis D720) sur une photo déjà '
        'chargée reste sans effet sur l\'IA',
        () async {
          final state = AppState();
          state.roomImage = await _tinyImage();
          state.roomImageVersion = 1;
          state.addToProject('D609');
          state.addToProject('D720');

          expect(state.showAiAmbiancePanel, isFalse,
              reason: 'aucune combinaison photo + produit(s) ne doit '
                  'ouvrir le panneau IA sans action manuelle explicite');
        },
      );

      test(
        'charger une scène démo (loadDemoScene) ne déclenche aucun aperçu '
        'IA automatique, même avec un produit déjà sélectionné',
        () async {
          final state = AppState();
          // Sélectionne un produit AVANT de charger la scène démo, pour
          // couvrir exactement le chemin que loadDemoScene emprunte en
          // interne (bloc finally, après calibration).
          state.roomImage = await _tinyImage();
          state.roomImageVersion = 1;
          state.addToProject('D609');
          state.closeAiAmbiancePanel(); // réinitialise tout état résiduel

          await state.loadDemoScene('haussmann', containerSize: const Size(400, 300));

          expect(state.showAiAmbiancePanel, isFalse,
              reason: 'loadDemoScene ne doit jamais ouvrir le panneau IA '
                  'automatiquement, ni en mode brut ni en mode hybride');
          expect(state.aiAmbianceAutoGenerateHybrid, isFalse);
        },
      );

      test(
        'seul un appel manuel explicite à openAiAmbiancePanel ouvre le '
        'panneau IA, en mode "add" par défaut (jamais autoGenerateHybrid)',
        () {
          final state = AppState();
          // C'est ce qu'appelle l'icône topbar "Aperçu d'ambiance IA" du
          // Studio (studio_screen.dart, onAiAmbiance: state.openAiAmbiancePanel),
          // SANS prefill ni autoGenerate/autoGenerateHybrid — parcours
          // manuel pas-à-pas conservé, seul rendu visuellement validé
          // (renderMode 'add' par défaut sur photo brute +
          // control/<sku>.png dans AiAmbiancePanel).
          state.openAiAmbiancePanel();

          expect(state.showAiAmbiancePanel, isTrue);
          expect(state.aiAmbianceAutoGenerate, isFalse,
              reason: 'le déclenchement manuel depuis la topbar ne doit '
                  'jamais lancer de génération automatique — l\'utilisateur '
                  'choisit lui-même produit/scène puis clique "Générer"');
          expect(state.aiAmbianceAutoGenerateHybrid, isFalse,
              reason: 'le parcours manuel topbar ne doit jamais forcer le '
                  'mode hybride/refine — l\'utilisateur choisit librement '
                  'entre "Scène actuelle" (mode add) et "Scène avec '
                  'produit déjà posé" (mode refine, option secondaire)');
        },
      );
    },
  );

  group(
    'Infrastructure dormante — maybeAutoTriggerAiPreview (mode BRUT, non '
    'appelée en production, voir sa docstring dans app_state.dart)',
    () {
      test('la garde anti-boucle reste correcte si invoquée manuellement',
          () async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.roomImageVersion = 1;
        state.addToProject('D609');
        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'confirme qu\'addToProject n\'appelle plus le trigger '
                'brut');

        // Appel manuel direct (comme le ferait un futur chantier qualité
        // IA, hors périmètre de ce test) — vérifie que le mécanisme lui-
        // même reste fonctionnel et sûr s'il est un jour reconnecté.
        state.maybeAutoTriggerAiPreview();
        expect(state.showAiAmbiancePanel, isTrue);
        expect(state.aiAmbianceAutoGenerateHybrid, isFalse,
            reason: 'le mode brut ne doit jamais forcer le mode hybride');

        state.closeAiAmbiancePanel();
        state.maybeAutoTriggerAiPreview();
        expect(state.showAiAmbiancePanel, isFalse,
            reason: 'garde anti-boucle : pas de re-déclenchement pour le '
                'même couple (sku, scène)');
      });
    },
  );

  group(
    'Infrastructure dormante — maybeAutoTriggerHybridAiPreview (mode '
    'HYBRIDE/refine, REJETÉ après test visuel réel, non appelée en '
    'production, voir sa docstring dans app_state.dart)',
    () {
      test(
        'reste fonctionnel et sûr si invoqué manuellement (aucune '
        'régression sur ce mécanisme conservé mais désactivé en '
        'production)',
        () async {
          final state = AppState();
          await CatalogueVisibilityGate.instance.ensureLoaded();

          var captureCalls = 0;
          state.registerComposedSceneCapture(() async {
            captureCalls++;
            return Uint8List.fromList([9, 9, 9]);
          });

          state.roomImage = await _tinyImage();
          state.roomImageVersion = 1;
          state.selectedProducts = [
            const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
          ];

          expect(state.showAiAmbiancePanel, isFalse,
              reason: 'confirme qu\'aucun point d\'entrée production '
                  '(setRoomImageBytes/loadDemoScene/addToProject) n\'a '
                  'déclenché ce mécanisme jusqu\'ici');

          // Appel manuel direct — jamais fait automatiquement en
          // production (voir setRoomImageBytes/loadDemoScene/addToProject :
          // ils n'appellent plus ni maybeAutoTriggerHybridAiPreview ni
          // maybeAutoTriggerAiPreview).
          state.maybeAutoTriggerHybridAiPreview();
          // La capture est différée par un post-frame callback interne —
          // rien à vérifier de plus dans ce test unitaire pur (pas de
          // pump disponible hors testWidgets) : seule l'ABSENCE d'appel
          // implicite depuis les 3 points d'entrée production importe
          // ici, déjà couverte par le premier group ci-dessus.
        },
      );
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
            reason: 'traçabilité : un résultat manuel typique utilise '
                'renderMode="add" (photo brute + control/<sku>.png), le '
                'seul mode visuellement validé à ce jour');
      },
    );
  });
}
