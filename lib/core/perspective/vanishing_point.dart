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
/// ⚠️ CORRECTION (conflation double-VP, ce commit) — la version
/// précédente de cette factory calculait `vp` par
/// `lineIntersect(fTL, fTR, fBL, fBR)` : l'intersection de la ligne
/// plafond et de la ligne sol. Ces deux droites sont COPLANAIRES dans le
/// mur du fond — leur intersection est le point de fuite de l'AXE
/// HORIZONTAL du mur du fond (le point vers lequel convergeraient des
/// lignes horizontales de CE mur si la photo n'était pas frontale), pas
/// celui de l'axe de PROFONDEUR (l'axe qui s'enfonce dans la pièce,
/// perpendiculaire au mur du fond — c'est CET axe que `toward()`/`frac()`
/// doivent utiliser pour faire reculer la face plafond/sol d'une
/// corniche/plinthe vers l'intérieur de la pièce). Sur les 4 photos démo,
/// mur du fond quasi-frontal, ces deux droites sont quasi-parallèles :
/// `lineIntersect` renvoyait soit `null` (repli sur le milieu de
/// `fTL→fTR`, un point qui ne dépend d'aucune fuyante réelle), soit un
/// point à des dizaines de milliers de pixels hors cadre (petit écart de
/// pente réel, intersection qui explose) — les deux régimes dégénérés
/// documentés par `test/core/perspective/vp_frac_degenere_test.dart`.
///
/// Le VP de profondeur correct, pour une prise quasi-frontale à un seul
/// point de fuite (cas des 4 scènes démo — vérifié : AUCUN vrai coin de
/// mur latéral n'y est mesurable, voir plus bas), est le CENTRE
/// géométrique du mur du fond photographié : centre horizontal (moyenne
/// des 4 abscisses `fTL/fTR/fBL/fBR`) et mi-hauteur entre la ligne
/// plafond et la ligne sol (l'horizon, au niveau des yeux de la caméra).
/// C'est la construction standard de la perspective à un point quand
/// l'axe optique est aligné avec l'axe de profondeur : aucune fuyante
/// latérale n'est nécessaire pour la déterminer.
///
/// Un VP de profondeur par intersection de vraies fuyantes latérales
/// (utilisant les points `wallTL/wallTR/wallBL/wallBR` de `PerspCalib`)
/// resterait pertinent pour une photo avec un VRAI coin de mur oblique
/// visible — non implémenté ici : mesure pixel précise (grilles 5%,
/// détection de gradient sous-pixel) effectuée sur les 4 photos démo
/// actuelles, AUCUNE ne présente de coin latéral réel exploitable (les
/// candidats visuels — ébrasements de porte/fenêtre, tuyaux de plafond,
/// bord de rideau, cloison de séparation — sont soit des plans sans
/// récession mesurable, soit des arêtes incohérentes selon la hauteur,
/// jamais une seule arête convergente cohérente). Ce cas n'a donc aucune
/// donnée réelle pour être écrit ni validé maintenant ; la signature de
/// [compute] reste volontairement à 4 points tant qu'aucun call site réel
/// n'en a besoin.
library;

import 'dart:ui';
import 'persp_geometry.dart' show dist;

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

  /// Calcule le VP de profondeur comme le centre géométrique du mur du
  /// fond : abscisse moyenne des 4 coins, ordonnée à mi-hauteur entre la
  /// ligne plafond (`fTL`/`fTR`) et la ligne sol (`fBL`/`fBR`). Voir la
  /// docstring de la classe ci-dessus pour la justification complète
  /// (correction de la conflation VP-horizontal / VP-profondeur).
  ///
  /// Ce point ne peut jamais être indéfini (contrairement à l'ancienne
  /// version basée sur `lineIntersect`, qui pouvait renvoyer `null` sur
  /// des droites parallèles) : c'est une simple moyenne, toujours
  /// calculable, y compris quand le mur du fond est parfaitement
  /// frontal — cas qui n'est plus un cas dégénéré à contourner par un
  /// repli, mais le cas normal que cette formule traite nativement.
  factory VanishingPoint.compute({
    required Offset fTL,
    required Offset fTR,
    required Offset fBL,
    required Offset fBR,
  }) {
    final cx = (fTL.dx + fTR.dx + fBL.dx + fBR.dx) / 4;
    final ceilY = (fTL.dy + fTR.dy) / 2;
    final floorY = (fBL.dy + fBR.dy) / 2;
    final cy = (ceilY + floorY) / 2;
    final vp = Offset(cx, cy);
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
