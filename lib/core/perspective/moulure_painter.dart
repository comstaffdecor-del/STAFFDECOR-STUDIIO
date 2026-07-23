/// Rendu des familles "moulure horizontale à hauteur variable" —
/// Moulures et Profils LED : une bande horizontale continue tracée sur
/// TOUTE la largeur de la scène (murs latéraux + fond), à une hauteur
/// définie par la snap line utilisateur.
///
/// Port fidèle de `case 'Moulures'` / `case 'Profils LED'` de
/// `renderProductOnPhoto` (studio.js), mais consommant désormais le
/// [VanishingPoint] RÉEL partagé au lieu d'un point de fuite recalculé
/// localement (Bug #5).
library;

import 'dart:ui';
import 'persp_geometry.dart';
import 'vanishing_point.dart';

/// Convertit une snap line en fraction t (0 = plafond, 1 = sol) le long
/// du mur — port exact des valeurs de l'ancien `case 'Moulures'`.
double snapLineToT(String snapLine) {
  switch (snapLine) {
    case 'ceiling':
      return 0.18;
    case 'floor':
      return 0.80;
    case 'lower-mid':
      return 0.62;
    default: // 'mid'
      return 0.45;
  }
}

/// Dessine une moulure fine en perspective entre deux points [a]→[b],
/// épaisseur dégressive [w1]→[w2] (perspective : plus fin au loin, plus
/// épais près de l'observateur). Port exact de `drawMoulure`.
void drawMoulureBand(
  Canvas canvas,
  Offset a,
  Offset b,
  Color color, {
  double w1 = 4,
  double w2 = 4,
  double glowBlur = 0,
}) {
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  final len = dist(a, b);
  if (len < 1) return;
  final nx = -dy / len, ny = dx / len;
  final h1 = w1 / 2, h2 = w2 / 2;
  final p0 = Offset(a.dx + nx * h1, a.dy + ny * h1);
  final p1 = Offset(b.dx + nx * h2, b.dy + ny * h2);
  final p2 = Offset(b.dx - nx * h2, b.dy - ny * h2);
  final p3 = Offset(a.dx - nx * h1, a.dy - ny * h1);

  final path = Path()
    ..moveTo(p0.dx, p0.dy)
    ..lineTo(p1.dx, p1.dy)
    ..lineTo(p2.dx, p2.dy)
    ..lineTo(p3.dx, p3.dy)
    ..close();

  final gdist = dist(p0, p3);
  final paint = Paint();
  if (gdist > 1) {
    paint.shader = Gradient.linear(p0, p3, [
      const Color(0xF2FFFFFF),
      color,
      color,
      const Color(0x4D504636),
    ], const [0.0, 0.15, 0.80, 1.0]);
  } else {
    paint.color = color;
  }
  if (glowBlur > 0) {
    paint.maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur);
  }
  canvas.drawPath(path, paint);

  // Liseré d'ombre portante sous la moulure.
  canvas.drawLine(
    p3,
    p2,
    Paint()
      ..color = const Color(0x38443A2E)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke,
  );
}

/// Dessine une bande Moulure/Profil LED continue (latéral G → fond →
/// latéral D) à la hauteur [t] (fraction 0..1 depuis le plafond).
///
/// [canvasW]/[canvasH] = dimensions totales du canvas (pour situer les
/// coins avant de la scène, équivalent de `cTL/cTR/cBL/cBR` de l'original).
/// [w1]/[w2] = épaisseurs fond/latéral, [glowBlur] > 0 pour un effet
/// lumineux (Profils LED).
void paintHorizontalBandSet(
  Canvas canvas,
  VanishingPoint vp, {
  required double t,
  required Color color,
  required double wFond,
  required double wLat,
  required double canvasW,
  required double canvasH,
  double glowBlur = 0,
}) {
  final mL = lerpPt(vp.fTL, vp.fBL, t);
  final mR = lerpPt(vp.fTR, vp.fBR, t);
  // Coins avant de la scène — bord gauche/droit du canvas, interpolés
  // verticalement entre haut (0) et bas (canvasH) à la fraction t.
  final frontL = Offset(0, canvasH * t);
  final frontR = Offset(canvasW, canvasH * t);

  drawMoulureBand(canvas, mL, mR, color, w1: wFond, w2: wFond, glowBlur: glowBlur);
  drawMoulureBand(canvas, frontL, mL, color, w1: wLat, w2: wFond, glowBlur: glowBlur);
  drawMoulureBand(canvas, mR, frontR, color, w1: wFond, w2: wLat, glowBlur: glowBlur);
}
