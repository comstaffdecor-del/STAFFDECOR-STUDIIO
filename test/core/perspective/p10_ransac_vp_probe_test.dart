// P10 TEMPS 3 — sonde RANSAC de point de fuite (permanent, PAS un
// *_tmp_*). Additive/lecture seule : consomme uniquement l'API publique
// existante `detectRoomEdgesStages` (non modifiée, déjà exposée dans
// `edge_detect.dart` par un tour précédent), sans toucher à
// `_classifyLines`, `_buildGeometry`, `_computeVanishingPoint`,
// `PerspCalib`, aux presets, à `RoomPainter` ni au devis.
//
// Objectif (brief P10 TEMPS 3) : mesurer, à partir de `rawLines` (sortie
// brute de `_houghLines`, AVANT clustering et AVANT le cap 4+4 utilisé en
// production par `_computeVanishingPoint`), si un sous-ensemble cohérent
// de diagonales gauche/droite permet de faire converger un point de fuite
// stable via une approche RANSAC (hypothèses = intersections de TOUTES
// les paires diagonale_gauche × diagonale_droite, inliers = distance
// point-droite normalisée en fraction de largeur).
//
// Aucun `expect` qui échoue : instrument de mesure, jamais rouge par
// construction (même philosophie que P9a/P9b/P9c/P10/P10bis) — la
// décision revient à un humain qui lit le VERDICT et les fichiers JSON
// générés.
//
// Interdits respectés : le VP calculé ici n'est branché sur aucun rendu,
// `_buildGeometry` n'est ni appelé ni modifié, `confidence` n'est lu ni
// exposé dans une UI (ce fichier n'a pas d'UI).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/edge_detect.dart';

// P10 TEMPS3 — PRIORITE 2 : témoin aléatoire de validation/invalidation
// du RANSAC. Ajout ADDITIF pur (aucune ligne ci-dessus modifiée) :
// pour chaque scène, on tire 500 points uniformément dans [-0.5,1.5]²
// (espace xPct/yPct, mêmes bornes que `kVpBoundLow`/`kVpBoundHigh` du
// verdict `usable`) et on compte, au MÊME seuil `kInlierDistThreshold`
// (0.05) et sur les MÊMES `rawLines` (allDiags), combien de droites
// chaque point aléatoire "explique" par hasard. Objectif : établir si
// le `bestInlierCount` du RANSAC est significativement meilleur qu'un
// témoin aléatoire, ou si 60-70 inliers est simplement ce qu'on obtient
// n'importe où dans l'image avec ~250-300 diagonales disponibles et un
// seuil de 5% de largeur (auquel cas le RANSAC ne "trouve" rien de
// spécifique). Seed fixe (reproductibilité du probe, pas un aléa réel
// d'un tirage à l'autre — même philosophie déterministe que le reste
// de la suite p9/p10).
//
// ⚠️ NOTE MÉTHODOLOGIQUE OBLIGATOIRE (documentée ici ET dans les
// fichiers de sortie) : `radialMAD` et `maxResidual` du RANSAC sont
// CIRCULAIRES — ils sont calculés UNIQUEMENT sur les distances des
// inliers déjà sélectionnés par le seuil `kInlierDistThreshold`, donc
// ils sont mathématiquement bornés par ce seuil (maxResidual <= 0.05
// par construction) et ne peuvent JAMAIS être mauvais, quelle que soit
// la qualité réelle du point trouvé. Ils NE DOIVENT PAS servir de
// critère de qualité ou de décision — seul `inlierCount`/`inlierRatio`
// comparé au témoin aléatoire ci-dessous a un pouvoir discriminant.
const int kRandomWitnessTrials = 500;
const int kRandomWitnessSeed = 42;

double _percentile(List<double> xs, double p) {
  if (xs.isEmpty) return double.nan;
  final s = [...xs]..sort();
  final idx = (p * (s.length - 1)).round().clamp(0, s.length - 1);
  return s[idx];
}

const List<String> kPresetKeys = [
  'haussmann',
  'moderne',
  'provencal',
  'scandinave',
];

/// Seuil de distance point-droite (en fraction de largeur, espace
/// isotrope `y_widthfrac = yPct * h / w`) sous lequel une droite
/// diagonale est comptée comme inlier d'une hypothèse de VP donnée.
/// Choix de sonde (non normatif, documenté ici) : 0.05 = 5% de la
/// largeur de l'image — du même ordre de grandeur que les tolérances de
/// clustering déjà en place dans le pipeline (`_clusterRho` ≈ 6.6% de la
/// largeur de travail 240px), sans reprendre exactement cette valeur
/// puisqu'on travaille ici sur `rawLines` non fusionnées.
const double kInlierDistThreshold = 0.05;

/// Règles de verdict fournies par le brief P10 TEMPS 3.
const int kUsableMinInliers = 6;
const double kUsableMinInlierRatio = 0.25;
const double kUsableMaxRadialMad = 0.06;
const int kWeakMinInliers = 4;
const double kWeakMaxRadialMad = 0.09;
const double kVpBoundLow = -0.5;
const double kVpBoundHigh = 1.5;

Future<ui.Image> _decodeImageFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Point 2D dans l'espace "width-fraction" (x et y tous deux exprimés en
/// fraction de la LARGEUR de l'image, pour rendre les distances
/// comparables sur les deux axes malgré un ratio w/h != 1).
class _WPt {
  final double x, y;
  const _WPt(this.x, this.y);
}

/// Une diagonale, avec ses deux extrémités converties en espace
/// width-fraction, et sa [LineDiagnostic] d'origine conservée pour le
/// rapport (theta/rho/score/classification/endpoints en pct image).
class _DiagLine {
  final LineDiagnostic diag;
  final _WPt p1, p2;
  const _DiagLine({required this.diag, required this.p1, required this.p2});
}

_DiagLine _toDiagLine(LineDiagnostic d, double hw) => _DiagLine(
  diag: d,
  p1: _WPt(d.x1Pct, d.y1Pct * hw),
  p2: _WPt(d.x2Pct, d.y2Pct * hw),
);

/// Intersection de deux droites (chacune définie par 2 points), dans
/// l'espace width-fraction. `null` si quasi-parallèles.
_WPt? _intersect(_DiagLine a, _DiagLine b) {
  final x1 = a.p1.x, y1 = a.p1.y, x2 = a.p2.x, y2 = a.p2.y;
  final x3 = b.p1.x, y3 = b.p1.y, x4 = b.p2.x, y4 = b.p2.y;
  final denom = (x2 - x1) * (y4 - y3) - (y2 - y1) * (x4 - x3);
  if (denom.abs() < 1e-9) return null;
  final t = ((x3 - x1) * (y4 - y3) - (y3 - y1) * (x4 - x3)) / denom;
  return _WPt(x1 + t * (x2 - x1), y1 + t * (y2 - y1));
}

/// Distance perpendiculaire (espace width-fraction) du point [p] à la
/// droite (infinie) portée par le segment [l].
double _pointToLineDist(_WPt p, _DiagLine l) {
  final x1 = l.p1.x, y1 = l.p1.y, x2 = l.p2.x, y2 = l.p2.y;
  final num = ((x2 - x1) * (p.y - y1) - (y2 - y1) * (p.x - x1)).abs();
  final den = math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
  if (den < 1e-9) return double.infinity;
  return num / den;
}

double _median(List<double> xs) {
  if (xs.isEmpty) return double.nan;
  final s = [...xs]..sort();
  final n = s.length;
  if (n.isOdd) return s[n ~/ 2];
  return (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

double _mad(List<double> xs, double med) {
  if (xs.isEmpty) return double.nan;
  final devs = xs.map((x) => (x - med).abs()).toList();
  return _median(devs);
}

Map<String, dynamic> _lineToReportJson(_DiagLine l, double distToVp) => {
  ...l.diag.toJson(),
  'distToVpWidthFrac': distToVp,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'P10 TEMPS3 : sonde RANSAC point de fuite depuis rawLines (avant '
    'clustering, avant cap 4+4), inliers par distance point-droite en '
    'fraction de largeur, sur les 4 scènes démo',
    () async {
      final summaryLines = <String>[];
      void logLine(String s) {
        summaryLines.add(s);
        // ignore: avoid_print
        print(s);
      }

      for (final key in kPresetKeys) {
        final imgPath = 'assets/demo_scenes/$key.jpg';
        final file = File(imgPath);
        if (!file.existsSync()) {
          logLine('[p10ransac] scene=$key image introuvable path=$imgPath');
          continue;
        }

        final image = await _decodeImageFile(imgPath);
        final srcW = image.width;
        final srcH = image.height;
        final stages = await detectRoomEdgesStages(image);
        image.dispose();

        if (stages == null) {
          logLine('[p10ransac] scene=$key detectRoomEdgesStages=null');
          continue;
        }

        // h/w de l'image DE TRAVAIL == h/w de l'image source (le
        // downscale dans edge_detect.dart préserve le ratio, voir
        // `detectRoomEdges` : wH = (srcH * (_workW/srcW)).round()).
        final hw = srcH / srcW;

        // --- rawLines AVANT clustering, AVANT cap 4+4 -------------------
        final rawL = stages.rawLines
            .where((l) => l.classification == 'diagonal_left')
            .map((l) => _toDiagLine(l, hw))
            .toList();
        final rawR = stages.rawLines
            .where((l) => l.classification == 'diagonal_right')
            .map((l) => _toDiagLine(l, hw))
            .toList();

        // --- Comptes "avant/après troncature" pour le rapport ----------
        // Après clustering + cap par bande (20/bande, pipeline actuel
        // post-TEMPS1) :
        final cappedLCount = stages.capped
            .where((l) => l.classification == 'diagonal_left')
            .length;
        final cappedRCount = stages.capped
            .where((l) => l.classification == 'diagonal_right')
            .length;
        // Après l'ancienne troncature 4+4 de `_computeVanishingPoint`
        // (appliquée en production APRÈS le cap par bande) :
        final vpTruncL = math.min(cappedLCount, 4);
        final vpTruncR = math.min(cappedRCount, 4);

        // --- Verticales survivantes après le correctif TEMPS1 -----------
        final verticalsCapped = stages.capped
            .where((l) => l.classification == 'vertical')
            .toList();
        final vLeftXs = <double>[];
        final vRightXs = <double>[];
        for (final v in verticalsCapped) {
          final xMid = (v.x1Pct + v.x2Pct) / 2;
          if (xMid < 0.5) {
            vLeftXs.add(xMid);
          } else {
            vRightXs.add(xMid);
          }
        }
        final vLeftMedianX = _median(vLeftXs);
        final vRightMedianX = _median(vRightXs);

        // --- Génération d'hypothèses RANSAC : TOUTES les paires --------
        // gauche×droite parmi rawL×rawR (aucune limite 4+4, aucun cap
        // par bande — c'est exactement le point demandé par TEMPS3).
        final allDiags = <_DiagLine>[...rawL, ...rawR];
        final totalDiagCount = allDiags.length;

        _WPt? bestVp;
        int bestInlierCount = -1;
        double bestSumSq = double.infinity;
        List<double> bestDistances = const [];
        List<_DiagLine> bestInlierLines = const [];

        for (final l in rawL) {
          for (final r in rawR) {
            final hyp = _intersect(l, r);
            if (hyp == null) continue;

            var inlierCount = 0;
            var sumSq = 0.0;
            final distances = <double>[];
            final inlierLines = <_DiagLine>[];
            for (final cand in allDiags) {
              final d = _pointToLineDist(hyp, cand);
              if (d <= kInlierDistThreshold) {
                inlierCount++;
                sumSq += d * d;
                distances.add(d);
                inlierLines.add(cand);
              }
            }

            final better =
                inlierCount > bestInlierCount ||
                (inlierCount == bestInlierCount && sumSq < bestSumSq);
            if (better) {
              bestInlierCount = inlierCount;
              bestSumSq = sumSq;
              bestVp = hyp;
              bestDistances = distances;
              bestInlierLines = inlierLines;
            }
          }
        }

        // --- Témoin aléatoire (PRIORITE 2) : 500 VP tirés uniformément --
        // dans [-0.5,1.5]², même seuil, mêmes rawLines (allDiags). Calculé
        // AVANT le `if (bestVp == null)` pour rester disponible même si
        // le RANSAC lui-même n'a trouvé aucune hypothèse valide (cas
        // dégénéré : le témoin reste une mesure indépendante).
        final rng = math.Random(kRandomWitnessSeed);
        final randomInlierCounts = <int>[];
        for (var t = 0; t < kRandomWitnessTrials; t++) {
          final rx = kVpBoundLow + rng.nextDouble() * (kVpBoundHigh - kVpBoundLow);
          final ry = kVpBoundLow + rng.nextDouble() * (kVpBoundHigh - kVpBoundLow);
          final randPt = _WPt(rx, ry * hw);
          var cnt = 0;
          for (final cand in allDiags) {
            if (_pointToLineDist(randPt, cand) <= kInlierDistThreshold) {
              cnt++;
            }
          }
          randomInlierCounts.add(cnt);
        }
        final randomMedian = _median(
          randomInlierCounts.map((e) => e.toDouble()).toList(),
        );
        final randomP95 = _percentile(
          randomInlierCounts.map((e) => e.toDouble()).toList(),
          0.95,
        );
        logLine(
          '[p10ransac][witness] scene=$key trials=$kRandomWitnessTrials '
          'seed=$kRandomWitnessSeed medianInliers='
          '${randomMedian.toStringAsFixed(2)} p95Inliers='
          '${randomP95.toStringAsFixed(2)} '
          '(comparer a bestInlierCount du RANSAC ci-dessous)',
        );
        final randomWitnessJson = {
          'trials': kRandomWitnessTrials,
          'seed': kRandomWitnessSeed,
          'sampleBounds': {'low': kVpBoundLow, 'high': kVpBoundHigh},
          'inlierDistThreshold': kInlierDistThreshold,
          'medianInlierCount': randomMedian,
          'p95InlierCount': randomP95,
          'note':
              'temoin aleatoire : compare bestInlierCount (RANSAC) a ces '
              'valeurs. radialMAD/maxResidual sont CIRCULAIRES (calcules '
              'uniquement sur les inliers du seuil retenu, bornes par '
              'kInlierDistThreshold) et ne doivent PAS servir de critere '
              'de qualite ou de decision.',
        };

        if (bestVp == null) {
          logLine(
            '[p10ransac] scene=$key AUCUNE hypothèse valide '
            '(rawL=${rawL.length} rawR=${rawR.length}, toutes paires '
            'parallèles ou absence de diagonales) verdict=not_usable',
          );
          final jsonMap = {
            'scene': key,
            'imagePath': imgPath,
            'rawDiagonalCounts': {'left': rawL.length, 'right': rawR.length},
            'cappedDiagonalCounts': {
              'left': cappedLCount,
              'right': cappedRCount,
            },
            'vpTruncated4x4DiagonalCounts': {
              'left': vpTruncL,
              'right': vpTruncR,
            },
            'inlierDistThreshold': kInlierDistThreshold,
            'bestVP': null,
            'inlierCount': 0,
            'inlierRatio': 0.0,
            'radialMAD': null,
            'maxResidual': null,
            'selectedLines': [],
            'rejectedLines': [],
            'verdict': 'not_usable',
            'survivingVerticalsAfterFix': {
              'count': verticalsCapped.length,
              'medianXPctLeft': vLeftMedianX.isNaN ? null : vLeftMedianX,
              'medianXPctRight': vRightMedianX.isNaN ? null : vRightMedianX,
            },
            'randomWitness': randomWitnessJson,
          };
          File('/tmp/p10_ransac_vp_$key.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(jsonMap),
          );
          continue;
        }

        final medianDist = _median(bestDistances);
        final radialMad = _mad(bestDistances, medianDist);
        final maxResidual = bestDistances.isEmpty
            ? 0.0
            : bestDistances.reduce(math.max);
        final inlierRatio = totalDiagCount == 0
            ? 0.0
            : bestInlierCount / totalDiagCount;

        // Reconversion en pct image d'origine (x est déjà une fraction
        // de largeur, y était en fraction de largeur -> on divise par hw
        // pour revenir en fraction de hauteur, cohérent avec `xPct`/
        // `yPct` utilisés partout ailleurs dans le pipeline).
        final bestVpXPct = bestVp.x;
        final bestVpYPct = bestVp.y / hw;

        final vpInBounds =
            bestVpXPct >= kVpBoundLow &&
            bestVpXPct <= kVpBoundHigh &&
            bestVpYPct >= kVpBoundLow &&
            bestVpYPct <= kVpBoundHigh;

        String verdict;
        if (bestInlierCount >= kUsableMinInliers &&
            inlierRatio >= kUsableMinInlierRatio &&
            radialMad <= kUsableMaxRadialMad &&
            vpInBounds) {
          verdict = 'usable';
        } else if (bestInlierCount >= kWeakMinInliers &&
            radialMad <= kWeakMaxRadialMad) {
          verdict = 'weak';
        } else {
          verdict = 'not_usable';
        }

        // rejectedLines = diagonales NON retenues comme inliers de la
        // meilleure hypothèse (parmi l'ensemble complet rawL+rawR).
        final inlierSet = bestInlierLines.toSet();
        final rejectedLines = allDiags
            .where((l) => !inlierSet.contains(l))
            .toList();

        logLine(
          '[p10ransac] scene=$key rawL=${rawL.length} rawR=${rawR.length} '
          'cappedL=$cappedLCount cappedR=$cappedRCount '
          'vpTrunc4x4L=$vpTruncL vpTrunc4x4R=$vpTruncR '
          'hypotheses=${rawL.length * rawR.length} '
          'bestVP=(${bestVpXPct.toStringAsFixed(4)}, '
          '${bestVpYPct.toStringAsFixed(4)}) '
          'inlierCount=$bestInlierCount inlierRatio='
          '${inlierRatio.toStringAsFixed(4)} '
          'radialMAD=${radialMad.toStringAsFixed(4)} (CIRCULAIRE, ne pas '
          'utiliser comme critere) '
          'maxResidual=${maxResidual.toStringAsFixed(4)} (CIRCULAIRE, ne '
          'pas utiliser comme critere) '
          'verdict=$verdict',
        );
        logLine(
          '[p10ransac][witness-vs-ransac] scene=$key '
          'bestInlierCount(RANSAC)=$bestInlierCount vs '
          'medianInliers(temoin)=${randomMedian.toStringAsFixed(2)} vs '
          'p95Inliers(temoin)=${randomP95.toStringAsFixed(2)} -> '
          '${bestInlierCount > randomP95 ? "RANSAC bat le p95 aleatoire" : bestInlierCount > randomMedian ? "RANSAC bat la mediane mais pas le p95 aleatoire" : "RANSAC NE BAT PAS le temoin aleatoire"}',
        );
        logLine(
          '[p10ransac] scene=$key verticalsAfterFix='
          '${verticalsCapped.length} medianXPctLeft='
          '${vLeftMedianX.isNaN ? "n/a" : vLeftMedianX.toStringAsFixed(4)} '
          'medianXPctRight='
          '${vRightMedianX.isNaN ? "n/a" : vRightMedianX.toStringAsFixed(4)} '
          '(nLeft=${vLeftXs.length} nRight=${vRightXs.length})',
        );

        final jsonMap = {
          'scene': key,
          'imagePath': imgPath,
          'rawDiagonalCounts': {'left': rawL.length, 'right': rawR.length},
          'cappedDiagonalCounts': {
            'left': cappedLCount,
            'right': cappedRCount,
          },
          'vpTruncated4x4DiagonalCounts': {
            'left': vpTruncL,
            'right': vpTruncR,
          },
          'hypothesesGenerated': rawL.length * rawR.length,
          'inlierDistThreshold': kInlierDistThreshold,
          'bestVP': {'xPct': bestVpXPct, 'yPct': bestVpYPct},
          'inlierCount': bestInlierCount,
          'totalDiagonalCount': totalDiagCount,
          'inlierRatio': inlierRatio,
          'radialMAD': radialMad,
          'radialMAD_WARNING':
              'CIRCULAIRE : calcule uniquement sur les inliers deja '
              'selectionnes par inlierDistThreshold, borne par construction '
              '<= inlierDistThreshold. Ne pas utiliser comme critere de '
              'qualite/decision.',
          'maxResidual': maxResidual,
          'maxResidual_WARNING':
              'CIRCULAIRE : borne par construction <= inlierDistThreshold '
              '(meme raison que radialMAD_WARNING). Ne pas utiliser comme '
              'critere de qualite/decision.',
          'vpInBounds': vpInBounds,
          'randomWitness': randomWitnessJson,
          'selectedLines': [
            for (var i = 0; i < bestInlierLines.length; i++)
              _lineToReportJson(bestInlierLines[i], bestDistances[i]),
          ],
          'rejectedLines': [
            for (final l in rejectedLines)
              _lineToReportJson(l, _pointToLineDist(bestVp, l)),
          ],
          'verdict': verdict,
          'survivingVerticalsAfterFix': {
            'count': verticalsCapped.length,
            'medianXPctLeft': vLeftMedianX.isNaN ? null : vLeftMedianX,
            'medianXPctRight': vRightMedianX.isNaN ? null : vRightMedianX,
            'nLeft': vLeftXs.length,
            'nRight': vRightXs.length,
          },
        };
        final outPath = '/tmp/p10_ransac_vp_$key.json';
        File(outPath).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(jsonMap),
        );
        logLine('[p10ransac] scene=$key fichier_json=$outPath');
      }

      final outTxt = '/tmp/p10_ransac_vp.txt';
      File(outTxt).writeAsStringSync(summaryLines.join('\n'));
      // ignore: avoid_print
      print('[p10ransac] resume_ecrit=$outTxt');

      // Aucun expect qui échoue : instrument de mesure, jamais rouge par
      // construction, exactement comme P9a/P9b/P9c/P10/P10bis.
      expect(true, isTrue);
    },
  );
}
