// Test rouge d'abord (discipline Bug 1 : e0908fa puis 85bb204).
//
// Contexte : le batch d'extraction Piste A a produit 56 fichiers
// `statut: OK` dans `assets/profiles/`, mais seuls 31 passent le gate de
// sanité (`tools/dxf_pipeline/gate_sanite.py`, critère bloquant 2 —
// débord du plan de pose mur/plafond, copie littérale de l'ancienne
// assertion debug de ce loader). Les 25 autres sont `statut: OK` sur le
// fichier mais géométriquement invalides pour ce critère précis.
//
// D614 est un cas RÉEL, déjà présent dans `assets/profiles/D614.json`,
// confirmé hors gate (`bbox_mm.w=62.389` vs `projectionMm` recalculé
// depuis `profil_mm` = 52.8634 — écart 9.5257mm, largement > 0.001mm).
// Reproduit expérimentalement AVANT ce commit (script jetable, non
// commité) : `loadProfileDims('D614')` FAISAIT TOMBER `flutter test` en
// mode debug via un `assert()` réel — pas un throw contrôlé, un crash.
//
// Ce test fixe le nouveau contrat : un tel profil doit rendre `null`,
// jamais lever, et incrémenter un compteur exposé en lecture seule
// (déliverable "compteur de rejets" du brief de câblage) — pour que
// l'appelant (ProfileDimsCache) puisse continuer sans jamais planter,
// et que la télémétrie de rejet soit observable sans dépendre de logs
// console.
//
// ⚠️ `TestWidgetsFlutterBinding.ensureInitialized()` requis avant tout
// `rootBundle.loadString` sous `flutter test` — piège déjà documenté
// dans `profile_dims_test.dart`.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/profile_dims.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetRejectedByContractCountForTesting();
  });

  test(
    'D614 (statut OK, debord plan mur > 0.001mm, HORS gate) -> null, '
    'PAS de throw, compteur de rejet incremente de 1',
    () async {
      expect(rejectedByContractCount, 0);

      final d = await loadProfileDims('D614');

      expect(d, isNull);
      expect(
        rejectedByContractCount,
        1,
        reason:
            'Le rejet par le controle bbox_mm vs profil_mm recalcule doit '
            'etre silencieux (null) et comptabilise, jamais un assert qui '
            'leve.',
      );
    },
  );

  test(
    'un second profil en debord (D888) incremente ENCORE le compteur '
    '(cumulatif, pas un simple booleen)',
    () async {
      await loadProfileDims('D614');
      await loadProfileDims('D888');

      expect(rejectedByContractCount, 2);
    },
  );

  test(
    'un profil SAIN (D705, gate-OK) ne touche PAS au compteur de rejet',
    () async {
      final d = await loadProfileDims('D705');

      expect(d, isNotNull);
      expect(rejectedByContractCount, 0);
    },
  );
}
