/// Cache global des dimensions métriques réelles ([ProfileDims]) — calqué
/// structurellement sur [ProductTextureCache] (voir ce fichier et son
/// historique de commits `4e0041b`/`97879ac` pour le raisonnement complet
/// sur le mécanisme de repaint et l'invariant de notification asynchrone).
///
/// ⚠️ Ce fichier EST branché à [RoomPainter] depuis le câblage du
/// 13-17 août 2026 (`Listenable.merge` dans son `repaint:`, cas
/// `'Corniches'` de `room_painter.dart`) — voir `docs/ETAT_MOTEUR_RENDU
/// .md` section 6. Cette docstring affirmait autrefois le contraire,
/// corrigé ici après relecture directe de `room_painter.dart` (le
/// câblage existait déjà, seule sa couverture — 8 refs, jamais étendue
/// depuis — restait à mettre à jour).
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
/// tentatives `rootBundle.loadString` (déjà gérées sans throw par
/// [loadProfileDims] lui-même, mais le coût réel).
///
/// ## Couverture : `assets/profiles/index.json`, PAS `AssetManifest.json`
///
/// ⚠️ CORRECTION (brief de câblage, étape 0) : ce cache dérivait
/// initialement sa couverture d'`AssetManifest.json`, qui liste les 56
/// fichiers `statut: "OK"` produits par le pipeline d'extraction — SANS
/// filtrer par le gate de sanité (`tools/dxf_pipeline/gate_sanite.py`).
/// Sur les 56, seuls 31 passent `statut_gate == "OK"` ; les 25 autres
/// sont géométriquement invalides pour au moins un des deux critères
/// bloquants du gate (contrat loader ou débord de plan de pose). Un
/// cache filtrant par `AssetManifest.json` aurait tenté de charger ces
/// 25 profils — 16 d'entre eux faisaient lever un `assert()` réel dans
/// l'ancienne version de [loadProfileDims] (crash reproduit
/// expérimentalement sur `D614` avant ce commit), les 9 autres
/// n'avaient aucune garantie de validité géométrique.
///
/// Ce cache lit désormais `assets/profiles/index.json` — généré par
/// `tools/dxf_pipeline/build_profiles_index.py` depuis
/// `gate_sanite_rapport.csv`, liste exacte des 31 SKU gate-OK — UNE
/// FOIS, mémoïsé, et ne tente [loadProfileDims] QUE pour les refs qui y
/// figurent. **Fail-closed, imposé** : si `index.json` est absent,
/// illisible, malformé, ou que son tableau `refs` est vide, la
/// couverture résolue est l'ensemble VIDE — aucune ref n'est jamais
/// chargée dans ce cas, et le rendu retombe entièrement sur
/// `StripThickness.corniceDefault(pH)` côté appelant (voir `corniceFor`,
/// `cornice_plinth_painter.dart`). **Ce cache ne retombe JAMAIS sur
/// `AssetManifest.json` en cas d'échec de lecture de `index.json`** —
/// un tel repli ressusciterait exactement le bug que cette réécriture
/// corrige (chargement des 25 profils hors gate). Un rendu ratio pixels
/// honnête (silencieux, connu) est préférable à un rendu métrique sur
/// des données non garanties par le gate.
///
/// En prime, la liste des refs couvertes (`coveredRefsForTesting` /
/// usage futur : indicateur UI "non calibré") est calculée une fois,
/// réutilisable sans nouvelle lecture disque.
///
/// ## Repli TEMPORAIRE pendant le bootstrap de l'index — PAS un repli
/// permanent
///
/// Le chargement de `index.json` est lui-même asynchrone
/// (`rootBundle.loadString`), mémoïsé dans [_indexLoading]. [_resolve]
/// `await`e sa résolution AVANT de décider si une ref est couverte — la
/// décision n'est donc jamais prise prématurément : tant que l'index
/// n'est pas prêt, la ref reste marquée `_loading` (PAS `_failed`),
/// [_resolve] est simplement suspendu sur ce `await`, et aucune
/// notification n'est envoyée.
///
/// Concrètement, la toute première frame après démarrage affichera en
/// repli (`StripThickness.corniceDefault`, côté appelant, via
/// `getIfLoaded` qui renvoie `null` tant que rien n'est en cache) MÊME
/// pour une ref couverte par `index.json` — c'est un choix délibéré,
/// MAIS c'est une fenêtre de latence, pas un classement en échec : une
/// fois l'index résolu, la vraie décision est prise et notifiée
/// normalement, y compris pour une ref qui aurait été demandée pendant
/// la fenêtre de bootstrap. Le `repaint:` de [RoomPainter]
/// (`Listenable.merge`) rattrape l'affichage dès que l'index est prêt,
/// exactement comme il rattrape déjà le chargement des textures produit.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'profile_dims.dart';

class ProfileDimsCache extends ChangeNotifier {
  ProfileDimsCache._();
  static final ProfileDimsCache instance = ProfileDimsCache._();

  final Map<String, ProfileDims> _cache = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};

  /// `null` tant que `index.json` n'a pas été lu, sinon l'ensemble des
  /// refs gate-OK (31 SKU, `statut_gate == "OK"` dans
  /// `gate_sanite_rapport.csv`) listées par
  /// `assets/profiles/index.json`. Calculé une seule fois. Reste un
  /// ensemble VIDE si `index.json` est absent/illisible/vide — jamais
  /// un repli sur `AssetManifest.json` (voir docstring de fichier).
  Set<String>? _coveredRefs;
  Future<Set<String>>? _indexLoading;

  /// Dimensions déjà chargées pour [ref], ou `null` si pas encore
  /// disponibles (chargement en cours, pas démarré, ref non couverte, ou
  /// échec).
  ProfileDims? getIfLoaded(String ref) => _cache[ref];

  bool hasFailed(String ref) => _failed.contains(ref);

  @visibleForTesting
  bool isLoadingForTesting(String ref) => _loading.contains(ref);

  /// Liste des refs gate-OK couvertes par `assets/profiles/index.json`,
  /// une fois l'index résolu (`null` avant résolution) — utile pour un
  /// futur indicateur "non calibré" côté UI catalogue.
  @visibleForTesting
  Set<String>? get coveredRefsForTesting => _coveredRefs;

  /// Nombre de refs actuellement en cache (dimensions chargées avec
  /// succès). Lecture seule, aucun effet sur le repaint — déliverable
  /// "log hit/miss" du brief de câblage : à consulter à la demande
  /// (ex. bouton debug, log manuel), jamais un second canal de
  /// notification (voir garde-fou "pas de compteur de génération
  /// séparé" du brief : `Listenable.merge` suffit pour le repaint).
  int get loadedCountForLogging => _cache.length;

  /// Nombre de refs ayant échoué (non couvertes par index.json, ou
  /// rejetées par [loadProfileDims] — asset absent, statut non-OK,
  /// contrat géométrique violé). Lecture seule.
  int get failedCountForLogging => _failed.length;

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
    _indexLoading = null;
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
    // Garde défensive calquée sur ProductTextureCache (97879ac) : tout le
    // travail réel — y compris la consultation du manifeste — est différé
    // à une microtâche plutôt qu'exécuté directement dans la pile d'appel
    // de ensureLoading. Objectif : qu'aucun futur préfixe synchrone
    // susceptible de lever, ajouté en tête de _resolve, ne puisse faire
    // partir notifyListeners() de façon synchrone.
    //
    // Portée réelle, vérifiée par mutation testing (flutter test
    // test/core/perspective/ avec ce microtask retiré → 35/35 tests
    // passent toujours, y compris le test dédié à cet invariant dans
    // profile_dims_cache_test.dart) : garantie par construction, NON
    // couverte par un test aujourd'hui, par absence de chemin
    // déclencheur. _resolve commence par `await
    // _ensureCoveredRefsLoaded()` — aucun code synchrone susceptible de
    // lever ne précède la première suspension, donc rien n'exerce
    // actuellement la différence entre appel direct et microtâche. Ce
    // n'est pas le cas de ProductTextureCache._load, dont le Uri.parse
    // pré-await était le vrai défaut corrigé par 97879ac — d'où un test
    // qui, lui, verrouille réellement l'invariant côté texture.
    Future.microtask(() => _resolve(ref));
  }

  Future<void> _resolve(String ref) async {
    // Fail-closed STRICT : contrairement à l'ancienne version (repli sur
    // une tentative directe de loadProfileDims si AssetManifest.json
    // était indisponible), aucun try/catch de contournement ici. Si
    // _ensureCoveredRefsLoaded() échoue, l'ensemble résolu est VIDE
    // (voir son implémentation) — ref non couverte, jamais de repli sur
    // AssetManifest.json qui ressusciterait le chargement des 25 refs
    // hors gate.
    final covered = await _ensureCoveredRefsLoaded();
    if (!covered.contains(ref)) {
      _loading.remove(ref);
      _failed.add(ref);
      notifyListeners();
      return;
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

  /// Lit `assets/profiles/index.json` une seule fois (mémoïsé par
  /// [_indexLoading]) et renvoie l'ensemble des refs gate-OK qu'il liste.
  ///
  /// ⚠️ FAIL-CLOSED, imposé : toute anomalie (asset absent, JSON
  /// malformé, champ `refs` absent/non-liste) renvoie un ensemble VIDE
  /// — jamais une exception propagée à l'appelant, jamais un repli sur
  /// `AssetManifest.json`. Un ensemble vide fait échouer TOUTES les
  /// refs (`_failed`), donc TOUT le rendu retombe sur
  /// `StripThickness.corniceDefault(pH)` — le seul cas où l'ancien
  /// chemin en dur est préférable à un rendu métrique reposant sur des
  /// données non garanties par le gate.
  Future<Set<String>> _ensureCoveredRefsLoaded() {
    final cached = _coveredRefs;
    if (cached != null) return Future.value(cached);

    return _indexLoading ??= () async {
      final refs = <String>{};
      try {
        final raw = await rootBundle.loadString('assets/profiles/index.json');
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final list = decoded['refs'];
          if (list is List) {
            for (final r in list) {
              if (r is String) refs.add(r);
            }
          }
        }
      } catch (e) {
        // Fail-closed : index.json absent/illisible/malformé -> refs
        // reste l'ensemble vide construit ci-dessus, PAS un repli sur
        // AssetManifest.json. Journalisé pour diagnostic uniquement.
        if (kDebugMode) {
          debugPrint(
            'ProfileDimsCache: assets/profiles/index.json indisponible '
            'ou invalide ($e) — couverture vide, repli intégral sur '
            'StripThickness.corniceDefault pour toutes les refs.',
          );
        }
      }
      _coveredRefs = refs;
      return refs;
    }();
  }
}
