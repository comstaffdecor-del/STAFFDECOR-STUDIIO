// P9b — décomposition signée dx/dy de l'écart entre la calibration
// détectée automatiquement (`detectRoomEdges`,
// `lib/core/perspective/edge_detect.dart`) et la calibration de vérité
// terrain (`PerspCalib.forDemoScene`, `lib/models/persp_calib.dart`,
// calée à la main) sur les 4 photos de scènes démo
// (`assets/demo_scenes/<key>.jpg`).
//
// Permanent (PAS un *_tmp_*). Aucun `expect` qui échoue : instrument de
// mesure, pas un test de non-régression.
//
// Arbitrage Cas A / Cas B (Bloc 1-bis, brief 9b) : la détection PRODUIT
// les 4 points `wall*` (`wallTL`/`wallTR`/`wallBL`/`wallBR`) —
// `edge_detect.dart:597-600` les affecte via des formules calculées
// (`wallTopYPct = clamp01(ceilYPct * 0.5)`, `wallBotYPct =
// clamp01(floorYPct + (1 - floorYPct) * 0.5)`, lignes 589-590), pas un
// pass-through de valeurs fixes. Cas B retenu : décomposition sur les 8
// points, écart de point de fuite calculé avec les `wall*` DÉTECTÉS
// d'un côté, ceux du PRESET de l'autre.
//
// Formule de conversion, reproduite depuis `CalibCanvasPoints.fromCalib`
// (`lib/core/perspective/calib_canvas.dart:38-46`), branche
// `imgDraw == null`, jamais inventée : `Offset(p.xPct * w, p.yPct * h)`.
//
// Écart du point de fuite : `lineIntersect(wallTL, fTL, wallTR, fTR)`
// pour vpTop, `lineIntersect(wallBL, fBL, wallBR, fBR)` pour vpBottom
// (`vanishing_point.dart:246-247`), appelés directement — jamais via
// `VanishingPoint.compute` — pour obtenir les deux intersections
// séparément, pas la position fusionnée.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/calib_canvas.dart';
import 'package:staff_decor_studio/core/perspective/edge_detect.dart';
import 'package:staff_decor_studio/core/perspective/persp_geometry.dart'
    as pg;
import 'package:staff_decor_studio/models/persp_calib.dart';

const double kCanvasW = 1400.0;
const double kCanvasH = 975.0;

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

/// Reproduction exacte de `CalibCanvasPoints.fromCalib` (branche
/// `imgDraw == null`) : `Offset(p.xPct * w, p.yPct * h)` — voir
/// `lib/core/perspective/calib_canvas.dart:38-46`.
CalibCanvasPoints _toCanvasNoLetterbox(PerspCalib calib) {
  return CalibCanvasPoints.fromCalib(
    calib,
    imgDraw: null,
    w: kCanvasW,
    h: kCanvasH,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'P9b : décomposition signée dx/dy par point (8 pts, cas B) et écart '
    'du point de fuite',
    () async {
      for (final key in kPresetKeys) {
        final imgPath = 'assets/demo_scenes/$key.jpg';
        final file = File(imgPath);
        if (!file.existsSync()) {
          // ignore: avoid_print
          print('[p9b] preset=$key image introuvable path=$imgPath');
          continue;
        }

        final image = await _decodeImageFile(imgPath);
        final detected = await detectRoomEdges(image);
        image.dispose();

        if (detected == null) {
          // ignore: avoid_print
          print(
            '[p9b] preset=$key conf=null (detectRoomEdges a renvoyé null, '
            'aucun point disponible)',
          );
          continue;
        }

        final truth = PerspCalib.forDemoScene(key);
        final detCanvas = _toCanvasNoLetterbox(detected.calib);
        final refCanvas = _toCanvasNoLetterbox(truth);

        // --- Famille 1 : écart signé par point (8 points, cas B) ---
        final points = <String, (ui.Offset det, ui.Offset ref)>{
          'ceilL': (detCanvas.ceilL, refCanvas.ceilL),
          'ceilR': (detCanvas.ceilR, refCanvas.ceilR),
          'floorL': (detCanvas.floorL, refCanvas.floorL),
          'floorR': (detCanvas.floorR, refCanvas.floorR),
          'wallTL': (detCanvas.wallTL, refCanvas.wallTL),
          'wallTR': (detCanvas.wallTR, refCanvas.wallTR),
          'wallBL': (detCanvas.wallBL, refCanvas.wallBL),
          'wallBR': (detCanvas.wallBR, refCanvas.wallBR),
        };

        final calibPoints = <String, (CalibPoint det, CalibPoint ref)>{
          'ceilL': (detected.calib.ceilL, truth.ceilL),
          'ceilR': (detected.calib.ceilR, truth.ceilR),
          'floorL': (detected.calib.floorL, truth.floorL),
          'floorR': (detected.calib.floorR, truth.floorR),
          'wallTL': (detected.calib.wallTL, truth.wallTL),
          'wallTR': (detected.calib.wallTR, truth.wallTR),
          'wallBL': (detected.calib.wallBL, truth.wallBL),
          'wallBR': (detected.calib.wallBR, truth.wallBR),
        };

        double sumAbsDx = 0;
        double sumAbsDy = 0;
        final signsDy = <int>[];

        for (final ptName in points.keys) {
          final (detOff, refOff) = points[ptName]!;
          final (detCp, refCp) = calibPoints[ptName]!;

          final dx = detOff.dx - refOff.dx;
          final dy = detOff.dy - refOff.dy;
          final d = pg.dist(detOff, refOff);

          sumAbsDx += dx.abs();
          sumAbsDy += dy.abs();
          if (dy > 0) {
            signsDy.add(1);
          } else if (dy < 0) {
            signsDy.add(-1);
          } else {
            signsDy.add(0);
          }

          // ignore: avoid_print
          print(
            '[p9b] preset=$key pt=$ptName '
            'det_xPct=${detCp.xPct.toStringAsFixed(6)} '
            'det_yPct=${detCp.yPct.toStringAsFixed(6)} '
            'ref_xPct=${refCp.xPct.toStringAsFixed(6)} '
            'ref_yPct=${refCp.yPct.toStringAsFixed(6)} '
            'dx=${dx.toStringAsFixed(4)} dy=${dy.toStringAsFixed(4)} '
            'd=${d.toStringAsFixed(4)}',
          );
        }

        // --- Famille 2 : synthèse par scène ---
        final dominante = sumAbsDx >= sumAbsDy ? 'x' : 'y';
        final allSame = signsDy.every((s) => s == signsDy.first);
        final signeDy = allSame
            ? (signsDy.first > 0
                  ? '+'
                  : (signsDy.first < 0 ? '-' : 'mixte'))
            : 'mixte';

        // ignore: avoid_print
        print(
          '[p9b] preset=$key conf=${detected.confidence.toStringAsFixed(4)} '
          'sum_abs_dx=${sumAbsDx.toStringAsFixed(4)} '
          'sum_abs_dy=${sumAbsDy.toStringAsFixed(4)} '
          'dominante=$dominante signe_dy=$signeDy',
        );

        // --- Famille 3 : écart du point de fuite ---
        // vpTop/vpBottom DÉTECTÉS : wall* détectés + f* détectés.
        final vpTopDet = pg.lineIntersect(
          detCanvas.wallTL,
          detCanvas.ceilL,
          detCanvas.wallTR,
          detCanvas.ceilR,
        );
        final vpBottomDet = pg.lineIntersect(
          detCanvas.wallBL,
          detCanvas.floorL,
          detCanvas.wallBR,
          detCanvas.floorR,
        );
        // vpTop/vpBottom de RÉFÉRENCE : wall*/f* du preset.
        final vpTopRef = pg.lineIntersect(
          refCanvas.wallTL,
          refCanvas.ceilL,
          refCanvas.wallTR,
          refCanvas.ceilR,
        );
        final vpBottomRef = pg.lineIntersect(
          refCanvas.wallBL,
          refCanvas.floorL,
          refCanvas.wallBR,
          refCanvas.floorR,
        );

        final dVpTop = (vpTopDet != null && vpTopRef != null)
            ? pg.dist(vpTopDet, vpTopRef)
            : null;
        final dVpBottom = (vpBottomDet != null && vpBottomRef != null)
            ? pg.dist(vpBottomDet, vpBottomRef)
            : null;

        String fmtOffset(ui.Offset? o) =>
            o == null ? 'null' : '${o.dx.toStringAsFixed(4)},${o.dy.toStringAsFixed(4)}';

        // ignore: avoid_print
        print(
          '[p9b] preset=$key '
          'd_vpTop=${dVpTop == null ? 'null' : dVpTop.toStringAsFixed(4)} '
          'd_vpBottom=${dVpBottom == null ? 'null' : dVpBottom.toStringAsFixed(4)} '
          'vpTop_det=${fmtOffset(vpTopDet)} vpTop_ref=${fmtOffset(vpTopRef)} '
          'vpBottom_det=${fmtOffset(vpBottomDet)} '
          'vpBottom_ref=${fmtOffset(vpBottomRef)}',
        );
      }

      // Aucun expect : instrument de mesure, jamais de rouge par
      // construction.
      expect(true, isTrue);
    },
  );
}
