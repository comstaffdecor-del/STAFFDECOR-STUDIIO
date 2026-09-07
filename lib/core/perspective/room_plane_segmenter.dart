/// P11 — contrat de segmentation par plans de pièce (plafond / mur /
/// sol), indépendant de tout provider concret (fake de test, backend
/// HTTP web...).
///
/// ⚠️ Ce fichier ne définit QUE le contrat de données + l'interface —
/// aucun algorithme de détection ici. Les providers concrets
/// (`fake_room_plane_segmenter.dart`, `http_room_plane_segmenter.dart`)
/// implémentent [RoomPlaneSegmenter]. L'extraction de frontières
/// (`plane_boundary_extractor.dart`) et la conversion en [PerspCalib]
/// (`segmentation_to_persp_calib.dart`) consomment [RoomPlaneMaskResult]
/// sans jamais dépendre d'un provider particulier.
///
/// ⚠️ INTERDITS (rappel P11) : ce fichier n'est branché sur aucun rendu
/// (`RoomPainter` non touché), n'expose aucune notion de `confidence`
/// (l'ancien champ de `edge_detect.dart`) — voir plutôt `qualityScore`/
/// `qualitySubScores` dans `segmentation_to_persp_calib.dart`.
library;

import 'dart:typed_data';

/// Les 4 classes de plan reconnues, dans l'ordre EXACT attendu par tout
/// backend de segmentation (`labels.txt`) : `["unknown", "ceiling",
/// "wall", "floor"]`. Cet ordre est la source de vérité unique — voir
/// `room_plane_labels.dart` (`kRoomPlaneLabelOrder`) qui doit rester
/// synchronisé avec `RoomPlaneClass.values` (vérifié par un test
/// unitaire dédié, jamais par une simple convention non testée).
enum RoomPlaneClass { unknown, ceiling, wall, floor }

/// Masque de segmentation encodé en RLE (run-length encoding) sur
/// l'ensemble du raster, en ordre ligne-major (row-major) : chaque paire
/// `[classIndex, runLength]` représente `runLength` pixels consécutifs
/// de la classe `RoomPlaneClass.values[classIndex]`. La somme de tous
/// les `runLength` DOIT être exactement égale à `width * height`.
///
/// Choix RLE (plutôt qu'un buffer de pixels brut) : format compact,
/// facilement transmissible en JSON par un backend HTTP (voir
/// `http_room_plane_segmenter.dart`), sans dépendance à `package:image`
/// ni `dart:io` (contrainte Web — voir brief P11).
class RoomPlaneMaskResult {
  final int width;
  final int height;

  /// Paires `[classIndex, runLength]`, ordre ligne-major, somme des
  /// `runLength` == `width * height`.
  final List<List<int>> rle;

  /// Nom du provider ayant produit ce masque (`'fake'`, `'http:<url>'`,
  /// ...) — purement informatif, jamais utilisé pour une logique
  /// métier (aucun `if (source == 'fake')` ailleurs dans le pipeline).
  final String providerName;

  RoomPlaneMaskResult({
    required this.width,
    required this.height,
    required this.rle,
    required this.providerName,
  }) {
    final total = rle.fold<int>(0, (sum, pair) => sum + pair[1]);
    if (total != width * height) {
      throw ArgumentError(
        'RoomPlaneMaskResult: somme des runLength ($total) != '
        'width*height (${width * height})',
      );
    }
    for (final pair in rle) {
      final idx = pair[0];
      if (idx < 0 || idx >= RoomPlaneClass.values.length) {
        throw ArgumentError(
          'RoomPlaneMaskResult: classIndex $idx hors bornes '
          '(0..${RoomPlaneClass.values.length - 1})',
        );
      }
    }
  }

  /// Décode le RLE en un buffer plat ligne-major (1 octet/pixel =
  /// index de classe). Calculé à la demande — jamais mis en cache dans
  /// l'objet (immutable, coût négligeable aux résolutions de travail
  /// utilisées ici, 512×384 ou moins).
  Uint8List decode() {
    final out = Uint8List(width * height);
    var pos = 0;
    for (final pair in rle) {
      final classIdx = pair[0];
      final runLen = pair[1];
      out.fillRange(pos, pos + runLen, classIdx);
      pos += runLen;
    }
    return out;
  }

  /// Classe au pixel `(x, y)` (coordonnées entières, ligne-major).
  /// Implémenté via [decode] — si appelé pixel par pixel en boucle
  /// serrée, préférer décoder une fois et indexer directement le
  /// buffer retourné par [decode].
  RoomPlaneClass classAt(int x, int y) {
    final flat = decode();
    return RoomPlaneClass.values[flat[y * width + x]];
  }

  /// `true` si au moins un pixel du masque appartient à [cls] — sert au
  /// test de contrat P11 ("3 masques non vides").
  bool hasAny(RoomPlaneClass cls) {
    final target = cls.index;
    for (final pair in rle) {
      if (pair[0] == target && pair[1] > 0) return true;
    }
    return false;
  }

  /// Compte total de pixels appartenant à [cls] sur l'ensemble du
  /// masque (somme des runLength de cette classe, sans décoder).
  int countOf(RoomPlaneClass cls) {
    final target = cls.index;
    var total = 0;
    for (final pair in rle) {
      if (pair[0] == target) total += pair[1];
    }
    return total;
  }

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'rle': rle,
    'providerName': providerName,
  };
}

/// Contrat unique implémenté par tout provider de segmentation par
/// plans de pièce — qu'il s'agisse d'un fake déterministe (tests) ou
/// d'un backend HTTP réel (production Web, voir
/// `http_room_plane_segmenter.dart`).
///
/// [width]/[height] : résolution de travail À LAQUELLE le provider doit
/// produire son masque (le provider peut redimensionner en interne
/// l'image source, mais [RoomPlaneMaskResult.width]/[height] du retour
/// doivent correspondre exactement à ces valeurs demandées).
abstract class RoomPlaneSegmenter {
  Future<RoomPlaneMaskResult?> segment({
    required Uint8List imageBytes,
    required int width,
    required int height,
  });
}
