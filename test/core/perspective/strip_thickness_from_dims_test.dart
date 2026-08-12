// Test rouge d'abord (même discipline que Bug 1 et que le loader
// ProfileDims) — ce fichier doit échouer tant que
// `lib/core/perspective/strip_thickness_from_dims.dart` n'existe pas.
//
// Fonction PURE, SYNCHRONE, SANS AUCUNE ENTRÉE-SORTIE : contrairement à
// `loadProfileDims` (async, `rootBundle`), cette fonction ne peut pas être
// appelée depuis `CustomPainter.paint` (synchrone) si elle fait du
// chargement — elle prend donc des dimensions déjà résolues en entrée
// (obtenues en amont, précédemment, par un mécanisme d'acheminement
// asynchrone→synchrone du même genre que `ProductTextureCache`, hors
// périmètre de ce commit).
//
// Facteur de conversion : pxParMm = pH / (metresHauteur * 1000).
// Valeurs choisies à la main (vérifiées par calcul indépendant avant
// écriture de ce test) :
//   pH = 500 px, metresHauteur = 2.5 m -> facteur = 0.2 px/mm
//   D720 : retombeeMm = 202.87, projectionMm = 199.145
//     -> retombeePx = 40.574, projectionPx = 39.829
//   Repli actuel (coefficients en dur, cornice_plinth_painter.dart) :
//     0.055 * pH = 27.5, 0.140 * pH = 70.0
// Les deux jeux de valeurs sont volontairement présents dans ce test :
// ça documente noir sur blanc l'inversion de proportion (0.39 en repli
// contre 1.02 en métrique réel, cf. docs/ETAT_MOTEUR_RENDU.md section 5)
// et évite qu'un changement visuel net soit pris pour une régression.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/strip_thickness_from_dims.dart';

void main() {
  const tol = 0.001;

  test('D720, pH=500, metresHauteur=2.5 -> conversion métrique réelle', () {
    final r = strippxFromDims(
      pH: 500.0,
      metresHauteur: 2.5,
      retombeeMm: 202.87,
      projectionMm: 199.145,
    );
    expect(r.faceMurFondPx, closeTo(40.574, tol));
    expect(r.faceHorizFondPx, closeTo(39.829, tol));
  });

  test(
    'Repli documenté : anciens coefficients 0.055/0.140*pH ne sont PAS '
    'ce que produit la conversion métrique (inversion de proportion : '
    '0.39 en repli contre ~1.02 en réel, à ne pas prendre pour une '
    'régression visuelle)',
    () {
      const pH = 500.0;
      final ancien = (faceMurFond: 0.055 * pH, faceHorizFond: 0.140 * pH);
      expect(ancien.faceMurFond, closeTo(27.5, tol));
      expect(ancien.faceHorizFond, closeTo(70.0, tol));

      final r = strippxFromDims(
        pH: pH,
        metresHauteur: 2.5,
        retombeeMm: 202.87,
        projectionMm: 199.145,
      );
      // La conversion métrique diverge nettement de l'ancien repli — pas
      // une erreur, l'ancien repli avait une proportion inversée.
      expect(r.faceMurFondPx, isNot(closeTo(ancien.faceMurFond, 1.0)));
      expect(r.faceHorizFondPx, isNot(closeTo(ancien.faceHorizFond, 1.0)));
    },
  );

  test('D718, pH=500, metresHauteur=2.5', () {
    final r = strippxFromDims(
      pH: 500.0,
      metresHauteur: 2.5,
      retombeeMm: 153.547,
      projectionMm: 153.405,
    );
    expect(r.faceMurFondPx, closeTo(30.7094, tol));
    expect(r.faceHorizFondPx, closeTo(30.681, tol));
  });

  test(
    'metresHauteur = 0 -> repli sur les coefficients actuels (0.055/0.140*pH), '
    'pas de division par zéro',
    () {
      final r = strippxFromDims(
        pH: 500.0,
        metresHauteur: 0.0,
        retombeeMm: 202.87,
        projectionMm: 199.145,
      );
      expect(r.faceMurFondPx, closeTo(27.5, tol));
      expect(r.faceHorizFondPx, closeTo(70.0, tol));
    },
  );

  test(
    'metresHauteur négative -> repli sur les coefficients actuels, pas de '
    'facteur négatif',
    () {
      final r = strippxFromDims(
        pH: 500.0,
        metresHauteur: -1.0,
        retombeeMm: 202.87,
        projectionMm: 199.145,
      );
      expect(r.faceMurFondPx, closeTo(27.5, tol));
      expect(r.faceHorizFondPx, closeTo(70.0, tol));
    },
  );

  test(
    'dims absentes (null) -> repli sur les coefficients actuels',
    () {
      final r = strippxFromDims(
        pH: 500.0,
        metresHauteur: 2.5,
        retombeeMm: null,
        projectionMm: null,
      );
      expect(r.faceMurFondPx, closeTo(27.5, tol));
      expect(r.faceHorizFondPx, closeTo(70.0, tol));
    },
  );
}
