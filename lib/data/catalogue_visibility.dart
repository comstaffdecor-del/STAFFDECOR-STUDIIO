/// Filtre de visibilité du catalogue en mode présentation — P15-PRES,
/// Volets 2+3 ("Option A stricte").
///
/// `presentationVisible(sku)` = appartenance de `sku` à
/// `assets/profiles/index.json` (`refs`), c'est-à-dire l'ensemble exact
/// des 43 SKU qui satisfont le **critère double** : statut JSON
/// `statut == "OK"` (fiabilité de l'extraction géométrique,
/// `assets/profiles/<ref>.json`) ET statut du gate géométrique
/// `statut_gate == "OK"` (cohérence bbox/profil,
/// `tools/dxf_pipeline/gate_sanite.py`, voir aussi
/// `tools/dxf_pipeline/build_profiles_index.py` qui génère index.json à
/// partir de `gate_sanite_rapport.csv`).
///
/// C'est la MÊME source que [ProfileDimsCache] utilise déjà pour décider
/// quels SKU bénéficient du rendu métrique (voir
/// `lib/core/perspective/profile_dims_cache.dart`) — réutilisée ici pour
/// un besoin différent (visibilité catalogue) **en LECTURE UNIQUEMENT**.
///
/// ⚠️ POINT DE VIGILANCE EXPLICITE : ce fichier ne DOIT JAMAIS écrire
/// dans `assets/profiles/index.json`, dans un quelconque
/// `assets/profiles/<ref>.json`, ni dans `catalogue_data.dart`. Élargir
/// la liste visible en modifiant `index.json` casserait le fail-closed
/// de [ProfileDimsCache] (qui lit le même fichier pour décider quels SKU
/// bénéficient d'un rendu métrique géométriquement vérifié) — un SKU
/// ajouté ici sans être passé par le gate recevrait un rendu métrique
/// non garanti. Aucun champ `render_status`/`renderable` n'est ajouté
/// nulle part : la présence/absence dans `index.json` (déjà existant,
/// déjà utilisé ailleurs) est la seule source de vérité, jamais dupliquée.
///
/// **Jointure SKU insensible à la casse et aux espaces** : les refs
/// GED (`catalogue_data.dart`) et les SKU JSON (`assets/profiles/*.json`)
/// peuvent différer par la casse (ex. `1145C` vs `1145c`) — la
/// comparaison normalise donc casse + espaces avant de matcher.
///
/// **Réversibilité — POINT UNIQUE** : [kPresentationFilter]. Le remettre
/// à `false` désactive intégralement le filtre (retour au catalogue
/// complet, comportement antérieur) sans toucher à aucune autre ligne de
/// ce fichier ni d'aucun autre.
///
/// **Fail-open, pas fail-closed** : si `index.json` est absent, illisible
/// ou malformé, l'ensemble résolu reste vide et [applyPresentationVisibility]
/// renvoie alors la liste INCHANGÉE (aucun masquage) — un incident de
/// lecture d'asset ne doit jamais vider silencieusement le catalogue
/// présenté à un visiteur. C'est l'inverse du choix de [ProfileDimsCache]
/// (fail-closed, car là un rendu métrique faux serait pire qu'un rendu en
/// repli) — les deux usages ont des enjeux différents, d'où deux
/// stratégies différentes sur la même source de données, lue mais jamais
/// écrite par ce fichier.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// POINT UNIQUE DE RÉVERSIBILITÉ du filtre de visibilité présentation.
/// `false` => catalogue complet, comme avant ce commit. Défaut : actif.
const bool kPresentationFilter = true;

/// Normalise un SKU/ref pour une comparaison insensible à la casse et
/// aux espaces (ex. `'1145c'` et `'1145 C'` -> `'1145C'`).
String normalizeSkuForJoin(String s) => s.replaceAll(RegExp(r'\s+'), '').toUpperCase();

/// Charge une seule fois `assets/profiles/index.json` (LECTURE SEULE —
/// voir avertissement en tête de fichier) et expose l'ensemble normalisé
/// des refs SKU satisfaisant le critère double (JSON=OK ET gate=OK).
class CatalogueVisibilityGate {
  CatalogueVisibilityGate._();
  static final CatalogueVisibilityGate instance = CatalogueVisibilityGate._();

  /// Clé = SKU normalisé ([normalizeSkuForJoin]), valeur = SKU original
  /// tel que présent dans index.json (utile pour diagnostic/rapport).
  Map<String, String>? _visibleRefsNormalized;
  Future<Map<String, String>>? _loading;

  /// `null` tant que le chargement n'est pas terminé (succès ou échec
  /// fail-open), sinon la table normalisée des refs visibles.
  Map<String, String>? get visibleRefsIfLoaded => _visibleRefsNormalized;

  /// Nombre de refs visibles une fois chargées, sinon `null`.
  int? get visibleCountIfLoaded => _visibleRefsNormalized?.length;

  @visibleForTesting
  void resetForTesting() {
    _visibleRefsNormalized = null;
    _loading = null;
  }

  /// Démarre (ou renvoie) le chargement mémoïsé de l'index. Sûr à appeler
  /// plusieurs fois (ex. à chaque `initState` d'écran présentation).
  /// N'ÉCRIT JAMAIS `assets/profiles/index.json` — lecture seule via
  /// `rootBundle.loadString`.
  Future<Map<String, String>> ensureLoaded() {
    final cached = _visibleRefsNormalized;
    if (cached != null) return Future.value(cached);

    return _loading ??= () async {
      final refs = <String, String>{};
      try {
        final raw = await rootBundle.loadString('assets/profiles/index.json');
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final list = decoded['refs'];
          if (list is List) {
            for (final r in list) {
              if (r is String) refs[normalizeSkuForJoin(r)] = r;
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            'CatalogueVisibilityGate: assets/profiles/index.json '
            'indisponible ou invalide ($e) — filtre présentation '
            'désactivé pour cette session (fail-open, catalogue complet).',
          );
        }
      }
      _visibleRefsNormalized = refs;
      return refs;
    }();
  }

  /// `true` si [sku] (normalisé casse/espaces) figure dans index.json.
  /// `null` tant que l'index n'est pas chargé (ni oui ni non tranché).
  bool? presentationVisible(String sku) {
    final table = _visibleRefsNormalized;
    if (table == null) return null;
    return table.containsKey(normalizeSkuForJoin(sku));
  }
}

/// Filtre [items] pour le mode présentation via [refOf] (extracteur de
/// référence SKU). Ne fait rien (liste inchangée) si :
///  - le filtre est désactivé ([kPresentationFilter]==false), ou
///  - l'index n'est pas encore chargé, ou
///  - l'index a échoué à charger (table vide résultante, fail-open).
List<T> applyPresentationVisibility<T>(
  List<T> items,
  String Function(T item) refOf,
) {
  if (!kPresentationFilter) return items;
  final visible = CatalogueVisibilityGate.instance.visibleRefsIfLoaded;
  if (visible == null || visible.isEmpty) return items;
  return items
      .where((item) => visible.containsKey(normalizeSkuForJoin(refOf(item))))
      .toList();
}
