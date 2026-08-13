/// Cache global des textures produit — VRAIES photos staffdecor.fr des
/// profils (feuillage, perles, oves, gorges...), pour remplacer le rendu
/// 100% procédural (dégradé synthétique) de [drawProfileFace] par un
/// texture-mapping réel.
///
/// ⚠️ CORRECTION Bug #2/motifs (retour utilisateur : "pas d'apprentissage
/// des motifs ni perspectives") — jusqu'ici, `drawProfileFace` ne
/// chargeait AUCUNE image produit : il dessinait une silhouette procédurale
/// (nombre de bandes dérivé du ratio w/h) IDENTIQUE en texture pour tous
/// les produits, sans jamais représenter le vrai relief sculpté (visible
/// sur les photos catalogue `Produit.img`, hébergées sur staffdecor.fr
/// avec CORS ouvert `access-control-allow-origin: *`, vérifié directement).
///
/// Ce cache charge une fois chaque photo produit (par `ref`) via
/// `ui.instantiateImageCodec`, la garde en mémoire, et notifie les
/// widgets abonnés ([ChangeNotifier]) une fois disponible pour déclencher
/// un repaint — le rendu procédural reste utilisé comme fallback pendant
/// le chargement réseau ou en cas d'échec (offline).
library;

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ProductTextureCache extends ChangeNotifier {
  ProductTextureCache._();
  static final ProductTextureCache instance = ProductTextureCache._();

  final Map<String, ui.Image> _cache = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};

  /// Texture déjà chargée pour [ref], ou `null` si pas encore disponible
  /// (chargement en cours, pas démarré, ou échec réseau).
  ui.Image? getIfLoaded(String ref) => _cache[ref];

  bool hasFailed(String ref) => _failed.contains(ref);

  /// Démarre le chargement de la photo produit [url] pour [ref] si elle
  /// n'est ni en cache, ni en cours, ni déjà en échec. Sans effet si déjà
  /// traité — sûr à appeler à CHAQUE frame depuis [RoomPainter.paint].
  void ensureLoading(String ref, String url) {
    if (_cache.containsKey(ref) || _loading.contains(ref) || _failed.contains(ref)) {
      return;
    }
    if (url.isEmpty) {
      _failed.add(ref);
      return;
    }
    _loading.add(ref);
    // ⚠️ INVARIANT STRUCTUREL, pas correctif ponctuel : _load est appelée
    // via Future.microtask, jamais directement. Ceci garantit qu'AUCUNE
    // notifyListeners() ne peut jamais partir de façon synchrone dans la
    // pile d'appel de ensureLoading — même si une instruction future,
    // ajoutée un jour dans le préfixe pré-await de _load, lève une
    // exception avant sa première suspension (ex. actuel :
    // `Uri.parse(url)` dans `http.get(Uri.parse(url))`, qui lève une
    // FormatException synchrone sur une URL non vide mais malformée,
    // attrapée par le catch qui notifie).
    //
    // Ça compte parce que ensureLoading est appelé depuis
    // RoomPainter.paint() (voir room_painter.dart) — un notifyListeners()
    // synchrone y déclencherait, via le repaint: câblé sur ce singleton,
    // un markNeedsPaint() PENDANT la phase de peinture, ce que
    // RenderObject.markNeedsPaint interdit (assert(!debugDoingPaint) en
    // debug ; comportement non caractérisé en release, pas testé ici).
    // Les microtâches ne se vident qu'au retour de l'exécution synchrone
    // courante (donc après la fin de handleDrawFrame), jamais pendant.
    Future.microtask(() => _load(ref, url));
  }

  Future<void> _load(String ref, String url) async {
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode} pour $url');
      }
      final codec = await ui.instantiateImageCodec(resp.bodyBytes);
      final frame = await codec.getNextFrame();
      _cache[ref] = frame.image;
      _loading.remove(ref);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ProductTextureCache: échec chargement $ref ($url) — $e');
      }
      _loading.remove(ref);
      _failed.add(ref);
      notifyListeners();
    }
  }
}
