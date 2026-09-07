/// P11 — provider `RoomPlaneSegmenter` backend HTTP, PRIORITAIRE pour
/// le Web : `package:http` UNIQUEMENT (déjà présent, `http: 1.5.0`),
/// AUCUN `dart:io` (compatibilité Web stricte — pas de `HttpClient`
/// natif). N'utilise ni `package:image` ni `tflite_flutter` (absents du
/// projet, brief P11 : le mapping modèle -> classes se fait côté
/// backend, une seule fois — ce fichier ne fait QUE consommer un
/// contrat JSON déjà mappé).
///
/// Contrat JSON attendu de la réponse backend :
/// ```json
/// {
///   "width": 512,
///   "height": 384,
///   "labels": ["unknown", "ceiling", "wall", "floor"],
///   "rle": [[0, 120], [1, 340], ...]
/// }
/// ```
///
/// Vérification STRICTE et FRANCHE (échec explicite, jamais de repli
/// silencieux) : `labels` DOIT être exactement égal, dans l'ordre, à
/// `["unknown", "ceiling", "wall", "floor"]` == l'ordre de
/// `RoomPlaneClass.values` (voir `room_plane_labels.dart`,
/// `kRoomPlaneLabelOrder`). Toute divergence (modèle Pascal VOC sans
/// `ceiling`/`floor`, ordre différent, labels manquants/en trop) lève
/// une [RoomPlaneContractViolationException] plutôt que de produire un
/// masque silencieusement mal mappé.
///
/// ⚠️ NE PAS créer `tflite_room_plane_segmenter.dart` dans cette passe
/// (brief P11) — ce fichier-ci est le SEUL provider "réel" pour
/// l'instant, et il délègue tout le travail de modèle au backend HTTP.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'room_plane_labels.dart';
import 'room_plane_segmenter.dart';

/// Levée quand la réponse backend ne respecte pas le contrat de
/// classes attendu — jamais rattrapée silencieusement par
/// [HttpRoomPlaneSegmenter.segment], qui la laisse remonter (échec
/// franc, voir docstring de tête de fichier).
class RoomPlaneContractViolationException implements Exception {
  final String reason;
  const RoomPlaneContractViolationException(this.reason);

  @override
  String toString() => 'RoomPlaneContractViolationException: $reason';
}

/// Provider HTTP : envoie [imageBytes] (multipart) à [endpoint] et
/// attend en retour le contrat JSON décrit en tête de fichier.
///
/// [client] : injectable pour les tests (défaut : `http.Client()` réel,
/// jamais `dart:io`'s `HttpClient`).
class HttpRoomPlaneSegmenter implements RoomPlaneSegmenter {
  final Uri endpoint;
  final http.Client client;

  HttpRoomPlaneSegmenter({required this.endpoint, http.Client? client})
    : client = client ?? http.Client();

  @override
  Future<RoomPlaneMaskResult?> segment({
    required Uint8List imageBytes,
    required int width,
    required int height,
  }) async {
    final request = http.MultipartRequest('POST', endpoint)
      ..fields['width'] = width.toString()
      ..fields['height'] = height.toString()
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'room.jpg',
        ),
      );

    final streamedResponse = await client.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw RoomPlaneContractViolationException(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw RoomPlaneContractViolationException('reponse non-JSON: $e');
    }

    return decodeRoomPlaneMaskJson(body);
  }
}

/// Décode et VALIDE STRICTEMENT le contrat JSON backend décrit en tête
/// de fichier, produisant un [RoomPlaneMaskResult]. Exposé séparément
/// de [HttpRoomPlaneSegmenter.segment] pour être testable sans réseau
/// (un simple `Map<String, dynamic>` déjà décodé).
///
/// Échec franc ([RoomPlaneContractViolationException]) si :
///   - `labels` absent, de longueur différente de
///     `RoomPlaneClass.values.length`, ou dans un ordre différent de
///     [kRoomPlaneLabelOrder] (ex : modèle Pascal VOC sans
///     ceiling/floor — voir docstring de tête de fichier) ;
///   - `width`/`height`/`rle` absents ou de type incorrect ;
///   - le RLE décodé ne respecte pas les contraintes de
///     [RoomPlaneMaskResult] (somme des runLength, bornes de
///     classIndex — délégué au constructeur de [RoomPlaneMaskResult],
///     qui lève déjà [ArgumentError] dans ce cas, laissé remonter tel
///     quel).
RoomPlaneMaskResult decodeRoomPlaneMaskJson(Map<String, dynamic> body) {
  final labelsRaw = body['labels'];
  if (labelsRaw is! List) {
    throw const RoomPlaneContractViolationException(
      'champ "labels" absent ou de type incorrect (attendu List<String>)',
    );
  }
  final labels = labelsRaw.map((e) => e.toString()).toList();

  if (labels.length != kRoomPlaneLabelOrder.length) {
    throw RoomPlaneContractViolationException(
      'contrat de classes viole: ${labels.length} labels recus, '
      '${kRoomPlaneLabelOrder.length} attendus '
      '($kRoomPlaneLabelOrder). Le modele backend est probablement '
      'incompatible (ex: Pascal VOC sans ceiling/floor).',
    );
  }
  for (var i = 0; i < labels.length; i++) {
    if (labels[i] != kRoomPlaneLabelOrder[i]) {
      throw RoomPlaneContractViolationException(
        'contrat de classes viole a l\'index $i: recu "${labels[i]}", '
        'attendu "${kRoomPlaneLabelOrder[i]}" (ordre exact requis: '
        '$kRoomPlaneLabelOrder == RoomPlaneClass.values).',
      );
    }
  }
  if (!roomPlaneLabelOrderMatchesEnum()) {
    // Garde-fou interne : ne devrait jamais se produire (vérifié par
    // un test unitaire dédié sur room_plane_labels.dart), mais échec
    // franc plutôt que silence si la synchronisation casse un jour.
    throw const RoomPlaneContractViolationException(
      'kRoomPlaneLabelOrder desynchronise de RoomPlaneClass.values '
      '(bug interne, voir room_plane_labels.dart)',
    );
  }

  final widthRaw = body['width'];
  final heightRaw = body['height'];
  if (widthRaw is! int || heightRaw is! int) {
    throw const RoomPlaneContractViolationException(
      'champs "width"/"height" absents ou de type incorrect (attendu int)',
    );
  }

  final rleRaw = body['rle'];
  if (rleRaw is! List) {
    throw const RoomPlaneContractViolationException(
      'champ "rle" absent ou de type incorrect (attendu List<List<int>>)',
    );
  }
  final rle = <List<int>>[];
  for (final pair in rleRaw) {
    if (pair is! List || pair.length != 2) {
      throw const RoomPlaneContractViolationException(
        'element "rle" invalide (attendu paire [classIndex, runLength])',
      );
    }
    rle.add([(pair[0] as num).toInt(), (pair[1] as num).toInt()]);
  }

  // RoomPlaneMaskResult valide deja somme(runLength)==width*height et
  // les bornes de classIndex dans son constructeur (ArgumentError si
  // violation) - echec franc herite, pas de nouvelle logique dupliquee.
  return RoomPlaneMaskResult(
    width: widthRaw,
    height: heightRaw,
    rle: rle,
    providerName: 'http',
  );
}
