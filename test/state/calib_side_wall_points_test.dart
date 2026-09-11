// Brief "Phase 1 moteur dynamique : calibration complète" — test ciblé
// demandé explicitement :
//   1) modifier un point wallTL / wallTR via updateCalibPoint ;
//   2) vérifier que perspCalib est bien mis à jour ;
//   3) vérifier que RoomPainter consomme toujours les 8 points (via le
//      VanishingPoint qu'il calcule, qui dépend directement de
//      wallTL/wallTR/wallBL/wallBR — voir room_painter.dart:_paintOverlays,
//      appel à VanishingPoint.compute avec les 8 points de
//      CalibCanvasPoints.fromCalib).
//
// Ne modifie ni PerspCalib (models/persp_calib.dart) ni la logique de
// updateCalibPoint (déjà complète sur les 8 clés avant ce brief, vérifié
// par lecture directe de app_state.dart lignes 353-378) : ce test constate
// un comportement déjà présent côté state/moteur, il ne le crée pas. Ce
// qui manquait était uniquement l'exposition UI (calib_handles.dart),
// couverte séparément par un test widget dans ce même fichier.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:staff_decor_studio/core/perspective/calib_canvas.dart';
import 'package:staff_decor_studio/core/perspective/vanishing_point.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';
import 'package:staff_decor_studio/state/app_state.dart';
import 'package:staff_decor_studio/widgets/studio/calib_handles.dart';

const _kContainerSize = Size(1400, 868);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Brief calibration complète — points de mur latéral (wallTL/'
      'wallTR/wallBL/wallBR)', () {
    test(
      '1) updateCalibPoint("wallTL", ...) met a jour perspCalib.wallTL '
      "SEUL (les 7 autres points, dont wallTR, restent inchanges) — meme "
      'garantie que le Livrable 6.3 deja verifie pour floorL, etendue ici '
      'explicitement a un point de mur lateral.',
      () async {
        final state = AppState();
        await state.loadDemoScene('haussmann', containerSize: _kContainerSize);
        state.isCalibrated = false;

        final before = state.perspCalib!;
        const moved = CalibPoint(xPct: 0.02, yPct: 0.11);
        state.updateCalibPoint('wallTL', moved);

        final after = state.perspCalib!;
        expect(after.wallTL.xPct, moved.xPct);
        expect(after.wallTL.yPct, moved.yPct);
        expect(after.ceilL, before.ceilL);
        expect(after.ceilR, before.ceilR);
        expect(after.floorL, before.floorL);
        expect(after.floorR, before.floorR);
        expect(after.wallTR, before.wallTR);
        expect(after.wallBL, before.wallBL);
        expect(after.wallBR, before.wallBR);
        expect(state.isCalibrated, isTrue);
      },
    );

    test(
      '2) updateCalibPoint("wallTR", ...) idem, point symetrique — et '
      'notifyListeners est bien emis (meme contrat que les 4 points '
      'plafond/sol deja verifies par calib_path_regression_test.dart).',
      () async {
        final state = AppState();
        await state.loadDemoScene('moderne', containerSize: _kContainerSize);
        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        const moved = CalibPoint(xPct: 0.97, yPct: 0.09);
        state.updateCalibPoint('wallTR', moved);

        expect(state.perspCalib!.wallTR.xPct, moved.xPct);
        expect(state.perspCalib!.wallTR.yPct, moved.yPct);
        expect(notifyCount, greaterThan(0));
      },
    );

    test(
      '3) RoomPainter consomme toujours les 8 points : apres modification '
      'de wallTL/wallTR via updateCalibPoint, VanishingPoint.compute — '
      'appele par RoomPainter._paintOverlays avec exactement les 8 points '
      'de CalibCanvasPoints.fromCalib(perspCalib, ...) — reflete bien le '
      'nouveau wallTL/wallTR (pas figé sur une ancienne valeur, pas '
      'ignoré). Reproduit ICI le meme appel que room_painter.dart (memes '
      'arguments, meme fallbackMode) sans dupliquer sa logique de rendu, '
      'pour verifier que le point de fuite change réellement quand '
      'wallTL/wallTR changent — la preuve directe que ces 2 points ne '
      'sont pas morts cote moteur, seulement cote UI (avant ce brief).',
      () async {
        final state = AppState();
        await state.loadDemoScene('scandinave', containerSize: _kContainerSize);

        const w = 1400.0, h = 868.0;
        final imgDraw = state.imgDraw;

        VanishingPoint computeVpFor(PerspCalib calib) {
          final cp = CalibCanvasPoints.fromCalib(calib, imgDraw: imgDraw, w: w, h: h);
          return VanishingPoint.compute(
            fTL: cp.ceilL,
            fTR: cp.ceilR,
            fBL: cp.floorL,
            fBR: cp.floorR,
            wallTL: cp.wallTL,
            wallTR: cp.wallTR,
            wallBL: cp.wallBL,
            wallBR: cp.wallBR,
            fallbackMode: VpFallbackMode.repliHistoriqueCoupleBas,
          );
        }

        final vpBefore = computeVpFor(state.perspCalib!);

        // Déplace wallTL ET wallTR de façon significative (loin de leur
        // position preset "scandinave") — un vrai changement géométrique,
        // pas un micro-ajustement qui pourrait rester dans la tolérance
        // numérique de l'intersection.
        state.updateCalibPoint('wallTL', const CalibPoint(xPct: 0.05, yPct: 0.30));
        state.updateCalibPoint('wallTR', const CalibPoint(xPct: 0.95, yPct: 0.30));

        final vpAfter = computeVpFor(state.perspCalib!);

        // Le VP fini (ou sa direction si à l'infini) doit avoir changé —
        // preuve que RoomPainter (qui appelle exactement ce même calcul,
        // avec les mêmes 8 points) verrait bien un rendu différent, donc
        // que les 4 points de mur latéral sont réellement consommés par
        // le moteur de perspective, pas seulement stockés.
        final movedEnough = vpBefore.isAtInfinity != vpAfter.isAtInfinity ||
            (!vpBefore.isAtInfinity &&
                !vpAfter.isAtInfinity &&
                (vpBefore.vp - vpAfter.vp).distance > 1.0) ||
            (vpBefore.isAtInfinity &&
                vpAfter.isAtInfinity &&
                (vpBefore.direction - vpAfter.direction).distance > 1e-6);
        expect(
          movedEnough,
          isTrue,
          reason:
              'Le point de fuite (ou sa direction) doit changer quand '
              'wallTL/wallTR changent — sinon RoomPainter ignorerait '
              'silencieusement ces 2 points de calibration.',
        );
      },
    );

    testWidgets(
      '4) CalibHandlesOverlay construit bien 8 poignées draguables '
      '(GestureDetector) — 4 mur du fond + 4 murs lateraux, apres le '
      'brief de calibration complete (avant ce brief, seules 4 etaient '
      'presentes dans l\'arbre de widgets).',
      (WidgetTester tester) async {
        final state = AppState();
        // `loadDemoScene` fait un vrai `rootBundle.load` (asset JPEG) suivi
        // d'un décodage d'image — cette I/O asynchrone réelle ne se résout
        // jamais dans la FakeAsync zone de `testWidgets` (elle attend un
        // évènement externe que `pump`/`pumpAndSettle` ne peut pas avancer),
        // d'où un blocage total du test. `tester.runAsync()` fait tourner
        // ce bloc sur une vraie zone asynchrone (comme dans les tests
        // `test()` de ce même fichier, qui n'ont pas ce problème car ils ne
        // passent jamais par `pumpWidget`/`WidgetTester`).
        await tester.runAsync(() async {
          await state.loadDemoScene('provencal', containerSize: _kContainerSize);
        });

        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<AppState>.value(
              value: state,
              child: Scaffold(
                body: SizedBox(
                  width: _kContainerSize.width,
                  height: _kContainerSize.height,
                  child: CalibHandlesOverlay(
                    canvasSize: _kContainerSize,
                    imgDraw: state.imgDraw,
                  ),
                ),
              ),
            ),
          ),
        );

        expect(
          find.byType(GestureDetector),
          findsNWidgets(8),
          reason:
              'Les 8 points de calibration (ceilL/ceilR/floorL/floorR + '
              'wallTL/wallTR/wallBL/wallBR) doivent tous être exposés par '
              'CalibHandlesOverlay comme poignées draguables.',
        );
      },
    );
  });
}
