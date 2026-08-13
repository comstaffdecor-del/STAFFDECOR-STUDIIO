// Test rouge d'abord — ce fichier doit échouer tant que
// `StripThickness.fromPx` n'existe pas encore.
//
// Commit 1/3 du câblage de la conversion métrique dans le peintre
// (StripThickness.fromPx seul, ProfileDimsCache ensuite, puis le site
// d'appel room_painter.dart:134 en dernier — décidé pour que le seul
// changement visible à l'écran, l'inversion 27.5/70 -> 40.6/39.8, atterrisse
// isolé dans le 3e commit).
//
// StripThickness.fromPx(StripPxResult r) est une factory PURE qui copie
// 1:1 les 4 champs de StripPxResult (faceMurFondPx, faceHorizFondPx,
// faceMurLatPx, faceHorizLatPx — mêmes 4 grandeurs, même unité px) vers
// les 4 champs de StripThickness (faceMurFond, faceHorizFond, faceMurLat,
// faceHorizLat). Mécanique par construction : les deux structures ont
// la même forme, cette factory ne fait aucun calcul, juste la traversée
// du type StripPxResult (défini dans strip_px_from_dims.dart, qui reste
// pur, sans dart:ui) vers StripThickness (défini dans
// cornice_plinth_painter.dart, qui importe dart:ui). Le sens de
// dépendance production est donc : cornice_plinth_painter.dart importe
// strip_px_from_dims.dart, jamais l'inverse — StripThickness.fromPx vit
// dans cornice_plinth_painter.dart précisément pour ça.
//
// Ce commit ne touche ni room_painter.dart ni aucun site d'appel : la
// factory existe, elle est testée isolément, mais rien ne l'invoque
// encore en dehors de ce test. Aucun changement de rendu.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/cornice_plinth_painter.dart';
import 'package:staff_decor_studio/core/perspective/strip_px_from_dims.dart';

void main() {
  const tol = 0.000001;

  test(
    'StripThickness.fromPx copie 1:1 les 4 champs de StripPxResult '
    '(D720, pH=500, metresHauteur=2.5)',
    () {
      final r = stripPxFromDims(
        pH: 500.0,
        metresHauteur: 2.5,
        retombeeMm: 202.87,
        projectionMm: 199.145,
      );
      expect(r, isNotNull);

      final rr = r!;
      final th = StripThickness.fromPx(rr);
      expect(th.faceMurFond, closeTo(rr.faceMurFondPx, tol));
      expect(th.faceHorizFond, closeTo(rr.faceHorizFondPx, tol));
      expect(th.faceMurLat, closeTo(rr.faceMurLatPx, tol));
      expect(th.faceHorizLat, closeTo(rr.faceHorizLatPx, tol));

      // Valeurs numériques épinglées (calculées indépendamment,
      // identiques à celles vérifiées dans strip_px_from_dims_test.dart)
      // pour que ce test ne devienne pas tautologique s'il ne comparait
      // qu'aux champs de r lui-même.
      expect(th.faceMurFond, closeTo(40.574, 0.001));
      expect(th.faceHorizFond, closeTo(39.829, 0.001));
      expect(th.faceMurLat, closeTo(59.016727, 0.001));
      expect(th.faceHorizLat, closeTo(56.898571, 0.001));
    },
  );

  test(
    'StripThickness.fromPx ne modifie pas le ratio lat/fond hérité de '
    'StripPxResult (pas de recalcul, pure copie)',
    () {
      final r = stripPxFromDims(
        pH: 500.0,
        metresHauteur: 2.5,
        retombeeMm: 153.547,
        projectionMm: 153.405,
      );
      expect(r, isNotNull);

      final rr = r!;
      final th = StripThickness.fromPx(rr);
      expect(
        th.faceMurLat / th.faceMurFond,
        closeTo(rr.faceMurLatPx / rr.faceMurFondPx, 1e-9),
      );
      expect(
        th.faceHorizLat / th.faceHorizFond,
        closeTo(rr.faceHorizLatPx / rr.faceHorizFondPx, 1e-9),
      );
    },
  );
}
