/// Détection automatique des arêtes de la pièce (plafond / sol / murs
/// latéraux) et calcul de la calibration de perspective correspondante.
///
/// Port fidèle de l'algorithme `edge-detect.js` de l'ancienne version :
///   Sobel (gradient) → seuillage → transformée de Hough (droites) →
///   clustering → classification (horizontales = plafond/sol, diagonales
///   = fuyantes latérales) → point de fuite réel → 8 points de
///   calibration ([PerspCalib]).
///
/// Objectif : que le produit sélectionné (corniche, plinthe...) épouse
/// automatiquement les vraies arêtes de la photo importée/démo, au lieu
/// d'utiliser systématiquement [PerspCalib.defaultCalib] (fixe, sans
/// rapport avec la perspective réelle de l'image).
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/persp_calib.dart';

/// Largeur de travail (image réduite pour la vitesse de l'algorithme).
const _workW = 240;

/// Seuil Sobel (0-255) — gradient gardé si magnitude ≥ seuil.
const _sobelTh = 26.0;

/// Seuil Hough (fraction du vote maximum de l'accumulateur).
const _houghThFrac = 0.35;

/// Fusion de lignes similaires : tolérance angle (degrés) et rho (px).
const _clusterAngleDeg = 8.0;
const _clusterRho = 16.0;

/// Confiance minimum pour valider la détection (sinon on retombe sur la
/// calibration par défaut).
const _minConfidence = 0.22;

/// Résultat de la détection : calibration 8 points + score de confiance
/// (0..1, ~0.3 = faible, ~0.7+ = bonne détection plafond+sol+murs).
class EdgeDetectResult {
  final PerspCalib calib;
  final double confidence;
  const EdgeDetectResult({required this.calib, required this.confidence});

  /// Alias explicite utilisé par [AppState.autoDetectEdges] — renvoie la
  /// calibration détectée sous forme de [PerspCalib] prête à l'emploi.
  PerspCalib toPerspCalib() => calib;
}

/// Analyse [image] et retourne la calibration détectée, ou `null` si la
/// confiance est trop faible (photo peu contrastée, pas d'arêtes nettes,
/// pièce hors-champ...). Ne lève jamais d'exception (comportement
/// identique à l'original : `resolve(null)` en cas d'erreur).
Future<EdgeDetectResult?> detectRoomEdges(ui.Image image) async {
  try {
    final srcW = image.width;
    final srcH = image.height;
    if (srcW == 0 || srcH == 0) return null;

    final scale = _workW / srcW;
    final wW = _workW;
    final wH = (srcH * scale).round().clamp(40, 2000);

    final small = await _downscale(image, wW, wH);
    final byteData = await small.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    small.dispose();
    if (byteData == null) return null;
    final px = byteData.buffer.asUint8List();

    final gray = _toGray(px, wW, wH);
    final blurred = _blur3x3(gray, wW, wH);
    final edges = _sobel(blurred, wW, wH, _sobelTh);

    // P9o : neutralise le cadre artificiel créé par le prétraitement.
    // _blur3x3 n'écrit que l'intérieur (y=1..h-2, x=1..w-2) d'un buffer
    // initialisé à zéro : Sobel rencontre donc une discontinuité parfaite
    // en y=1 et y=h-2. Depuis P9n, ces horizontales exactes (theta=90°,
    // cosT=0) sont de nouveau des segments valides, Hough les vote au
    // maximum, et _classifyLines les choisit par position (first/last).
    // Mesuré sur les 4 scènes : plafond détecté à y≈0.006 (ligne 1), sol à
    // y≈0.987 (ligne h-2), quelle que soit la vraie géométrie.
    const borderPx = 3;
    for (var y = 0; y < wH; y++) {
      for (var x = 0; x < wW; x++) {
        if (y < borderPx ||
            y >= wH - borderPx ||
            x < borderPx ||
            x >= wW - borderPx) {
          edges[y * wW + x] = 0;
        }
      }
    }

    final lines = _houghLines(edges, wW, wH, _houghThFrac);
    if (lines.isEmpty) return null;

    final clustered = _clusterLines(lines, _clusterAngleDeg, _clusterRho);
    final capped = _capParBande(clustered, 20);
    final cls = _classifyLines(capped, wW, wH);
    if (cls == null) return null;

    final vp = _computeVanishingPoint(cls, wW, wH);
    return _buildGeometry(cls, vp, wW, wH);
  } catch (_) {
    return null;
  }
}

/// Redimensionne [src] en [w]×[h] via un canvas offscreen (léger, pas de
/// dépendance externe au package `image`).
Future<ui.Image> _downscale(ui.Image src, int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final srcRect = ui.Rect.fromLTWH(
    0,
    0,
    src.width.toDouble(),
    src.height.toDouble(),
  );
  final dstRect = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  canvas.drawImageRect(src, srcRect, dstRect, ui.Paint());
  final picture = recorder.endRecording();
  final img = await picture.toImage(w, h);
  picture.dispose();
  return img;
}

Float32List _toGray(Uint8List px, int w, int h) {
  final gray = Float32List(w * h);
  for (var i = 0; i < w * h; i++) {
    final o = i * 4;
    final r = px[o], g = px[o + 1], b = px[o + 2];
    gray[i] = 0.299 * r + 0.587 * g + 0.114 * b;
  }
  return gray;
}

/// Flou gaussien simplifié 3×3 (réduction du bruit avant Sobel).
Float32List _blur3x3(Float32List gray, int w, int h) {
  final out = Float32List(w * h);
  const k = [1, 2, 1, 2, 4, 2, 1, 2, 1];
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      var s = 0.0;
      var ki = 0;
      for (var ky = -1; ky <= 1; ky++) {
        for (var kx = -1; kx <= 1; kx++) {
          s += gray[(y + ky) * w + (x + kx)] * k[ki++];
        }
      }
      out[y * w + x] = s / 16;
    }
  }
  return out;
}

/// Sobel — masque binaire (1 = pixel d'arête, 0 = fond).
Uint8List _sobel(Float32List gray, int w, int h, double threshold) {
  final edges = Uint8List(w * h);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final tl = gray[(y - 1) * w + (x - 1)];
      final tc = gray[(y - 1) * w + x];
      final tr = gray[(y - 1) * w + (x + 1)];
      final ml = gray[y * w + (x - 1)];
      final mr = gray[y * w + (x + 1)];
      final bl = gray[(y + 1) * w + (x - 1)];
      final bc = gray[(y + 1) * w + x];
      final br = gray[(y + 1) * w + (x + 1)];
      final gx = -tl - 2 * ml - bl + tr + 2 * mr + br;
      final gy = -tl - 2 * tc - tr + bl + 2 * bc + br;
      final mag = math.sqrt(gx * gx + gy * gy);
      edges[y * w + x] = mag >= threshold ? 1 : 0;
    }
  }
  return edges;
}

/// Une droite détectée par la transformée de Hough (avec son segment
/// dans l'image de travail + sa classification éventuelle).
class _HLine {
  final double rho;
  final double theta;
  final double angle;
  final double score;
  final double x1, y1, x2, y2;
  final String cls;

  const _HLine({
    required this.rho,
    required this.theta,
    required this.angle,
    required this.score,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.cls = '',
  });

  _HLine withCls(String c) => _HLine(
    rho: rho,
    theta: theta,
    angle: angle,
    score: score,
    x1: x1,
    y1: y1,
    x2: x2,
    y2: y2,
    cls: c,
  );
}

/// Transformée de Hough simplifiée — vote uniquement les pixels d'arête,
/// extrait les maxima locaux de l'accumulateur (rho, thêta), garde les
/// 60 meilleures droites.
List<_HLine> _houghLines(Uint8List edges, int w, int h, double threshFrac) {
  final diagLen = math.sqrt(w * w + h * h).ceil();
  final nRho = 2 * diagLen + 1;
  const thStepDeg = 1;
  final nTheta = (180 / thStepDeg).round();

  final cosT = Float32List(nTheta);
  final sinT = Float32List(nTheta);
  for (var t = 0; t < nTheta; t++) {
    final a = (t * thStepDeg * math.pi) / 180;
    cosT[t] = math.cos(a);
    sinT[t] = math.sin(a);
  }

  final acc = Int32List(nRho * nTheta);
  var maxAcc = 0;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (edges[y * w + x] == 0) continue;
      for (var t = 0; t < nTheta; t++) {
        final rho = (x * cosT[t] + y * sinT[t]).round() + diagLen;
        if (rho < 0 || rho >= nRho) continue;
        final idx = rho * nTheta + t;
        final v = ++acc[idx];
        if (v > maxAcc) maxAcc = v;
      }
    }
  }

  if (maxAcc == 0) return [];
  final minVote = math.max(5, (maxAcc * threshFrac).round());

  final lines = <_HLine>[];
  for (var rhoIdx = 2; rhoIdx < nRho - 2; rhoIdx++) {
    for (var t = 2; t < nTheta - 2; t++) {
      final v = acc[rhoIdx * nTheta + t];
      if (v < minVote) continue;
      var isMax = true;
      outer:
      for (var dr = -2; dr <= 2; dr++) {
        for (var dt = -2; dt <= 2; dt++) {
          if (dr == 0 && dt == 0) continue;
          if (acc[(rhoIdx + dr) * nTheta + (t + dt)] > v) {
            isMax = false;
            break outer;
          }
        }
      }
      if (!isMax) continue;

      final rho = (rhoIdx - diagLen).toDouble();
      final theta = t * thStepDeg * math.pi / 180;
      final seg = _rhoThetaToSegment(rho, theta, w, h);
      if (seg == null) continue;
      lines.add(
        _HLine(
          rho: rho,
          theta: theta,
          angle: (t * thStepDeg).toDouble(),
          score: v / maxAcc,
          x1: seg[0],
          y1: seg[1],
          x2: seg[2],
          y2: seg[3],
        ),
      );
    }
  }

  lines.sort((a, b) => b.score.compareTo(a.score));
  return lines; // cap deplace apres clustering, par bande angulaire
}

/// Convertit (rho, theta) en segment (x1,y1,x2,y2) dans la bbox image.
List<double>? _rhoThetaToSegment(double rho, double theta, int w, int h) {
  final cosT = math.cos(theta), sinT = math.sin(theta);
  final pts = <List<double>>[];

  void tryPt(double x, double y) {
    if (x >= -0.5 && x <= w + 0.5 && y >= -0.5 && y <= h + 0.5) {
      pts.add([x.roundToDouble(), y.roundToDouble()]);
    }
  }

  // P9n : gardes corrigées — on divise par cosT pour les intersections
  // avec y=0/y=h, donc c'est cosT qu'il faut garder non-nul (pas sinT) ;
  // symétriquement pour x=0/x=w, qui divisent par sinT. L'ancien code
  // inversait les deux, ce qui supprimait silencieusement toute ligne
  // proche de l'horizontale pure (theta=90°, cosT≈0) : les deux points
  // valides (x=0/x=w) étaient sautés à tort tandis que les deux points
  // invalides (division par cosT≈0) étaient tentés puis rejetés par le
  // bounds-check — pts.length<2, segment nul.
  if (cosT.abs() > 1e-6) tryPt(rho / cosT, 0);
  if (cosT.abs() > 1e-6) tryPt((rho - h * sinT) / cosT, h.toDouble());
  if (sinT.abs() > 1e-6) tryPt(0, rho / sinT);
  if (sinT.abs() > 1e-6) tryPt(w.toDouble(), (rho - w * cosT) / sinT);

  if (pts.length < 2) return null;
  var best = [pts[0], pts[1]];
  var bestD = 0.0;
  for (var i = 0; i < pts.length; i++) {
    for (var j = i + 1; j < pts.length; j++) {
      final dxp = pts[i][0] - pts[j][0];
      final dyp = pts[i][1] - pts[j][1];
      final d = dxp * dxp + dyp * dyp;
      if (d > bestD) {
        bestD = d;
        best = [pts[i], pts[j]];
      }
    }
  }
  return [best[0][0], best[0][1], best[1][0], best[1][1]];
}

/// Fusionne les droites proches en angle + rho (une même arête physique
/// génère souvent plusieurs pics voisins dans l'accumulateur de Hough).
List<_HLine> _clusterLines(
  List<_HLine> lines,
  double angleTol,
  double rhoTol,
) {
  final used = List<bool>.filled(lines.length, false);
  final clusters = <_HLine>[];

  for (var i = 0; i < lines.length; i++) {
    if (used[i]) continue;
    final grp = <_HLine>[lines[i]];
    used[i] = true;
    for (var j = i + 1; j < lines.length; j++) {
      if (used[j]) continue;
      if (_bandeAngulaire(lines[i]) != _bandeAngulaire(lines[j])) continue;
      final dAngle = math.min(
        (lines[i].angle - lines[j].angle).abs(),
        180 - (lines[i].angle - lines[j].angle).abs(),
      );
      final dRho = (lines[i].rho - lines[j].rho).abs();
      if (dAngle <= angleTol && dRho <= rhoTol) {
        grp.add(lines[j]);
        used[j] = true;
      }
    }
    grp.sort((a, b) => b.score.compareTo(a.score));
    clusters.add(grp.first);
  }

  clusters.sort((a, b) => b.score.compareTo(a.score));
  return clusters;
}

class _Classified {
  final _HLine? ceiling;
  final _HLine? floor;
  final List<_HLine> leftDiags;
  final List<_HLine> rightDiags;
  const _Classified({
    this.ceiling,
    this.floor,
    required this.leftDiags,
    required this.rightDiags,
  });
}

/// Angle de la LIGNE (0-180°) déduit de l'angle Hough (thêta = angle de
/// la normale à la droite).
double _lineAngle(_HLine l) => (90 - l.angle + 360) % 180;

/// Bande angulaire grossière : 0 = horizontal (plafond/sol), 1 = fuyante
/// gauche, 2 = fuyante droite. Utilisée pour (a) empêcher le clustering
/// de fusionner une horizontale faible avec une diagonale forte proche
/// en rho, et (b) capper le nombre de candidats PAR bande plutôt que
/// globalement (une bande dominée par des doublons diagonaux non fusionnés
/// ne doit plus évincer les rares candidats horizontaux).
int _bandeAngulaire(_HLine l) {
  final a = _lineAngle(l);
  if (a <= 15 || a >= 165) return 0; // horizontal
  if (a <= 55) return 1; // fuyante gauche
  return 2; // fuyante droite
}

/// Cap le nombre de lignes gardées, séparément par bande angulaire, pour
/// que les diagonales (souvent majoritaires) ne masquent plus les rares
/// candidats horizontaux plafond/sol.
List<_HLine> _capParBande(List<_HLine> lines, int nParBande) {
  final bandes = <List<_HLine>>[[], [], []];
  for (final l in lines) {
    bandes[_bandeAngulaire(l)].add(l);
  }
  for (final b in bandes) {
    b.sort((x, y) => y.score.compareTo(x.score));
  }
  return [
    ...bandes[0].take(nParBande),
    ...bandes[1].take(nParBande),
    ...bandes[2].take(nParBande),
  ]..sort((x, y) => y.score.compareTo(x.score));
}

/// Classifie les droites en horizontales (plafond/sol), fuyantes gauche
/// et fuyantes droite, puis sépare les horizontales en "plafond" (haut
/// de l'image) et "sol" (bas de l'image).
_Classified? _classifyLines(List<_HLine> lines, int w, int h) {
  final horizontals = <_HLine>[];
  final leftDiags = <_HLine>[];
  final rightDiags = <_HLine>[];

  for (final l in lines) {
    final a = _lineAngle(l);
    if (a <= 15 || a >= 165) {
      horizontals.add(l.withCls('horizontal'));
    } else if (a > 15 && a <= 55) {
      leftDiags.add(l.withCls('left-diag'));
    } else if (a > 125 && a < 165) {
      rightDiags.add(l.withCls('right-diag'));
    }
  }

  if (horizontals.length < 2) {
    for (final l in lines) {
      final a = _lineAngle(l);
      if (a <= 22 || a >= 158) horizontals.add(l.withCls('horizontal'));
    }
    if (horizontals.isEmpty) return null;
  }

  final hmid = h * 0.5;
  final ceilLines =
      horizontals.where((l) => (l.y1 + l.y2) / 2 < h * 0.35).toList()
        ..sort((a, b) => (a.y1 + a.y2).compareTo(b.y1 + b.y2));
  // P9o-D : le sol reprend le tri par score Hough decroissant de B (gain
  // mesure sur floor : 0.1131 -> 0.0671), le plafond reste positionnel
  // comme en A (0.0615, non degrade par B). La marge de bord 3% de B a
  // ete testee separement (D2) : resultat rigoureusement identique a D1
  // (sans marge) sur les 16 valeurs p9c ET p9d — elle est redondante avec
  // la neutralisation 3px du cadre deja faite en amont (voir P9o-A,
  // au-dessus dans detectRoomEdges), donc non reprise ici.
  final floorLines =
      horizontals.where((l) => (l.y1 + l.y2) / 2 >= hmid * 0.65).toList()
        ..sort((a, b) => b.score.compareTo(a.score));

  return _Classified(
    ceiling: ceilLines.isNotEmpty ? ceilLines.first : null,
    floor: floorLines.isNotEmpty ? floorLines.first : null,
    leftDiags: leftDiags,
    rightDiags: rightDiags,
  );
}

class _Pt {
  final double x, y;
  const _Pt(this.x, this.y);
}

/// Point de fuite = intersection des fuyantes gauche/droite (médiane
/// robuste si plusieurs candidats), fallback centre/plafond sinon.
_Pt _computeVanishingPoint(_Classified cls, int w, int h) {
  final intersections = <_Pt>[];
  final lds = cls.leftDiags.length > 4
      ? cls.leftDiags.sublist(0, 4)
      : cls.leftDiags;
  final rds = cls.rightDiags.length > 4
      ? cls.rightDiags.sublist(0, 4)
      : cls.rightDiags;

  for (final ld in lds) {
    for (final rd in rds) {
      final pt = _lineIntersection(ld, rd);
      if (pt != null &&
          pt.x > -w * 0.5 &&
          pt.x < w * 1.5 &&
          pt.y > -h &&
          pt.y < h * 2) {
        intersections.add(pt);
      }
    }
  }

  if (intersections.isNotEmpty) {
    final xs = intersections.map((p) => p.x).toList()..sort();
    final ys = intersections.map((p) => p.y).toList()..sort();
    return _Pt(xs[xs.length ~/ 2], ys[ys.length ~/ 2]);
  }

  final ceilY = cls.ceiling != null
      ? (cls.ceiling!.y1 + cls.ceiling!.y2) / 2
      : h * 0.25;
  return _Pt(w * 0.5, ceilY);
}

_Pt? _lineIntersection(_HLine l1, _HLine l2) {
  final dx1 = l1.x2 - l1.x1, dy1 = l1.y2 - l1.y1;
  final dx2 = l2.x2 - l2.x1, dy2 = l2.y2 - l2.y1;
  final denom = dx1 * dy2 - dy1 * dx2;
  if (denom.abs() < 1e-6) return null;
  final t = ((l2.x1 - l1.x1) * dy2 - (l2.y1 - l1.y1) * dx2) / denom;
  return _Pt(l1.x1 + t * dx1, l1.y1 + t * dy1);
}

/// Interpole (jamais n'extrapole au-delà d'une marge raisonnable) la
/// hauteur Y de la droite [l] à l'abscisse [x]. [x] est ramené dans les
/// bornes du segment détecté ÉLARGIES de 25% avant interpolation — cela
/// permet d'extrapoler légèrement la ligne jusqu'aux bords de l'image
/// (nécessaire pour placer wallTL/wallTR/wallBL/wallBR, voir
/// [_buildGeometry]) sans pour autant partir dans des valeurs aberrantes
/// quand le point de fuite calculé tombe loin en dehors de l'image
/// (bruit du Hough sur une photo peu perspectivée), qui sinon déforment
/// tout le rendu du produit (effet "nœud papillon"/X observé en pratique).
double _lineYAtX(_HLine l, double x, {double marginFrac = 0.0}) {
  if ((l.x2 - l.x1).abs() < 1e-3) return (l.y1 + l.y2) / 2;
  final xMin0 = math.min(l.x1, l.x2);
  final xMax0 = math.max(l.x1, l.x2);
  final span = xMax0 - xMin0;
  final xMin = xMin0 - span * marginFrac;
  final xMax = xMax0 + span * marginFrac;
  final xc = x.clamp(xMin, xMax);
  final t = (xc - l.x1) / (l.x2 - l.x1);
  return l.y1 + t * (l.y2 - l.y1);
}

// Note : l'ancienne fonction `_estimateWallX` (projection des fuyantes
// latérales pour estimer le X du mur du fond) a été retirée — elle
// était la source du bug du grand "X" en diagonale sur les photos
// complexes (cadres, meubles créant de fausses fuyantes). Les positions
// X du mur du fond sont désormais fixes (voir `_buildGeometry`), seule
// la pente réelle du plafond/sol détecté fait varier Y.

/// Construit la calibration finale (8 points % image) + confiance à
/// partir des droites classifiées et du point de fuite calculé.
///
/// ⚠️ CORRECTION du bug du grand "X" en diagonale : la version
/// précédente calculait les positions X du mur du fond (ceilXL/ceilXR/
/// floorXL/floorXR) en cherchant où les droites DIAGONALES (fuyantes
/// latérales) croisent la hauteur du plafond/sol (`_estimateWallX`).
/// Sur une photo réelle chargée (cadre de miroir en angle, montants de
/// porte, meubles), les diagonales détectées par le Hough sont souvent
/// des faux positifs sans rapport avec les vraies fuyantes de la pièce
/// — leur intersection avec la ligne plafond produit des X totalement
/// erratiques, parfois inversés d'un côté à l'autre entre plafond et
/// sol, ce qui dessine le grand "X"/nœud papillon en diagonale au lieu
/// d'un bandeau suivant le plafond.
///
/// Nouvelle approche, plus robuste : on garde des positions X FIXES
/// (comme [PerspCalib.defaultCalib], 20%/80% de la largeur) — seule la
/// PENTE (inclinaison) de la vraie ligne plafond/sol détectée par le
/// Hough est utilisée pour faire varier Y entre le côté gauche et le
/// côté droit. C'est la partie la plus fiable de la détection (une
/// ligne horizontale nette du plafond/sol est un signal fort et stable,
/// contrairement à la classification gauche/droite des diagonales) et
/// c'est exactement ce qui permet au produit d'épouser l'inclinaison
/// réelle du plafond/sol visible sur la photo.
EdgeDetectResult? _buildGeometry(_Classified cls, _Pt vp, int wW, int wH) {
  double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  // Positions X fixes du mur du fond (comme la calibration par défaut)
  // — évite toute dépendance aux diagonales latérales potentiellement
  // bruitées.
  final xL = wW * 0.20;
  final xR = wW * 0.80;

  double ceilY, floorY, ceilYL, ceilYR, floorYL, floorYR;

  if (cls.ceiling != null) {
    final l = cls.ceiling!;
    // marginFrac généreux : xL/xR (20%/80%) peuvent être hors du
    // segment détecté (souvent plus court que l'image) — on suit la
    // pente réelle de la droite en l'extrapolant modérément.
    ceilYL = _lineYAtX(l, xL, marginFrac: 1.0);
    ceilYR = _lineYAtX(l, xR, marginFrac: 1.0);
    ceilY = (ceilYL + ceilYR) / 2;
  } else {
    ceilY = wH * 0.22;
    ceilYL = ceilY;
    ceilYR = ceilY;
  }

  if (cls.floor != null) {
    final l = cls.floor!;
    floorYL = _lineYAtX(l, xL, marginFrac: 1.0);
    floorYR = _lineYAtX(l, xR, marginFrac: 1.0);
    floorY = (floorYL + floorYR) / 2;
  } else {
    floorY = wH * 0.78;
    floorYL = floorY;
    floorYR = floorY;
  }

  // Garde-fous de sanité géométrique : la pente d'une photo de pièce
  // réelle reste modérée (une inclinaison trop forte trahit une fausse
  // détection — reflet, cadre en biais...). On plafonne l'écart entre
  // les deux côtés à 12% de la hauteur de l'image, et on exige un écart
  // plafond/sol suffisant pour représenter un vrai mur du fond.
  final maxTilt = wH * 0.12;
  double clampTilt(double yl, double yr, double yMid) {
    final dl = (yl - yMid).clamp(-maxTilt, maxTilt);
    return yMid + dl;
  }

  ceilYL = clampTilt(ceilYL, ceilYR, ceilY);
  ceilYR = clampTilt(ceilYR, ceilYL, ceilY);
  floorYL = clampTilt(floorYL, floorYR, floorY);
  floorYR = clampTilt(floorYR, floorYL, floorY);

  if (ceilY >= floorY) {
    final ty = ceilY;
    ceilY = floorY;
    floorY = ty;
    final tyl = ceilYL, tyr = ceilYR;
    ceilYL = floorYL;
    ceilYR = floorYR;
    floorYL = tyl;
    floorYR = tyr;
  }

  final yGapOk = (floorY - ceilY) / wH >= 0.10; // au moins 10% de hauteur
  if (!yGapOk) return null;

  final hasCeil = cls.ceiling != null;
  final hasFloor = cls.floor != null;
  final hasLeft = cls.leftDiags.isNotEmpty;
  final hasRight = cls.rightDiags.isNotEmpty;
  final confidence =
      (hasCeil ? 0.30 : 0.05) +
      (hasFloor ? 0.30 : 0.05) +
      (hasLeft ? 0.20 : 0.05) +
      (hasRight ? 0.20 : 0.05);

  if (confidence < _minConfidence) return null;

  CalibPoint norm(double x, double y) =>
      CalibPoint(xPct: clamp01(x / wW), yPct: clamp01(y / wH));

  // Coins des murs latéraux (wallTL/TR/BL/BR) : rapprochés
  // proportionnellement de ceilY/floorY (comme [PerspCalib.defaultCalib]
  // : wallTL.y=0.08 vs ceilL.y=0.15) plutôt que fixés aux coins absolus
  // de l'image — sinon un plafond détecté loin du haut de l'image (ex:
  // 35% de hauteur) créerait une bande murale latérale disproportionnée.
  final ceilYPct = clamp01(ceilY / wH);
  final floorYPct = clamp01(floorY / wH);
  final wallTopYPct = clamp01(ceilYPct + 0.010);
  final wallBotYPct = clamp01(floorYPct + 0.020);

  final calib = PerspCalib(
    ceilL: norm(xL, ceilYL),
    ceilR: norm(xR, ceilYR),
    floorL: norm(xL, floorYL),
    floorR: norm(xR, floorYR),
    wallTL: CalibPoint(xPct: 0.0, yPct: wallTopYPct),
    wallTR: CalibPoint(xPct: 1.0, yPct: wallTopYPct),
    wallBL: CalibPoint(xPct: 0.0, yPct: wallBotYPct),
    wallBR: CalibPoint(xPct: 1.0, yPct: wallBotYPct),
  );

  return EdgeDetectResult(calib: calib, confidence: confidence);
}

// ============================================================================
// P10 — sonde diagnostique ADDITIVE (aucune ligne existante ci-dessus n'est
// modifiée). Objectif unique : exposer, pour `test/core/perspective/
// p10_image_reading_probe_test.dart`, les données intermédiaires de
// `detectRoomEdges` (lignes Hough, classification enrichie, intersections
// diagonales, point de fuite, inliers, plafond/sol choisis) qui sont
// aujourd'hui invisibles depuis l'extérieur car portées par des types/
// fonctions privés (`_HLine`, `_Classified`, `_houghLines`, etc. — la
// visibilité `_` de Dart est PAR FICHIER, donc un fichier de test externe
// ne peut pas y accéder). La seule façon d'exposer ces données sans toucher
// au pipeline de production est d'ajouter ici, dans le même fichier, une
// fonction supplémentaire qui rejoue EXACTEMENT les mêmes étapes/constantes
// que `detectRoomEdges` (même downscale, même Sobel, même Hough, même
// clustering, même cap par bande, même `_classifyLines`, même
// `_computeVanishingPoint`, même `_buildGeometry` appelé sans modification)
// et capture au passage les informations demandées. `detectRoomEdges` et
// `_buildGeometry` ne sont ni modifiés ni dupliqués dans leur logique
// géométrique : ils sont appelés tels quels.
// ============================================================================

/// Une droite Hough exposée pour diagnostic (theta/rho/score/longueur/
/// endpoints en xPct/yPct + classification enrichie).
///
/// Classification enrichie (distincte de la classification interne de
/// `_classifyLines`, qui ne connaît que horizontal/left-diag/right-diag et
/// ignore silencieusement le reste) :
///   - `horizontal`      : angle ligne <=15° ou >=165° (candidat plafond/sol)
///   - `diagonal_left`   : angle ligne dans ]15°,55°]  (fuyante gauche)
///   - `diagonal_right`  : angle ligne dans ]125°,165°[ (fuyante droite)
///   - `vertical`        : angle ligne dans ]75°,105°[ (quasi-verticale,
///                         jamais utilisée par le pipeline de production)
///   - `ignored`         : reste (]55°,75°] ou [105°,125°]) — zone
///                         ambiguë, ni assez plate pour une fuyante latérale,
///                         ni assez verticale pour `vertical` ; c'est
///                         exactement la zone que `_classifyLines` élimine
///                         déjà silencieusement en production.
class LineDiagnostic {
  final double theta;
  final double rho;
  final double score;
  final double length;
  final double x1Pct, y1Pct, x2Pct, y2Pct;
  final String classification;

  const LineDiagnostic({
    required this.theta,
    required this.rho,
    required this.score,
    required this.length,
    required this.x1Pct,
    required this.y1Pct,
    required this.x2Pct,
    required this.y2Pct,
    required this.classification,
  });

  Map<String, dynamic> toJson() => {
    'theta': theta,
    'rho': rho,
    'houghScore': score,
    'length': length,
    'x1Pct': x1Pct,
    'y1Pct': y1Pct,
    'x2Pct': x2Pct,
    'y2Pct': y2Pct,
    'classification': classification,
  };
}

/// Une intersection entre une fuyante gauche et une fuyante droite,
/// exposée pour diagnostic (mêmes bornes de validité que
/// `_computeVanishingPoint`, reproduites sans modification de cette
/// fonction).
class IntersectionDiagnostic {
  final double xPct;
  final double yPct;

  const IntersectionDiagnostic({required this.xPct, required this.yPct});

  Map<String, dynamic> toJson() => {'xPct': xPct, 'yPct': yPct};
}

/// Résultat complet de la sonde diagnostique P10 pour une image donnée.
class EdgeDetectDiagnostics {
  /// Toutes les droites Hough survivant au clustering + cap par bande
  /// (== l'ensemble réellement soumis à `_classifyLines` en production),
  /// avec classification enrichie.
  final List<LineDiagnostic> lines;

  /// Intersections gauche×droite retenues comme valides par
  /// `_computeVanishingPoint` (mêmes bornes, même troncature à 4
  /// lignes/côté).
  final List<IntersectionDiagnostic> diagonalIntersections;

  /// Estimation du point de fuite (fraction de l'image de travail),
  /// `null` seulement si la classification a échoué avant ce calcul
  /// (`_classifyLines` a renvoyé `null`, aucune horizontale trouvée).
  final double? vpXPct;
  final double? vpYPct;

  /// Nombre de droites diagonales DISTINCTES (gauche + droite confondues)
  /// ayant participé à au moins une intersection valide retenue ci-dessus
  /// — c'est la mesure directe du critère de décision du brief P10
  /// (">= 3 lignes diagonales inliers").
  final int inlierDiagonalCount;

  final LineDiagnostic? chosenCeiling;
  final LineDiagnostic? chosenFloor;

  /// Calibration 8 points générée par `_buildGeometry` — `null` si
  /// `_buildGeometry` a rejeté la détection (écart plafond/sol
  /// insuffisant, ou confiance < seuil minimum).
  final PerspCalib? calib;

  /// Confiance — reproduit ICI la formule de `_buildGeometry`
  /// (`(hasCeil?0.30:0.05)+(hasFloor?0.30:0.05)+(hasLeft?0.20:0.05)+
  /// (hasRight?0.20:0.05)`), calculée indépendamment pour rester
  /// disponible même quand `_buildGeometry` rejette la détection AVANT
  /// d'atteindre son propre calcul de confiance (le test `yGapOk` est
  /// évalué avant, voir `_buildGeometry` ci-dessus) — sans cette
  /// duplication, aucune confiance ne serait mesurable dans ce cas précis.
  /// Formule dupliquée volontairement à l'identique, jamais modifiée
  /// séparément de l'original (voir commentaire au site d'appel).
  final double confidence;

  /// `true` si et seulement si `detectRoomEdges` (production, appelé sans
  /// modification) aurait renvoyé un résultat non-null pour cette image —
  /// c'est-à-dire `_buildGeometry` a validé à la fois `yGapOk` ET
  /// `confidence >= _minConfidence`. Reflet exact du comportement réel de
  /// l'app, pas un seuil recalculé séparément.
  final bool usable;

  const EdgeDetectDiagnostics({
    required this.lines,
    required this.diagonalIntersections,
    required this.vpXPct,
    required this.vpYPct,
    required this.inlierDiagonalCount,
    required this.chosenCeiling,
    required this.chosenFloor,
    required this.calib,
    required this.confidence,
    required this.usable,
  });

  Map<String, dynamic> toJson() => {
    'lines': lines.map((l) => l.toJson()).toList(),
    'diagonalIntersections': diagonalIntersections
        .map((i) => i.toJson())
        .toList(),
    'vanishingPoint': (vpXPct == null || vpYPct == null)
        ? null
        : {'xPct': vpXPct, 'yPct': vpYPct},
    'inlierDiagonalCount': inlierDiagonalCount,
    'chosenCeiling': chosenCeiling?.toJson(),
    'chosenFloor': chosenFloor?.toJson(),
    'perspCalib': calib?.toJson(),
    'confidence': confidence,
    'verdict': usable ? 'usable' : 'not usable',
  };
}

/// Angle de ligne (0-180°) enrichi en 5 catégories pour diagnostic
/// uniquement — voir docstring de [LineDiagnostic]. N'affecte en rien
/// `_classifyLines` (non modifiée, appelée séparément ci-dessous).
String _diagClassify(_HLine l) {
  final a = _lineAngle(l);
  if (a <= 15 || a >= 165) return 'horizontal';
  if (a > 15 && a <= 55) return 'diagonal_left';
  if (a > 125 && a < 165) return 'diagonal_right';
  if (a > 75 && a < 105) return 'vertical';
  return 'ignored';
}

LineDiagnostic _toLineDiagnostic(_HLine l, int wW, int wH) {
  final length = math.sqrt(
    (l.x2 - l.x1) * (l.x2 - l.x1) + (l.y2 - l.y1) * (l.y2 - l.y1),
  );
  return LineDiagnostic(
    theta: l.theta,
    rho: l.rho,
    score: l.score,
    length: length,
    x1Pct: l.x1 / wW,
    y1Pct: l.y1 / wH,
    x2Pct: l.x2 / wW,
    y2Pct: l.y2 / wH,
    classification: _diagClassify(l),
  );
}

/// Sonde diagnostique P10 — voir docstring de section ci-dessus. Rejoue
/// EXACTEMENT le même pipeline que `detectRoomEdges` (mêmes constantes,
/// même ordre d'appels, `_buildGeometry` non modifié et appelé tel quel)
/// et capture les données intermédiaires demandées par le brief P10.
/// Ne lève jamais d'exception (`resolve(null)` en cas d'erreur, comme
/// `detectRoomEdges`).
Future<EdgeDetectDiagnostics?> detectRoomEdgesDiagnostic(ui.Image image) async {
  try {
    final srcW = image.width;
    final srcH = image.height;
    if (srcW == 0 || srcH == 0) return null;

    final scale = _workW / srcW;
    final wW = _workW;
    final wH = (srcH * scale).round().clamp(40, 2000);

    final small = await _downscale(image, wW, wH);
    final byteData = await small.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    small.dispose();
    if (byteData == null) return null;
    final px = byteData.buffer.asUint8List();

    final gray = _toGray(px, wW, wH);
    final blurred = _blur3x3(gray, wW, wH);
    final edges = _sobel(blurred, wW, wH, _sobelTh);

    const borderPx = 3;
    for (var y = 0; y < wH; y++) {
      for (var x = 0; x < wW; x++) {
        if (y < borderPx ||
            y >= wH - borderPx ||
            x < borderPx ||
            x >= wW - borderPx) {
          edges[y * wW + x] = 0;
        }
      }
    }

    final rawLines = _houghLines(edges, wW, wH, _houghThFrac);
    if (rawLines.isEmpty) {
      return const EdgeDetectDiagnostics(
        lines: [],
        diagonalIntersections: [],
        vpXPct: null,
        vpYPct: null,
        inlierDiagonalCount: 0,
        chosenCeiling: null,
        chosenFloor: null,
        calib: null,
        confidence: 0.0,
        usable: false,
      );
    }

    final clustered = _clusterLines(rawLines, _clusterAngleDeg, _clusterRho);
    final capped = _capParBande(clustered, 20);
    final lineDiags = capped.map((l) => _toLineDiagnostic(l, wW, wH)).toList();

    final cls = _classifyLines(capped, wW, wH);
    if (cls == null) {
      return EdgeDetectDiagnostics(
        lines: lineDiags,
        diagonalIntersections: const [],
        vpXPct: null,
        vpYPct: null,
        inlierDiagonalCount: 0,
        chosenCeiling: null,
        chosenFloor: null,
        calib: null,
        confidence: 0.0,
        usable: false,
      );
    }

    // Intersections diagonales + inliers — reproduit à l'identique la
    // boucle de `_computeVanishingPoint` (même troncature à 4 lignes/
    // côté, mêmes bornes de validité) pour capturer chaque intersection
    // retenue et les droites qui l'ont produite, SANS modifier
    // `_computeVanishingPoint` : elle est appelée normalement juste après
    // pour obtenir le VP final réellement utilisé par le pipeline.
    final lds = cls.leftDiags.length > 4
        ? cls.leftDiags.sublist(0, 4)
        : cls.leftDiags;
    final rds = cls.rightDiags.length > 4
        ? cls.rightDiags.sublist(0, 4)
        : cls.rightDiags;
    final diagInter = <IntersectionDiagnostic>[];
    final inlierLines = <_HLine>{};
    for (final ld in lds) {
      for (final rd in rds) {
        final pt = _lineIntersection(ld, rd);
        if (pt != null &&
            pt.x > -wW * 0.5 &&
            pt.x < wW * 1.5 &&
            pt.y > -wH &&
            pt.y < wH * 2) {
          diagInter.add(
            IntersectionDiagnostic(xPct: pt.x / wW, yPct: pt.y / wH),
          );
          inlierLines.add(ld);
          inlierLines.add(rd);
        }
      }
    }

    final vp = _computeVanishingPoint(cls, wW, wH);
    final result = _buildGeometry(cls, vp, wW, wH);

    // Confiance dupliquée à l'identique de `_buildGeometry` (voir
    // docstring de [EdgeDetectDiagnostics.confidence]) pour rester
    // mesurable même quand `_buildGeometry` rejette avant d'y arriver.
    final hasCeil = cls.ceiling != null;
    final hasFloor = cls.floor != null;
    final hasLeft = cls.leftDiags.isNotEmpty;
    final hasRight = cls.rightDiags.isNotEmpty;
    final confidence =
        (hasCeil ? 0.30 : 0.05) +
        (hasFloor ? 0.30 : 0.05) +
        (hasLeft ? 0.20 : 0.05) +
        (hasRight ? 0.20 : 0.05);

    return EdgeDetectDiagnostics(
      lines: lineDiags,
      diagonalIntersections: diagInter,
      vpXPct: vp.x / wW,
      vpYPct: vp.y / wH,
      inlierDiagonalCount: inlierLines.length,
      chosenCeiling: cls.ceiling == null
          ? null
          : _toLineDiagnostic(cls.ceiling!, wW, wH),
      chosenFloor: cls.floor == null
          ? null
          : _toLineDiagnostic(cls.floor!, wW, wH),
      calib: result?.calib,
      confidence: confidence,
      usable: result != null,
    );
  } catch (_) {
    return null;
  }
}

// ============================================================================
// Sonde complémentaire (additive, lecture seule) : expose les 3 états
// successifs de la liste de lignes que `detectRoomEdges`/
// `detectRoomEdgesDiagnostic` traversent en interne, SANS ajouter ni
// retirer aucune étape : (a) `rawLines` = sortie brute de `_houghLines`
// (avant tout filtrage), (b) `clustered` = sortie de `_clusterLines`
// (fusion des doublons proches en angle+rho), (c) `capped` = sortie de
// `_capParBande` (troncature à N par bande angulaire — c'est exactement
// la liste `capped` que `detectRoomEdges` transmet ensuite à
// `_classifyLines`, aucune différence). Les trois appels ci-dessous sont
// rigoureusement identiques à ceux de `detectRoomEdgesDiagnostic`
// (mêmes constantes `_houghThFrac`/`_clusterAngleDeg`/`_clusterRho`/20),
// aucune nouvelle logique de filtrage n'est introduite.
class EdgeDetectStages {
  final List<LineDiagnostic> rawLines;
  final List<LineDiagnostic> clustered;
  final List<LineDiagnostic> capped;
  const EdgeDetectStages({
    required this.rawLines,
    required this.clustered,
    required this.capped,
  });
}

Future<EdgeDetectStages?> detectRoomEdgesStages(ui.Image image) async {
  try {
    final srcW = image.width;
    final srcH = image.height;
    if (srcW == 0 || srcH == 0) return null;

    final scale = _workW / srcW;
    final wW = _workW;
    final wH = (srcH * scale).round().clamp(40, 2000);

    final small = await _downscale(image, wW, wH);
    final byteData = await small.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    small.dispose();
    if (byteData == null) return null;
    final px = byteData.buffer.asUint8List();

    final gray = _toGray(px, wW, wH);
    final blurred = _blur3x3(gray, wW, wH);
    final edges = _sobel(blurred, wW, wH, _sobelTh);

    const borderPx = 3;
    for (var y = 0; y < wH; y++) {
      for (var x = 0; x < wW; x++) {
        if (y < borderPx ||
            y >= wH - borderPx ||
            x < borderPx ||
            x >= wW - borderPx) {
          edges[y * wW + x] = 0;
        }
      }
    }

    final rawLines = _houghLines(edges, wW, wH, _houghThFrac);
    final clustered = rawLines.isEmpty
        ? <_HLine>[]
        : _clusterLines(rawLines, _clusterAngleDeg, _clusterRho);
    final capped = clustered.isEmpty
        ? <_HLine>[]
        : _capParBande(clustered, 20);

    return EdgeDetectStages(
      rawLines: rawLines.map((l) => _toLineDiagnostic(l, wW, wH)).toList(),
      clustered: clustered.map((l) => _toLineDiagnostic(l, wW, wH)).toList(),
      capped: capped.map((l) => _toLineDiagnostic(l, wW, wH)).toList(),
    );
  } catch (_) {
    return null;
  }
}
