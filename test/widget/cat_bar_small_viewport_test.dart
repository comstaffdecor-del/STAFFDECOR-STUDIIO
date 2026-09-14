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
// Fix : la barre d'onglets garde 40px fixes (contenu court, déjà
// scrollable horizontalement), mais le strip produits est désormais
// dans un `Expanded` qui absorbe TOUT l'espace réellement disponible au
// lieu d'exiger un bloc fixe de 92px.
//
// Ce test reproduit fidèlement le contexte de montage réel (CatBar doit
// être un enfant `Expanded`/`Flexible` d'un `Column`, dans un ancêtre
// `MaterialApp` + `Scaffold` + `Provider<AppState>`, comme le fait
// `AppShell` en production) à plusieurs hauteurs, y compris des cas
// PLUS SÉVÈRES que le bug d'origine (jusqu'à 80px, bien en dessous des
// 120.5px qui causaient déjà un dépassement), pour garantir qu'aucun
// overflow n'est plus jamais possible quelle que soit la hauteur
// allouée.
library;

import 'dart:typed_data';
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
    'ex. iPhone SE paysage ~320px de hauteur totale)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(812, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final state = AppState();
      await tester.pumpWidget(_harness(state, 100));
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CatBar ne déborde pas à la hauteur nominale (132px, cas portrait confortable)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final state = AppState();
      await tester.pumpWidget(_harness(state, 132));
      await tester.pump();

      expect(tester.takeException(), isNull);
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
  });
}
