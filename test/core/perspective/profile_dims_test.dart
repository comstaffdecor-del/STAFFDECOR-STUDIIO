// Test rouge d'abord (discipline Bug 1 : e0908fa puis 85bb204) — ce fichier
// doit échouer à la compilation/exécution tant que
// `lib/core/perspective/profile_dims.dart` n'existe pas, PAS pour une
// raison annexe (asset non déclaré, binding non initialisé).
//
// ⚠️ `TestWidgetsFlutterBinding.ensureInitialized()` en première ligne de
// `main()` : sans cet appel, `rootBundle.loadString` lève immédiatement
// sous `flutter test`, ce qui rendrait ce test rouge pour une raison qui
// n'est ni l'absence du loader ni un défaut de déclaration pubspec.yaml
// (piège explicitement signalé, à désamorcer avant toute chose).
//
// Cinq cas couverts, valeurs mesurées lors de la lecture directe des JSON
// (sortie brute Python de cette session, `assets/profiles/*.json`) :
// - D720 : retombée 202.87 mm, projection 199.145 mm (bbox_mm h/w)
// - D718 : retombée 153.547 mm, projection 153.405 mm (bbox_mm h/w)
// - D705 : retombée 102.661 mm, projection 101.453 mm (bbox_mm h/w) —
//   PAS de normalisation de signe : la retombée/projection sont définies
//   comme des DISTANCES aux plans de pose (face_pose_plafond/
//   face_pose_mur), donc insensibles au fait que D705 a son contour en
//   y >= 0 alors que D718/D720 l'ont en y <= 0 (anomalie déjà identifiée,
//   non résolue ici — hors périmètre de ce loader).
// - 0900 : voie DXF, `statut: "ERREUR_SELECTION"`, `profil_mm: []` — doit
//   rendre `null`, pas lever.
// - référence inexistante au catalogue (`INEXISTANT_XYZ`) — doit aussi
//   rendre `null` (275 références sur 283 n'ont simplement pas de
//   fichier, ce n'est jamais une erreur applicative).
//
// Tolérance de comparaison : 0.001 mm, comme convenu.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/profile_dims.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tol = 0.001;

  test('D720 : retombée 202.87mm, projection 199.145mm', () async {
    final d = await loadProfileDims('D720');
    expect(d, isNotNull);
    expect(d!.ref, 'D720');
    expect(d.retombeeMm, closeTo(202.87, tol));
    expect(d.projectionMm, closeTo(199.145, tol));
  });

  test('D718 : retombée 153.547mm, projection 153.405mm', () async {
    final d = await loadProfileDims('D718');
    expect(d, isNotNull);
    expect(d!.retombeeMm, closeTo(153.547, tol));
    expect(d.projectionMm, closeTo(153.405, tol));
  });

  test(
    'D705 : retombée 102.661mm, projection 101.453mm (contour y>=0, '
    'pas de normalisation de signe — distances aux plans de pose)',
    () async {
      final d = await loadProfileDims('D705');
      expect(d, isNotNull);
      expect(d!.retombeeMm, closeTo(102.661, tol));
      expect(d.projectionMm, closeTo(101.453, tol));
    },
  );

  test(
    '0900 (voie DXF, statut ERREUR_SELECTION, profil_mm vide) -> null',
    () async {
      final d = await loadProfileDims('0900');
      expect(d, isNull);
    },
  );

  test('référence inexistante au catalogue -> null (pas de throw)', () async {
    final d = await loadProfileDims('INEXISTANT_XYZ');
    expect(d, isNull);
  });
}
