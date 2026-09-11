// ⚠️ TEST DIAGNOSTIC TEMPORAIRE — brief "Stop patch scène — retour au
// moteur dynamique", point 5 : "vérifier explicitement si D609 utilise
// ses vraies dimensions". Ce fichier n'est PAS destiné à rester dans la
// suite de tests permanente — il exerce le vrai pipeline paint() de
// RoomPainter avec D609/Corniches sur la calibration réelle de la scène
// 'moderne', capture le log debug ajouté temporairement dans
// room_painter.dart (case 'Corniches'), et affirme que la convergence
// finale utilise bien ProfileDims (pas le fallback StripThickness
// .corniceDefault) — sans golden, sans comparaison de pixels, même
// discipline que room_painter_paint_integration_test.dart (D720).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/profile_dims_cache.dart';
import 'package:staff_decor_studio/core/perspective/room_painter.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';
import 'package:staff_decor_studio/models/project_item.dart';

void main() {
  setUp(() {
    ProfileDimsCache.instance.resetForTesting();
  });

  testWidgets(
    'DIAGNOSTIC D609 : sur la scène moderne, D609/Corniches converge '
    'vers ses dimensions réelles (retombeeMm≈186.96, projectionMm≈196.48) '
    'et non vers StripThickness.corniceDefault (fallback).',
    (WidgetTester tester) async {
      const item = ProjectItem(
        ref: 'D609',
        famille: 'Corniches',
        qte: 2.0,
        unite: 'ml',
      );

      final painter = RoomPainter(
        roomImage: null,
        imgDraw: null,
        calib: PerspCalib.forDemoScene('moderne'),
        selectedProducts: const [item],
        prodPositions: const {},
        metresHauteur: 2.5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 1400,
            height: 868,
            child: CustomPaint(painter: painter),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final dims = ProfileDimsCache.instance.getIfLoaded('D609');
      // ignore: avoid_print
      print(
        '[DIAGNOSTIC D609] ProfileDimsCache.getIfLoaded("D609") = $dims '
        '(null => fallback StripThickness.corniceDefault aurait été '
        'utilisé pour TOUTE la session de paint() ci-dessus)',
      );

      expect(
        dims,
        isNotNull,
        reason:
            'Si null ici, D609 n\'est PAS dans assets/profiles/index.json '
            '(couverture gate-OK) ou loadProfileDims a rejeté le fichier '
            '— le moteur serait alors TOUJOURS en fallback proportionnel '
            'pour cette ref, ce qui expliquerait un rendu générique.',
      );
      if (dims != null) {
        expect(dims.retombeeMm, closeTo(186.963, 0.01));
        expect(dims.projectionMm, closeTo(196.4815, 0.01));
      }
    },
  );
}
