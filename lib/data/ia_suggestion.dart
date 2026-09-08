/// Volet B — "Suggestion automatique (démo)", P15-IA-DEMO.
///
/// Piste retenue : **Piste 1 — similarité image**, sur les vignettes
/// techniques `assets/profiles/control/<ref>.png` (schémas de coupe
/// matplotlib, PAS des photos produit). Aucune Piste 2 (scoring
/// dimensionnel) n'est utilisée : `famille` est `null` dans 43/43 des
/// JSON profils, ce qui casse un des 4 critères nommés par le brief ;
/// Piste 1 a été validée à 100% (voir round-trip ci-dessous) et est donc
/// la méthode "prête" au sens du brief ("Choisis celle qui est prête").
///
/// ⚠️ PÉRIMÈTRE STRICT (règle absolue du brief) :
///  - la base de comparaison n'est construite QUE depuis les refs
///    présentes dans [CatalogueVisibilityGate] (= les 43 de
///    `assets/profiles/index.json`, même gate, même jointure
///    [normalizeSkuForJoin], LECTURE SEULE) ;
///  - parmi ces 43, seules celles qui possèdent une vignette locale dans
///    `assets/profiles/control/*.png` peuvent être notées par similarité
///    image — 31/43 en ont une (12 n'ont qu'une URL distante dans
///    `catalogue_data.dart`, inutilisable : aucun appel réseau autorisé
///    ici). Ce module ne suggère donc jamais un SKU absent de ces 31,
///    mais les 43 restent TOUJOURS accessibles via le catalogue manuel
///    (bouton "Voir les 43 modèles validés", jamais restreint par ce
///    fichier) ;
///  - AUCUNE écriture dans `index.json`, un `<ref>.json`, ou
///    `catalogue_data.dart` ;
///  - AUCUN appel réseau, AUCUN modèle téléchargé : tout le calcul est un
///    descripteur déterministe pur-Dart (histogramme de forme + traits
///    géométriques), comparé par similarité cosinus ;
///  - ce module ne valide NI la géométrie, NI le STEP/STL, NI la
///    "renderability" d'un produit — [CatalogueVisibilityGate] a déjà
///    tranché cela, ce module ne fait QUE proposer un ordre de
///    pertinence visuelle parmi les refs déjà validées.
///
/// Le score affiché à l'utilisateur DOIT être libellé "correspondance
/// X %" (une similarité réellement calculée), jamais "confiance IA X %"
/// (aucune certitude/confiance de ce type n'est mesurée ici).
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'catalogue_visibility.dart';

/// POINT UNIQUE DE RÉVERSIBILITÉ du module de suggestion automatique.
///
/// `true` UNIQUEMENT si le test aller-retour Dart (voir
/// `test/data/ia_suggestion_test.dart`) est passé à 100% sur la base
/// réelle des vignettes bundlées, AVEC les seuils [kMinIaScore]/
/// [kMinIaGap] ci-dessous — voir `/tmp/presentation_ai_demo.txt` pour le
/// taux exact obtenu (n/31, les 31 refs qui possèdent une vignette parmi
/// les 43 de présentation) au moment du dernier calibrage.
///
/// Si un seul cas d'aller-retour échouait, cette constante DOIT repasser
/// à `false` (message d'incertitude permanent dans l'UI) — jamais
/// compensé par un résultat simulé/mock.
const bool kIaSuggestionEnabled = true;

/// Score minimal (similarité cosinus, 0..1) du meilleur candidat pour
/// qu'un résultat soit considéré "exploitable". Calibré empiriquement en
/// Dart (voir `ia_suggestion_test.dart`, sonde + gate) sur les 31
/// vignettes réellement bundlées.
const double kMinIaScore = 0.5;

/// Écart minimal entre le score du 1er et du 2e candidat pour que le
/// résultat soit jugé discriminant (évite un "faux top-1" parmi des
/// candidats quasi ex æquo). Même calibrage que [kMinIaScore].
const double kMinIaGap = 0.008;

/// Taille de la grille de pooling (12x12 = 144 valeurs de forme).
const int _kGridSize = 12;

/// Résolution de travail (image redimensionnée en carré avant analyse).
const int _kWorkSize = 128;

/// Seuil de binarisation "encre" (luminance normalisée 0..1, encre = trait
/// sombre du schéma technique) — même valeur que le prototype Python
/// validé (`gray < 0.6`).
const double _kInkThreshold = 0.6;

/// Un candidat de suggestion : référence produit + score de similarité
/// réellement calculé (0..1).
class IaSuggestionMatch {
  final String ref;
  final double score;
  const IaSuggestionMatch(this.ref, this.score);

  /// Score formaté pour affichage UI, EXPLICITEMENT libellé
  /// "correspondance" et jamais "confiance IA" (voir doc de fichier).
  String get scorePercentLabel => 'correspondance ${(score * 100).round()}%';
}

/// Résultat complet d'une tentative de suggestion.
class IaSuggestionRankResult {
  /// `true` si au moins [kMinIaScore]/[kMinIaGap] sont satisfaits par le
  /// meilleur candidat — dans ce cas [matches] contient jusqu'à 3
  /// candidats triés par score décroissant.
  final bool exploitable;

  /// Jusqu'à 3 candidats (peut être vide si [exploitable]==false ou si
  /// la base de référence est vide/non chargée).
  final List<IaSuggestionMatch> matches;

  /// Motif lisible (diagnostic/log), jamais affiché tel quel à
  /// l'utilisateur final (l'UI affiche le message d'incertitude fixe du
  /// brief) — utile pour le rapport et le débogage.
  final String reason;

  const IaSuggestionRankResult({
    required this.exploitable,
    required this.matches,
    required this.reason,
  });

  factory IaSuggestionRankResult.nonExploitable(String reason) =>
      IaSuggestionRankResult(exploitable: false, matches: const [], reason: reason);
}

/// Extrait le vecteur de traits (148 valeurs : 144 grille + 4 traits de
/// forme) d'une image quelconque (bytes bruts PNG/JPEG/etc.), ou `null`
/// si l'image est illisible/corrompue/format non supporté, ou si son
/// masque d'encre est dégénéré (image blanche/vide — non exploitable par
/// construction, jamais un crash).
///
/// Réplique fidèlement le prototype Python validé (v3) :
///  1. niveaux de gris, redimensionné en [_kWorkSize]x[_kWorkSize] ;
///  2. binarisation encre (`gray < _kInkThreshold`) ;
///  3. rejet si masque quasi vide (< 1 pixel d'encre) ;
///  4. recadrage sur la boîte englobante de l'encre ;
///  5. pooling par blocs (padding zéro) sur une grille [_kGridSize]² ;
///  6. centrage (grille - moyenne(grille)) ;
///  7. 4 traits supplémentaires : aspect (w/h), fill_ratio, centre de
///     masse relatif (cy, cx).
Future<List<double>?> extractIaFeatures(Uint8List imageBytes) async {
  ui.Image decoded;
  try {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    decoded = frame.image;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('extractIaFeatures: décodage image échoué ($e) — non exploitable.');
    }
    return null;
  }

  try {
    // Redimensionne en _kWorkSize x _kWorkSize via un canvas (letterbox
    // "stretch", cohérent avec le prototype Python `Image.resize`).
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      decoded,
      ui.Rect.fromLTWH(0, 0, decoded.width.toDouble(), decoded.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, _kWorkSize.toDouble(), _kWorkSize.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final resized = await picture.toImage(_kWorkSize, _kWorkSize);
    final byteData = await resized.toByteData(format: ui.ImageByteFormat.rawRgba);
    resized.dispose();
    decoded.dispose();
    if (byteData == null) return null;

    final rgba = byteData.buffer.asUint8List();
    // Niveaux de gris (luma ITU-R 601, identique à PIL `.convert('L')`).
    final gray = List<double>.filled(_kWorkSize * _kWorkSize, 0);
    for (var i = 0; i < _kWorkSize * _kWorkSize; i++) {
      final r = rgba[i * 4];
      final g = rgba[i * 4 + 1];
      final b = rgba[i * 4 + 2];
      gray[i] = (r * 0.299 + g * 0.587 + b * 0.114) / 255.0;
    }

    // Masque d'encre binaire.
    final ink = List<bool>.filled(_kWorkSize * _kWorkSize, false);
    var totalInk = 0;
    for (var i = 0; i < gray.length; i++) {
      final isInk = gray[i] < _kInkThreshold;
      ink[i] = isInk;
      if (isInk) totalInk++;
    }
    if (totalInk < 1) {
      // Image blanche/vide/dégénérée — non exploitable par construction,
      // pas une erreur : on renvoie null pour que l'appelant affiche le
      // message d'incertitude standard.
      return null;
    }

    // Boîte englobante de l'encre.
    var y0 = _kWorkSize, y1 = -1, x0 = _kWorkSize, x1 = -1;
    for (var y = 0; y < _kWorkSize; y++) {
      for (var x = 0; x < _kWorkSize; x++) {
        if (ink[y * _kWorkSize + x]) {
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
        }
      }
    }
    final h = y1 - y0 + 1;
    final w = x1 - x0 + 1;

    // Padding au multiple de _kGridSize (zéro = "pas d'encre"), pooling
    // par blocs moyennés — réplique exacte de la logique numpy du
    // prototype (pad + reshape(GRID, bh, GRID, bw).mean(axis=(1,3))).
    final ph = (_kGridSize - h % _kGridSize) % _kGridSize;
    final pw = (_kGridSize - w % _kGridSize) % _kGridSize;
    final paddedH = h + ph;
    final paddedW = w + pw;
    final bh = paddedH ~/ _kGridSize;
    final bw = paddedW ~/ _kGridSize;

    final grid = List<double>.filled(_kGridSize * _kGridSize, 0);
    for (var gi = 0; gi < _kGridSize; gi++) {
      for (var gj = 0; gj < _kGridSize; gj++) {
        double sum = 0;
        for (var dy = 0; dy < bh; dy++) {
          final cropY = gi * bh + dy;
          if (cropY >= h) continue; // zone de padding = 0, ne contribue pas
          final srcY = y0 + cropY;
          for (var dx = 0; dx < bw; dx++) {
            final cropX = gj * bw + dx;
            if (cropX >= w) continue;
            final srcX = x0 + cropX;
            if (ink[srcY * _kWorkSize + srcX]) sum += 1.0;
          }
        }
        grid[gi * _kGridSize + gj] = sum / (bh * bw);
      }
    }

    // Centrage.
    final gridMean = grid.reduce((a, b) => a + b) / grid.length;
    final gridCentered = grid.map((v) => v - gridMean).toList();

    // Traits supplémentaires.
    final aspect = h > 0 ? w / h : 1.0;
    final fillRatio = totalInk / (_kWorkSize * _kWorkSize);
    double sumY = 0, sumX = 0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if (ink[y * _kWorkSize + x]) {
          sumY += y;
          sumX += x;
        }
      }
    }
    final cy = (sumY / totalInk - y0) / math.max(h, 1);
    final cx = (sumX / totalInk - x0) / math.max(w, 1);

    return [...gridCentered, aspect, fillRatio, cy, cx];
  } catch (e) {
    if (kDebugMode) {
      debugPrint('extractIaFeatures: extraction échouée ($e) — non exploitable.');
    }
    return null;
  }
}

/// Similarité cosinus entre deux vecteurs de même longueur. Renvoie 0.0
/// si l'un des deux est un vecteur nul (évite une division par zéro).
double cosineSimilarity(List<double> a, List<double> b) {
  assert(a.length == b.length);
  double dot = 0, na = 0, nb = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0.0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

/// Charge (une seule fois, mémoïsé) les vecteurs de traits des vignettes
/// `assets/profiles/control/<ref>.png` correspondant aux refs
/// présentation-visibles ([CatalogueVisibilityGate]) qui EN POSSÈDENT
/// une — jamais plus large que ces deux contraintes combinées. Réutilise
/// EXACTEMENT [CatalogueVisibilityGate.instance] (même gate, même
/// jointure [normalizeSkuForJoin]) plutôt que de relire `index.json`
/// séparément.
class IaSuggestionGate {
  IaSuggestionGate._();
  static final IaSuggestionGate instance = IaSuggestionGate._();

  Map<String, List<double>>? _refFeatures;
  Future<Map<String, List<double>>>? _loading;

  /// `null` tant que le chargement n'est pas terminé.
  Map<String, List<double>>? get refFeaturesIfLoaded => _refFeatures;

  @visibleForTesting
  void resetForTesting() {
    _refFeatures = null;
    _loading = null;
  }

  /// Charge la base de référence. Sûr à appeler plusieurs fois. Ne
  /// déclenche AUCUNE écriture, AUCUN appel réseau — uniquement
  /// `rootBundle.load` sur des PNG déjà bundlés dans l'app
  /// (`assets/profiles/control/`, déjà déclaré dans `pubspec.yaml` via
  /// `assets/profiles/`).
  Future<Map<String, List<double>>> ensureLoaded() {
    final cached = _refFeatures;
    if (cached != null) return Future.value(cached);

    return _loading ??= () async {
      final result = <String, List<double>>{};
      // Même gate que le filtre présentation — jamais de relecture
      // indépendante de index.json.
      final visible = await CatalogueVisibilityGate.instance.ensureLoaded();
      for (final ref in visible.values) {
        try {
          final data = await rootBundle.load('assets/profiles/control/$ref.png');
          final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          final features = await extractIaFeatures(bytes);
          if (features != null) {
            result[ref] = features;
          }
          // Si `features == null` ou si l'asset n'existe pas (catch plus
          // bas) : cette ref n'a simplement pas de vignette locale
          // exploitable (12/43 refs concernées, voir doc de fichier) —
          // elle reste hors de la base de comparaison IA, mais reste
          // accessible via le catalogue manuel complet (43 refs).
        } catch (_) {
          // Asset introuvable pour cette ref — attendu pour les 12 refs
          // sans vignette locale, pas une erreur à signaler à l'utilisateur.
        }
      }
      _refFeatures = result;
      return result;
    }();
  }

  /// Calcule le classement de similarité pour l'image [queryBytes],
  /// restreint à la base chargée par [ensureLoaded] (donc déjà limitée
  /// aux refs présentation-visibles ayant une vignette). Ne lève jamais
  /// d'exception : toute image absente/corrompue/format non supporté
  /// aboutit à un [IaSuggestionRankResult] non exploitable, jamais un
  /// crash.
  Future<IaSuggestionRankResult> rank(Uint8List queryBytes, {int topN = 3}) async {
    if (!kIaSuggestionEnabled) {
      return IaSuggestionRankResult.nonExploitable(
        'Module désactivé (kIaSuggestionEnabled=false, voir '
        '/tmp/presentation_ai_demo.txt pour le motif du dernier calibrage).',
      );
    }
    final db = _refFeatures;
    if (db == null || db.isEmpty) {
      return IaSuggestionRankResult.nonExploitable(
        'Base de référence non chargée ou vide (appeler ensureLoaded() '
        'au préalable, ou aucune vignette control/*.png exploitable).',
      );
    }

    final queryFeatures = await extractIaFeatures(queryBytes);
    if (queryFeatures == null) {
      return IaSuggestionRankResult.nonExploitable(
        'Image non exploitable (décodage échoué, format non supporté, ou '
        'masque encre dégénéré — image blanche/vide).',
      );
    }

    final scored = <IaSuggestionMatch>[];
    for (final entry in db.entries) {
      final s = cosineSimilarity(queryFeatures, entry.value);
      scored.add(IaSuggestionMatch(entry.key, s));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    if (scored.isEmpty) {
      return IaSuggestionRankResult.nonExploitable('Base de référence vide.');
    }

    final top1 = scored[0].score;
    final top2 = scored.length > 1 ? scored[1].score : 0.0;
    final gap = top1 - top2;
    final exploitable = top1 >= kMinIaScore && gap >= kMinIaGap;

    if (!exploitable) {
      return IaSuggestionRankResult(
        exploitable: false,
        matches: const [],
        reason: 'Seuils non atteints (top1=${top1.toStringAsFixed(4)} '
            'gap=${gap.toStringAsFixed(4)}, requis score>=$kMinIaScore '
            'et gap>=$kMinIaGap).',
      );
    }

    return IaSuggestionRankResult(
      exploitable: true,
      matches: scored.take(topN).toList(),
      reason: 'top1=${top1.toStringAsFixed(4)} gap=${gap.toStringAsFixed(4)}.',
    );
  }
}
