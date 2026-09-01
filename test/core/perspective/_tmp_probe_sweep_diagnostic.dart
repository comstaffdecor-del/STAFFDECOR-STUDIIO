// SONDE JETABLE — diagnostic relecture externe #2, anomalie -78.0px.
// Balaye delta sur wallTL.yPct/wallTR.yPct (symétrique, comme le test de
// falsification commité) et journalise À CHAQUE PAS : les coordonnées
// effectives wallTL/wallTR/fTL/fTR utilisées, vpTop==null, vpBottom==null,
// residualPx, residualFrac, dy, dy/pH — pour trancher entre bug de sonde,
// vpTop==null (repli sur vpBottom), ou autre cause.
// À SUPPRIMER après usage — ne pas committer.
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/calib_canvas.dart';
import 'package:staff_decor_studio/core/perspective/persp_geometry.dart';
import 'package:staff_decor_studio/core/perspective/vanishing_point.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

const double kCanvasW = 1400.0;
const double kCanvasH = 975.0;

const Map<String, (double, double)> kDemoSceneNativeSize = {
  'haussmann': (2560.0, 1783.0),
  'moderne': (1960.0, 1470.0),
  'provencal': (2560.0, 1707.0),
  'scandinave': (1920.0, 1088.0),
};

ImgDraw imgDrawFor(double srcW, double srcH) {
  final scale = (kCanvasW / srcW < kCanvasH / srcH) ? kCanvasW / srcW : kCanvasH / srcH;
  final dw = srcW * scale, dh = srcH * scale;
  return ImgDraw(scale: scale, dw: dw, dh: dh, dx: (kCanvasW - dw) / 2, dy: (kCanvasH - dh) / 2);
}

void main() {
  for (final key in kDemoSceneNativeSize.keys) {
    test('SWEEP $key', () {
      final base = PerspCalib.forDemoScene(key);
      final (srcW, srcH) = kDemoSceneNativeSize[key]!;
      final imgDraw = imgDrawFor(srcW, srcH);

      print('=== SWEEP preset=$key ===');
      for (int i = -5; i <= 5; i++) {
        final delta = i * 0.01;
        final calib = base.copyWith(
          wallTL: base.wallTL.copyWith(yPct: base.wallTL.yPct + delta),
          wallTR: base.wallTR.copyWith(yPct: base.wallTR.yPct + delta),
        );
        final cp = CalibCanvasPoints.fromCalib(calib, imgDraw: imgDraw, w: kCanvasW, h: kCanvasH);

        // Recalcul manuel vpTop/vpBottom pour observer directement les
        // branches internes de VanishingPoint.compute (mêmes couples).
        final vpTop = lineIntersect(cp.wallTL, cp.ceilL, cp.wallTR, cp.ceilR);
        final vpBottom = lineIntersect(cp.wallBL, cp.floorL, cp.wallBR, cp.floorR);

        final vp = VanishingPoint.compute(
          fTL: cp.ceilL, fTR: cp.ceilR, fBL: cp.floorL, fBR: cp.floorR,
          wallTL: cp.wallTL, wallTR: cp.wallTR, wallBL: cp.wallBL, wallBR: cp.wallBR,
        );
        final wallCenterY = (cp.ceilL.dy + cp.ceilR.dy + cp.floorL.dy + cp.floorR.dy) / 4;
        final dy = (vp.vp.dy - wallCenterY).abs();
        final dyOverPh = dy / vp.pH;

        print('delta=${delta.toStringAsFixed(2)}  '
            'wallTL=${cp.wallTL}  wallTR=${cp.wallTR}  '
            'ceilL(fTL)=${cp.ceilL}  ceilR(fTR)=${cp.ceilR}  '
            'vpTop=${vpTop == null ? "NULL" : vpTop}  '
            'vpBottom=${vpBottom == null ? "NULL" : vpBottom}  '
            'vp.vp=${vp.vp}  residualPx=${vp.residualPx}  '
            'residualFrac=${vp.residualFrac}  dy=${dy.toStringAsFixed(4)}  '
            'dy/pH=${dyOverPh.toStringAsFixed(6)}');
      }
    });
  }
}
