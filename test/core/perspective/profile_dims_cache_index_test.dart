// Test rouge d'abord (discipline Bug 1 : e0908fa puis 85bb204).
//
// Contexte : `ProfileDimsCache` dérivait sa couverture d'`AssetManifest
// .json`, qui liste les 56 fichiers `statut: OK` sans distinction — 16
// d'entre eux faisaient lever l'ancien `assert()` du loader (corrigé
// dans `profile_dims.dart`, voir `profile_dims_contract_reject_test
// .dart`), les autres passaient avec des dimensions correctes MAIS sans
// aucune garantie structurelle (une simple coïncidence bbox_mm/profil_mm,
// pas un contrôle de gate). Ce test fixe le nouveau contrat : la
// couverture doit venir de `assets/profiles/index.json` (généré par
// `tools/dxf_pipeline/build_profiles_index.py` depuis les 31 SKU
// `statut_gate == "OK"`), PAS d'AssetManifest.json.
//
// ⚠️ CE N'EST PAS UNE EXTENSION DE COUVERTURE, c'est une RESTRICTION
// (56 -> 31) : `D830` (gate-OK) ET `D705` (gate-OK) étaient TOUS LES DEUX
// déjà présents dans `AssetManifest.json` avant ce commit (fichiers
// `statut: OK` sur disque depuis le batch Piste A), donc DEJA "couverts"
// et rendus en métrique en build RELEASE par l'ancien mécanisme (le
// contrôle bbox_mm n'était qu'un `assert()`, absent du binaire release).
// Ce test ne vérifie donc PAS que D830 devient nouvellement accessible
// -- il vérifie que le nouveau mécanisme (index.json, 31 gate-OK)
// couvre D830 pour la BONNE raison structurelle (gate), et non plus par
// la coïncidence de l'ancien mécanisme (AssetManifest.json, 56
// statut:OK sans distinction).
//
// Règle fail-closed (imposée par le brief) : une ref simplement absente
// d'index.json (mais dont le fichier <ref>.json existe bel et bien,
// cas de D614/D888, statut OK mais hors gate) ne doit JAMAIS être
// chargée, même si elle passerait le contrôle bbox_mm — l'exclusion est
// une décision de gate, pas une question de validité géométrique locale.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/profile_dims_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ProfileDimsCache.instance.resetForTesting();
  });

  test(
    'D830 (gate-OK, deja rendu en metrique par l\'ancien mecanisme AVANT '
    'ce commit -- pas une nouvelle couverture) est couvert par index.json '
    'pour la bonne raison structurelle (gate), et charge reellement ses '
    'dimensions reelles',
    () async {
      final completer = Completer<void>();
      void cb() {
        if (!completer.isCompleted) completer.complete();
      }

      ProfileDimsCache.instance.addListener(cb);
      ProfileDimsCache.instance.ensureLoading('D830');

      await completer.future.timeout(const Duration(seconds: 5));

      final dims = ProfileDimsCache.instance.getIfLoaded('D830');
      expect(dims, isNotNull);
      expect(dims!.ref, 'D830');
      // bbox_mm = {w: 104.513, h: 124.561}, verifie par lecture directe
      // du fichier dans cette session.
      expect(dims.projectionMm, closeTo(104.513, 0.01));
      expect(dims.retombeeMm, closeTo(124.561, 0.01));
      expect(ProfileDimsCache.instance.hasFailed('D830'), isFalse);

      ProfileDimsCache.instance.removeListener(cb);
    },
  );

  test(
    'D614 (statut OK, fichier existe, mais HORS des 31 gate-OK) ne doit '
    'JAMAIS etre charge par ensureLoading, meme si le fichier existe sur '
    'disque -- exclusion par decision de gate (index.json), pas par '
    'validite geometrique locale',
    () async {
      final completer = Completer<void>();
      void cb() {
        if (!completer.isCompleted) completer.complete();
      }

      ProfileDimsCache.instance.addListener(cb);
      ProfileDimsCache.instance.ensureLoading('D614');

      await completer.future.timeout(const Duration(seconds: 5));

      expect(ProfileDimsCache.instance.getIfLoaded('D614'), isNull);
      expect(ProfileDimsCache.instance.hasFailed('D614'), isTrue);

      ProfileDimsCache.instance.removeListener(cb);
    },
  );

  test(
    'preuve STRUCTURELLE (pas seulement empirique) : la couverture vient '
    'de index.json (31 refs) et non d\'AssetManifest.json (56 fichiers '
    'statut:OK) -- coveredRefsForTesting doit avoir EXACTEMENT 31 '
    'elements apres resolution, jamais 56. Necessaire car aucune '
    'divergence gate/loader n\'existe empiriquement sur le jeu de '
    'donnees actuel (verifie separement) -- cette garantie doit tenir '
    'independamment de cette coincidence, y compris si le gate durcit '
    'ses criteres demain sans que le loader change.',
    () async {
      final completer = Completer<void>();
      void cb() {
        if (!completer.isCompleted) completer.complete();
      }

      ProfileDimsCache.instance.addListener(cb);
      ProfileDimsCache.instance.ensureLoading('D705');

      await completer.future.timeout(const Duration(seconds: 5));

      final covered = ProfileDimsCache.instance.coveredRefsForTesting;
      expect(covered, isNotNull);
      expect(
        covered!.length,
        31,
        reason:
            'Si ce nombre vaut 56, le cache lit encore AssetManifest.json '
            'au lieu de index.json -- regression exactement ciblee par ce '
            'test.',
      );
      expect(covered.contains('D830'), isTrue);
      expect(covered.contains('D614'), isFalse);

      ProfileDimsCache.instance.removeListener(cb);
    },
  );

  // Le test fail-closed (index.json absent/illisible/vide) est desormais
  // EXECUTE reellement, par mock de rootBundle via
  // TestDefaultBinaryMessengerBinding, dans
  // profile_dims_cache_fail_closed_test.dart -- plus de skip ici.
}
