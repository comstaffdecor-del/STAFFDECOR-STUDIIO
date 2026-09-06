// P10bis — sonde de diagnostic (permanent, PAS un *_tmp_*), lecture seule,
// additive. Objectif unique (demande explicite) : comparer trois états
// successifs de la liste de lignes Hough, PAR SCÈNE DÉMO, en utilisant la
// fonction diagnostique additive `detectRoomEdgesStages` ajoutée dans
// `lib/core/perspective/edge_detect.dart` (elle-même rejoue exactement les
// mêmes appels/constantes que `detectRoomEdges`, sans aucune divergence de
// logique) :
//   (a) rawLines  — sortie brute de `_houghLines` (avant tout filtrage)
//   (b) clustered — sortie de `_clusterLines` (fusion des doublons)
//   (c) capped    — sortie de `_capParBande` (troncature à 20/bande)
//
// Pour chaque état : histogramme d'angles par tranches de 10° (0-180°),
// décompte de lignes dans la bande verticale ]75°,105°[ et leur score
// Hough médian.
//
// AUCUNE modification de rendu : ni `RoomPainter`, ni `_buildGeometry`, ni
// `detectRoomEdges`, ni aucune fonction de production existante ne sont
// touchées. Aucun `expect` qui échoue (instrument de mesure, même
// philosophie que P9a/P9b/P9c/P10).

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/edge_detect.dart';

const List<String> kPresetKeys = [
  'haussmann',
  'moderne',
  'provencal',
  'scandinave',
];

Future<ui.Image> _decodeImageFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Angle de LIGNE (0-180°) recalculé depuis (x1,y1,x2,y2) en pourcentage
/// — indépendant de `theta` (qui est l'angle de la NORMALE côté Hough,
/// déjà converti en angle de ligne côté production via `_lineAngle`, mais
/// cette fonction est privée : on retrouve le même angle ici directement
/// depuis les coordonnées du segment exposées par `LineDiagnostic`, sans
/// dupliquer `_lineAngle`).
double _lineAngleDeg(LineDiagnostic l) {
  final dx = l.x2Pct - l.x1Pct;
  final dy = l.y2Pct - l.y1Pct;
  var deg = math.atan2(dy, dx) * 180 / math.pi;
  deg = deg % 180;
  if (deg < 0) deg += 180;
  return deg;
}

/// Histogramme par tranches de 10°, bornes [0,10) [10,20) ... [170,180].
Map<String, int> _histogram10deg(List<LineDiagnostic> lines) {
  final buckets = <String, int>{};
  for (var b = 0; b < 180; b += 10) {
    buckets['[$b-${b + 10})'] = 0;
  }
  for (final l in lines) {
    final a = _lineAngleDeg(l);
    var b = (a ~/ 10) * 10;
    if (b >= 180) b = 170;
    buckets['[$b-${b + 10})'] = (buckets['[$b-${b + 10})'] ?? 0) + 1;
  }
  return buckets;
}

double _median(List<double> xs) {
  if (xs.isEmpty) return double.nan;
  final s = [...xs]..sort();
  final n = s.length;
  if (n.isOdd) return s[n ~/ 2];
  return (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

void _printStageReport(String scene, String stageName, List<LineDiagnostic> lines) {
  final hist = _histogram10deg(lines);
  // ignore: avoid_print
  print('[p10bis] scene=$scene stage=$stageName total=${lines.length}');
  for (var b = 0; b < 180; b += 10) {
    final key = '[$b-${b + 10})';
    // ignore: avoid_print
    print('[p10bis] scene=$scene stage=$stageName bucket=$key count=${hist[key]}');
  }
  final verticals = lines.where((l) {
    final a = _lineAngleDeg(l);
    return a > 75 && a < 105;
  }).toList();
  final medScore = _median(verticals.map((l) => l.score).toList());
  // ignore: avoid_print
  print(
    '[p10bis] scene=$scene stage=$stageName verticals_75_105=${verticals.length} '
    'medianHoughScore=${verticals.isEmpty ? "n/a" : medScore.toStringAsFixed(4)}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'P10bis : histogrammes angulaires par tranche de 10° aux 3 étapes '
    '(rawLines / clustered / capped) + bande verticale ]75°,105°[, '
    '4 scènes démo',
    () async {
      for (final key in kPresetKeys) {
        final imgPath = 'assets/demo_scenes/$key.jpg';
        final file = File(imgPath);
        if (!file.existsSync()) {
          // ignore: avoid_print
          print('[p10bis] scene=$key image introuvable path=$imgPath');
          continue;
        }

        final image = await _decodeImageFile(imgPath);
        final stages = await detectRoomEdgesStages(image);
        image.dispose();

        if (stages == null) {
          // ignore: avoid_print
          print('[p10bis] scene=$key detectRoomEdgesStages=null');
          continue;
        }

        _printStageReport(key, 'a_raw', stages.rawLines);
        _printStageReport(key, 'b_clustered', stages.clustered);
        _printStageReport(key, 'c_capped', stages.capped);

        // ignore: avoid_print
        print(
          '[p10bis] scene=$key RESUME_COMPTES raw=${stages.rawLines.length} '
          'clustered=${stages.clustered.length} capped=${stages.capped.length}',
        );
      }

      expect(true, isTrue);
    },
  );
}
