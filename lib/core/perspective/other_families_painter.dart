/// Rendu des familles restantes : Lambris, Parements, Colonnes,
/// Encadrements (rosaces plafond), Ornements.
///
/// Port fidèle de leurs `case` respectifs dans `renderProductOnPhoto`
/// (studio.js), consommant le [VanishingPoint] partagé unique — corrige
/// le Bug #5 (unification des moteurs) et le Bug #6 (fallback xPct
/// centralisé via [famRatioFallback]/[famSnapDefault] au lieu de
/// logiques dupliquées par famille).
library;

import 'dart:math' as math;
import 'dart:ui';
import 'persp_geometry.dart';
import 'vanishing_point.dart';

/// ── Lambris : aplat semi-transparent bas de mur + ligne de finition. ──
void paintLambris(
  Canvas canvas,
  VanishingPoint vp, {
  required String snapLine,
  required Color color,
}) {
  final tL = snapLine == 'mid' ? 0.50 : (snapLine == 'lower-mid' ? 0.60 : 0.68);
  final lTop = lerpPt(vp.fTL, vp.fBL, tL);
  final lTopR = lerpPt(vp.fTR, vp.fBR, tL);

  final path = Path()
    ..moveTo(lTop.dx, lTop.dy)
    ..lineTo(lTopR.dx, lTopR.dy)
    ..lineTo(vp.fBR.dx, vp.fBR.dy)
    ..lineTo(vp.fBL.dx, vp.fBL.dy)
    ..close();
  canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.28));

  canvas.drawLine(
    lTop,
    lTopR,
    Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke,
  );
}

/// ── Parements : mur du fond avec joints pierre/brique. ──
void paintParements(
  Canvas canvas,
  VanishingPoint vp, {
  required Color color,
}) {
  final path = Path()
    ..moveTo(vp.fTL.dx, vp.fTL.dy)
    ..lineTo(vp.fTR.dx, vp.fTR.dy)
    ..lineTo(vp.fBR.dx, vp.fBR.dy)
    ..lineTo(vp.fBL.dx, vp.fBL.dy)
    ..close();
  canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));

  final jointPaint = Paint()
    ..color = const Color(0xB38C7A5A)
    ..strokeWidth = 1.2
    ..style = PaintingStyle.stroke;
  const nRows = 6;
  for (var i = 1; i < nRows; i++) {
    final t = i / nRows;
    final pL = lerpPt(vp.fTL, vp.fBL, t);
    final pR = lerpPt(vp.fTR, vp.fBR, t);
    canvas.drawLine(pL, pR, jointPaint);
  }

  final vJointPaint = Paint()
    ..color = const Color(0xB38C7A5A)
    ..strokeWidth = 0.8
    ..style = PaintingStyle.stroke;
  const nCols = 4;
  for (var row = 0; row <= nRows; row++) {
    final t0 = row / nRows, t1 = (row + 1) / nRows;
    final offset = row % 2 == 0 ? 0.0 : 0.5;
    for (var col = 0; col < nCols; col++) {
      final xf = (col + offset) / nCols;
      if (xf <= 0 || xf >= 1) continue;
      final pT = lerpPt(lerpPt(vp.fTL, vp.fTR, xf), lerpPt(vp.fBL, vp.fBR, xf), t0);
      final pB = lerpPt(lerpPt(vp.fTL, vp.fTR, xf), lerpPt(vp.fBL, vp.fBR, xf), t1);
      canvas.drawLine(pT, pB, vJointPaint);
    }
  }
}

/// ── Colonnes : fût cylindrique + chapiteau + base, placé sur le mur du
/// fond à la position [xPct] (fraction horizontale entre fTL et fTR). ──
void paintColonne(
  Canvas canvas,
  VanishingPoint vp, {
  required double xPct,
  required Color color,
}) {
  final colT = lerpPt(vp.fTL, vp.fTR, xPct);
  final colB = lerpPt(vp.fBL, vp.fBR, xPct);
  final fondW = vp.fTR.dx - vp.fTL.dx;
  final colW = fondW * 0.040;
  final colH = colB.dy - colT.dy;
  if (colH < 5) return;

  final shaftPaint = Paint()
    ..shader = Gradient.linear(
      Offset(colT.dx - colW, 0),
      Offset(colT.dx + colW, 0),
      [
        const Color(0xD9A09690),
        color,
        const Color(0xF2FFFFFF),
        color,
        const Color(0xCC968C82),
      ],
      const [0.0, 0.25, 0.55, 0.80, 1.0],
    );
  canvas.drawRect(
    Rect.fromLTWH(colT.dx - colW, colT.dy, colW * 2, colH),
    shaftPaint,
  );

  final capH = colH * 0.08 < 6 ? 6.0 : colH * 0.08;
  final capPaint = Paint()..color = color;
  final strokePaint = Paint()
    ..color = const Color(0x66504636)
    ..strokeWidth = 0.8
    ..style = PaintingStyle.stroke;

  final capRectTop = Rect.fromLTWH(colT.dx - colW * 1.8, colT.dy, colW * 3.6, capH);
  canvas.drawRect(capRectTop, capPaint);
  canvas.drawRect(capRectTop, strokePaint);

  final capRectBot = Rect.fromLTWH(colT.dx - colW * 1.8, colB.dy - capH, colW * 3.6, capH);
  canvas.drawRect(capRectBot, capPaint);
  canvas.drawRect(capRectBot, strokePaint);

  final flutePaint = Paint()
    ..color = const Color(0x1E504636)
    ..strokeWidth = 0.6
    ..style = PaintingStyle.stroke;
  for (var i = 1; i < 5; i++) {
    final cx = colT.dx - colW + (colW * 2 * i / 5);
    canvas.drawLine(
      Offset(cx, colT.dy + capH),
      Offset(cx, colB.dy - capH),
      flutePaint,
    );
  }
}

/// ── Encadrements (rosaces) : ellipse concentrique dans la zone plafond
/// visible (entre le haut de l'image et l'arête plafond/mur), position
/// [xPct] dans la largeur de l'image. ──
void paintEncadrement(
  Canvas canvas,
  VanishingPoint vp, {
  required double xPct,
  required Color color,
  required double imgTop,
  required double imgLeft,
  required double imgW,
}) {
  final ceilMidY = imgTop + (vp.fTL.dy - imgTop) * 0.55;
  final rX = imgLeft + xPct * imgW;
  final rY = ceilMidY;
  final ceilH = (vp.fTL.dy - imgTop).abs() < 10 ? 10.0 : (vp.fTL.dy - imgTop).abs();
  final rx = (imgW * 0.30) < (ceilH * 1.2) ? imgW * 0.30 : ceilH * 1.2;
  final ry = rx * 0.45;
  if (rx < 6) return;

  canvas.drawOval(
    Rect.fromCenter(center: Offset(rX, rY), width: rx * 2, height: ry * 2),
    Paint()..color = color.withValues(alpha: 0.08),
  );

  for (final entry in const [
    (1.0, 2.8, 0.85),
    (0.72, 1.8, 0.65),
    (0.50, 1.2, 0.65),
    (0.28, 1.2, 0.65),
  ]) {
    final (s, lw, alpha) = entry;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(rX, rY), width: rx * 2 * s, height: ry * 2 * s),
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = lw
        ..style = PaintingStyle.stroke,
    );
  }

  final rayPaint = Paint()
    ..color = color.withValues(alpha: 0.55)
    ..strokeWidth = 1;
  for (var a = 0; a < 12; a++) {
    final angle = (a / 12) * math.pi * 2;
    final cosA = math.cos(angle), sinA = math.sin(angle);
    canvas.drawLine(
      Offset(rX + cosA * rx * 0.18, rY + sinA * ry * 0.18),
      Offset(rX + cosA * rx * 0.90, rY + sinA * ry * 0.90),
      rayPaint,
    );
  }

  canvas.drawCircle(Offset(rX, rY), 3.5, Paint()..color = color.withValues(alpha: 0.85));
}

/// ── Ornements : motif feuille d'acanthe simplifié, position libre sur
/// le mur (xPct horizontal, snapLine pour la hauteur verticale). ──
void paintOrnement(
  Canvas canvas,
  VanishingPoint vp, {
  required double xPct,
  required String snapLine,
  required Color color,
  required double imgLeft,
  required double imgW,
  required double canvasW,
}) {
  final oX = imgLeft + xPct * imgW;
  final tOY = snapLine == 'ceiling' ? 0.15 : (snapLine == 'floor' ? 0.70 : 0.48);
  final oY = vp.fTL.dy + (vp.fBL.dy - vp.fTL.dy) * tOY;
  final oS = canvasW * 0.040;

  final paint = Paint()
    ..color = color.withValues(alpha: 0.80)
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  final path1 = Path()
    ..moveTo(oX, oY - oS)
    ..cubicTo(oX + oS * 0.8, oY - oS * 0.4, oX + oS, oY + oS * 0.4, oX, oY + oS * 0.2)
    ..cubicTo(oX - oS, oY + oS * 0.4, oX - oS * 0.8, oY - oS * 0.4, oX, oY - oS);
  canvas.drawPath(path1, paint);

  final path2 = Path()
    ..moveTo(oX - oS * 0.5, oY - oS * 0.5)
    ..cubicTo(
      oX - oS * 0.2,
      oY + oS * 0.3,
      oX + oS * 0.2,
      oY + oS * 0.3,
      oX + oS * 0.5,
      oY - oS * 0.5,
    );
  canvas.drawPath(path2, paint);
}


