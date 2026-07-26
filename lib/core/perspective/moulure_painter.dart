/// Rendu des familles "moulure horizontale à hauteur variable" —
/// Moulures et Profils LED : une bande horizontale continue tracée sur
/// TOUTE la largeur de la scène (murs latéraux + fond), à une hauteur
/// définie par la snap line utilisateur.
///
/// Port fidèle de `case 'Moulures'` / `case 'Profils LED'` de
/// `renderProductOnPhoto` (studio.js), mais consommant désormais le
/// [VanishingPoint] RÉEL partagé au lieu d'un point de fuite recalculé
/// localement (Bug #5).
///
/// ⚠️ CORRECTION Bug #7 (retour utilisateur : "quel que soit le modèle,
/// le choix de la moulure ne s'incrémente ni sur la photo, ni sur la
/// vignette") — cette famille ne consommait JAMAIS la vraie photo produit
/// ([ProductTextureCache]), contrairement à Corniches/Plinthes/Ornements :
/// on dessinait toujours la même bande plate procédurale. [drawMoulureBand]
/// accepte désormais un [texture] optionnel, mappé sur le quadrilatère du
/// segment exactement comme [drawProfileFace] (profile_strip.dart) — même
/// pattern `Canvas.drawVertices` + `ImageShader` + `TileMode.repeated`.
library;

import 'dart:typed_data';
import 'dart:ui';
import 'persp_geometry.dart';
import 'vanishing_point.dart';

/// Matrice identité 4x4 — voir profile_strip.dart pour le détail.
final Float64List _kIdentityMatrix4 = Float64List.fromList([
  1, 0, 0, 0,
  0, 1, 0, 0,
  0, 0, 1, 0,
  0, 0, 0, 1,
]);

/// Cf. `_kMotifRepeatPx` dans profile_strip.dart — même calibration
/// empirique de répétition horizontale du motif.
const double _kMotifRepeatPx = 90.0;

/// Mappe la vraie photo produit [texture] sur le quadrilatère de la bande
/// (p0→p1→p2→p3, sens direct) — port du pattern de
/// `profile_strip._drawTexturedFace`, adapté à une bande fine (pas de
/// retournement plinthe ici, la moulure n'a pas de sens haut/bas fixe).
void _drawTexturedBand(
  Canvas canvas,
  Offset p0,
  Offset p1,
  Offset p2,
  Offset p3,
  Image texture,
) {
  final segLen = dist(p0, p1);
  final repeats = (segLen / _kMotifRepeatPx).clamp(1.0, 40.0);
  final texW = texture.width.toDouble();
  final texH = texture.height.toDouble();
  final uRight = texW * repeats;

  final positions = <Offset>[p0, p1, p2, p0, p2, p3];
  final texCoords = <Offset>[
    const Offset(0, 0),
    Offset(uRight, 0),
    Offset(uRight, texH),
    const Offset(0, 0),
    Offset(uRight, texH),
    Offset(0, texH),
  ];

  final vertices = Vertices(
    VertexMode.triangles,
    positions,
    textureCoordinates: texCoords,
  );

  final shader = ImageShader(
    texture,
    TileMode.repeated,
    TileMode.clamp,
    _kIdentityMatrix4,
    filterQuality: FilterQuality.medium,
  );

  canvas.drawVertices(vertices, BlendMode.srcOver, Paint()..shader = shader);
}

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
  Image? texture,
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

  // ⚠️ CORRECTION Bug #7 : si une vraie photo produit est disponible
  // (chargée par [ProductTextureCache] pour ce ref), on la mappe sur le
  // quadrilatère de la bande au lieu du dégradé plat générique — chaque
  // modèle de moulure affiche désormais SON relief réel, plus fin/épais
  // selon la largeur perspective du segment.
  if (texture != null) {
    canvas.save();
    canvas.clipPath(path);
    _drawTexturedBand(canvas, p0, p1, p2, p3, texture);
    canvas.restore();
    // Liseré d'ombre portante conservé même en mode texture, pour la
    // cohérence visuelle avec le rendu procédural.
    canvas.drawLine(
      p3,
      p2,
      Paint()
        ..color = const Color(0x38443A2E)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
    return;
  }

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
/// ⚠️ CORRECTION Bug "calepinage ne fonctionne pas / bande plate au milieu
/// de la photo" (retour utilisateur, capture Haussmannien/D570+1102) —
/// AVANT, les extrémités latérales de la bande ([frontL]/[frontR])
/// étaient calculées comme `Offset(0, canvasH * t)` / `Offset(canvasW,
/// canvasH * t)` : une droite PARFAITEMENT HORIZONTALE à une hauteur fixe
/// en pixels canvas, totalement indépendante de la calibration de
/// perspective (les points [wallTL]/[wallTR]/[wallBL]/[wallBR] mesurés
/// sur la VRAIE photo). Résultat : dès que la calibration de la pièce
/// n'est pas parfaitement de niveau (cas de la quasi-totalité des photos
/// réelles), la bande partait à plat depuis le bord de l'image et
/// tranchait en diagonale à travers le miroir, les portes et le canapé —
/// exactement le défaut signalé, "ne suit pas la perspective".
///
/// Désormais [frontL]/[frontR] sont interpolés le long des VRAIS segments
/// de mur latéral ([wallTL]→[wallBL] et [wallTR]→[wallBR], en coordonnées
/// canvas déjà calibrées), à la même fraction [t] que le point sur le mur
/// du fond ([mL]/[mR]) — exactement le même principe que
/// [paintCorniceSet]/[paintPlintheSet] (cornice_plinth_painter.dart), qui
/// eux suivaient déjà correctement la perspective réelle.
void paintHorizontalBandSet(
  Canvas canvas,
  VanishingPoint vp, {
  required double t,
  required Color color,
  required double wFond,
  required double wLat,
  required Offset wallTL,
  required Offset wallTR,
  required Offset wallBL,
  required Offset wallBR,
  double glowBlur = 0,
  Image? texture,
}) {
  final mL = lerpPt(vp.fTL, vp.fBL, t);
  final mR = lerpPt(vp.fTR, vp.fBR, t);
  // Points sur les VRAIS murs latéraux calibrés, à la même hauteur
  // relative [t] que sur le mur du fond — suit la perspective réelle de
  // la pièce au lieu d'une ligne horizontale plate arbitraire.
  final frontL = lerpPt(wallTL, wallBL, t);
  final frontR = lerpPt(wallTR, wallBR, t);

  drawMoulureBand(canvas, mL, mR, color, w1: wFond, w2: wFond, glowBlur: glowBlur, texture: texture);
  drawMoulureBand(canvas, frontL, mL, color, w1: wLat, w2: wFond, glowBlur: glowBlur, texture: texture);
  drawMoulureBand(canvas, mR, frontR, color, w1: wFond, w2: wLat, glowBlur: glowBlur, texture: texture);
}
