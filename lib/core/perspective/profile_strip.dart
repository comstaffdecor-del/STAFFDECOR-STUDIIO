/// Rendu de la face "mur" d'une corniche ou plinthe — silhouette
/// plâtre procédurale pilotée par le VRAI ratio largeur/hauteur du
/// profil (`PROD_PROFILES`).
///
/// ⚠️ CORRECTION Bug #2/#3 (audit rendering) : dans l'ancienne version,
/// `_getProfileImg()` chargeait bien un PNG `/static/profiles/{ref}.png`
/// (asset qui n'existe même pas dans les sources livrées), MAIS
/// `_drawProfileStrip()` ne l'utilisait JAMAIS pour dessiner quoi que ce
/// soit — le PNG servait uniquement de flag "chargé/pas chargé" et la
/// fonction traçait un dégradé ivoire IDENTIQUE pour tous les produits,
/// quelle que soit leur vraie géométrie de coupe. Et `PROD_PROFILES`
/// (283 ratios réels extraits des PDF) n'était consulté par AUCUNE
/// fonction de rendu.
///
/// Ici, le ratio réel `w/h` du profil (`ProdProfile.r`) module directement
/// la silhouette procédurale (position de la gorge, nombre de moulures,
/// contraste) : deux produits différents rendent visuellement différent,
/// proportionnellement à leur vraie coupe transversale.
///
/// ⚠️ CORRECTION Bug motifs (retour utilisateur : "pas d'apprentissage des
/// motifs ni perspectives") — la silhouette procédurale ci-dessus ne
/// montre JAMAIS le vrai relief sculpté (feuillages, perles, oves...).
/// [drawProfileFace] accepte désormais une VRAIE photo produit ([texture],
/// chargée depuis staffdecor.fr par [ProductTextureCache]) : quand elle
/// est disponible, on la mappe sur le quadrilatère exact du segment via
/// [Canvas.drawVertices] + [ImageShader] (2 triangles, coordonnées UV en
/// pixels image, [TileMode.repeated] en X pour répéter le motif sur toute
/// la longueur du mur) — un vrai texture-mapping, pas une approximation
/// rectangulaire. Le rendu procédural reste le SEUL utilisé en fallback
/// (image pas encore chargée ou échec réseau).
library;

import 'dart:ui';
import 'dart:math' as math;
import 'dart:typed_data';
import 'persp_geometry.dart' show dist;

/// Matrice identité 4x4 (column-major, layout attendu par [ImageShader]) —
/// évite une dépendance à `vector_math`/`Matrix4` pour un simple identity.
final Float64List _kIdentityMatrix4 = Float64List.fromList([
  1, 0, 0, 0,
  0, 1, 0, 0,
  0, 0, 1, 0,
  0, 0, 0, 1,
]);

/// Dessine la face murale d'un segment de corniche/plinthe dans le
/// quadrilatère exact (topA→topB→botB→botA).
///
/// Si [texture] est fournie (vraie photo produit chargée par
/// [ProductTextureCache]), elle est mappée en texture réelle sur le
/// quadrilatère via [Canvas.drawVertices] (2 triangles + UV), avec
/// répétition horizontale du motif le long du mur — c'est le VRAI relief
/// sculpté (feuillages, perles, oves) qui apparaît, pas une approximation.
/// Sinon (image pas encore chargée / échec réseau), on retombe sur la
/// silhouette procédurale dérivée de [ratio] (w/h du profil réel).
///
/// [isPlinthe] inverse le sens du dégradé procédural (plinthe = lumière en
/// haut, ombre en bas) et, en mode texture, inverse verticalement la photo
/// (une plinthe au sol est visuellement le miroir d'une corniche au
/// plafond) — cohérent avec l'original.
void drawProfileFace(
  Canvas canvas,
  Offset topA,
  Offset topB,
  Offset botA,
  Offset botB, {
  required double ratio,
  required bool isPlinthe,
  Image? texture,
}) {
  final path = Path()
    ..moveTo(topA.dx, topA.dy)
    ..lineTo(topB.dx, topB.dy)
    ..lineTo(botB.dx, botB.dy)
    ..lineTo(botA.dx, botA.dy)
    ..close();

  canvas.save();
  canvas.clipPath(path);

  // Fond plâtre blanc ivoire.
  canvas.drawPath(path, Paint()..color = const Color(0xFFFCFAF6));

  if (texture != null) {
    _drawTexturedFace(canvas, topA, topB, botA, botB, texture, isPlinthe);
    canvas.restore();
    return;
  }

  // Gradient perpendiculaire à l'arête (le long de la hauteur du profil),
  // exactement comme l'original : du milieu du bord haut vers le milieu
  // du bord bas.
  final ux = topB.dx - topA.dx, uy = topB.dy - topA.dy;
  final vx = botA.dx - topA.dx, vy = botA.dy - topA.dy;
  final g0 = Offset(topA.dx + ux * 0.5, topA.dy + uy * 0.5);
  final g1 = Offset(g0.dx + vx, g0.dy + vy);

  // ── Ratio réel → nombre de "moulures" (cannelures/gorges) visibles.
  // Un profil large et bas (ratio élevé, ex: corniche à large développé
  // comme une doucine) affiche 3 bandes de relief ; un profil étroit et
  // haut (ratio faible, ex: petit talon) reste sobre à 2 bandes.
  final r = ratio.clamp(0.25, 4.0);
  final nBands = r > 1.6
      ? 3
      : r > 0.8
      ? 2
      : 1;

  final stops = <double>[];
  final colors = <Color>[];
  final baseLight = isPlinthe
      ? const Color(0xFFFFFFFF)
      : const Color(0xFFFFFFFF);
  final baseShadow = isPlinthe
      ? const Color(0xFFA89E8F)
      : const Color(0xB0AF9F90);

  // Position de la gorge (creux sombre) proportionnelle au ratio réel :
  // plus le profil est "plat" (ratio élevé), plus la gorge est repoussée
  // vers le bas (profondeur perçue plus grande) ; plus il est "haut"
  // (ratio faible), plus la gorge remonte près du sommet.
  final groovePos = (0.30 + 0.35 * (1.0 - (1.0 / (1.0 + r)))).clamp(0.2, 0.65);

  stops.add(0.0);
  colors.add(baseLight.withValues(alpha: 1.0));
  for (var i = 1; i <= nBands; i++) {
    final t = groovePos * (i / nBands);
    stops.add(t);
    colors.add(
      i.isOdd
          ? const Color(0xFF3A2E22).withValues(alpha: 0.35 / i)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.9),
    );
  }
  stops.add(1.0);
  colors.add(baseShadow.withValues(alpha: 0.80));

  // S'assurer que les stops sont strictement croissants (contrainte Skia).
  for (var i = 1; i < stops.length; i++) {
    if (stops[i] <= stops[i - 1]) stops[i] = stops[i - 1] + 0.001;
  }
  if (stops.last > 1.0) stops[stops.length - 1] = 1.0;

  final shader = Gradient.linear(g0, g1, colors, stops);
  canvas.drawPath(path, Paint()..shader = shader);

  canvas.restore();
}

/// Mappe la vraie photo produit [texture] sur le quadrilatère
/// (topA→topB→botB→botA) via [Canvas.drawVertices] (2 triangles avec
/// coordonnées UV en pixels image) — un vrai texture-mapping qui suit la
/// perspective du segment (les 2 triangles interpolent linéairement les
/// UV entre les 4 coins, donc un mur qui rétrécit vers le point de fuite
/// compresse proportionnellement le motif, exactement comme une vraie
/// corniche photographiée en perspective).
///
/// Le motif est répété horizontalement ([TileMode.repeated] sur l'axe X
/// de l'image) : la largeur perspective en pixels canvas du segment est
/// convertie en un nombre de répétitions du motif source, calé sur une
/// largeur de référence [_kMotifRepeatPx] (empirique, ~1 répétition tous
/// les 90px canvas pour une bande cohérente ni trop étirée, ni trop
/// tassée) — évite qu'un long mur du fond n'affiche qu'un seul motif géant
/// écrasé, ou qu'un mur latéral court en affiche des dizaines minuscules.
const double _kMotifRepeatPx = 90.0;

void _drawTexturedFace(
  Canvas canvas,
  Offset topA,
  Offset topB,
  Offset botA,
  Offset botB,
  Image texture,
  bool isPlinthe,
) {
  final segLen = dist(topA, topB);
  final repeats = (segLen / _kMotifRepeatPx).clamp(1.0, 40.0);
  final texW = texture.width.toDouble();
  final texH = texture.height.toDouble();
  final uRight = texW * repeats;

  // UV : plinthe = photo retournée verticalement (le relief "tombe" vers
  // le sol au lieu de "descendre" du plafond), corniche = photo telle
  // quelle (haut de la photo = haut du profil, côté plafond).
  final uv0 = isPlinthe ? texH : 0.0;
  final uv1 = isPlinthe ? 0.0 : texH;

  final positions = <Offset>[topA, topB, botB, topA, botB, botA];
  final texCoords = <Offset>[
    Offset(0, uv0),
    Offset(uRight, uv0),
    Offset(uRight, uv1),
    Offset(0, uv0),
    Offset(uRight, uv1),
    Offset(0, uv1),
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

/// Trace un liseré fin (arête vive) entre deux points — équivalent des
/// `ctx.stroke()` de liserés hauts/bas de l'original.
void drawEdgeLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Color color,
  double width,
) {
  canvas.drawLine(
    a,
    b,
    Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke,
  );
}

/// Utilitaire — angle non utilisé actuellement mais conservé pour de
/// futures variations de silhouette (cintrage des profils courbes).
double angleOf(Offset a, Offset b) => math.atan2(b.dy - a.dy, b.dx - a.dx);
