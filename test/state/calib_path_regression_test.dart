// Livrable 6.3 (brief "livrables réunion") — comble un trou identifié sur
// plusieurs tours : aucun des 46 fichiers de test existants ne couvrait
// `updateCalibPoint`, `isCalibrated` ni `calibAutoDetected` — exactement la
// logique que P9l a découplée (isCalibrated ne doit JAMAIS être vrai sur une
// géométrie non certifiée) et que P9m a rebranchée sur les presets démo.
//
// Ce test vérifie le comportement RÉEL observé dans `app_state.dart` au
// moment où il a été écrit (HEAD proche de 3a99b75), il ne redéfinit aucun
// comportement. Toute divergence entre ce qui aurait pu être supposé et ce
// qui est réellement observé est documentée en commentaire à l'endroit
// concerné plutôt que "corrigée" silencieusement.
//
// Signatures/champs vérifiés par grep avant écriture (voir rapport livré) :
//   - `loadDemoScene(key, {containerSize})` : pour une clé de preset connue,
//     positionne `perspCalib = preset`, `calibAutoDetected = true`,
//     `isCalibrated = true`, `edgeDetectConfidence = 1.0` (app_state.dart
//     ~L335-340).
//   - `updateCalibPoint(key, CalibPoint)` : modifie SEULEMENT le point ciblé
//     via `copyWith`, puis positionne `isCalibrated = true` sans jamais le
//     redescendre (app_state.dart ~L349-377).
//   - Clé de scène inconnue → `_presetForScene` retourne `null` → branche
//     `unawaited(autoDetectEdges())` (app_state.dart ~L342-343), qui NE
//     positionne JAMAIS `isCalibrated = true` (seul `updateCalibPoint` le
//     fait — voir commentaire app_state.dart ~L185-191 : "isCalibrated
//     reste à sa valeur courante... PAS mis à true").
//
// DIVERGENCE OBSERVÉE (documentée, non corrigée — hors périmètre 6.3/6.6) :
// `loadDemoScene` ne réinitialise PAS `isCalibrated` à `false` avant de
// tenter le chemin `autoDetectEdges` pour une clé inconnue. Si l'appelant
// avait auparavant chargé une scène démo (isCalibrated=true) puis appelle
// `loadDemoScene` avec une clé inconnue, `isCalibrated` reste `true` — donc
// la garantie "jamais calibré sur une géométrie non certifiée" n'est vraie
// que si `isCalibrated` était déjà `false` avant l'appel. Ce test le
// documente en partant d'un état initial explicite (`isCalibrated=false`,
// aucune scène chargée au préalable), qui est le cas réel au démarrage de
// l'app (valeur par défaut du champ, app_state.dart L71) — la séquence
// "scène connue puis scène inconnue sans re-render" n'est de toute façon
// pas un chemin UI atteignable (le sélecteur de scène ne propose que les 4
// clés connues), donc ce n'est pas un bug fonctionnel, seulement un
// non-invariant interne à surveiller si l'API `loadDemoScene` est un jour
// appelée directement avec une clé arbitraire.
library;

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:staff_decor_studio/models/persp_calib.dart';
import 'package:staff_decor_studio/state/app_state.dart';

const _kContainerSize = Size(1400, 868); // 1400 x (1400*0.62), cf. studio_screen.dart

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Livrable 6.3 — chemin de calibration (updateCalibPoint / '
      'isCalibrated / calibAutoDetected)', () {
    test(
      '1) une scène démo connue (preset) arrive calibAutoDetected=true, '
      'isCalibrated=true, edgeDetectConfidence=1.0',
      () async {
        final state = AppState();
        expect(state.isCalibrated, isFalse,
            reason: 'valeur initiale attendue avant tout chargement');

        await state.loadDemoScene('haussmann', containerSize: _kContainerSize);

        expect(state.calibAutoDetected, isTrue);
        expect(state.isCalibrated, isTrue);
        expect(state.edgeDetectConfidence, 1.0);
        expect(state.perspCalib, PerspCalib.forDemoScene('haussmann'));
      },
    );

    test(
      '2) updateCalibPoint déplace le point ciblé, lève isCalibrated, et '
      "n'écrase pas les 7 autres points",
      () async {
        final state = AppState();
        await state.loadDemoScene('moderne', containerSize: _kContainerSize);
        // isCalibrated est déjà true après un chargement de preset (point 1)
        // — on repart explicitement à false pour vérifier que c'est bien
        // updateCalibPoint qui le (re)lève, et pas un résidu du chargement.
        state.isCalibrated = false;

        final before = state.perspCalib!;
        const moved = CalibPoint(xPct: 0.15, yPct: 0.33);
        state.updateCalibPoint('floorL', moved);

        final after = state.perspCalib!;
        expect(after.floorL.xPct, moved.xPct);
        expect(after.floorL.yPct, moved.yPct);
        // Les 7 autres points doivent rester strictement identiques.
        expect(after.ceilL, before.ceilL);
        expect(after.ceilR, before.ceilR);
        expect(after.floorR, before.floorR);
        expect(after.wallTL, before.wallTL);
        expect(after.wallTR, before.wallTR);
        expect(after.wallBL, before.wallBL);
        expect(after.wallBR, before.wallBR);
        expect(state.isCalibrated, isTrue);
      },
    );

    test(
      "3) une clé de scène inconnue retombe sur autoDetectEdges sans lever "
      'isCalibrated (découplage P9l : jamais "calibré" sur une géométrie '
      'non certifiée)',
      () async {
        final state = AppState();
        expect(state.isCalibrated, isFalse);

        await state.loadDemoScene('scene_inconnue_xyz',
            containerSize: _kContainerSize);
        // loadDemoScene lance autoDetectEdges en arrière-plan
        // (unawaited) : on laisse le temps aux microtasks de se dérouler.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(state.calibAutoDetected, isFalse);
        expect(state.isCalibrated, isFalse,
            reason: 'garantie P9l : autoDetectEdges ne doit jamais lever '
                'isCalibrated tout seul');
      },
    );

    test('4) notifyListeners est bien émis par loadDemoScene et par '
        'updateCalibPoint', () async {
      final state = AppState();
      var notifyCount = 0;
      state.addListener(() => notifyCount++);

      await state.loadDemoScene('provencal', containerSize: _kContainerSize);
      expect(notifyCount, greaterThan(0),
          reason: 'loadDemoScene doit notifier au moins une fois');

      final countAfterLoad = notifyCount;
      state.updateCalibPoint('ceilR', const CalibPoint(xPct: 0.9, yPct: 0.2));
      expect(notifyCount, greaterThan(countAfterLoad),
          reason: 'updateCalibPoint doit notifier');
    });
  });
}
