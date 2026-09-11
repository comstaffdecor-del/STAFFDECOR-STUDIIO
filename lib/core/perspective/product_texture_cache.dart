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
///
/// ⚠️ AJOUT (brief "voie légère" — suppression du bandeau plafond blanc
/// artificiel, SANS toucher à la géométrie/au texture-mapping) : ce cache
/// calcule aussi, une fois par [ref] et en même temps que le chargement de
/// la texture, sa **couleur moyenne** ([getAverageColorIfLoaded]) — un
/// simple échantillonnage pixel, PAS un nouveau texture-mapping. Objectif
/// unique : remplacer les 4 couleurs `Color(0x...)` codées en dur du
/// gradient de la face plafond (`cornice_plinth_painter.dart::
/// _drawCorniceStrip`) par une teinte dérivée du VRAI plâtre du produit,
/// tout en gardant exactement le même `Gradient.linear` (même géométrie,
/// aucun `drawVertices`, aucun nouvel UV). Le calcul se fait sur une
/// version RÉDUITE de l'image (24×24, redessinée dans un petit canvas
/// hors-écran puis lue via `Image.toByteData`) pour rester bon marché —
/// une seule fois par ref, mémoïsé comme la texture elle-même. Les pixels quasi-blancs/quasi-transparents (fond de studio photo
/// staffdecor.fr, PAS le plâtre du profil) sont exclus de la moyenne —
/// voir [_computeAverageColor].
library;

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ProductTextureCache extends ChangeNotifier {
  ProductTextureCache._();
  static final ProductTextureCache instance = ProductTextureCache._();

  final Map<String, ui.Image> _cache = {};
  final Map<String, ui.Color> _avgColorCache = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};

  /// Texture déjà chargée pour [ref], ou `null` si pas encore disponible
  /// (chargement en cours, pas démarré, ou échec réseau).
  ui.Image? getIfLoaded(String ref) => _cache[ref];

  /// Couleur moyenne (plâtre réel du produit, fond photo exclu) de la
  /// texture [ref], ou `null` si la texture n'est pas encore chargée /
  /// que le calcul n'a pas encore abouti. Voir docstring de fichier.
  ui.Color? getAverageColorIfLoaded(String ref) => _avgColorCache[ref];

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
      // Couleur moyenne calculée APRÈS la mise en cache de la texture et
      // AVANT le premier notifyListeners() : un seul repaint suffit côté
      // RoomPainter pour bénéficier à la fois de la texture (face mur) et
      // de la teinte plafond dérivée (voir docstring de fichier). Un échec
      // de ce calcul (image dégénérée, décodage impossible) ne doit
      // jamais faire échouer le chargement de la texture elle-même — la
      // face plafond retombe alors sur son propre défaut, géré au site
      // d'appel (cornice_plinth_painter.dart), pas ici.
      try {
        final avg = await _computeAverageColor(frame.image);
        if (avg != null) _avgColorCache[ref] = avg;
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            'ProductTextureCache: échec calcul couleur moyenne $ref — $e '
            '(sans impact sur la texture déjà mise en cache)',
          );
        }
      }
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

  /// Échantillonne [image] à basse résolution et renvoie la couleur
  /// moyenne des pixels **opaques et non quasi-blancs** — le fond de
  /// studio photo staffdecor.fr (blanc/quasi-blanc, souvent semi-
  /// transparent en PNG) domine sinon complètement la moyenne (mesuré :
  /// D609 sans filtre ≈ RGB(221,221,220), un blanc cassé quasi identique
  /// à l'ancien gradient codé en dur — le filtre est donc essentiel, pas
  /// une simple précaution). Renvoie `null` si aucun pixel ne passe le
  /// filtre (image entièrement blanche/transparente — cas dégénéré non
  /// rencontré sur le catalogue actuel, géré par prudence).
  static Future<ui.Color?> _computeAverageColor(ui.Image image) async {
    // Downscale explicite à une taille fixe modeste : le coût de decode
    // dépend de la taille de l'image SOURCE, pas de la taille de sortie
    // demandée à `toByteData` — on redessine donc l'image dans un petit
    // canvas hors-écran avant d'en lire les pixels, plutôt que de lire
    // les pixels de l'image pleine résolution (jusqu'à plusieurs Mpx pour
    // les photos catalogue) à chaque calcul.
    const sampleSize = 24;
    const sampleSizeD = 24.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      const ui.Rect.fromLTWH(0, 0, sampleSizeD, sampleSizeD),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
    final picture = recorder.endRecording();
    final small = await picture.toImage(sampleSize, sampleSize);
    final byteData = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    small.dispose();
    if (byteData == null) return null;

    final bytes = byteData.buffer.asUint8List();
    int rSum = 0, gSum = 0, bSum = 0, count = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      final r = bytes[i];
      final g = bytes[i + 1];
      final b = bytes[i + 2];
      final a = bytes[i + 3];
      // Exclut : quasi-transparent (fond détouré) ET quasi-blanc opaque
      // (fond de studio photo) — seul le plâtre réel du profil doit
      // contribuer à la moyenne.
      if (a < 200) continue;
      if (r > 235 && g > 235 && b > 235) continue;
      rSum += r;
      gSum += g;
      bSum += b;
      count++;
    }
    if (count == 0) return null;
    return ui.Color.fromARGB(255, rSum ~/ count, gSum ~/ count, bSum ~/ count);
  }
}
