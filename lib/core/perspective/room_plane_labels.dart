/// P11 — table de labels attendue par tout backend/modèle de
/// segmentation par plans de pièce.
///
/// L'ORDRE de cette liste est LA source de vérité de mapping
/// classIndex -> nom de classe pour tout provider externe (voir
/// `http_room_plane_segmenter.dart`), et DOIT rester strictement
/// synchronisé avec `RoomPlaneClass.values` (ordre de déclaration de
/// l'enum dans `room_plane_segmenter.dart`) — un backend qui renverrait
/// des indices de classe dans un ordre différent (ex : `labels.txt`
/// d'un modèle Pascal VOC générique, qui n'a ni `ceiling` ni `floor`)
/// produirait un masque silencieusement mal interprété.
///
/// Synchronisation vérifiée par un test unitaire dédié (voir le test de
/// contrat P11) plutôt que laissée à une simple convention non testée.
library;

import 'room_plane_segmenter.dart';

/// Ordre exact attendu : `["unknown", "ceiling", "wall", "floor"]`.
/// Doit être identique, position par position, à
/// `RoomPlaneClass.values.map((c) => c.name)`.
const List<String> kRoomPlaneLabelOrder = [
  'unknown',
  'ceiling',
  'wall',
  'floor',
];

/// Vérifie que [kRoomPlaneLabelOrder] et `RoomPlaneClass.values` sont
/// synchronisés (même longueur, même ordre de noms). Retourne `true` si
/// tout concorde, `false` sinon — utilisé par le test de contrat P11
/// pour matérialiser cette exigence, plutôt que de la supposer vraie
/// silencieusement.
bool roomPlaneLabelOrderMatchesEnum() {
  final enumNames = RoomPlaneClass.values.map((c) => c.name).toList();
  if (enumNames.length != kRoomPlaneLabelOrder.length) return false;
  for (var i = 0; i < enumNames.length; i++) {
    if (enumNames[i] != kRoomPlaneLabelOrder[i]) return false;
  }
  return true;
}

/// Parse un fichier `labels.txt` (une classe par ligne, lignes vides
/// ignorées) et vérifie qu'il correspond EXACTEMENT à
/// [kRoomPlaneLabelOrder] — c'est le garde-fou explicite demandé par le
/// brief P11 contre les modèles Pascal VOC (qui n'ont ni `ceiling` ni
/// `floor`) : le mapping label -> classe se fait une seule fois côté
/// backend, mais ce contrôle côté client permet de détecter un
/// `labels.txt` incompatible avant d'utiliser un masque silencieusement
/// mal interprété.
bool validateLabelsTxt(String labelsTxtContent) {
  final lines = labelsTxtContent
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.length != kRoomPlaneLabelOrder.length) return false;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i] != kRoomPlaneLabelOrder[i]) return false;
  }
  return true;
}
