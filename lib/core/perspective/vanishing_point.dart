/// Modèle de point de fuite (VP) — perspective à 1 point de fuite.
///
/// ⚠️ CORRECTION Bug #4/#5 (audit rendering) : l'ancienne version avait
/// TROIS moteurs de perspective incompatibles :
///   1. `_drawSliderCornicePlinth` — bandes plates, AUCUNE perspective
///      (STATE.corniceYPct / STATE.plinthYPct, `_ctx.fillRect` horizontal)
///   2. `renderProductOnPhoto` — VP heuristique approximatif
///      (`vpX = milieu(fTL,fTR)`, `vpY = fTL.y - 0.10*(fBL.y-fTL.y)`,
///      jamais un vrai point d'intersection géométrique)
///   3. `comparateur.js/_perspPoints` — VP à pourcentages FIXES
///      (`vpX = w*0.50`, `vpY = h*0.40`), sans lien avec la calibration
///
/// Cette classe est l'UNIQUE source de vérité désormais : le VP est
/// calculé par intersection géométrique réelle des 2 droites du mur du
/// fond (ligne plafond fTL→fTR ∩ ligne sol fBL→fBR), exactement comme
/// le faisait le code mort `_drawArchitectureOnRoomCanvas` — jamais
/// appelé dans l'ancienne version en pratique. Studio ET Comparateur
/// consomment maintenant ce même calcul (Bug #5 corrigé).
library;

import 'dart:ui';
import 'persp_geometry.dart';

/// Point de fuite réel + repères architecturaux dérivés de la
/// calibration (mur du fond en pixels canvas).
class VanishingPoint {
  final Offset vp;
  final Offset fTL, fTR, fBL, fBR;

  const VanishingPoint({
    required this.vp,
    required this.fTL,
    required this.fTR,
    required this.fBL,
    required this.fBR,
  });

  /// Calcule le VP réel par intersection géométrique des droites
  /// (fTL→fTR) et (fBL→fBR). Fallback au milieu de la ligne haute si les
  /// droites sont parallèles (photo sans perspective visible) — même
  /// filet de sécurité que l'original.
  factory VanishingPoint.compute({
    required Offset fTL,
    required Offset fTR,
    required Offset fBL,
    required Offset fBR,
  }) {
    final real = lineIntersect(fTL, fTR, fBL, fBR);
    final vp = real ?? Offset((fTL.dx + fTR.dx) / 2, (fTL.dy + fTR.dy) / 2);
    return VanishingPoint(vp: vp, fTL: fTL, fTR: fTR, fBL: fBL, fBR: fBR);
  }

  /// Hauteur perspective réelle du mur du fond (repère d'échelle pour
  /// dimensionner tous les produits, indépendant du letterboxing).
  double get pH => fBL.dy - fTL.dy;

  /// Projette [p] vers le VP d'une fraction [frac] (0 = p, 1 = VP).
  /// Port exact de `vpToward`.
  Offset toward(Offset p, double frac) =>
      Offset(p.dx + (vp.dx - p.dx) * frac, p.dy + (vp.dy - p.dy) * frac);

  /// Convertit une profondeur en pixels canvas en fraction de
  /// convergence vers le VP, plafonnée à 0.45 — port exact de `vpFrac`.
  double frac(Offset p, double depthPx) {
    final d = dist(p, vp);
    final distVp = d == 0 ? 1.0 : d;
    final f = depthPx / distVp;
    return f > 0.45 ? 0.45 : f;
  }
}
