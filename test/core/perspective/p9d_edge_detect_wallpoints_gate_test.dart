// P9d — harnais de mesure (permanent, PAS un *_tmp_*) : écart ABSOLU en
// `yPct` sur les 4 points `wall*` (`wallTL`/`wallTR`/`wallBL`/`wallBR`)
// entre `detectRoomEdges` et les presets de vérité terrain, avec
// agrégation par TYPE DE POINT en plus de l'agrégation par scène (ce que
// P9c ne fait pas — P9c s'arrête aux 4 points `f*`).
//
// ## Prédiction écrite AVANT exécution (obligatoire — sinon la mesure ne
// vaut rien, cf. protocole)
//
// `wallTopYPct = clamp01(ceilYPct * 0.5)` et `wallBotYPct =
// clamp01(floorYPct + (1 - floorYPct) * 0.5)` (`edge_detect.dart:589-590`)
// sont des fonctions déterministes de `ceilY`/`floorY` — AUCUNE donnée
// d'image n'entre dans leur calcul (pas de segment, pas de ligne Hough
// dédiée aux murs latéraux). Deux prédictions falsifiables :
//
//   1. Trivial par construction : `wallTL.yPct == wallTR.yPct` et
//      `wallBL.yPct == wallBR.yPct` côté DÉTECTÉ (formule symétrique,
//      xPct fixe 0.0/1.0) — mais PAS forcément égal côté VÉRITÉ (les
//      presets ont des yPct légèrement différents entre L et R, ex.
//      haussmann wallTL=0.100 vs wallTR=0.095).
//
//   2. Non trivial : l'erreur wall* sera PLUS GRANDE que l'erreur
//      ceil/floor correspondante, pas simplement corrélée à l'identique.
//      Raison : la vérité terrain place les murs PRÈS du plafond/sol
//      (écart de 5 à 10 points de %, voir les presets), alors que la
//      formule détectée tire le point à 50% de la distance vers le bord
//      de l'image (0% ou 100%) — une distorsion géométrique FIXE qui
//      s'AJOUTE à l'erreur de ceilY/floorY, elle ne la reproduit pas.
//
// Ce fichier vérifie ces deux prédictions par la mesure, sans jamais
// faire échouer le test lui-même (instrument de mesure, même philosophie
// que P9a/P9c) — la conclusion (résultat confirmé ou infirmé) est
// imprimée pour lecture humaine, pas encodée en assertion bloquante.
//
// Espace de coordonnées : identique à P9c, `yPct` brut, sans conversion
// canvas — voir docstring de P9c pour la justification.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/edge_detect.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

const List<String> kPresetKeys = [
  'haussmann',
  'moderne',
  'provencal',
  'scandinave',
];

/// Même seuils que P9c (barrière inchangée) + nouvelle barrière wall*.
const double kMeanThreshold = 0.02;
const double kPerSceneMaxThreshold = 0.04;

Future<ui.Image> _decodeImageFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

double _absDiff(double a, double b) => (a - b).abs();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'P9d : écart absolu en yPct sur les points wall*, agrégation par '
    'type de point ET par scène, vérification de la prédiction '
    "d'absence de détection propre",
    () async {
      // Erreurs par point (wallTL/wallTR/wallBL/wallBR), toutes scènes
      // confondues, pour l'agrégation "par type de point".
      final errByPoint = <String, List<double>>{
        'wallTL': [],
        'wallTR': [],
        'wallBL': [],
        'wallBR': [],
      };
      // Pour la comparaison directe wall vs ceil/floor correspondant.
      final ratioWallOverCeilFloor = <double>[];

      // Vérification de la prédiction 1 (trivialité détectée) —
      // compteur d'occurrences confirmées/infirmées.
      var detTopEqualCount = 0;
      var detBotEqualCount = 0;
      var scenesMeasured = 0;

      for (final key in kPresetKeys) {
        final imgPath = 'assets/demo_scenes/$key.jpg';
        final file = File(imgPath);
        if (!file.existsSync()) {
          // ignore: avoid_print
          print('[p9d] preset=$key image introuvable path=$imgPath');
          continue;
        }

        final image = await _decodeImageFile(imgPath);
        final detected = await detectRoomEdges(image);
        image.dispose();

        if (detected == null) {
          // ignore: avoid_print
          print('[p9d] preset=$key detectRoomEdges=null (pas de mesure)');
          continue;
        }

        final truth = PerspCalib.forDemoScene(key);
        final d = detected.calib;
        scenesMeasured++;

        // --- Prédiction 1 : trivialité détectée (formule symétrique) ---
        final topEqual = d.wallTL.yPct == d.wallTR.yPct;
        final botEqual = d.wallBL.yPct == d.wallBR.yPct;
        if (topEqual) detTopEqualCount++;
        if (botEqual) detBotEqualCount++;

        // --- Erreurs yPct par point wall* ---
        final eTL = _absDiff(d.wallTL.yPct, truth.wallTL.yPct);
        final eTR = _absDiff(d.wallTR.yPct, truth.wallTR.yPct);
        final eBL = _absDiff(d.wallBL.yPct, truth.wallBL.yPct);
        final eBR = _absDiff(d.wallBR.yPct, truth.wallBR.yPct);
        errByPoint['wallTL']!.add(eTL);
        errByPoint['wallTR']!.add(eTR);
        errByPoint['wallBL']!.add(eBL);
        errByPoint['wallBR']!.add(eBR);

        final wallMax = [eTL, eTR, eBL, eBR].reduce((a, b) => a > b ? a : b);
        final wallMean = (eTL + eTR + eBL + eBR) / 4;

        // --- Comparaison directe : erreur wall vs erreur ceil/floor
        // correspondant (prédiction 2 : wall > ceil/floor, pas égal) ---
        final eCeilL = _absDiff(d.ceilL.yPct, truth.ceilL.yPct);
        final eCeilR = _absDiff(d.ceilR.yPct, truth.ceilR.yPct);
        final eFloorL = _absDiff(d.floorL.yPct, truth.floorL.yPct);
        final eFloorR = _absDiff(d.floorR.yPct, truth.floorR.yPct);
        final ceilFloorMean = (eCeilL + eCeilR + eFloorL + eFloorR) / 4;
        if (ceilFloorMean > 0) {
          ratioWallOverCeilFloor.add(wallMean / ceilFloorMean);
        }

        // ignore: avoid_print
        print(
          '[p9d] preset=$key '
          'yErr_wallTL=${eTL.toStringAsFixed(4)} '
          'yErr_wallTR=${eTR.toStringAsFixed(4)} '
          'yErr_wallBL=${eBL.toStringAsFixed(4)} '
          'yErr_wallBR=${eBR.toStringAsFixed(4)} '
          'wallMean=${wallMean.toStringAsFixed(4)} '
          'wallMax=${wallMax.toStringAsFixed(4)} '
          'ceilFloorMean=${ceilFloorMean.toStringAsFixed(4)} '
          'ratio_wall/ceilFloor=${(ceilFloorMean > 0 ? wallMean / ceilFloorMean : double.nan).toStringAsFixed(2)} '
          'detTopEqual=$topEqual detBotEqual=$botEqual',
        );
      }

      if (scenesMeasured == 0) {
        // ignore: avoid_print
        print('[p9d] AUCUNE mesure obtenue — impossible de statuer.');
        expect(true, isTrue);
        return;
      }

      // --- Agrégation par TYPE DE POINT (ce que P9c ne fait pas) ---
      // ignore: avoid_print
      print('[p9d] --- Agrégation par type de point (toutes scènes) ---');
      final meanByPoint = <String, double>{};
      final maxByPoint = <String, double>{};
      for (final entry in errByPoint.entries) {
        if (entry.value.isEmpty) continue;
        final mean = entry.value.reduce((a, b) => a + b) / entry.value.length;
        final max = entry.value.reduce((a, b) => a > b ? a : b);
        meanByPoint[entry.key] = mean;
        maxByPoint[entry.key] = max;
        // ignore: avoid_print
        print(
          '[p9d] point=${entry.key} mean_yPct_error=${mean.toStringAsFixed(4)} '
          'max_yPct_error=${max.toStringAsFixed(4)} n=${entry.value.length}',
        );
      }

      final globalWallMean =
          meanByPoint.values.reduce((a, b) => a + b) / meanByPoint.length;
      final globalWallMax = maxByPoint.values.reduce(
        (a, b) => a > b ? a : b,
      );
      final wallMeanOk = globalWallMean < kMeanThreshold;
      final wallMaxOk = globalWallMax < kPerSceneMaxThreshold;

      // ignore: avoid_print
      print(
        '[p9d] GLOBAL wall* mean_yPct_error=${globalWallMean.toStringAsFixed(4)} '
        '(seuil<${kMeanThreshold.toStringAsFixed(2)}, '
        '${wallMeanOk ? "OK" : "DEPASSE"}) '
        'max_yPct_error=${globalWallMax.toStringAsFixed(4)} '
        '(seuil<${kPerSceneMaxThreshold.toStringAsFixed(2)}, '
        '${wallMaxOk ? "OK" : "DEPASSE"})',
      );

      // --- Vérification des deux prédictions ---
      final pred1Confirmed =
          detTopEqualCount == scenesMeasured &&
          detBotEqualCount == scenesMeasured;
      // ignore: avoid_print
      print(
        '[p9d] PREDICTION 1 (trivialite detectee wallTL==wallTR et '
        'wallBL==wallBR cote DETECTE, sur $scenesMeasured scenes) : '
        'detTopEqual=$detTopEqualCount/$scenesMeasured '
        'detBotEqual=$detBotEqualCount/$scenesMeasured -> '
        '${pred1Confirmed ? "CONFIRMEE" : "INFIRMEE"}',
      );

      if (ratioWallOverCeilFloor.isNotEmpty) {
        final avgRatio =
            ratioWallOverCeilFloor.reduce((a, b) => a + b) /
            ratioWallOverCeilFloor.length;
        final minRatio = ratioWallOverCeilFloor.reduce(
          (a, b) => a < b ? a : b,
        );
        final pred2Confirmed = minRatio > 1.0;
        // ignore: avoid_print
        print(
          '[p9d] PREDICTION 2 (erreur wall* > erreur ceil/floor '
          'correspondante, pas simple reproduction a l\'identique) : '
          'ratio moyen wall/ceilFloor=${avgRatio.toStringAsFixed(2)} '
          'ratio minimum observe=${minRatio.toStringAsFixed(2)} -> '
          '${pred2Confirmed ? "CONFIRMEE (ratio>1 sur toutes les scenes)" : "INFIRMEE ou PARTIELLE (au moins une scene avec ratio<=1)"}',
        );
      }

      final verdict = (wallMeanOk && wallMaxOk)
          ? 'SEUIL wall* ATTEINT'
          : 'SEUIL wall* NON ATTEINT - detecteur absent sur ce volet, pas '
                'seulement imprecis (confirme la lecture P9b : wallTL=wallTR '
                'et wallBL=wallBR par construction, aucune donnee d\'image '
                'consommee)';
      // ignore: avoid_print
      print('[p9d] VERDICT wall* = $verdict');

      // Aucun expect qui échoue : instrument de mesure, même philosophie
      // que P9a/P9c. La décision (fonctionnalité à créer, pas régression
      // à réparer) revient à un humain qui lit ce qui précède.
      expect(true, isTrue);
    },
  );
}
