/// Cache global des dimensions métriques réelles ([ProfileDims]) — calqué
/// structurellement sur [ProductTextureCache] (voir ce fichier et son
/// historique de commits `4e0041b`/`97879ac` pour le raisonnement complet
/// sur le mécanisme de repaint et l'invariant de notification asynchrone).
///
/// ⚠️ Ce fichier n'est PAS encore branché à [RoomPainter] (aucun import
/// dans `room_painter.dart`, aucun `super(repaint: ...)` mis à jour) —
/// c'est un cache isolé, testé seul. Le câblage (`Listenable.merge` dans
/// le `repaint:` de [RoomPainter] et le remplacement du site
/// `room_painter.dart:134`) est une étape ultérieure distincte, dans son
/// propre commit.
///
/// ## Différence de contexte avec [ProductTextureCache]
///
/// [ProductTextureCache] charge une photo réseau (HTTP) : une URL
/// malformée est un événement rare, non prévu par le catalogue actuel
/// (458 URLs bien formées, vérifié). Ici, la source est un **asset
/// local** (`assets/profiles/<ref>.json` via [loadProfileDims]), et
/// 275 références sur 283 du catalogue N'ONT PAS de fichier associé —
/// ce n'est jamais une erreur applicative, c'est le cas normal. Un cache
/// naïf qui appelle directement [loadProfileDims] pour chaque `ref`
/// produirait, à chaque premier rendu de catalogue, jusqu'à 275
/// exceptions `rootBundle.loadString` levées puis rattrapées (déjà gérées
/// sans throw par [loadProfileDims] lui-même, mais le coût de lever +
/// attraper 275 fois reste réel).
///
/// Pour éviter cette tempête, ce cache lit `AssetManifest.json` UNE FOIS
/// (`AssetManifest.loadFromAssetBundle(rootBundle)`, disponible depuis
/// Flutter 3.7 — largement couvert par la version figée de ce projet,
/// 3.35.4, vérifié) et ne tente [loadProfileDims] QUE pour les refs dont
/// `assets/profiles/<ref>.json` apparaît réellement dans le manifeste.
/// Les refs absentes du manifeste sont marquées `_failed` directement,
/// sans jamais invoquer [loadProfileDims]. `AssetManifest
/// .loadFromAssetBundle` a été vérifié empiriquement fonctionnel sous
/// `TestWidgetsFlutterBinding` (avec `ensureInitialized()` en tête de
/// test) — pas seulement en production — donc le chemin de test et le
/// chemin réel exercent la même logique de filtrage, pas une variante.
///
/// En prime, la liste des refs couvertes par le manifeste
/// (`coveredRefsForTesting` / usage futur : indicateur UI "non calibré")
/// est calculée une fois, réutilisable sans nouvelle lecture disque.
///
/// Défense en profondeur : si `AssetManifest.loadFromAssetBundle` devait
/// un jour échouer (binding absent, asset manifeste corrompu — aucun cas
/// observé à ce stade, mais le risque n'est pas nul), le chargement du
/// manifeste est protégé par un `try/catch` qui dégrade vers une
/// tentative directe de [loadProfileDims] pour CHAQUE ref demandée —
/// exactement le comportement naïf qu'on cherche à éviter dans le cas
/// normal, mais qui reste correct (juste plus coûteux) si le filtrage en
/// amont n'est pas disponible.
///
/// ## Repli TEMPORAIRE pendant le bootstrap du manifeste — PAS un repli
/// permanent
///
/// Le chargement du manifeste est lui-même asynchrone
/// (`AssetManifest.loadFromAssetBundle` retourne un `Future`), mémoïsé
/// dans [_manifestLoading]. [_resolve] `await`e sa résolution AVANT de
/// décider si une ref est couverte — la décision n'est donc jamais
/// prise prématurément : tant que le manifeste n'est pas prêt, la ref
/// reste marquée `_loading` (PAS `_failed`), [_resolve] est simplement
/// suspendu sur ce `await`, et aucune notification n'est envoyée.
///
/// Concrètement, la toute première frame après démarrage affichera en
/// repli (`StripThickness.corniceDefault`, côté appelant, via
/// `getIfLoaded` qui renvoie `null` tant que rien n'est en cache) MÊME
/// pour les 8 refs réellement couvertes (`D705`, `D718`, `D720`, `0900`,
/// `1000`, `1005`, `1145c`, `20-54`) — c'est un choix délibéré, MAIS
/// c'est une fenêtre de latence, pas un classement en échec : une fois
/// le manifeste résolu, la vraie décision est prise et notifiée
/// normalement, y compris pour une ref qui aurait été demandée pendant
/// la fenêtre de bootstrap. Le futur `repaint:` (commit de câblage)
/// rattrape l'affichage dès que le manifeste est prêt, exactement comme
/// il rattrape déjà le chargement des textures produit. Vérifié par
/// test (`profile_dims_cache_test.dart`, cas D720, `setUp` remettant
/// aussi `_manifestLoading` à `null` avant chaque test — donc exécuté à
/// froid, pas avec un manifeste déjà chaud d'un test précédent).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;

import 'profile_dims.dart';

class ProfileDimsCache extends ChangeNotifier {
  ProfileDimsCache._();
  static final ProfileDimsCache instance = ProfileDimsCache._();

  final Map<String, ProfileDims> _cache = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};

  /// `null` tant que le manifeste n'a pas été lu, sinon l'ensemble des
  /// refs (sans préfixe `assets/profiles/` ni suffixe `.json`) réellement
  /// présentes dans `assets/profiles/`. Calculé une seule fois.
  Set<String>? _coveredRefs;
  Future<Set<String>>? _manifestLoading;

  /// Dimensions déjà chargées pour [ref], ou `null` si pas encore
  /// disponibles (chargement en cours, pas démarré, ref non couverte, ou
  /// échec).
  ProfileDims? getIfLoaded(String ref) => _cache[ref];

  bool hasFailed(String ref) => _failed.contains(ref);

  @visibleForTesting
  bool isLoadingForTesting(String ref) => _loading.contains(ref);

  /// Liste des refs couvertes par `assets/profiles/`, une fois le
  /// manifeste résolu (`null` avant résolution) — utile pour un futur
  /// indicateur "non calibré" côté UI catalogue.
  @visibleForTesting
  Set<String>? get coveredRefsForTesting => _coveredRefs;

  /// Réinitialise tout l'état interne. Réservé aux tests : le singleton
  /// est partagé entre tous les tests du process, et une ref déjà en
  /// cache/failed par un test précédent prendrait le retour anticipé de
  /// [ensureLoading] dans les tests suivants sans notifier.
  @visibleForTesting
  void resetForTesting() {
    _cache.clear();
    _loading.clear();
    _failed.clear();
    _coveredRefs = null;
    _manifestLoading = null;
  }

  /// Démarre le chargement des dimensions de [ref] si elles ne sont ni
  /// en cache, ni en cours, ni déjà en échec. Sans effet si déjà traité —
  /// sûr à appeler à CHAQUE frame, pour chaque produit affiché.
  void ensureLoading(String ref) {
    if (_cache.containsKey(ref) || _loading.contains(ref) || _failed.contains(ref)) {
      return;
    }
    // Marquage SYNCHRONE avant la microtâche — copié de
    // ProductTextureCache (97879ac) : sans ce marquage synchrone, deux
    // appels à ensureLoading(ref) dans la même frame (paint() itère sur
    // plusieurs produits) planifieraient deux microtâches de chargement
    // pour le même ref.
    _loading.add(ref);
    // Invariant STRUCTUREL, pas correctif ponctuel (voir 97879ac pour le
    // raisonnement complet) : tout le travail réel — y compris la
    // consultation du manifeste — est différé à une microtâche, jamais
    // exécuté directement dans la pile d'appel de ensureLoading. Ceci
    // garantit qu'aucune notifyListeners() ne peut jamais partir de
    // façon synchrone, quoi que contienne le corps de _resolve, y
    // compris du code qui n'existe pas encore.
    Future.microtask(() => _resolve(ref));
  }

  Future<void> _resolve(String ref) async {
    try {
      final covered = await _ensureCoveredRefsLoaded();
      if (!covered.contains(ref)) {
        _loading.remove(ref);
        _failed.add(ref);
        notifyListeners();
        return;
      }
    } catch (e) {
      // Défense en profondeur : le manifeste n'a pas pu être lu (aucun
      // cas observé, voir docstring de fichier). On dégrade vers une
      // tentative directe de loadProfileDims — plus coûteux si beaucoup
      // de refs sont absentes, mais correct.
      if (kDebugMode) {
        debugPrint(
          'ProfileDimsCache: AssetManifest indisponible, repli sur '
          'loadProfileDims direct pour $ref — $e',
        );
      }
    }

    try {
      final dims = await loadProfileDims(ref);
      if (dims == null) {
        _loading.remove(ref);
        _failed.add(ref);
        notifyListeners();
        return;
      }
      _cache[ref] = dims;
      _loading.remove(ref);
      notifyListeners();
    } catch (e) {
      // loadProfileDims ne lève déjà jamais (voir profile_dims.dart) —
      // ce catch ne protège que contre une évolution future de ce
      // contrat, pas un cas observé aujourd'hui.
      if (kDebugMode) {
        debugPrint('ProfileDimsCache: échec chargement $ref — $e');
      }
      _loading.remove(ref);
      _failed.add(ref);
      notifyListeners();
    }
  }

  /// Lit `AssetManifest.json` une seule fois (mémoïsé par [_manifestLoading])
  /// et renvoie l'ensemble des refs couvertes par `assets/profiles/`.
  Future<Set<String>> _ensureCoveredRefsLoaded() {
    final cached = _coveredRefs;
    if (cached != null) return Future.value(cached);

    return _manifestLoading ??= () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final refs = <String>{};
      for (final asset in manifest.listAssets()) {
        const prefix = 'assets/profiles/';
        const suffix = '.json';
        if (asset.startsWith(prefix) && asset.endsWith(suffix)) {
          refs.add(asset.substring(prefix.length, asset.length - suffix.length));
        }
      }
      _coveredRefs = refs;
      return refs;
    }();
  }
}
