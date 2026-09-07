/// P12-bis — TEST DE DIAGNOSTIC JETABLE, non couvert par les garanties
/// de la suite standard, n'est PAS destine a rester dans le depot.
///
/// Objectif unique : mesurer ceilL/ceilR (et le reste des 6 erreurs)
/// sur la scene haussmann avec do_resize=True (comportement de
/// production actuel, deja mesure par P12) puis do_resize=False
/// (hypothese A du brief P12-bis), EN REUTILISANT SANS MODIFICATION
/// HttpRoomPlaneSegmenter et analyseLabelMap -- seule la query string
/// de l'URI passee au constructeur change. Zero fichier lib/ touche.
///
/// Prerequis : service FastAPI local sur le port 8000, avec le
/// parametre de diagnostic `do_resize` ajoute a /segment (query
/// string, cf. backend/segformer_service/main.py).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/http_room_plane_segmenter.dart';
import 'package:staff_decor_studio/core/perspective/room_plane_analysis.dart';
import 'package:staff_decor_studio/core/perspective/room_plane_segmenter.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

const int kMaskWidth = 512;
const int kMaskHeight = 384;
const String kScene = 'haussmann';

Future<void> _probe(String label, Uri endpoint) async {
  final truth = PerspCalib.forDemoScene(kScene);
  final imageBytes = File('assets/demo_scenes/$kScene.jpg').readAsBytesSync();
  final segmenter = HttpRoomPlaneSegmenter(endpoint: endpoint);

  final RoomPlaneMaskResult? mask = await segmenter.segment(
    imageBytes: imageBytes,
    width: kMaskWidth,
    height: kMaskHeight,
  );
  if (mask == null) {
    // ignore: avoid_print
    print('$label: mask null');
    return;
  }

  final analysis = analyseLabelMap(mask);
  final ceilingWall = analysis.ceilingWallBoundary;
  final wallFloor = analysis.wallFloorBoundary;

  final ceilL = ceilingWall != null ? ceilingWall.yAt(truth.ceilL.xPct) - truth.ceilL.yPct : null;
  final ceilR = ceilingWall != null ? ceilingWall.yAt(truth.ceilR.xPct) - truth.ceilR.yPct : null;
  final floorL = wallFloor != null ? wallFloor.yAt(truth.floorL.xPct) - truth.floorL.yPct : null;
  final floorR = wallFloor != null ? wallFloor.yAt(truth.floorR.xPct) - truth.floorR.yPct : null;
  final detectedCorners = ceilingWall?.corners ?? wallFloor?.corners;
  final xL = detectedCorners != null ? detectedCorners[0] - truth.ceilL.xPct : null;
  final xR = detectedCorners != null ? detectedCorners[1] - truth.ceilR.xPct : null;

  String fmt(double? v) => v == null ? 'N/A' : v.toStringAsFixed(4);

  // ignore: avoid_print
  print(
    '$label: ceilL=${fmt(ceilL)} ceilR=${fmt(ceilR)} floorL=${fmt(floorL)} '
    'floorR=${fmt(floorR)} xL=${fmt(xL)} xR=${fmt(xR)} '
    'qualityScore=${analysis.qualityScore.toStringAsFixed(4)} '
    'manualRequired=${analysis.manualRequired}',
  );
}

void main() {
  test('P12-bis diagnostic: do_resize=true vs do_resize=false sur haussmann', () async {
    await _probe('do_resize=TRUE ', Uri.parse('http://localhost:8000/segment'));
    await _probe('do_resize=FALSE', Uri.parse('http://localhost:8000/segment?do_resize=false'));
  });
}
