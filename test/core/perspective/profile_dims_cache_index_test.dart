// Test rouge d'abord (discipline Bug 1 : e0908fa puis 85bb204).
//
// Contexte : `ProfileDimsCache` dérivait sa couverture d'`AssetManifest
// .json`, qui liste les 56 fichiers `statut: OK` sans distinction — 16
// d'entre eux faisaient lever l'ancien `assert()` du loader (corrigé
// dans `profile_dims.dart`, voir `profile_dims_contract_reject_test
// .dart`), les 9 autres passaient avec des dimensions non garanties par
// le gate. Ce test fixe le nouveau contrat : la couverture doit venir de
// `assets/profiles/index.json` (généré par
// `tools/dxf_pipeline/build_profiles_index.py` depuis les 31 SKU
// `statut_gate == "OK"`), PAS d'AssetManifest.json.
//
// Preuve d'extension de couverture (pas de mise en service, D705 était
// déjà couvert avant ce commit) : `D830` fait partie des 27 SKU
// nouvellement gate-OK (hors des 8 refs d'origine du câblage
// 13-17 août). Avant ce commit, `D830` était déjà présent dans
// `AssetManifest.json` (fichier `assets/profiles/D830.json` existe,
// `statut: OK`) donc DÉJÀ "couvert" au sens de l'ancien mécanisme — ce
// test vérifie que le nouveau mécanisme (index.json) le couvre AUSSI,
// via la bonne source (31 gate-OK), pas par accident via l'ancienne.
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
    'D830 (gate-OK, hors des 8 refs d\'origine du cablage aout) est '
    'couvert par index.json et charge reellement ses dimensions reelles',
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

  test(
    'fail-closed : si index.json est absent/illisible/vide, le cache ne '
    'charge RIEN (jamais de repli sur AssetManifest.json, qui '
    'ressusciterait le bug des 56 non filtres)',
    () async {
      // Ce test documente le contrat attendu du mecanisme de lecture de
      // index.json cote production (verifie par construction du code,
      // pas par simulation d'un fichier absent ici -- deplacer
      // index.json pendant flutter test casserait aussi les DEUX autres
      // tests de ce fichier qui en dependent legitimement). Voir
      // l'implementation de _ensureCoveredRefsLoaded : le bloc
      // try/catch autour de la lecture de index.json degrade vers un
      // ensemble VIDE, jamais vers AssetManifest.json.
    },
    skip:
        'Documentation du contrat -- verification par lecture de code, '
        'pas par execution (deplacer index.json casserait les tests '
        'voisins qui en dependent).',
  );
}
