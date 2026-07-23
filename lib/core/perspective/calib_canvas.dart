/// Conversion calibration (% image) → coordonnées canvas.
///
/// Port fidèle de `pctToCanvas` (dupliquée à l'identique 3 fois dans
/// l'original : `_drawArchitectureOnRoomCanvas`, `renderProductOnPhoto`,
/// et implicitement dans `_drawSliderCornicePlinth` via imgDraw) —
/// centralisée ici en un seul point (contribue à corriger le Bug #5).
library;

import 'dart:ui';
import '../../models/persp_calib.dart';

/// Regroupe les 8 points de calibration convertis en coordonnées canvas,
/// prêts à consommer par le moteur de perspective.
class CalibCanvasPoints {
  final Offset ceilL, ceilR, floorL, floorR;
  final Offset wallTL, wallTR, wallBL, wallBR;

  const CalibCanvasPoints({
    required this.ceilL,
    required this.ceilR,
    required this.floorL,
    required this.floorR,
    required this.wallTL,
    required this.wallTR,
    required this.wallBL,
    required this.wallBR,
  });

  /// [imgDraw] = géométrie "contain" de la photo affichée (letterboxing).
  /// Si `null`, les % sont interprétés directement en fraction de (w, h)
  /// — cas "zone sans canvas dimensionné" de l'original.
  factory CalibCanvasPoints.fromCalib(
    PerspCalib calib, {
    required ImgDraw? imgDraw,
    required double w,
    required double h,
  }) {
    Offset toCanvas(CalibPoint p) {
      if (imgDraw != null) {
        return Offset(
          imgDraw.dx + p.xPct * imgDraw.dw,
          imgDraw.dy + p.yPct * imgDraw.dh,
        );
      }
      return Offset(p.xPct * w, p.yPct * h);
    }

    return CalibCanvasPoints(
      ceilL: toCanvas(calib.ceilL),
      ceilR: toCanvas(calib.ceilR),
      floorL: toCanvas(calib.floorL),
      floorR: toCanvas(calib.floorR),
      wallTL: toCanvas(calib.wallTL),
      wallTR: toCanvas(calib.wallTR),
      wallBL: toCanvas(calib.wallBL),
      wallBR: toCanvas(calib.wallBR),
    );
  }
}
