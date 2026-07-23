/// Primitives géométriques 2D pour le moteur de perspective.
///
/// Port fidèle des fonctions `_lineIntersect` / `_seg2Intersect` /
/// `_perpDown` / `_perpUp` / `_bisectorOffset` extraites du code mort
/// `_drawArchitectureOnRoomCanvas` (studio.js lignes ~960-1450) — la
/// SEULE géométrie de perspective réellement correcte de l'ancienne
/// version, jamais exécutée en pratique (Bug #1/#4/#5 de l'audit).
library;

import 'dart:math' as math;
import 'dart:ui';

/// Interpole linéairement entre [a] et [b] selon `t ∈ [0,1]`.
Offset lerpPt(Offset a, Offset b, double t) =>
    Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);

/// Intersection de deux droites (p1→p2) et (p3→p4).
/// Retourne `null` si les droites sont parallèles (comportement
/// identique à `_lineIntersect`/`_seg2Intersect` de studio.js).
Offset? lineIntersect(Offset p1, Offset p2, Offset p3, Offset p4) {
  final d1x = p2.dx - p1.dx, d1y = p2.dy - p1.dy;
  final d2x = p4.dx - p3.dx, d2y = p4.dy - p3.dy;
  final denom = d1x * d2y - d1y * d2x;
  if (denom.abs() < 0.001) return null;
  final t = ((p3.dx - p1.dx) * d2y - (p3.dy - p1.dy) * d2x) / denom;
  return Offset(p1.dx + t * d1x, p1.dy + t * d1y);
}

/// Vecteur perpendiculaire au segment A→B, orienté "vers le bas du mur"
/// (utilisé pour la corniche : descend depuis la ligne plafond).
/// Pour le mur du fond (A.y ≈ B.y) → perpendiculaire verticale pure.
/// Pour un mur latéral (A→B diagonal) → perpendiculaire inclinée,
/// épouse la perspective — port exact de `_perpDown`.
Offset perpDown(Offset a, Offset b, double fH) {
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  final len = math.sqrt(dx * dx + dy * dy);
  final l = len == 0 ? 1.0 : len;
  return Offset(-dy / l * fH, dx / l * fH);
}

/// Négation de [perpDown] — "vers le haut du mur" (utilisé par la plinthe).
Offset perpUp(Offset a, Offset b, double fH) {
  final p = perpDown(a, b, fH);
  return Offset(-p.dx, -p.dy);
}

/// Bissectrice d'angle pour une coupe d'onglet propre : retourne le point
/// décalé perpendiculairement à la bissectrice de (dirIn → sommet → dirOut)
/// à une distance [fHPx] du sommet [s]. Port exact de `_bisectorOffset`
/// (non utilisée par [lineIntersect]-based onglets mais conservée pour
/// compatibilité/cas futurs à angles non-géométriques).
Offset bisectorOffset(Offset s, Offset dirIn, Offset dirOut, double fHPx) {
  final ax = s.dx - dirIn.dx, ay = s.dy - dirIn.dy;
  final bx = dirOut.dx - s.dx, by = dirOut.dy - s.dy;
  final aLen = math.sqrt(ax * ax + ay * ay);
  final bLen = math.sqrt(bx * bx + by * by);
  final al = aLen == 0 ? 1.0 : aLen;
  final bl = bLen == 0 ? 1.0 : bLen;
  final bsx = ax / al + bx / bl;
  final bsy = ay / al + by / bl;
  final bsLen = math.sqrt(bsx * bsx + bsy * bsy);
  final bsl = bsLen == 0 ? 1.0 : bsLen;
  return Offset(s.dx - (bsy / bsl) * fHPx, s.dy + (bsx / bsl) * fHPx);
}

/// Distance euclidienne entre deux points.
double dist(Offset a, Offset b) {
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  return math.sqrt(dx * dx + dy * dy);
}
