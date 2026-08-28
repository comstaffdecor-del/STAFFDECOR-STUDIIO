// Test rouge d'abord (discipline Bug 1 : e0908fa puis 85bb204).
//
// Contexte : la tolérance du contrôle de cohérence bbox_mm/profil_mm
// (`ASSERTION_TOL_MM` côté `tools/dxf_pipeline/gate_sanite.py`, contrôle
// équivalent côté `lib/core/perspective/profile_dims.dart`) passe de
// 0.001mm à 0.5mm, lue depuis la SOURCE UNIQUE
// `assets/config/gate_config.json` (voir ce fichier pour la justification
// physique : tolérance de fabrication d'un moulage en plâtre, choisie au
// milieu d'un intervalle de plus d'un ordre de grandeur entre le plus gros
// bruit mesuré sur le batch de calibration -- 0.111mm -- et le plus petit
// défaut géométrique réel observé -- 1.94mm).
//
// Ce changement fait passer 4 SKU de `SUSPECT_GEOMETRIE` à `OK` côté gate
// (D569, D617, D815, D840 -- tous leurs motifs bloquants sont des débords
// strictement < 0.111mm, donc du bruit au sens de ce nouveau seuil), et
// `kExpectedGateOkCount` de 39 à 43 dans `gate_ok_count_helper.dart`.
//
// CE FICHIER EXISTE POUR UNE RAISON PRÉCISE, DISTINCTE DU SIMPLE COMPTAGE
// 39 -> 43 (qui pourrait tout aussi bien traduire un contrôle DÉSACTIVÉ
// qu'une tolérance RELEVÉE) : il verrouille explicitement que 5 SKU au
// motif bloquant géométriquement différent (au moins un débord réel
// >= 1.94mm, ou un motif CONTRAT_LOADER_PLAFOND_VIDE indépendant de toute
// tolérance numérique) restent rejetés APRÈS le changement --
//   - D898 : DEBORD_PLAN_MUR=0.001mm (bruit, aurait pu passer), mais
//     DEBORD_PLAN_PLAFOND=1.94mm (défaut réel) -- reste SUSPECT.
//   - D561 : DEBORD_PLAN_MUR=17.555mm (défaut réel, pas rattrapable par
//     aucune tolérance raisonnable) -- reste SUSPECT.
//   - D578, D814 : CONTRAT_LOADER_PLAFOND_VIDE (indices de face de pose
//     plafond vides -- motif totalement indépendant d'ASSERTION_TOL_MM,
//     qui ne peut par construction jamais être "guéri" par ce changement)
//     PLUS un débord mur > 24mm -- reste SUSPECT sur les deux motifs.
//   - D628 : DEBORD_PLAN_PLAFOND=28.725mm (défaut réel) -- reste SUSPECT.
//
// Si un jour ce test rougit parce que l'un de ces 5 SKU est passé à `OK`,
// c'est le signal que la tolérance a été relevée bien au-delà de 1.94mm
// (ou qu'un contrôle a été contourné), pas un simple ajustement de bruit
// -- c'est précisément ce qui rend le commit de relâchement de tolérance
// défendable dans le temps, indépendamment du compteur global.
//
// ⚠️ `TestWidgetsFlutterBinding.ensureInitialized()` requis avant tout
// `rootBundle.loadString` sous `flutter test` -- piège déjà documenté
// dans `profile_dims_test.dart`.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/profile_dims.dart';
import 'package:staff_decor_studio/core/perspective/profile_dims_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ProfileDimsCache.instance.resetForTesting();
    resetRejectedByContractCountForTesting();
  });

  group('relaxation de tolerance (0.001mm -> 0.5mm) -- SKU repasses OK', () {
    for (final ref in ['D569', 'D617', 'D815', 'D840']) {
      test(
        '$ref : motifs bloquants purement bruit (< 0.111mm) -> '
        'loadProfileDims renvoie desormais des dimensions non-null, '
        'PAS un rejet',
        () async {
          final dims = await loadProfileDims(ref);
          expect(
            dims,
            isNotNull,
            reason:
                '$ref devrait desormais passer le controle de coherence '
                '(tous ses debords sont < 0.111mm, donc strictement '
                'sous la nouvelle tolerance de 0.5mm) -- si null, la '
                'tolerance lue depuis assets/config/gate_config.json '
                'n\'est pas celle attendue.',
          );
          expect(rejectedByContractCount, 0, reason: '$ref ne doit pas incrementer le compteur de rejet.');
        },
      );
    }
  });

  group(
    'GARDE : SKU a defaut geometrique reel (>= 1.94mm) ou motif '
    'independant -- doivent rester rejetes APRES le relachement de '
    'tolerance, sous peine de prouver un controle desactive plutot '
    'qu\'une tolerance relevee',
    () {
      test(
        'D898 : bruit sur le mur (0.001mm) MAIS defaut reel au plafond '
        '(1.94mm) -> reste rejete (null)',
        () async {
          final dims = await loadProfileDims('D898');
          expect(
            dims,
            isNull,
            reason:
                'D898 a un debord plafond de 1.94mm, largement au-dessus '
                'de la nouvelle tolerance de 0.5mm -- doit rester rejete '
                'independamment du fait que son debord mur (0.001mm) '
                'soit lui du bruit pur.',
          );
        },
      );

      test('D561 : defaut mur reel (17.555mm) -> reste rejete (null)', () async {
        final dims = await loadProfileDims('D561');
        expect(
          dims,
          isNull,
          reason:
              'D561 a un debord mur de 17.555mm -- aucune tolerance '
              'physiquement raisonnable ne peut absorber cet ecart.',
        );
      });

      test('D628 : defaut plafond reel (28.725mm) -> reste rejete (null)', () async {
        final dims = await loadProfileDims('D628');
        expect(dims, isNull, reason: 'D628 a un debord plafond de 28.725mm -- defaut reel, pas du bruit.');
      });

      test(
        'D578 : CONTRAT_LOADER_PLAFOND_VIDE (indices face_pose_plafond '
        'vides) -> reste rejete (null), motif independant de toute '
        'tolerance numerique de debord',
        () async {
          final dims = await loadProfileDims('D578');
          expect(
            dims,
            isNull,
            reason:
                'D578 a face_pose_plafond.indices vide -- ce rejet a '
                'lieu AVANT meme le calcul du controle bbox_mm/'
                'profil_mm (voir loadProfileDims), donc ne peut par '
                'construction jamais etre affecte par ASSERTION_TOL_MM.',
          );
        },
      );

      test(
        'D814 : CONTRAT_LOADER_PLAFOND_VIDE + defaut mur reel (24.771mm) '
        '-> reste rejete (null)',
        () async {
          final dims = await loadProfileDims('D814');
          expect(dims, isNull, reason: 'D814 : meme motif que D578, plus un debord mur de 24.771mm.');
        },
      );

      test(
        'bilan cumulatif : les 5 SKU de garde ci-dessus incrementent '
        'rejectedByContractCount de 0 A 2 exactement (D898, D561, D628 '
        'passent bien le controle CONTRAT_LOADER_* et sont rejetes par '
        'le controle bbox_mm/profil_mm ; D578 et D814 sont rejetes plus '
        'tot, avant ce compteur, par indices de face de pose vides)',
        () async {
          var expectedIncrements = 0;
          for (final ref in ['D898', 'D561', 'D628']) {
            final dims = await loadProfileDims(ref);
            expect(dims, isNull);
            expectedIncrements++;
            expect(
              rejectedByContractCount,
              expectedIncrements,
              reason: '$ref devrait incrementer rejectedByContractCount (rejet par controle bbox_mm).',
            );
          }
          for (final ref in ['D578', 'D814']) {
            final dims = await loadProfileDims(ref);
            expect(dims, isNull);
            expect(
              rejectedByContractCount,
              expectedIncrements,
              reason:
                  '$ref rejete par indices de face de pose vides, avant '
                  'le controle bbox_mm -- ne doit PAS incrementer '
                  'rejectedByContractCount.',
            );
          }
        },
      );
    },
  );

  group('bout-en-bout via le cache reel (ProfileDimsCache), pas seulement loadProfileDims direct', () {
    test(
      'les 4 SKU repasses OK chargent via le cache (getIfLoaded non-null) ; '
      'les 5 SKU de garde restent hasFailed==true',
      () async {
        Future<void> ensureSettled(String ref) async {
          ProfileDimsCache.instance.ensureLoading(ref);
          for (var i = 0; i < 200; i++) {
            if (ProfileDimsCache.instance.getIfLoaded(ref) != null ||
                ProfileDimsCache.instance.hasFailed(ref)) {
              return;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }

        for (final ref in ['D569', 'D617', 'D815', 'D840']) {
          await ensureSettled(ref);
          expect(
            ProfileDimsCache.instance.getIfLoaded(ref),
            isNotNull,
            reason: '$ref devrait charger via le cache (couvert par index.json regenere).',
          );
        }

        for (final ref in ['D898', 'D561', 'D578', 'D628', 'D814']) {
          await ensureSettled(ref);
          expect(
            ProfileDimsCache.instance.hasFailed(ref),
            isTrue,
            reason: '$ref doit rester hors-index (statut_gate != OK) -- hasFailed==true attendu.',
          );
        }
      },
    );
  });
}
