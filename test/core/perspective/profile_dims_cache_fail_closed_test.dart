// Test rouge d'abord (discipline Bug 1 : e0908fa puis 85bb204).
//
// Contrat fail-closed de `ProfileDimsCache._ensureCoveredRefsLoaded()`
// (voir `profile_dims_cache.dart`) : toute anomalie de lecture de
// `assets/profiles/index.json` (asset absent/erreur, JSON malformé,
// JSON valide mais `refs` vide ou absent) doit résoudre un ensemble de
// couverture VIDE -- jamais un repli sur `AssetManifest.json`, jamais
// une exception propagée.
//
// Ce contrat avait été "vérifié par lecture de code" dans
// `profile_dims_cache_index_test.dart` (test en `skip:`), ce qui ne
// prouve rien de l'exécution réelle. Ce fichier fait tourner le
// contrat pour de vrai, en interceptant le canal de plateforme
// `flutter/assets` que `rootBundle.loadString` utilise sous le capot
// (`PlatformAssetBundle.load`, `package:flutter/src/services/
// asset_bundle.dart`) via
// `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
// .setMockMessageHandler('flutter/assets', ...)`.
//
// Isolation : ce mock intercepte TOUT chargement d'asset dans ce
// fichier de test (pas seulement `index.json`), donc chaque test route
// explicitement sur la clé d'asset demandée et ne répond que pour
// `assets/profiles/index.json` -- toute autre clé (improbable ici,
// aucun autre asset n'est lu par le code exercé) reçoit une réponse
// `null`, cohérente avec "asset absent". Le handler est retiré dans
// `tearDown` pour ne jamais fuiter vers d'autres fichiers de test
// exécutés dans le même process.
//
// Aucun fichier déplacé, aucun `assets/profiles/index.json` réel
// modifié -- les trois scénarios sont simulés uniquement via le canal
// mocké, donc les tests voisins qui dépendent du vrai contenu
// d'`index.json` (`profile_dims_cache_index_test.dart`,
// `profile_dims_cache_coverage_31_test.dart`) restent inchangés.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/profile_dims_cache.dart';

const _assetsChannel = 'flutter/assets';
const _indexAssetKey = 'assets/profiles/index.json';

/// Décode la clé d'asset demandée par `PlatformAssetBundle.load` à
/// partir du message brut envoyé sur le canal `flutter/assets` (UTF-8,
/// voir `PlatformAssetBundle.load` : `utf8.encode(Uri(path:
/// Uri.encodeFull(key)).path)`).
String _decodeRequestedKey(ByteData message) {
  return utf8.decode(message.buffer.asUint8List(
    message.offsetInBytes,
    message.lengthInBytes,
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ProfileDimsCache.instance.resetForTesting();
    // `rootBundle` (PlatformAssetBundle extends CachingAssetBundle)
    // mémoïse `loadString` PAR CLÉ, y compris un résultat en échec
    // (`_stringCache.putIfAbsent`, voir `asset_bundle.dart`) -- sans cet
    // `evict`, le premier test (CAS 1, erreur simulée) laisserait un
    // Future en échec mémoïsé pour `index.json`, et TOUS les tests
    // suivants de ce fichier recevraient cette même erreur périmée sans
    // jamais réinterroger le canal mocké de ce test. Découvert
    // empiriquement (le log d'erreur du CAS 1 réapparaissait identique
    // dans CAS 2/3/CONTROLE avant l'ajout de cet evict).
    rootBundle.evict(_indexAssetKey);
  });

  tearDown(() {
    // Retire le mock avant le test suivant, dans CE fichier ou dans un
    // autre exécuté dans le même process -- sinon un mock laissé en
    // place intercepterait aussi les chargements d'assets réels des
    // tests voisins (index.json, mais aussi tout autre asset packagé).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_assetsChannel, null);
    // Idem : évite qu'un résultat (erreur ou JSON simulé) mémoïsé par
    // CE test ne pollue le suivant, dans ce fichier ou dans un autre
    // fichier de test exécuté ensuite dans le même process VM.
    rootBundle.evict(_indexAssetKey);
  });

  Future<Set<String>> resolveCoveredRefsViaProbe(String probeRef) async {
    final completer = Completer<void>();
    void cb() {
      if (!completer.isCompleted) completer.complete();
    }

    ProfileDimsCache.instance.addListener(cb);
    ProfileDimsCache.instance.ensureLoading(probeRef);
    await completer.future.timeout(const Duration(seconds: 5));
    ProfileDimsCache.instance.removeListener(cb);

    final covered = ProfileDimsCache.instance.coveredRefsForTesting;
    expect(
      covered,
      isNotNull,
      reason:
          'coveredRefsForTesting doit etre resolu (non-null) une fois '
          'ensureLoading termine, meme en cas d\'echec de lecture -- '
          'resolu vers un ensemble VIDE, jamais laisse null.',
    );
    return covered!;
  }

  test(
    'CAS 1/3 -- erreur de chargement (asset absent, canal renvoie une '
    'exception) -> couverture VIDE, aucune ref chargee, jamais de '
    'repli sur AssetManifest.json',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(_assetsChannel, (ByteData? message) async {
        final key = _decodeRequestedKey(message!);
        if (key == _indexAssetKey) {
          throw Exception('simulation : erreur de chargement index.json');
        }
        return null;
      });

      final covered = await resolveCoveredRefsViaProbe('D830');

      expect(covered, isEmpty);
      expect(ProfileDimsCache.instance.getIfLoaded('D830'), isNull);
      expect(ProfileDimsCache.instance.hasFailed('D830'), isTrue);
    },
  );

  test(
    'CAS 2/3 -- JSON malforme (contenu non-JSON) -> couverture VIDE, '
    'aucune ref chargee, aucune exception propagee au cache',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(_assetsChannel, (ByteData? message) async {
        final key = _decodeRequestedKey(message!);
        if (key == _indexAssetKey) {
          final bytes = utf8.encode('{ceci n\'est pas du json valide');
          return ByteData.sublistView(Uint8List.fromList(bytes));
        }
        return null;
      });

      final covered = await resolveCoveredRefsViaProbe('D830');

      expect(covered, isEmpty);
      expect(ProfileDimsCache.instance.getIfLoaded('D830'), isNull);
      expect(ProfileDimsCache.instance.hasFailed('D830'), isTrue);
    },
  );

  test(
    'CAS 3/3 -- JSON valide mais refs vide ({"refs": []}) -> couverture '
    'VIDE, aucune ref chargee (y compris une ref reellement gate-OK '
    'comme D830, dont le fichier <ref>.json existe et est valide sur '
    'disque -- seule la couverture d\'index.json manque ici)',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(_assetsChannel, (ByteData? message) async {
        final key = _decodeRequestedKey(message!);
        if (key == _indexAssetKey) {
          final bytes = utf8.encode(jsonEncode({'refs': <String>[]}));
          return ByteData.sublistView(Uint8List.fromList(bytes));
        }
        return null;
      });

      final covered = await resolveCoveredRefsViaProbe('D830');

      expect(covered, isEmpty);
      expect(ProfileDimsCache.instance.getIfLoaded('D830'), isNull);
      expect(ProfileDimsCache.instance.hasFailed('D830'), isTrue);
    },
  );

  test(
    'CONTROLE (pas un cas d\'echec) -- avec le VRAI index.json (mock '
    'retiré), D830 charge normalement -- confirme que les 3 tests '
    'ci-dessus echouent bien a cause du mock simule, pas d\'un defaut '
    'plus general du cache qui rejetterait D830 dans tous les cas',
    () async {
      // Aucun setMockMessageHandler ici : le canal utilise le handler
      // par defaut de flutter_test, qui lit les VRAIS assets packages
      // (voir mockFlutterAssets/mecanisme standard de
      // AutomatedTestWidgetsFlutterBinding).
      final covered = await resolveCoveredRefsViaProbe('D830');

      expect(covered, isNotEmpty);
      expect(covered.contains('D830'), isTrue);
      expect(ProfileDimsCache.instance.getIfLoaded('D830'), isNotNull);
      expect(ProfileDimsCache.instance.hasFailed('D830'), isFalse);
    },
  );
}
