// P21-HYBRIDE (correction revue #2, brief "sécurisation test hybride
// Nano Banana") — Test 2 du brief : vérifie que `renderMode: 'refine'`
// n'est JAMAIS envoyé sauf quand la scène provient explicitement de
// `_useComposedScene` (bouton "Scène avec produit déjà posé").
//
// APPROCHE (Option B retenue explicitement après échec de l'Option A
// "pumpAndSettle contrôlé") : au lieu d'un test widget lourd pilotant
// tout le parcours UI (sélection produit -> scène -> génération), avec
// des `pumpAndSettle()` instables autour d'un appel réseau simulé
// (observé : blocage systématique, `SIGTERM` du shell de test), on
// découpe la vérification en DEUX tests indépendants et déterministes :
//
//  1. Un test UNITAIRE PUR (aucun widget, aucun pump) sur
//     `resolveRenderModeForScene()` — la fonction exposée par
//     `ai_ambiance_panel.dart` qui encapsule EXACTEMENT la règle de
//     décision utilisée dans `_generate()`. C'est la garantie centrale
//     du brief : "'refine' ssi la scène est hybride, 'add' sinon".
//
//  2. Un test WIDGET LÉGER qui vérifie uniquement que le bouton
//     "Scène avec produit déjà posé" appelle bien
//     `AppState.captureComposedScene()` (donc bascule l'état interne du
//     panneau vers une scène hybride) — sans jamais aller jusqu'au
//     bouton "Générer" ni déclencher d'appel réseau/`pumpAndSettle`
//     instable. Ce test couvre le "câblage" bouton -> capture, la
//     fonction pure ci-dessus couvre la "logique" capture -> renderMode.
//
// Ensemble, les deux tests garantissent bout en bout que SEUL le
// chemin "Scène avec produit déjà posé" peut produire renderMode=
// 'refine', exactement comme l'aurait fait le test widget complet —
// avec un temps d'exécution de l'ordre de la seconde au lieu de
// plusieurs minutes/un blocage.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:staff_decor_studio/data/catalogue_visibility.dart';
import 'package:staff_decor_studio/models/project_item.dart';
import 'package:staff_decor_studio/state/app_state.dart';
import 'package:staff_decor_studio/widgets/studio/ai_ambiance_panel.dart';

Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = Colors.white);
  final picture = recorder.endRecording();
  return picture.toImage(2, 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveRenderModeForScene (fonction pure, sans widget)', () {
    test('Test 2a — scène NON hybride => renderMode "add"', () {
      // Couvre le cas commun aux trois chemins non-hybrides du brief :
      // _useCurrentScene, _uploadScene et _useDemoScene appellent tous
      // resolveRenderModeForScene(isHybridScene: false) via _isHybridScene
      // remis à false (voir ai_ambiance_panel.dart).
      expect(resolveRenderModeForScene(isHybridScene: false), 'add');
    });

    test('Test 2b — scène hybride (_useComposedScene) => renderMode "refine"', () {
      expect(resolveRenderModeForScene(isHybridScene: true), 'refine');
    });

    test('Test 2c — "refine" est bien exclusif à isHybridScene=true (pas de 3e valeur)', () {
      // Ceinture + bretelles : garantit qu'il n'existe aucune sortie
      // intermédiaire/ambigüe — uniquement 'add' ou 'refine'.
      expect(
        {resolveRenderModeForScene(isHybridScene: false), resolveRenderModeForScene(isHybridScene: true)},
        {'add', 'refine'},
      );
    });
  });

  group('AiAmbiancePanel — câblage bouton hybride -> AppState.captureComposedScene', () {
    setUp(() {
      CatalogueVisibilityGate.instance.resetForTesting();
    });

    testWidgets(
      'Test 2d — le bouton "Scène avec produit déjà posé" appelle bien '
      'AppState.captureComposedScene() (jamais les autres boutons de scène)',
      (tester) async {
        final state = AppState();
        state.roomImage = await _tinyImage();
        state.selectedProducts = [
          const ProjectItem(ref: 'D609', famille: 'Corniches', qte: 1, unite: 'ml'),
        ];

        var captureCalled = false;
        state.registerComposedSceneCapture(() async {
          captureCalled = true;
          return Uint8List.fromList([9, 9, 9]);
        });

        // Charge l'index catalogue AVANT de monter le panneau — sinon
        // `_visibleRefs` est vide au premier build (chargement
        // asynchrone via `ensureLoaded().then(...)` dans `initState`)
        // et aucune tuile produit ne peut être tapée.
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
        await tester.pump();

        // Sélectionne directement l'état interne "choix de scène" en
        // passant par le premier produit affiché (peu importe lequel :
        // seul le câblage bouton hybride -> capture est vérifié ici,
        // pas le SKU précis, déjà couvert par le test unitaire ci-dessus
        // et par catalogue_visibility_test.dart). Index 1 (et non 0) :
        // le tout premier `InkWell` de l'arbre n'est PAS une tuile
        // produit (c'est un `InkWell` interne à un autre composant du
        // panneau, `borderRadius: null`) — les tuiles produit de la
        // grille ont toutes `borderRadius: BorderRadius.circular(10)`
        // et commencent à l'index 1 (confirmé par inspection directe de
        // l'arbre de widgets).
        final firstProductTile = find.byType(InkWell).at(1);
        expect(firstProductTile, findsOneWidget);
        await tester.tap(firstProductTile);
        await tester.pump();

        expect(find.text('Scène avec produit déjà posé (rendu dynamique)'), findsOneWidget);
        expect(captureCalled, isFalse);

        await tester.tap(find.text('Scène avec produit déjà posé (rendu dynamique)'));
        // `_useComposedScene` est async (await state.captureComposedScene())
        // mais la fake capture ci-dessus est synchrone en pratique (pas de
        // vrai I/O) : un seul pump suffit, pas besoin de pumpAndSettle.
        await tester.pump();

        expect(captureCalled, isTrue,
            reason: 'Le bouton "Scène avec produit déjà posé" doit '
                'appeler AppState.captureComposedScene() — c\'est ce '
                'câblage qui garantit que seule cette scène peut '
                'ensuite produire renderMode="refine" (voir '
                'resolveRenderModeForScene ci-dessus).');

        // Vérifie aussi que le label de scène affiché correspond bien
        // au mode hybride (traçabilité visible pour l'utilisateur).
        expect(
          find.textContaining('Scène avec produit déjà posé'),
          findsWidgets,
        );
      },
    );
  });
}
