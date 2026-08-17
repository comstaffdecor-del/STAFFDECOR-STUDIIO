/// Rendu unifié Corniche/Plinthe en perspective réelle avec onglets
/// géométriques aux angles — bande CONTINUE mur latéral G → fond → mur
/// latéral D, exactement comme le ferait un logiciel de CAO (Autocad/Revit).
///
/// ⚠️ CORRECTION Bug #1 (audit rendering) — le cœur du problème signalé
/// par l'utilisateur ("pas les vrai rendus, pas de prise en compte des
/// perspectives"). Dans l'ancienne version :
///   - Le rendu RÉELLEMENT affiché (`_drawSliderCornicePlinth`) traçait
///     une simple `ctx.fillRect()` HORIZONTALE PLATE sur toute la largeur
///     de l'image, aucune perspective, aucun onglet.
///   - Les fonctions géométriquement correctes (`drawCorniceSet`,
///     `drawPlintheSet`, `_drawCorniceStrip`, `_drawPlinthStrip`,
///     `_seg2Intersect`) existaient dans `_drawArchitectureOnRoomCanvas`
///     mais n'étaient JAMAIS appelées pour ces deux familles (le bloc
///     `forEach` correspondant contenait un commentaire "Rien ici").
///
/// Ce fichier est le port fidèle de cette géométrie morte, désormais
/// RÉELLEMENT exécutée : onglets par intersection de droites
/// (`lineIntersect`), 3 segments (latéral G / fond / latéral D) tracés
/// comme UNE bande continue, faces plafond/sol convergeant vers le
/// vrai [VanishingPoint] calculé par [VanishingPoint.compute].
library;

import 'dart:math' as math;
import 'dart:ui';
import 'persp_geometry.dart';
import 'vanishing_point.dart';
import 'profile_strip.dart';
import 'strip_px_from_dims.dart';

/// ⚠️ CORRECTION Bug "bande diagonale décrochée" (retour utilisateur :
/// "aucun suivi de la perspective... l'appli doit fonctionner avec
/// n'importe quel visuel").
///
/// [lineIntersect] (droites wallTLb→fTLbG et fTLbF→fTRbF) n'est fiable
/// géométriquement QUE si les deux murs forment un VRAI angle (coin de
/// pièce). Or beaucoup de photos (dont les 4 scènes démo) sont des prises
/// quasi-frontales du mur du fond, SANS vrai coin visible : le point de
/// calibration [wallTL]/[wallTR] est alors quasi-ALIGNÉ avec la ligne
/// plafond/sol (angle réel de quelques degrés). Dans ce cas, l'intersection
/// de deux droites quasi-parallèles part arbitrairement loin (démontré :
/// pour la scène Haussmannienne, le point d'onglet calculé se retrouvait à
/// ~300px du point attendu) — c'est EXACTEMENT la bande diagonale
/// décrochée observée. On mesure ici la "netteté" du coin réel (sinus de
/// l'angle entre le segment latéral et le segment du fond) : si le coin
/// est quasi-plat (< ~7°, pas un vrai coin de mur), on renonce au calcul
/// d'onglet par intersection et on retombe sur la simple perpendiculaire
/// — cela reste vrai pour N'IMPORTE QUELLE calibration (photo importée,
/// calibration manuelle, IA), pas seulement les 4 démos.
double _cornerSharpness(Offset a, Offset b, Offset c) {
  final v1x = b.dx - a.dx, v1y = b.dy - a.dy;
  final v2x = c.dx - b.dx, v2y = c.dy - b.dy;
  final l1 = math.sqrt(v1x * v1x + v1y * v1y);
  final l2 = math.sqrt(v2x * v2x + v2y * v2y);
  if (l1 < 0.001 || l2 < 0.001) return 0.0;
  final cross = (v1x * v2y - v1y * v2x).abs();
  return cross / (l1 * l2); // |sin(angle)| : 0 = coin plat, 1 = perpendiculaire
}

/// Seuil sous lequel un "coin" est considéré trop plat pour un onglet
/// géométrique fiable (sin(7°) ≈ 0.12).
const double _kFlatCornerThreshold = 0.12;

/// Épaisseurs (en px canvas, dérivées de `pH` = hauteur perspective du
/// mur du fond) pour un segment de corniche ou de plinthe.
class StripThickness {
  final double faceMurFond; // hauteur face mur, segment du fond
  final double faceHorizFond; // profondeur face plafond/sol, segment du fond
  final double faceMurLat; // hauteur face mur, murs latéraux (plus grande = plus proche)
  final double faceHorizLat; // profondeur face plafond/sol, murs latéraux

  const StripThickness({
    required this.faceMurFond,
    required this.faceHorizFond,
    required this.faceMurLat,
    required this.faceHorizLat,
  });

  /// Épaisseurs par défaut pour une CORNICHE, proportionnelles à [pH]
  /// (port exact des coefficients 0.055/0.140 fond, 0.080/0.200 latéral
  /// de l'ancien code mort `Corniches_DISABLED`).
  ///
  /// Délègue à [corniceDefaultPx] (`strip_px_from_dims.dart`) : les
  /// coefficients ne sont plus portés en dur ici — ce fichier importe la
  /// valeur au lieu de la définir, pour la même raison que
  /// `stripPxFromDims` ne porte plus les siens (une seule source de
  /// vérité, voir la docstring de `corniceDefaultPx`).
  factory StripThickness.corniceDefault(double pH) =>
      StripThickness.fromPx(corniceDefaultPx(pH));

  /// Épaisseurs par défaut pour une PLINTHE (coefficients 0.065/0.115
  /// fond, 0.095/0.165 latéral — port exact de `Plinthes_DISABLED`).
  factory StripThickness.plintheDefault(double pH) => StripThickness(
    faceMurFond: pH * 0.065,
    faceHorizFond: pH * 0.115,
    faceMurLat: pH * 0.095,
    faceHorizLat: pH * 0.165,
  );

  /// Construit un [StripThickness] à partir d'un [StripPxResult] déjà
  /// résolu (dimensions réelles du profil converties en pixels canvas,
  /// voir `strip_px_from_dims.dart`).
  ///
  /// Factory PURE : copie 1:1 les 4 champs de [StripPxResult] vers les 4
  /// champs de [StripThickness] (mêmes 4 grandeurs, même unité px), sans
  /// aucun calcul. Volontairement placée ICI (dans ce fichier, qui
  /// importe déjà `dart:ui`) plutôt que côté `strip_px_from_dims.dart` —
  /// ce dernier reste pur et sans dépendance vers le peintre ; c'est ce
  /// fichier qui dépend de la conversion mm→px, jamais l'inverse.
  ///
  /// Cette factory ne gère PAS le cas où la conversion n'a pas pu être
  /// calculée (dimensions absentes, `metresHauteur<=0`) : dans ce cas,
  /// `stripPxFromDims` renvoie `null` et c'est à l'appelant de retomber
  /// sur [StripThickness.corniceDefault]/[StripThickness.plintheDefault]
  /// plutôt que d'appeler cette factory.
  factory StripThickness.fromPx(StripPxResult r) => StripThickness(
    faceMurFond: r.faceMurFondPx,
    faceHorizFond: r.faceHorizFondPx,
    faceMurLat: r.faceMurLatPx,
    faceHorizLat: r.faceHorizLatPx,
  );
}

/// Sélection pure de l'épaisseur à utiliser pour une CORNICHE : si [r]
/// (résultat déjà résolu de `stripPxFromDims`, voir `strip_px_from_dims.dart`)
/// est disponible, on l'utilise (`StripThickness.fromPx`) ; sinon on retombe
/// sur [StripThickness.corniceDefault].
///
/// Extraite du site d'appel `room_painter.dart` (case 'Corniches') pour
/// rendre le verrouillage bit-à-bit testable SANS `TestWidgetsFlutterBinding`
/// ni rendu : une simple assertion à quatre champs sur un appel de fonction.
/// `paint()` se réduit alors à `th: corniceFor(r, pH)`.
///
/// Ne concerne QUE les corniches — la plinthe garde
/// `StripThickness.plintheDefault(pH)` en dur au site d'appel, aucun profil
/// JSON de plinthe n'existant à ce jour dans le catalogue (voir docstring
/// de `strip_px_from_dims.dart`).
StripThickness corniceFor(StripPxResult? r, double pH) =>
    r == null ? StripThickness.corniceDefault(pH) : StripThickness.fromPx(r);

/// Dessine une corniche continue de [wallTL] à [wallTR], en passant par
/// [fTL]→[fTR] (mur du fond), avec onglets géométriques réels aux angles
/// si les murs latéraux existent (longueur > 8px canvas — même seuil que
/// l'original `hasLatG`/`hasLatD`).
void paintCorniceSet(
  Canvas canvas,
  VanishingPoint vpModel, {
  required Offset fTL,
  required Offset fTR,
  required Offset wallTL,
  required Offset wallTR,
  required StripThickness th,
  required double ratio,
  Image? texture,
}) {
  final lenLatG = dist(fTL, wallTL);
  final lenLatD = dist(wallTR, fTR);
  final hasLatG = lenLatG > 8;
  final hasLatD = lenLatD > 8;

  // 1. Perpendiculaire du mur fond (toujours présente).
  final dpFond = perpDown(fTL, fTR, th.faceMurFond);
  final fTLbF = fTL + dpFond;
  final fTRbF = fTR + dpFond;

  // 2. Onglets — seulement si les murs latéraux existent.
  var ongletL = fTLbF;
  var ongletR = fTRbF;
  var wallTLb = fTLbF;
  var wallTRb = fTRbF;

  // ⚠️ CORRECTION Bug "bande cassée en 3 segments avec becs pointus"
  // (retour utilisateur, capture Contemporain/D570) — quand le coin est
  // détecté "plat" (pas de vrai angle de mur photographié, juste une
  // estimation de mur latéral quasi-alignée avec la ligne plafond), le
  // segment latéral utilisait quand même l'épaisseur [faceMurLat]
  // (0.080·pH), DIFFÉRENTE de celle du segment du fond [faceMurFond]
  // (0.055·pH). Sur un segment latéral court (mur latéral peu profond
  // dans les photos quasi-frontales), ce changement brutal d'épaisseur
  // (~6-9px) au point de jonction crée un décroché net visible — le
  // "bec"/kink polygonal signalé. Sans vrai coin, il n'y a aucune
  // justification de perspective à une épaisseur différente : on utilise
  // alors la MÊME épaisseur que le fond pour ce segment latéral, ce qui
  // produit un bord bas continu, sans discontinuité, épousant la ligne
  // du plafond comme une seule bande lisse.
  if (hasLatG) {
    final sharp = _cornerSharpness(wallTL, fTL, fTR);
    final isFlat = sharp < _kFlatCornerThreshold;
    final latThick = isFlat ? th.faceMurFond : th.faceMurLat;
    final dpLatG = perpDown(wallTL, fTL, latThick);
    final fTLbG = fTL + dpLatG;
    wallTLb = wallTL + dpLatG;
    // Coin réel uniquement si l'angle wallTL→fTL→fTR est net (voir
    // [_cornerSharpness]) — sinon l'intersection de droites quasi-
    // parallèles part arbitrairement loin (bande diagonale décrochée).
    ongletL = !isFlat
        ? (lineIntersect(wallTLb, fTLbG, fTLbF, fTRbF) ?? fTLbF)
        : fTLbF;
  }
  if (hasLatD) {
    final sharp = _cornerSharpness(fTL, fTR, wallTR);
    final isFlat = sharp < _kFlatCornerThreshold;
    final latThick = isFlat ? th.faceMurFond : th.faceMurLat;
    final dpLatD = perpDown(fTR, wallTR, latThick);
    final fTRbD = fTR + dpLatD;
    wallTRb = wallTR + dpLatD;
    ongletR = !isFlat
        ? (lineIntersect(fTLbF, fTRbF, fTRbD, wallTRb) ?? fTRbF)
        : fTRbF;
  }

  // 3. Dessin — bande continue : latéral G, fond, latéral D.
  if (hasLatG) {
    _drawCorniceStrip(
      canvas,
      vpModel,
      wallTL,
      fTL,
      wallTLb,
      ongletL,
      th.faceHorizLat,
      ratio,
      texture,
    );
  }
  _drawCorniceStrip(
    canvas,
    vpModel,
    fTL,
    fTR,
    ongletL,
    ongletR,
    th.faceHorizFond,
    ratio,
    texture,
  );
  if (hasLatD) {
    _drawCorniceStrip(
      canvas,
      vpModel,
      fTR,
      wallTR,
      ongletR,
      wallTRb,
      th.faceHorizLat,
      ratio,
      texture,
    );
  }
}

/// Dessine une plinthe continue de [wallBL] à [wallBR], symétrique de
/// [paintCorniceSet] (monte depuis le sol au lieu de descendre du plafond).
void paintPlintheSet(
  Canvas canvas,
  VanishingPoint vpModel, {
  required Offset fBL,
  required Offset fBR,
  required Offset wallBL,
  required Offset wallBR,
  required StripThickness th,
  required double ratio,
  Image? texture,
}) {
  final lenLatG = dist(fBL, wallBL);
  final lenLatD = dist(wallBR, fBR);
  final hasLatG = lenLatG > 8;
  final hasLatD = lenLatD > 8;

  final upFond = perpUp(fBL, fBR, th.faceMurFond);
  final fBLtF = fBL + upFond;
  final fBRtF = fBR + upFond;

  var ongletL = fBLtF;
  var ongletR = fBRtF;
  var wallBLt = fBLtF;
  var wallBRt = fBRtF;

  // Voir commentaire équivalent dans [paintCorniceSet] : même épaisseur
  // fond/latéral quand le coin est plat, pour éviter le décroché.
  if (hasLatG) {
    final sharp = _cornerSharpness(wallBL, fBL, fBR);
    final isFlat = sharp < _kFlatCornerThreshold;
    final latThick = isFlat ? th.faceMurFond : th.faceMurLat;
    final upLatG = perpUp(wallBL, fBL, latThick);
    final fBLtG = fBL + upLatG;
    wallBLt = wallBL + upLatG;
    ongletL = !isFlat
        ? (lineIntersect(wallBLt, fBLtG, fBLtF, fBRtF) ?? fBLtF)
        : fBLtF;
  }
  if (hasLatD) {
    final sharp = _cornerSharpness(fBL, fBR, wallBR);
    final isFlat = sharp < _kFlatCornerThreshold;
    final latThick = isFlat ? th.faceMurFond : th.faceMurLat;
    final upLatD = perpUp(fBR, wallBR, latThick);
    final fBRtD = fBR + upLatD;
    wallBRt = wallBR + upLatD;
    ongletR = !isFlat
        ? (lineIntersect(fBLtF, fBRtF, fBRtD, wallBRt) ?? fBRtF)
        : fBRtF;
  }

  if (hasLatG) {
    _drawPlinthStrip(
      canvas,
      vpModel,
      wallBL,
      fBL,
      wallBLt,
      ongletL,
      th.faceHorizLat,
      ratio,
      texture,
    );
  }
  _drawPlinthStrip(
    canvas,
    vpModel,
    fBL,
    fBR,
    ongletL,
    ongletR,
    th.faceHorizFond,
    ratio,
    texture,
  );
  if (hasLatD) {
    _drawPlinthStrip(
      canvas,
      vpModel,
      fBR,
      wallBR,
      ongletR,
      wallBRt,
      th.faceHorizLat,
      ratio,
      texture,
    );
  }
}

/// Un segment de corniche avec ses 4 coins exacts.
/// topA/topB = arête haute (ligne plafond) ; botA/botB = arête basse
/// (résultat onglet ou perpendiculaire). Port exact de `_drawCorniceStrip`.
void _drawCorniceStrip(
  Canvas canvas,
  VanishingPoint vp,
  Offset topA,
  Offset topB,
  Offset botA,
  Offset botB,
  double depthPx,
  double ratio,
  Image? texture,
) {
  final len = dist(topA, topB);
  if (len < 2) return;

  // Face plafond : convergence vers VP depuis les deux points hauts.
  final pA = vp.toward(topA, vp.frac(topA, depthPx));
  final pB = vp.toward(topB, vp.frac(topB, depthPx));

  // ① Face MUR — vraie photo produit si chargée, sinon silhouette
  // procédurale pilotée par le ratio réel (fallback).
  drawProfileFace(canvas, topA, topB, botA, botB, ratio: ratio, isPlinthe: false, texture: texture);
  drawEdgeLine(canvas, topA, topB, const Color(0xF2FFFFFF), 2.0);
  drawEdgeLine(canvas, botA, botB, const Color(0x66413426), 0.8);

  // ② Face PLAFOND — plan horizontal convergent vers VP.
  final path = Path()
    ..moveTo(topA.dx, topA.dy)
    ..lineTo(topB.dx, topB.dy)
    ..lineTo(pB.dx, pB.dy)
    ..lineTo(pA.dx, pA.dy)
    ..close();
  final grd = Gradient.linear(topA, pA, const [
    Color(0xE6C3BEB7),
    Color(0xEBF0EDE6),
    Color(0xF2FFFDF8),
    Color(0xCCE6E2DA),
  ], const [0.0, 0.25, 0.65, 1.0]);
  canvas.drawPath(path, Paint()..shader = grd);
  drawEdgeLine(canvas, pA, pB, const Color(0x8CB4ACA2), 0.7);
}

/// Un segment de plinthe. Port exact de `_drawPlinthStrip`.
void _drawPlinthStrip(
  Canvas canvas,
  VanishingPoint vp,
  Offset botA,
  Offset botB,
  Offset topA,
  Offset topB,
  double depthPx,
  double ratio,
  Image? texture,
) {
  final len = dist(botA, botB);
  if (len < 2) return;

  final sA = vp.toward(botA, vp.frac(botA, depthPx));
  final sB = vp.toward(botB, vp.frac(botB, depthPx));

  // ① Face MUR — vraie photo produit si chargée, sinon silhouette
  // procédurale (fallback).
  drawProfileFace(canvas, topA, topB, botA, botB, ratio: ratio, isPlinthe: true, texture: texture);
  drawEdgeLine(canvas, topA, topB, const Color(0xF2FFFFFF), 1.8);
  drawEdgeLine(canvas, botA, botB, const Color(0x61322820), 0.8);

  // ② Face SOL — convergence vers VP.
  final path = Path()
    ..moveTo(botA.dx, botA.dy)
    ..lineTo(botB.dx, botB.dy)
    ..lineTo(sB.dx, sB.dy)
    ..lineTo(sA.dx, sA.dy)
    ..close();
  final grd = Gradient.linear(botA, sA, const [
    Color(0xC7A59E96),
    Color(0xA6D2CDC6),
    Color(0x85F8F5F0),
  ], const [0.0, 0.5, 1.0]);
  canvas.drawPath(path, Paint()..shader = grd);
}
