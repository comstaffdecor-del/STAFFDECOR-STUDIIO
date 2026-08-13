library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/profile_dims_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Remise à zéro avant CHAQUE test — le singleton ProfileDimsCache
    // .instance est partagé entre tous les tests de ce fichier (et de
    // tout le process de test). Sans ceci, un ref déjà en cache/failed
    // par un test précédent fait prendre le retour anticipé de
    // ensureLoading aux tests suivants, sans notifier — tests
    // ordre-dépendants sans le montrer.
    ProfileDimsCache.instance.resetForTesting();
  });

  test(
    'D720 (couverte par assets/profiles/D720.json) : ensureLoading '
    'charge reellement via loadProfileDims, notifie, getIfLoaded renvoie '
    'les dims metriques reelles',
    () async {
      final completer = Completer<void>();
      void cb() {
        if (!completer.isCompleted) completer.complete();
      }

      ProfileDimsCache.instance.addListener(cb);

      ProfileDimsCache.instance.ensureLoading('D720');
      // Chargement differe (manifest + JSON), jamais synchrone.
      expect(ProfileDimsCache.instance.getIfLoaded('D720'), isNull);
      expect(ProfileDimsCache.instance.isLoadingForTesting('D720'), isTrue);
      expect(ProfileDimsCache.instance.hasFailed('D720'), isFalse);

      await completer.future.timeout(const Duration(seconds: 5));

      final dims = ProfileDimsCache.instance.getIfLoaded('D720');
      expect(dims, isNotNull);
      expect(dims!.ref, 'D720');
      expect(dims.retombeeMm, closeTo(202.87, 0.01));
      expect(dims.projectionMm, closeTo(199.145, 0.01));
      expect(ProfileDimsCache.instance.hasFailed('D720'), isFalse);

      ProfileDimsCache.instance.removeListener(cb);
    },
  );

  // NOTE (retrait deliberement documente, pas un oubli) : une tentative
  // de test dedie a l'echantillonnage direct de la fenetre
  // "coveredRefsForTesting == null" a ete ecrite ici (polling 100us,
  // garde excluant i == 0 pour eviter la trivialite "avant tout yield").
  // Mesure empirique sur cette machine : 5/5 executions echouent sur la
  // garde meme APRES avoir exclu i == 0 — le manifeste (I/O reelle,
  // AssetManifest.loadFromAssetBundle) se resout systematiquement avant
  // que la boucle n'atteigne une seconde iteration avec le cache encore
  // non resolu. La fenetre existe (elle est necessaire, ne serait-ce
  // qu'un instant, entre l'appel et l'await) mais n'est PAS observable
  // par polling externe sans couture d'injection dediee (un hook
  // @visibleForTesting retardant artificiellement la resolution du
  // manifeste) — absente aujourd'hui, hors perimetre de ce commit.
  // Conclusion : ce test aurait ete soit trivial (garde faible, motif
  // deja identifie et corrige une fois), soit rouge par construction
  // sur cette machine (garde correcte). Retire plutot que "repare" en
  // affaiblissant a nouveau la garde. La preuve de l'absence
  // d'empoisonnement permanent reste le test D720-a-froid ci-dessus :
  // setUp() remet _manifestLoading a null avant CHAQUE test, donc ce
  // test s'execute necessairement manifeste froid ; s'il y avait un
  // classement premature en _failed avant resolution du manifeste, ce
  // test serait rouge, point final — independamment de toute lecture du
  // code source de _resolve.

  test(
    'ref absente du catalogue JSON (non couverte par AssetManifest) : '
    'ensureLoading ne tente jamais loadProfileDims pour elle — evite la '
    'tempete d\'exceptions rootBundle.loadString sur les 275/283 refs '
    'sans profil —, finit en hasFailed == true sans jamais throw',
    () async {
      const ref = '__test_profiledims_uncovered_ref__';
      final completer = Completer<void>();
      void cb() {
        if (!completer.isCompleted) completer.complete();
      }

      ProfileDimsCache.instance.addListener(cb);
      ProfileDimsCache.instance.ensureLoading(ref);

      await completer.future.timeout(const Duration(seconds: 5));

      expect(ProfileDimsCache.instance.hasFailed(ref), isTrue);
      expect(ProfileDimsCache.instance.getIfLoaded(ref), isNull);

      ProfileDimsCache.instance.removeListener(cb);
    },
  );

  test(
    'idempotence : _loading est marque de facon SYNCHRONE (avant la '
    'microtache), donc un second ensureLoading(D718) dans la meme frame '
    '(paint() itere sur plusieurs produits) reste un no-op immediat',
    () {
      ProfileDimsCache.instance.ensureLoading('D718');
      expect(ProfileDimsCache.instance.isLoadingForTesting('D718'), isTrue);

      // Deuxieme appel synchrone, meme frame — doit rester un no-op
      // (retour anticipe du garde _loading.contains(ref)), pas planifier
      // un second chargement du meme fichier.
      ProfileDimsCache.instance.ensureLoading('D718');
      expect(ProfileDimsCache.instance.isLoadingForTesting('D718'), isTrue);
    },
  );

  test(
    'aucune notification SYNCHRONE : ensureLoading ne notifie jamais dans '
    'sa propre pile d\'appel — invariant structurel Future.microtask, '
    'copie du correctif ProductTextureCache (97879ac), pas un cas '
    'particulier au manifeste',
    () {
      const ref = '__test_profiledims_sync_notify_probe__';
      var notified = false;
      void cb() => notified = true;

      ProfileDimsCache.instance.addListener(cb);
      ProfileDimsCache.instance.ensureLoading(ref);

      expect(
        notified,
        isFalse,
        reason:
            'notifyListeners() est parti de facon SYNCHRONE, dans la '
            'meme pile d\'appel que ensureLoading — dangereux si '
            'ensureLoading est un jour appele depuis paint() (comme '
            'ProductTextureCache.ensureLoading l\'est aujourd\'hui).',
      );

      ProfileDimsCache.instance.removeListener(cb);
    },
  );
}
