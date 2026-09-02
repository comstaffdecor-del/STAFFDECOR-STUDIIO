// Sonde de mesure versionnée (remplace un script jetable /tmp) — imprime,
// pour les 4 presets démo, l'ImgDraw réel (dx,dy,dw,dh,scale) calculé par
// imgDrawFor (réplique exacte de computeImgDraw pour canevas 1400x975) et
// le distVp EFFECTIF produit par l'implémentation ACTUELLE (sur disque)
// de VanishingPoint.compute — quelle qu'elle soit à la date d'exécution.
//
// Exécution : flutter test tools/calib_measure/vp_current_state_probe.dart
// (ce fichier n'est pas un test au sens flutter_test — group()/test() sans
// assertion — il sert uniquement à produire une trace reproductible pour
// docs/logs/. Aucune assertion : il ne peut donc jamais faire échouer le
// pipeline de test ; il n'est pas un remplaçant de vp_frac_degenere_test.
//
// Ce script est LA source versionnée des chiffres ImgDraw/distVp cités
// dans docs/logs/rouge_vp_frac_degenere.txt — règle de provenance du
// brief "câblage du moteur géométrique réel", section 5 : plus aucun
// chiffre committé sans script producteur committé.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/calib_canvas.dart';
import 'package:staff_decor_studio/core/perspective/persp_geometry.dart' show dist;
import 'package:staff_decor_studio/core/perspective/strip_px_from_dims.dart';
import 'package:staff_decor_studio/core/perspective/vanishing_point.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

const double kCanvasW = 1400.0;
const double kCanvasH = 975.0;

ImgDraw imgDrawFor(double srcW, double srcH) {
  final scale = (kCanvasW / srcW < kCanvasH / srcH) ? kCanvasW / srcW : kCanvasH / srcH;
  final dw = srcW * scale;
  final dh = srcH * scale;
  return ImgDraw(
    dx: (kCanvasW - dw) / 2,
    dy: (kCanvasH - dh) / 2,
    dw: dw,
    dh: dh,
    scale: scale,
  );
}

const Map<String, (double, double)> kDemoSceneNativeSize = {
  'haussmann': (2560.0, 1783.0),
  'moderne': (1960.0, 1470.0),
  'provencal': (2560.0, 1707.0),
  'scandinave': (1920.0, 1088.0),
};

void main() {
  test('sonde: ImgDraw + distVp effectif par preset (VanishingPoint.compute actuel)', () {
    // ignore: avoid_print
    print('=== SONDE vp_current_state_probe — VanishingPoint.compute actuel sur disque ===');
    for (final key in kDemoSceneNativeSize.keys) {
      final calib = PerspCalib.forDemoScene(key);
      final (srcW, srcH) = kDemoSceneNativeSize[key]!;
      final imgDraw = imgDrawFor(srcW, srcH);
      final cp = CalibCanvasPoints.fromCalib(calib, imgDraw: imgDraw, w: kCanvasW, h: kCanvasH);
      final vp = VanishingPoint.compute(
        fTL: cp.ceilL,
        fTR: cp.ceilR,
        fBL: cp.floorL,
        fBR: cp.floorR,
        wallTL: cp.wallTL,
        wallTR: cp.wallTR,
        wallBL: cp.wallBL,
        wallBR: cp.wallBR,
        // Sonde de mesure du comportement ACTUEL — conservée sur le membre
        // historique pour continuer à observer exactement ce qu'elle
        // observait avant l'introduction de VpFallbackMode (Point 7b-1).
        fallbackMode: VpFallbackMode.repliHistoriqueCoupleBas,
      );
      final depthPx = corniceDefaultPx(vp.pH).faceHorizFondPx;
      final frac = vp.frac(cp.ceilL, depthPx);
      final vpDesc = vp.isAtInfinity
          ? 'infini(dir=(${vp.direction.dx.toStringAsFixed(4)}, ${vp.direction.dy.toStringAsFixed(4)}))'
          : '(${vp.vp.dx.toStringAsFixed(2)}, ${vp.vp.dy.toStringAsFixed(2)})';
      final distVp = vp.isAtInfinity ? double.infinity : dist(cp.ceilL, vp.vp);
      // ignore: avoid_print
      print(
        '$key : '
        'imgDraw(dx=${imgDraw.dx.toStringAsFixed(2)}, dy=${imgDraw.dy.toStringAsFixed(2)}, '
        'dw=${imgDraw.dw.toStringAsFixed(2)}, dh=${imgDraw.dh.toStringAsFixed(2)}, '
        'scale=${imgDraw.scale.toStringAsFixed(6)}) | '
        'vp=$vpDesc | '
        'pH=${vp.pH.toStringAsFixed(3)} | depthPx=${depthPx.toStringAsFixed(3)} | '
        'distVp=${distVp.toStringAsFixed(2)} | frac=${frac.toStringAsFixed(5)}',
      );
    }
    expect(true, isTrue); // sonde sans assertion de fond, ne doit jamais casser le suite
  });
}
