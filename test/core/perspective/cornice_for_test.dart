// Test rouge d'abord — ce fichier doit échouer tant que `corniceFor`
// n'existe pas encore dans `cornice_plinth_painter.dart`.
//
// Commit 3/3 du câblage de la conversion métrique (mm->px) dans le
// peintre : `corniceFor` est la fonction pure extraite du site d'appel
// `room_painter.dart` (case 'Corniches'), pour rendre le verrouillage
// bit-à-bit testable SANS binding ni rendu — une simple assertion à
// quatre champs sur un appel de fonction.
//
// StripThickness corniceFor(StripPxResult? r, double pH) =>
//     r == null ? StripThickness.corniceDefault(pH) : StripThickness.fromPx(r);
//
// Deux branches à verrouiller :
//   1. r == null (cas normal, 275/283 refs sans profil JSON) -> repli
//      IDENTIQUE à StripThickness.corniceDefault(pH). C'est le test de
//      non-régression qui compte le plus : si un jour ce repli change
//      par erreur, ce test doit rougir.
//   2. r non-null (refs couvertes par assets/profiles/index.json, 31 SKU
//      gate-OK à ce jour — le nombre exact n'est pas ce que ce test
//      verrouille, voir profile_dims_cache.dart pour l'historique de ce
//      chiffre) -> copie 1:1 des 4 champs de r, via StripThickness.fromPx
//      — déjà testé isolément dans strip_thickness_from_px_test.dart,
//      revérifié ici seulement au niveau de la sélection (le "if"
//      lui-même), pas de l'arithmétique.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/cornice_plinth_painter.dart';

void main() {
  const tol = 0.001;

  test(
    'corniceFor(null, pH) == StripThickness.corniceDefault(pH) — repli '
    'identique, cas des 275 refs sans profil JSON. Valeurs lues sur '
    'l\'objet réel (pas recopiées en littéral) pour que ce test reste '
    'un verrou : si corniceDefault change un jour, il doit rougir.',
    () {
      const pH = 500.0;
      final attendu = StripThickness.corniceDefault(pH);
      final r = corniceFor(null, pH);

      expect(r.faceMurFond, closeTo(attendu.faceMurFond, tol));
      expect(r.faceHorizFond, closeTo(attendu.faceHorizFond, tol));
      expect(r.faceMurLat, closeTo(attendu.faceMurLat, tol));
      expect(r.faceHorizLat, closeTo(attendu.faceHorizLat, tol));
    },
  );

  test(
    'corniceFor(r, pH) avec r non-null == StripThickness.fromPx(r) — '
    'copie 1:1, cas des refs couvertes (D720 notamment). N\'exerce PAS '
    'à nouveau l\'arithmétique de stripPxFromDims (déjà verrouillée dans '
    'strip_px_from_dims_test.dart) : vérifie uniquement que la branche '
    'r != null de corniceFor délègue bien à fromPx plutôt qu\'à '
    'corniceDefault.',
    () {
      const pH = 500.0;
      const r = (
        faceMurFondPx: 40.574,
        faceHorizFondPx: 39.829,
        faceMurLatPx: 59.016727,
        faceHorizLatPx: 56.898571,
      );

      final result = corniceFor(r, pH);
      final attendu = StripThickness.fromPx(r);

      expect(result.faceMurFond, closeTo(attendu.faceMurFond, tol));
      expect(result.faceHorizFond, closeTo(attendu.faceHorizFond, tol));
      expect(result.faceMurLat, closeTo(attendu.faceMurLat, tol));
      expect(result.faceHorizLat, closeTo(attendu.faceHorizLat, tol));

      // Valeurs numériques épinglées, indépendantes de r lui-même, pour
      // que ce test ne soit pas tautologique.
      expect(result.faceMurFond, closeTo(40.574, tol));
      expect(result.faceHorizFond, closeTo(39.829, tol));
      expect(result.faceMurLat, closeTo(59.016727, tol));
      expect(result.faceHorizLat, closeTo(56.898571, tol));
    },
  );

  test(
    'corniceFor(r, pH) NE retombe PAS sur corniceDefault quand r != null '
    '— distingue les deux branches (si l\'implémentation ignorait r et '
    'retournait toujours corniceDefault(pH), ce test rougirait alors que '
    'le test précédent pourrait rester vert par coïncidence numérique).',
    () {
      const pH = 500.0;
      const r = (
        faceMurFondPx: 40.574,
        faceHorizFondPx: 39.829,
        faceMurLatPx: 59.016727,
        faceHorizLatPx: 56.898571,
      );
      final result = corniceFor(r, pH);
      final defaut = StripThickness.corniceDefault(pH);

      expect(result.faceMurFond, isNot(closeTo(defaut.faceMurFond, tol)));
    },
  );
}
