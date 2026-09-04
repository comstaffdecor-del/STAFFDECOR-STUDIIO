// P9c — harnais de mesure (permanent, PAS un *_tmp_*) : écart ABSOLU en
// `yPct` entre la calibration détectée automatiquement (`detectRoomEdges`,
// `lib/core/perspective/edge_detect.dart`) et la calibration de vérité
// terrain conventionnelle (`PerspCalib.forDemoScene`,
// `lib/models/persp_calib.dart`, calée à la main) sur les 4 photos de
// scènes démo (`assets/demo_scenes/<key>.jpg`).
//
// Différence avec P9a (`p9a_edge_detect_baseline_test.dart`) : P9a convertit
// les deux calibrations en pixels sur un canvas 1400×975 avant de mesurer
// une distance euclidienne — utile pour juger l'écart visuel à l'écran,
// mais ce n'est PAS la métrique retenue pour la décision de brancher un
// futur détecteur. Ici on mesure l'écart BRUT en `yPct` (fraction 0-1 de
// l'image source), sans passer par aucune conversion canvas : les deux
// calibrations sont déjà dans le même espace (voir docstring de P9a,
// confirmée par `persp_calib.dart` : "en pourcentage, xPct/yPct de l'image
// source"), donc `|yPct_detecté - yPct_vérité|` est directement
// comparable entre scènes, indépendamment de toute taille d'affichage.
//
// Seuil de décision, FIXÉ AVANT toute réécriture du détecteur (règle
// explicite du protocole — sans quoi on rejoue P9j) :
//   - erreur absolue MOYENNE en yPct < 0.02 sur les 4 scènes
//   - AUCUNE scène au-delà de 0.04
// Ce fichier ne fait qu'afficher le résultat de cette comparaison — il ne
// fait pas échouer le test si le seuil n'est pas atteint (instrument de
// mesure, jamais rouge par construction, même philosophie que P9a) :
// c'est un humain qui décide de brancher ou non un futur détecteur au vu
// du chiffre imprimé, pas ce fichier.
//
// Portée volontairement limitée aux 4 points `f*` (`ceilL`/`ceilR`/
// `floorL`/`floorR`) — ce sont ceux qui pilotent directement le rendu du
// mur du fond (voir `room_painter.dart`). Les points `wall*` ne sont pas
// mesurés ici (voir P9b pour leur statut : dérivés proportionnellement de
// `ceilY`/`floorY`, jamais mesurés indépendamment par `detectRoomEdges`).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/edge_detect.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

/// Seuils de décision — voir docstring en tête de fichier. Déclarés ici en
/// constantes nommées pour qu'ils soient visibles sans lire tout le
/// fichier, et pour qu'un futur changement de seuil laisse une trace de
/// diff claire.
const double kMeanThreshold = 0.02;
const double kPerSceneMaxThreshold = 0.04;

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

double _absDiff(double a, double b) => (a - b).abs();

/// Écart max des 4 points `f*` pour une scène, en yPct.
double _maxYPctErrorForScene(PerspCalib detected, PerspCalib truth) {
  final errs = [
    _absDiff(detected.ceilL.yPct, truth.ceilL.yPct),
    _absDiff(detected.ceilR.yPct, truth.ceilR.yPct),
    _absDiff(detected.floorL.yPct, truth.floorL.yPct),
    _absDiff(detected.floorR.yPct, truth.floorR.yPct),
  ];
  return errs.reduce((a, b) => a > b ? a : b);
}

/// Écart moyen des 4 points `f*` pour une scène, en yPct.
double _meanYPctErrorForScene(PerspCalib detected, PerspCalib truth) {
  final errs = [
    _absDiff(detected.ceilL.yPct, truth.ceilL.yPct),
    _absDiff(detected.ceilR.yPct, truth.ceilR.yPct),
    _absDiff(detected.floorL.yPct, truth.floorL.yPct),
    _absDiff(detected.floorR.yPct, truth.floorR.yPct),
  ];
  return errs.reduce((a, b) => a + b) / errs.length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'P9c : écart absolu en yPct entre detectRoomEdges et les presets, '
    'sur les 4 scènes démo, contre le seuil de décision fixé à l\'avance',
    () async {
      final sceneMeans = <String, double>{};
      final sceneMaxes = <String, double>{};
      final skipped = <String>[];

      for (final key in kPresetKeys) {
        final imgPath = 'assets/demo_scenes/$key.jpg';
        final file = File(imgPath);
        if (!file.existsSync()) {
          // ignore: avoid_print
          print('[p9c] preset=$key image introuvable path=$imgPath');
          skipped.add(key);
          continue;
        }

        final image = await _decodeImageFile(imgPath);
        final detected = await detectRoomEdges(image);
        image.dispose();

        if (detected == null) {
          // ignore: avoid_print
          print('[p9c] preset=$key detectRoomEdges=null (pas de mesure)');
          skipped.add(key);
          continue;
        }

        final truth = PerspCalib.forDemoScene(key);
        final meanErr = _meanYPctErrorForScene(detected.calib, truth);
        final maxErr = _maxYPctErrorForScene(detected.calib, truth);
        sceneMeans[key] = meanErr;
        sceneMaxes[key] = maxErr;

        final dCeilL = _absDiff(detected.calib.ceilL.yPct, truth.ceilL.yPct);
        final dCeilR = _absDiff(detected.calib.ceilR.yPct, truth.ceilR.yPct);
        final dFloorL = _absDiff(
          detected.calib.floorL.yPct,
          truth.floorL.yPct,
        );
        final dFloorR = _absDiff(
          detected.calib.floorR.yPct,
          truth.floorR.yPct,
        );

        // ignore: avoid_print
        print(
          '[p9c] preset=$key conf=${detected.confidence.toStringAsFixed(4)} '
          'yErr_ceilL=${dCeilL.toStringAsFixed(4)} '
          'yErr_ceilR=${dCeilR.toStringAsFixed(4)} '
          'yErr_floorL=${dFloorL.toStringAsFixed(4)} '
          'yErr_floorR=${dFloorR.toStringAsFixed(4)} '
          'mean=${meanErr.toStringAsFixed(4)} '
          'max=${maxErr.toStringAsFixed(4)} '
          '(seuil scène: ${kPerSceneMaxThreshold.toStringAsFixed(2)})',
        );
      }

      if (sceneMeans.isEmpty) {
        // ignore: avoid_print
        print(
          '[p9c] AUCUNE mesure obtenue (4/4 scènes ignorées) — impossible '
          'de statuer sur le seuil.',
        );
      } else {
        final globalMean =
            sceneMeans.values.reduce((a, b) => a + b) / sceneMeans.length;
        final globalMax = sceneMaxes.values.reduce((a, b) => a > b ? a : b);
        final worstScene = sceneMaxes.entries.reduce(
          (a, b) => a.value > b.value ? a : b,
        );

        final meanOk = globalMean < kMeanThreshold;
        final maxOk = globalMax < kPerSceneMaxThreshold;

        // ignore: avoid_print
        print(
          '[p9c] GLOBAL mean_yPct_error=${globalMean.toStringAsFixed(4)} '
          '(seuil<${kMeanThreshold.toStringAsFixed(2)}, '
          '${meanOk ? "OK" : "DEPASSE"}) '
          'max_yPct_error=${globalMax.toStringAsFixed(4)} '
          'sur scene=${worstScene.key} '
          '(seuil<${kPerSceneMaxThreshold.toStringAsFixed(2)}, '
          '${maxOk ? "OK" : "DEPASSE"}) '
          'scenes_mesurees=${sceneMeans.length}/4 '
          'scenes_ignorees=${skipped.isEmpty ? "aucune" : skipped.join(",")}',
        );
        final verdict = (meanOk && maxOk)
            ? 'SEUIL ATTEINT - brancher est defendable sur cette mesure'
            : 'SEUIL NON ATTEINT - ne pas brancher, detecteur actuel trop '
                  'loin de la verite terrain';
        // ignore: avoid_print
        print(
          '[p9c] VERDICT (mean<${kMeanThreshold.toStringAsFixed(2)} ET '
          'max<${kPerSceneMaxThreshold.toStringAsFixed(2)} sur les scenes '
          'mesurees) = $verdict',
        );
      }

      // Aucun expect qui échoue : instrument de mesure, pas un test de
      // non-régression — il doit rester vert quel que soit le résultat
      // mesuré, exactement comme P9a. La décision de brancher revient à
      // un humain qui lit le VERDICT ci-dessus, pas à ce fichier.
      expect(true, isTrue);
    },
  );
}
