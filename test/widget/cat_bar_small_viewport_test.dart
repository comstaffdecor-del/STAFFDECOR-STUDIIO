// ⚠️ CORRECTION overflow (brief "product_strip.dart:45 — priorité
// rapide") — régression pour le bug confirmé empiriquement : `CatBar`
// (lib/widgets/studio/product_strip.dart) était monté par
// `studio_screen.dart` dans un `Expanded(child: CatBar())` dont la
// hauteur allouée dépend de l'espace restant après la zone photo
// (`photoZoneSize.height = constraints.maxHeight * 0.62`). En paysage
// (ex. 812×375, contexte réel confirmé par sonde de diagnostic), il ne
// restait que ~120.5px pour `CatBar`, alors que son `Column` exigeait
// une hauteur FIXE non négociable de 40+92=132px — d'où un
// `RenderFlex overflowed by 12 pixels` exact à
// `product_strip.dart:45:14`.
//
// Fix retenu (après revue — un premier essai avec un simple `Expanded`
// corrigeait l'overflow mais introduisait une RÉGRESSION VISUELLE en
// portrait confortable, en étirant démesurément les vignettes produits
// au-delà de 92px) : la barre d'onglets garde 40px fixes (contenu
// court, déjà scrollable horizontalement), et le strip produits est
// enveloppé dans `Flexible(fit: FlexFit.loose, child: SizedBox(height:
// 92, ...))` — apparence historique (92px) préservée à l'identique dès
// que l'espace disponible le permet (≥132px), compression progressive
// uniquement quand l'espace manque (<132px), plus jamais d'overflow.
//
// Ce test reproduit fidèlement le contexte de montage réel (CatBar doit
// être un enfant `Expanded`/`Flexible` d'un `Column`, dans un ancêtre
// `MaterialApp` + `Scaffold` + `Provider<AppState>`, comme le fait
// `AppShell` en production) à plusieurs hauteurs, y compris un cas plus
// sévère que le bug d'origine (100px, en dessous des 120.5px qui
// causaient déjà un dépassement), et vérifie explicitement que
// l'apparence historique (92px exacts) est préservée au-delà du seuil
// de 132px — pas seulement l'absence d'overflow.
//
// Limite assumée (documentée ici plutôt que passée sous silence) : le
// layout Studio n'est pas garanti lisible/exploitable en dessous de
// ~100px disponibles pour `CatBar` — sous ce seuil, les vignettes
// produits elles-mêmes (68px de large, contenu image + texte) deviennent
// trop contraintes verticalement. Ce test couvre le bug réel reproduit
// à 120.5px et un seuil plus sévère à 100px ; il ne prétend pas garantir
// un rendu exploitable à n'importe quelle hauteur (ex. 80px n'est plus
// couvert ici : au-delà du fix d'overflow proprement dit, c'est un
// problème d'espace utilisable, hors périmètre de ce brief).
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:staff_decor_studio/screens/studio/studio_screen.dart';
import 'package:staff_decor_studio/state/app_state.dart';
import 'package:staff_decor_studio/widgets/studio/product_strip.dart';

Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = Colors.white);
  final picture = recorder.endRecording();
  return picture.toImage(2, 2);
}

Widget _harness(AppState state, double availableHeight) {
  const totalHeight = 800.0;
  return MaterialApp(
    home: ChangeNotifierProvider<AppState>.value(
      value: state,
      child: Scaffold(
        // Reproduit fidèlement le montage réel : `CatBar` est un enfant
        // `Expanded` d'un `Column` de hauteur bornée (voir
        // studio_screen.dart:304, `Column` sous `LayoutBuilder`), et
        // c'est cette contrainte de hauteur STRICTE (tight) qui
        // déclenchait l'overflow avant le fix — pas un `SizedBox`
        // isolé englobant l'`Expanded` (erreur de harnais corrigée
        // ici : `Expanded` doit être un enfant DIRECT du `Column`).
        body: SizedBox(
          height: totalHeight,
          child: Column(
            children: [
              SizedBox(height: totalHeight - availableHeight),
              const Expanded(child: CatBar()),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'CatBar ne déborde pas à 120.5px (hauteur exacte du bug reproduit en paysage 812x375)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(812, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final state = AppState();
      await tester.pumpWidget(_harness(state, 120.5));
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CatBar ne déborde pas avec une hauteur encore plus réduite que le bug '
    '(100px — proche du minimum plausible sur un très petit écran paysage, '
    'ex. iPhone SE paysage ~320px de hauteur totale) — et le strip produits '
    'se comprime bien EN DESSOUS de 92px (FlexFit.loose), au lieu de '
    'déborder',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(812, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final state = AppState();
      await tester.pumpWidget(_harness(state, 100));
      await tester.pump();

      expect(tester.takeException(), isNull);

      // La barre d'onglets (40px) + le strip comprimé doivent tenir
      // exactement dans les 100px alloués — jamais plus.
      final catBarSize = tester.getSize(find.byType(CatBar));
      expect(catBarSize.height, lessThanOrEqualTo(100.0));
    },
  );

  testWidgets(
    'CatBar préserve l\'apparence historique (strip à 92px EXACTS, pas '
    'étiré) dès que l\'espace disponible est confortable (132px, cas '
    'portrait normal) — non-régression visuelle du fix FlexFit.loose',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final state = AppState();
      await tester.pumpWidget(_harness(state, 132));
      await tester.pump();

      expect(tester.takeException(), isNull);

      // Le strip produits doit garder EXACTEMENT sa hauteur historique de
      // 92px — pas plus (ce qui trahirait un `Expanded` résiduel étirant
      // les vignettes), pas moins (ce qui trahirait un `FlexFit.loose`
      // mal appliqué qui compresserait sans nécessité).
      final stripSize = tester.getSize(find.byType(ListView).last);
      expect(stripSize.height, 92.0);
    },
  );

  testWidgets(
    'CatBar préserve l\'apparence historique même avec BEAUCOUP plus '
    'd\'espace que nécessaire (400px, cas portrait très haut) — le strip '
    'ne doit JAMAIS s\'étirer au-delà de 92px',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final state = AppState();
      await tester.pumpWidget(_harness(state, 400));
      await tester.pump();

      expect(tester.takeException(), isNull);

      final stripSize = tester.getSize(find.byType(ListView).last);
      expect(stripSize.height, 92.0);
    },
  );

  group('_StudioTopbar (bug annexe découvert pendant le diagnostic)', () {
    testWidgets(
      'Le titre "Nouveau projet" ne fait plus déborder la topbar sur un '
      'écran étroit (375px), même avec les 9 boutons-outils affichés '
      '(cas roomImage != null — le pire cas, confirmé jusqu\'à 173px de '
      'dépassement avant le fix Flexible + SingleChildScrollView)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(375, 812));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final state = AppState();
        state.roomImage = await _tinyImage();

        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<AppState>.value(
              value: state,
              child: const Scaffold(body: StudioScreen()),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Le bouton "Devis" (dernier des 9 boutons-outils, potentiellement '
      'hors écran sur un très petit viewport de 320px) reste ATTEIGNABLE '
      'via le scroll horizontal du SingleChildScrollView, et déclenche '
      'bien state.goTo(\'devis\') une fois scrollé en vue',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 568));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final state = AppState();
        state.roomImage = await _tinyImage();

        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<AppState>.value(
              value: state,
              child: const Scaffold(body: StudioScreen()),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Le bouton "Devis" est identifié par son Tooltip (dernier
        // _ToolBtn de la Row scrollable) — on s'assure qu'il existe dans
        // l'arbre (même si potentiellement hors zone visible avant
        // scroll), puis on le fait défiler explicitement en vue avant de
        // taper dessus, exactement comme le ferait un utilisateur réel.
        final devisFinder = find.byTooltip('Devis');
        expect(devisFinder, findsOneWidget);

        await tester.ensureVisible(devisFinder);
        await tester.pumpAndSettle();

        await tester.tap(devisFinder, warnIfMissed: false);
        await tester.pump();

        expect(state.currentScreen, 'devis');
      },
    );
  });
}
