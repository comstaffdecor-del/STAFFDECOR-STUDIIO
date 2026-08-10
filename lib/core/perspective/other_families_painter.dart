/// Rendu des familles restantes : Lambris, Parements, Colonnes,
/// Rosaces (peintre plafond — anciennement nommé "Encadrements"), Ornements.
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

/// ── Rosace (rebaptisée depuis `paintEncadrement`, retour utilisateur :
/// le nom "Encadrement" — cadre mural — ne correspondait pas au rendu
/// réellement produit) : ellipse concentrique + rayons, TOUJOURS dans la
/// zone PLAFOND visible de l'image (entre le haut de l'image et l'arête
/// plafond/mur, jamais sur le mur du fond) — position [xPct] dans la
/// largeur de l'image.
///
/// PASSAGE AU PEINTRE PLAFOND : ce renommage acte explicitement que cette
/// fonction est — et a toujours été, cf. `ceilMidY` ci-dessous — le peintre
/// de la famille "plafond" (rosaces, plafonniers), par opposition aux
/// peintres "mur" (Lambris, Parements, Colonnes, Ornements) du même
/// fichier. Le calcul de position reste la même approximation 2D par
/// [VanishingPoint] (pas encore raccordé au plan 3D `ceilingPlane` de
/// `calib_to_camera.dart`/`sweep.dart` utilisé par le pipeline de rendu
/// photo-réaliste — ce raccordement dépasserait la portée du présent
/// renommage et n'a pas été demandé). ──
void paintRosace(
  Canvas canvas,
  VanishingPoint vp, {
  required double xPct,
  required Color color,
  required double imgTop,
  required double imgLeft,
  required double imgW,
}) {
  // Zone PLAFOND (jamais mur) : entre le haut de l'image (imgTop) et
  // l'arête plafond/mur (vp.fTL.dy) — c'est la définition même du
  // "peintre plafond".
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

/// ── Ornements : pièce sculptée unique (modillon, fleur de trumeau...)
/// posée sur le mur, position libre (xPct horizontal, snapLine pour la
/// hauteur verticale).
///
/// ⚠️ CORRECTION Bug "aucune ornementation" (retour utilisateur : "aucune
/// ornementation [visible]") — l'ancien rendu traçait UNIQUEMENT un
/// contour fin (`strokeWidth: 2`, `PaintingStyle.stroke`, sans aucun
/// remplissage) d'une forme abstraite minuscule (`canvasW * 0.040`, soit
/// ~4% de la largeur, quelques dizaines de px) dans une couleur quasi
/// blanche (`famColors['Ornements'] = 0xFFF0EDE8`) à 80% d'opacité —
/// vérifié : sur la plupart des photos (murs clairs, fenêtres, ciel), ce
/// motif devient indiscernable à l'oeil (confirmé par diff pixel-à-pixel :
/// seule une différence de quelques niveaux de gris sur ~45×40px, aucune
/// forme perceptible en observation directe du rendu).
///
/// Comme pour Corniches/Plinthes (voir [ProductTextureCache]), on mappe
/// désormais la VRAIE photo produit staffdecor.fr dans une plaque
/// arrondie avec ombre de contact — une pièce d'ornement plaquée au mur,
/// pas une silhouette procédurale générique. Si la photo n'est pas
/// encore chargée (ou échec réseau), le fallback procédural est
/// nettement plus visible : plaque REMPLIE (pas juste un contour), 2.6x
/// plus grande, contour sombre net + reflet clair pour un effet de
/// relief perceptible sur n'importe quel fond.
void paintOrnement(
  Canvas canvas,
  VanishingPoint vp, {
  required double xPct,
  required String snapLine,
  required Color color,
  required double imgLeft,
  required double imgW,
  required double canvasW,
  Image? texture,
}) {
  final oX = imgLeft + xPct * imgW;
  final tOY = snapLine == 'ceiling' ? 0.15 : (snapLine == 'floor' ? 0.70 : 0.48);
  final oY = vp.fTL.dy + (vp.fBL.dy - vp.fTL.dy) * tOY;

  // Taille de plaque perçue ~2.6x l'ancienne (0.040 → 0.105), cohérente
  // avec une pièce décorative posée (comparable à une petite rosace).
  final oS = canvasW * 0.105;
  final rectW = oS * 2;
  final rectH = oS * 2 * 1.15;
  final rect = Rect.fromCenter(center: Offset(oX, oY), width: rectW, height: rectH);
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(oS * 0.35));

  // Ombre de contact douce — détache visuellement la pièce du mur (sans
  // quoi même une plaque bien rendue reste "plate"/peu perceptible).
  canvas.drawRRect(
    rrect.shift(const Offset(0, 3)),
    Paint()
      ..color = const Color(0x552A2016)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
  );

  if (texture != null) {
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFFFCFAF6));

    // Recadrage "cover" manuel (équivalent BoxFit.cover) : on garde le
    // centre de la photo produit et on rogne l'excédent selon le ratio
    // de la plaque, pour éviter tout étirement déformant.
    final texW = texture.width.toDouble();
    final texH = texture.height.toDouble();
    final targetAspect = rectW / rectH;
    final texAspect = texW / texH;
    Rect src;
    if (texAspect > targetAspect) {
      final cropW = texH * targetAspect;
      src = Rect.fromLTWH((texW - cropW) / 2, 0, cropW, texH);
    } else {
      final cropH = texW / targetAspect;
      src = Rect.fromLTWH(0, (texH - cropH) / 2, texW, cropH);
    }
    canvas.drawImageRect(texture, src, rect, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xCCFFFFFF)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0x99413426)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
    return;
  }

  // ── Fallback procédural (photo pas encore chargée / échec réseau). ──
  canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.97));
  canvas.drawRRect(
    rrect,
    Paint()
      ..color = const Color(0x99413426)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke,
  );

  final leafS = oS * 0.62;
  final path1 = Path()
    ..moveTo(oX, oY - leafS)
    ..cubicTo(oX + leafS * 0.8, oY - leafS * 0.4, oX + leafS, oY + leafS * 0.4, oX, oY + leafS * 0.2)
    ..cubicTo(oX - leafS, oY + leafS * 0.4, oX - leafS * 0.8, oY - leafS * 0.4, oX, oY - leafS);
  final path2 = Path()
    ..moveTo(oX - leafS * 0.5, oY - leafS * 0.5)
    ..cubicTo(
      oX - leafS * 0.2,
      oY + leafS * 0.3,
      oX + leafS * 0.2,
      oY + leafS * 0.3,
      oX + leafS * 0.5,
      oY - leafS * 0.5,
    );

  // Trait sombre net (structure) + fin reflet clair décalé (relief perçu).
  final darkStroke = Paint()
    ..color = const Color(0xD9413426)
    ..strokeWidth = 2.6
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final lightStroke = Paint()
    ..color = const Color(0xF2FFFFFF)
    ..strokeWidth = 1.1
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  canvas.drawPath(path1, darkStroke);
  canvas.drawPath(path2, darkStroke);
  canvas.save();
  canvas.translate(-0.8, -0.8);
  canvas.drawPath(path1, lightStroke);
  canvas.drawPath(path2, lightStroke);
  canvas.restore();
}


