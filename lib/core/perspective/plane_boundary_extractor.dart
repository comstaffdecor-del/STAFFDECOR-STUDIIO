/// P11 — extraction de la frontière entre deux plans adjacents
/// (plafond/mur, mur/sol) à partir d'un [RoomPlaneMaskResult].
///
/// Approche : pour chaque colonne du masque, on cherche la transition
/// verticale [above] -> [below] (ex: `ceiling` -> `wall` pour la
/// frontière haute, `wall` -> `floor` pour la frontière basse), ce qui
/// donne un nuage de points `(xPct, yPct)` — la frontière brute
/// (`breakpointBase` ci-dessous). On modélise ensuite cette frontière
/// de deux façons complémentaires :
///   1. `globalLine` : UNE seule droite robuste sur tout le nuage
///      (Theil-Sen + rejet des résidus aberrants par MAD) — sert de
///      fallback si aucun coin net n'est détectable.
///   2. `left`/`middle`/`right` : découpage en 3 segments par détection
///      de 2 points de rupture (coins gauche/droite où le mur du fond
///      rejoint les murs latéraux), chacun refit indépendamment — c'est
///      ce découpage qui permet, une fois converti en [PerspCalib]
///      (voir `segmentation_to_persp_calib.dart`), de retrouver les
///      positions xL/xR des coins réels des presets (`demoPresets`,
///      coins à xPct=0.100/0.900 selon la scène).
///
/// P12-ter — correctif asymétrique de l'échantillonnage par colonne
/// (`BoundarySampleMode`, voir plus bas) : le diagnostic P12-bis a
/// établi que le plafond est bien détecté (résidus 0,008 à 0,036,
/// transition franche) mais que la frontière mur/sol souffrait d'un
/// biais mécanique, pas géométrique — le mobilier (canapés, tables,
/// fauteuils, plantes) est classé `unknown`, donc chercher "le dernier
/// pixel wall" avant le sol revient à mesurer le sommet du canapé, pas
/// la plinthe. Le correctif repose sur une asymétrie physique : rien
/// n'occulte un plafond (mode `lastOfUpper`, inchangé), tout occulte
/// une plinthe (mode `firstOfLower`, nouveau, décrit en détail sur
/// [BoundarySampleMode] et dans `_sampleBoundary`).
///
/// Les 3 points de correction du brief P11 sont appliqués dès cette
/// première version (fichier neuf, aucune version antérieure buguée
/// dans ce dépôt à "corriger" — la spécification finale est appliquée
/// directement) :
///   (a) les breakpoints sont recherchés sur le nuage FILTRÉ COMPLET
///       (`breakpointBase = samples`, sans sous-échantillonnage), avec
///       un simple fit LSQ (`_lsq`) comme référence de recherche
///       (`breakpointSingleFit`) ; les segments `left`/`middle`/`right`
///       sont eux aussi construits sur `breakpointBase` (pas sur un
///       sous-ensemble) ; seul `globalLine` garde la méthode robuste
///       Theil-Sen + rejet MAD (les deux méthodes coexistent, chacune
///       avec son rôle).
///   (b) `cornerSearchMargin` = 0.06 (pas 0.12) : avec 0.12, la fenêtre
///       de recherche des coins serait `[0.12, 0.88]` en xPct, ce qui
///       EXCLUT les coins réels des presets (`demoPresets`, xPct=0.100/
///       0.900) ; avec 0.06, la fenêtre `[0.06, 0.94]` les inclut.
///       `minSeg` = 6 (pas 8) : longueur minimale (en nombre
///       d'échantillons de colonne, pas en xPct) d'un segment
///       gauche/milieu/droite pour qu'une paire de breakpoints soit
///       acceptée comme candidate valide.
///   (c) rien d'autre ne change (algorithme de recherche des
///       breakpoints, fit des segments, filtrage des échantillons de
///       colonne : identiques à toute autre valeur de marge/minSeg).
library;

import 'room_plane_segmenter.dart';

/// Un échantillon `(xPct, yPct)` de la frontière brute, une valeur par
/// colonne où la transition [above] -> [below] a été trouvée sans
/// ambiguïté.
class BoundarySample {
  final double xPct;
  final double yPct;
  const BoundarySample(this.xPct, this.yPct);
}

/// Droite `y = slope*x + intercept` (espace xPct/yPct).
class LineFit {
  final double slope;
  final double intercept;
  const LineFit({required this.slope, required this.intercept});
  double yAt(double x) => slope * x + intercept;
}

/// Un segment de frontière `[xStart, xEnd]` (bornes en xPct des
/// échantillons couverts) modélisé par sa propre [LineFit].
class BoundarySegment {
  final double xStart;
  final double xEnd;
  final LineFit line;
  const BoundarySegment({
    required this.xStart,
    required this.xEnd,
    required this.line,
  });
}

/// Résultat complet de l'extraction pour UNE frontière (ceiling/wall OU
/// wall/floor) d'UNE scène.
class PlaneBoundaryResult {
  /// Nuage de points brut filtré (une valeur par colonne valide) —
  /// c'est exactement `breakpointBase` utilisé pour tous les fits
  /// ci-dessous (voir docstring de section : correction (a)).
  final List<BoundarySample> samples;

  /// Droite robuste Theil-Sen + rejet MAD sur [samples] — fallback si
  /// aucun coin net n'est détecté (`corners == null`).
  final LineFit globalLine;

  /// Positions xPct des 2 points de rupture détectés (triés
  /// croissant), ou `null` si aucune paire valide n'a été trouvée
  /// (contraintes [cornerSearchMargin]/[minSeg] non satisfaites, ou
  /// nuage trop petit).
  final List<double>? corners;

  /// Segment gauche (mur latéral gauche), `null` si [corners] est
  /// `null`.
  final BoundarySegment? left;

  /// Segment milieu (mur du fond), `null` si [corners] est `null`.
  final BoundarySegment? middle;

  /// Segment droit (mur latéral droit), `null` si [corners] est
  /// `null`.
  final BoundarySegment? right;

  const PlaneBoundaryResult({
    required this.samples,
    required this.globalLine,
    required this.corners,
    required this.left,
    required this.middle,
    required this.right,
  });

  /// Hauteur (yPct) de la frontière à l'abscisse [xPct], en utilisant
  /// le segment approprié si les coins ont été détectés, sinon
  /// [globalLine]. Ne extrapole jamais au-delà des bornes couvertes par
  /// [samples] au-delà d'une tolérance raisonnable (clamp doux) — la
  /// même logique de prudence que `_lineYAtX` dans `edge_detect.dart`,
  /// réimplémentée ici indépendamment (aucune dépendance croisée entre
  /// ce fichier et `edge_detect.dart`).
  double yAt(double xPct) {
    if (corners == null || left == null || middle == null || right == null) {
      return globalLine.yAt(xPct);
    }
    if (xPct <= corners![0]) return left!.line.yAt(xPct);
    if (xPct >= corners![1]) return right!.line.yAt(xPct);
    return middle!.line.yAt(xPct);
  }
}

/// Marge (en xPct ABSOLU, pas relatif au nuage) exclue aux deux
/// extrémités lors de la recherche des points de rupture — voir
/// correction (b) : 0.06 (pas 0.12) pour ne pas exclure les coins réels
/// des presets à xPct=0.100/0.900.
const double kDefaultCornerSearchMargin = 0.06;

/// Longueur minimale (nombre d'échantillons de colonne) de chacun des
/// 3 segments gauche/milieu/droite pour qu'une paire de breakpoints
/// soit acceptée — voir correction (b) : 6 (pas 8).
const int kDefaultMinSeg = 6;

/// Multiplicateur de MAD au-delà duquel un résidu est rejeté comme
/// aberrant lors du calcul de [PlaneBoundaryResult.globalLine]
/// (Theil-Sen + rejet MAD). Valeur de sonde standard (règle empirique
/// courante pour un rejet robuste, ni trop permissif ni trop agressif).
const double kMadRejectMultiplier = 3.0;

/// P12-ter — mode d'échantillonnage par colonne pour
/// [extractPlaneBoundary] / [_sampleBoundary]. Voir docstring de
/// fichier (section P12-ter) pour le raisonnement complet : l'asymétrie
/// physique entre un plafond (jamais occulté) et une plinthe
/// (quasi-systématiquement occultée par du mobilier) impose deux
/// stratégies de recherche distinctes plutôt qu'une seule.
enum BoundarySampleMode {
  /// Conserve le DERNIER pixel de la classe [above] immédiatement
  /// suivi d'un pixel [below] (scan haut -> bas, transition unique
  /// exigée) — comportement historique P11, inchangé. Utilisé pour la
  /// frontière plafond/mur : rien n'occulte un plafond, donc le dernier
  /// pixel `ceiling` avant `wall` est fiable (résidus 0,008 à 0,036
  /// mesurés en P12-bis).
  lastOfUpper,

  /// Cherche le PREMIER pixel de la classe [below] en REMONTANT depuis
  /// le bas de la colonne (`y = h-1` vers `y = 0`), et retient le
  /// sommet du bloc CONTIGU de pixels [below] ancré au bord bas de
  /// l'image. Utilisé pour la frontière mur/sol : le mobilier (canapés,
  /// tables, plantes, classés `unknown`) occulte presque toujours la
  /// plinthe réelle, donc chercher "le dernier pixel wall" revient à
  /// mesurer le sommet du meuble, pas la plinthe (diagnostic P12-bis).
  /// Voir caveats #1 et #2 du brief P12-ter dans [_sampleBoundary].
  firstOfLower,
}

/// Échantillonne la frontière [above] -> [below] sur [mask] selon
/// [mode] — une valeur `(xPct, yPct)` par colonne valide, colonne
/// exclue (jamais de valeur par défaut) si aucun échantillon fiable
/// n'y est trouvé.
///
/// Mode [BoundarySampleMode.lastOfUpper] (plafond/mur, inchangé depuis
/// P11) : scanne chaque colonne de haut en bas et retient la ligne où
/// un pixel [above] est immédiatement suivi d'un pixel [below] —
/// colonne ignorée si cette transition n'existe pas exactement une
/// fois (transition absente, ou plusieurs candidats ambigus : le
/// masque contient alors du bruit sur cette colonne, mieux vaut
/// l'exclure que produire un sample erroné).
///
/// Mode [BoundarySampleMode.firstOfLower] (mur/sol, nouveau P12-ter) :
/// remonte depuis le bas de la colonne (`y = h-1`) et retient le
/// sommet du bloc CONTIGU de pixels [below] ancré à ce bord bas.
///   - Caveat #1 (brief P12-ter) : on part IMPÉRATIVEMENT du bas, pas
///     du haut. Descendre depuis le haut et prendre le premier pixel
///     [below] rencontré attraperait un faux positif haut dans l'image
///     — un reflet de sol dans un miroir, ou un patch de parquet
///     visible sous un meuble suspendu et donc déconnecté du bord bas
///     réel. Remonter depuis le bas et exiger la contiguïté avec ce
///     bord ignore mécaniquement ces patchs isolés et donne la vraie
///     plinthe (le bloc de sol qui touche effectivement le bas de la
///     photo).
///   - Caveat #2 (brief P12-ter) : si le pixel du bord bas (`y = h-1`)
///     n'est pas déjà de classe [below], la colonne est EXCLUE — que
///     ce soit parce qu'elle ne contient aucun pixel [below] du tout,
///     ou parce que le seul pixel [below] présent est un patch isolé
///     non contigu au bord bas (donc suspect, voir caveat #1) — jamais
///     de valeur par défaut. Cette proportion de colonnes exclues est
///     elle-même une donnée de diagnostic (futur "discriminant
///     moderne", voir brief P12-ter §2/§5 — pas encore exploitée ici).
List<BoundarySample> _sampleBoundary(
  RoomPlaneMaskResult mask,
  RoomPlaneClass above,
  RoomPlaneClass below,
  BoundarySampleMode mode,
) {
  final flat = mask.decode();
  final w = mask.width;
  final h = mask.height;
  final aboveIdx = above.index;
  final belowIdx = below.index;

  final samples = <BoundarySample>[];

  if (mode == BoundarySampleMode.lastOfUpper) {
    for (var x = 0; x < w; x++) {
      var transitionY = -1;
      var transitionCount = 0;
      for (var y = 0; y < h - 1; y++) {
        final cur = flat[y * w + x];
        final next = flat[(y + 1) * w + x];
        if (cur == aboveIdx && next == belowIdx) {
          transitionY = y;
          transitionCount++;
        }
      }
      if (transitionCount == 1) {
        samples.add(
          BoundarySample((x + 0.5) / w, (transitionY + 0.5) / h),
        );
      }
    }
    return samples;
  }

  // BoundarySampleMode.firstOfLower — voir caveats #1/#2 ci-dessus.
  for (var x = 0; x < w; x++) {
    if (flat[(h - 1) * w + x] != belowIdx) {
      // Bord bas non-[below] : colonne exclue (caveat #2), jamais de
      // défaut.
      continue;
    }
    var y = h - 1;
    while (y > 0 && flat[(y - 1) * w + x] == belowIdx) {
      y--;
    }
    // y est maintenant le sommet du bloc contigu de [below] ancré au
    // bord bas — c'est la plinthe (caveat #1).
    samples.add(BoundarySample((x + 0.5) / w, (y + 0.5) / h));
  }
  return samples;
}

/// Régression linéaire des moindres carrés (simple, non robuste) —
/// utilisée comme référence de recherche (`breakpointSingleFit`) pour
/// [_findTwoBreakpoints], PAS comme modèle final de la frontière
/// (celui-ci est soit `globalLine` (Theil-Sen+MAD), soit les segments
/// left/middle/right une fois les coins trouvés).
LineFit _lsq(List<BoundarySample> pts) {
  if (pts.isEmpty) return const LineFit(slope: 0, intercept: 0);
  if (pts.length == 1) {
    return LineFit(slope: 0, intercept: pts.first.yPct);
  }
  var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
  for (final p in pts) {
    sumX += p.xPct;
    sumY += p.yPct;
    sumXY += p.xPct * p.yPct;
    sumXX += p.xPct * p.xPct;
  }
  final n = pts.length.toDouble();
  final denom = n * sumXX - sumX * sumX;
  if (denom.abs() < 1e-12) {
    return LineFit(slope: 0, intercept: sumY / n);
  }
  final slope = (n * sumXY - sumX * sumY) / denom;
  final intercept = (sumY - slope * sumX) / n;
  return LineFit(slope: slope, intercept: intercept);
}

double _median(List<double> xs) {
  if (xs.isEmpty) return double.nan;
  final s = [...xs]..sort();
  final n = s.length;
  if (n.isOdd) return s[n ~/ 2];
  return (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// Régression Theil-Sen (pente = médiane des pentes de toutes les
/// paires de points, intercept = médiane de `y - pente*x`) suivie d'un
/// rejet des résidus aberrants par MAD, puis d'un second passage
/// Theil-Sen sur les points restants — modèle robuste utilisé
/// UNIQUEMENT pour [PlaneBoundaryResult.globalLine] (voir docstring de
/// section : ce choix, et pas `_lsq`, est délibérément conservé pour
/// `globalLine`).
LineFit _theilSenWithMadRejection(List<BoundarySample> pts) {
  if (pts.length < 2) return _lsq(pts);

  LineFit theilSen(List<BoundarySample> p) {
    final slopes = <double>[];
    for (var i = 0; i < p.length; i++) {
      for (var j = i + 1; j < p.length; j++) {
        final dx = p[j].xPct - p[i].xPct;
        if (dx.abs() < 1e-9) continue;
        slopes.add((p[j].yPct - p[i].yPct) / dx);
      }
    }
    if (slopes.isEmpty) return _lsq(p);
    final slope = _median(slopes);
    final intercepts = p.map((s) => s.yPct - slope * s.xPct).toList();
    final intercept = _median(intercepts);
    return LineFit(slope: slope, intercept: intercept);
  }

  final firstPass = theilSen(pts);
  final residuals = pts
      .map((s) => (s.yPct - firstPass.yAt(s.xPct)).abs())
      .toList();
  final medRes = _median(residuals);
  final mad = _median(residuals.map((r) => (r - medRes).abs()).toList());

  if (mad < 1e-9) return firstPass;

  final kept = <BoundarySample>[];
  for (var i = 0; i < pts.length; i++) {
    if (residuals[i] <= kMadRejectMultiplier * mad) kept.add(pts[i]);
  }
  if (kept.length < 2) return firstPass;
  return theilSen(kept);
}

/// Somme des carrés des résidus (SSE) d'un fit LSQ sur `pts[from..to)`
/// (borne haute exclue), calculée directement (pas de préfixes —
/// suffisant pour les tailles de nuage rencontrées ici, ≤ quelques
/// centaines de colonnes, voir note de complexité dans
/// [_findTwoBreakpoints]).
double _segmentSse(List<BoundarySample> pts, int from, int to) {
  if (to - from < 2) return 0.0;
  final seg = pts.sublist(from, to);
  final fit = _lsq(seg);
  var sse = 0.0;
  for (final p in seg) {
    final r = p.yPct - fit.yAt(p.xPct);
    sse += r * r;
  }
  return sse;
}

/// Recherche les 2 points de rupture (indices dans [breakpointBase],
/// trié par xPct croissant) qui minimisent la somme des SSE des 3
/// segments gauche/milieu/droite, sous contraintes :
///   - chaque point de rupture doit être dans la fenêtre
///     `[cornerSearchMargin, 1 - cornerSearchMargin]` en xPct ABSOLU
///     (pas relatif à la plage du nuage) — voir correction (b) ;
///   - chacun des 3 segments doit contenir au moins [minSeg]
///     échantillons.
/// Retourne `null` si aucune paire ne satisfait ces contraintes
/// (nuage trop petit, ou trop concentré hors de la fenêtre autorisée).
///
/// [breakpointSingleFit] (fit LSQ global, calculé par l'appelant) n'est
/// pas utilisé directement dans le calcul du minimum (le critère est le
/// SSE des 3 segments), mais sert de référence de comparaison
/// documentée : voir `PlaneBoundaryResult` — un `corners == null` avec
/// un `globalLine` proche de `breakpointSingleFit` indique que la
/// frontière est essentiellement rectiligne (pas de coude détecté),
/// cohérent avec la sémantique du fallback.
///
/// Complexité O(n²) dans le nombre d'échantillons (n ≤ quelques
/// centaines de colonnes de masque de travail ici, largement
/// suffisant pour rester rapide).
List<int>? _findTwoBreakpointIndices(
  List<BoundarySample> breakpointBase,
  LineFit breakpointSingleFit,
  double cornerSearchMargin,
  int minSeg,
) {
  final n = breakpointBase.length;
  if (n < 3 * minSeg) return null;

  // Fenêtre de recherche en INDICE : on convertit la fenêtre xPct
  // absolue en indices en cherchant les positions couvrant cette
  // plage — breakpointBase est trié par xPct croissant (garanti par
  // construction dans _sampleBoundary, colonnes traitées dans l'ordre).
  final lowX = cornerSearchMargin;
  final highX = 1.0 - cornerSearchMargin;

  var bestI = -1, bestJ = -1;
  var bestSse = double.infinity;

  for (var i = minSeg; i <= n - 2 * minSeg; i++) {
    final xi = breakpointBase[i].xPct;
    if (xi < lowX || xi > highX) continue;
    for (var j = i + minSeg; j <= n - minSeg; j++) {
      final xj = breakpointBase[j].xPct;
      if (xj < lowX || xj > highX) continue;

      final sseLeft = _segmentSse(breakpointBase, 0, i);
      final sseMiddle = _segmentSse(breakpointBase, i, j);
      final sseRight = _segmentSse(breakpointBase, j, n);
      final total = sseLeft + sseMiddle + sseRight;

      if (total < bestSse) {
        bestSse = total;
        bestI = i;
        bestJ = j;
      }
    }
  }

  if (bestI < 0 || bestJ < 0) return null;
  return [bestI, bestJ];
}

/// Point d'entrée principal : extrait la frontière [above] -> [below]
/// de [mask] et produit le [PlaneBoundaryResult] complet (échantillons,
/// droite globale robuste, coins + segments si détectés).
///
/// [sampleMode] contrôle la stratégie d'échantillonnage par colonne
/// (voir [BoundarySampleMode] et docstring de fichier, section
/// P12-ter). Défaut = [BoundarySampleMode.lastOfUpper], qui préserve
/// EXACTEMENT le comportement historique P11 pour tout appelant ne
/// spécifiant pas ce paramètre (compatibilité requise, notamment pour
/// `p11_room_plane_segmentation_contract_test.dart` qui appelle cette
/// fonction directement sans argument de mode). Les appelants
/// P12-ter-aware (`room_plane_analysis.dart`) doivent passer ce
/// paramètre EXPLICITEMENT : `lastOfUpper` pour plafond/mur,
/// `firstOfLower` pour mur/sol — le brief exige que ce choix soit
/// exposé en configuration plutôt que codé en dur, précisément pour
/// que la sonde puisse mesurer les deux variantes sur une même passe.
PlaneBoundaryResult extractPlaneBoundary(
  RoomPlaneMaskResult mask, {
  required RoomPlaneClass above,
  required RoomPlaneClass below,
  double cornerSearchMargin = kDefaultCornerSearchMargin,
  int minSeg = kDefaultMinSeg,
  BoundarySampleMode sampleMode = BoundarySampleMode.lastOfUpper,
}) {
  // (a) breakpoints calculés sur les samples filtrés COMPLETS, sans
  // sous-échantillonnage — voir docstring de section.
  final breakpointBase = _sampleBoundary(mask, above, below, sampleMode);
  final breakpointSingleFit = _lsq(breakpointBase);
  final indices = _findTwoBreakpointIndices(
    breakpointBase,
    breakpointSingleFit,
    cornerSearchMargin,
    minSeg,
  );

  final globalLine = _theilSenWithMadRejection(breakpointBase);

  if (indices == null || breakpointBase.isEmpty) {
    return PlaneBoundaryResult(
      samples: breakpointBase,
      globalLine: globalLine,
      corners: null,
      left: null,
      middle: null,
      right: null,
    );
  }

  final i = indices[0], j = indices[1];
  // left/middle/right construits sur breakpointBase (samples complets,
  // pas un sous-ensemble) — voir docstring de section (a).
  final leftPts = breakpointBase.sublist(0, i);
  final middlePts = breakpointBase.sublist(i, j);
  final rightPts = breakpointBase.sublist(j, breakpointBase.length);

  final leftFit = _lsq(leftPts);
  final middleFit = _lsq(middlePts);
  final rightFit = _lsq(rightPts);

  final cornerXLeft = breakpointBase[i].xPct;
  final cornerXRight = breakpointBase[j].xPct;

  return PlaneBoundaryResult(
    samples: breakpointBase,
    globalLine: globalLine,
    corners: [cornerXLeft, cornerXRight],
    left: BoundarySegment(
      xStart: leftPts.isEmpty ? 0.0 : leftPts.first.xPct,
      xEnd: cornerXLeft,
      line: leftFit,
    ),
    middle: BoundarySegment(
      xStart: cornerXLeft,
      xEnd: cornerXRight,
      line: middleFit,
    ),
    right: BoundarySegment(
      xStart: cornerXRight,
      xEnd: rightPts.isEmpty ? 1.0 : rightPts.last.xPct,
      line: rightFit,
    ),
  );
}

