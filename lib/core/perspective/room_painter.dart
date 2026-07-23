/// Moteur de rendu unifié — orchestre le VP réel + toutes les familles.
///
/// ⚠️ Ce fichier est LE remplaçant unique des 3 systèmes disjoints
/// identifiés par l'audit (Bug #5) :
///   1. `_drawSliderCornicePlinth` (bandes plates sans perspective)
///   2. `renderProductOnPhoto` (VP heuristique, `_drawArchitectureOnRoomCanvas`
///      mort pour Corniches/Plinthes mais vivant pour les autres familles)
///   3. `comparateur.js/_drawProductOverlay` (VP à % fixes 50/40)
///
/// [RoomPainter] est utilisé À LA FOIS par l'écran Studio et l'écran
/// Comparateur (paramètre `withProducts` du côté "après") — même image,
/// même calibration, même VP, même rendu. Une seule vérité.
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../data/catalogue_data.dart';
import '../../models/persp_calib.dart';
import '../../models/project_item.dart';
import '../fam_constants.dart';
import 'calib_canvas.dart';
import 'vanishing_point.dart';
import 'cornice_plinth_painter.dart';
import 'moulure_painter.dart';
import 'other_families_painter.dart';
import 'product_texture_cache.dart';
import 'ratio_lookup.dart';

/// Dessine la pièce (photo + architecture démo si aucune photo) et,
/// optionnellement, les produits sélectionnés en perspective réelle.
class RoomPainter extends CustomPainter {
  final ui.Image? roomImage;
  final ImgDraw? imgDraw;
  final PerspCalib calib;
  final List<ProjectItem> selectedProducts;
  final Map<String, SnapPos> prodPositions;
  final bool withProducts;

  RoomPainter({
    required this.roomImage,
    required this.imgDraw,
    required this.calib,
    required this.selectedProducts,
    required this.prodPositions,
    this.withProducts = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // ── 1. Photo (mode "contain") ou pièce démo générique. ──
    if (roomImage != null && imgDraw != null) {
      final src = Rect.fromLTWH(
        0,
        0,
        roomImage!.width.toDouble(),
        roomImage!.height.toDouble(),
      );
      final dst = Rect.fromLTWH(imgDraw!.dx, imgDraw!.dy, imgDraw!.dw, imgDraw!.dh);
      canvas.drawImageRect(roomImage!, src, dst, Paint());
    } else {
      _paintDemoRoom(canvas, w, h);
    }

    if (!withProducts || selectedProducts.isEmpty) return;

    // ── 2. Calibration → coordonnées canvas → VP réel unique. ──
    final cp = CalibCanvasPoints.fromCalib(calib, imgDraw: imgDraw, w: w, h: h);
    final vp = VanishingPoint.compute(
      fTL: cp.ceilL,
      fTR: cp.ceilR,
      fBL: cp.floorL,
      fBR: cp.floorR,
    );
    final pH = vp.pH;

    final imgTop = imgDraw?.dy ?? 0.0;
    final imgLeft = imgDraw?.dx ?? 0.0;
    final imgW = imgDraw?.dw ?? w;

    // ── 3. Regrouper par famille — règle "1 produit par famille" déjà
    //      garantie par AppState.addToProject, mais on sécurise ici en
    //      ne prenant que le premier item de chaque famille. ──
    final byFam = <String, ProjectItem>{};
    for (final item in selectedProducts) {
      byFam.putIfAbsent(item.famille, () => item);
    }

    for (final entry in byFam.entries) {
      final fam = entry.key;
      final item = entry.value;
      final prod = getProdByRef(item.ref);
      if (prod == null) continue;

      final snapPos = prodPositions[item.ref];
      final snapLine = snapPos?.snapLine ?? (famSnapDefault[fam] ?? 'mid');
      final xPct = snapPos?.xPct ?? 0.5;
      final color = famColors[fam] ?? const Color(0xFFEDEAE4);
      final ratio = resolveProfileRatio(item.ref, fam);

      // ⚠️ CORRECTION Bug motifs — charge (une fois, mis en cache) la
      // VRAIE photo produit staffdecor.fr pour ce ref, et récupère la
      // texture si déjà disponible ; sinon `null` → fallback procédural
      // dans [drawProfileFace]. `ensureLoading` est sûr à appeler à
      // chaque frame (no-op si déjà chargé/en cours/en échec) et
      // déclenche un `notifyListeners()` → repaint dès que l'image
      // réseau arrive (voir [ProductTextureCache]).
      //
      // ⚠️ CORRECTION Bug "aucune ornementation" (retour utilisateur) —
      // les Ornements (pièces uniques : modillons, fleurs de trumeau...)
      // sont désormais également texturés avec la vraie photo produit,
      // au lieu du contour vectoriel abstrait générique précédent.
      if (fam == 'Corniches' || fam == 'Plinthes' || fam == 'Ornements') {
        ProductTextureCache.instance.ensureLoading(prod.ref, prod.img);
      }
      final texture = ProductTextureCache.instance.getIfLoaded(prod.ref);

      switch (fam) {
        case 'Corniches':
          paintCorniceSet(
            canvas,
            vp,
            fTL: cp.ceilL,
            fTR: cp.ceilR,
            wallTL: cp.wallTL,
            wallTR: cp.wallTR,
            th: StripThickness.corniceDefault(pH),
            ratio: ratio,
            texture: texture,
          );
          break;

        case 'Plinthes':
          paintPlintheSet(
            canvas,
            vp,
            fBL: cp.floorL,
            fBR: cp.floorR,
            wallBL: cp.wallBL,
            wallBR: cp.wallBR,
            th: StripThickness.plintheDefault(pH),
            ratio: ratio,
            texture: texture,
          );
          break;

        case 'Moulures':
          paintHorizontalBandSet(
            canvas,
            vp,
            t: snapLineToT(snapLine),
            color: color,
            wFond: pH * 0.045 < 6 ? 6 : pH * 0.045,
            wLat: pH * 0.060 < 8 ? 8 : pH * 0.060,
            canvasW: w,
            canvasH: h,
          );
          break;

        case 'Profils LED':
          paintHorizontalBandSet(
            canvas,
            vp,
            t: 0.06,
            color: color,
            wFond: 3.0,
            wLat: 3.0,
            canvasW: w,
            canvasH: h,
            glowBlur: 6,
          );
          break;

        case 'Lambris':
          paintLambris(canvas, vp, snapLine: snapLine, color: color);
          break;

        case 'Parements':
          paintParements(canvas, vp, color: color);
          break;

        case 'Colonnes':
          paintColonne(canvas, vp, xPct: snapPos != null ? xPct : 0.30, color: color);
          break;

        case 'Encadrements':
          paintEncadrement(
            canvas,
            vp,
            xPct: xPct,
            color: color,
            imgTop: imgTop,
            imgLeft: imgLeft,
            imgW: imgW,
          );
          break;

        case 'Ornements':
          paintOrnement(
            canvas,
            vp,
            xPct: xPct,
            snapLine: snapLine,
            color: color,
            imgLeft: imgLeft,
            imgW: imgW,
            canvasW: w,
            texture: texture,
          );
          break;
      }
    }
  }

  /// Pièce démo générique en perspective réelle (utilisée quand aucune
  /// photo n'a encore été importée), port simplifié de `_drawDemoRoom`.
  void _paintDemoRoom(Canvas canvas, double w, double h) {
    final cp = CalibCanvasPoints.fromCalib(
      PerspCalib.defaultCalib,
      imgDraw: null,
      w: w,
      h: h,
    );
    final ceil = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, cp.ceilL.dy),
        const [Color(0xFFD8D2C8), Color(0xFFEAE4DA)],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, cp.ceilL.dy), ceil);

    final floor = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, cp.floorL.dy),
        Offset(0, h),
        const [Color(0xFFB8A880), Color(0xFF8A7850)],
      );
    canvas.drawRect(Rect.fromLTWH(0, cp.floorL.dy, w, h - cp.floorL.dy), floor);

    final wallBack = Paint()..color = const Color(0xFFF4F0E8);
    final path = Path()
      ..moveTo(cp.ceilL.dx, cp.ceilL.dy)
      ..lineTo(cp.ceilR.dx, cp.ceilR.dy)
      ..lineTo(cp.floorR.dx, cp.floorR.dy)
      ..lineTo(cp.floorL.dx, cp.floorL.dy)
      ..close();
    canvas.drawPath(path, wallBack);

    final edge = Paint()
      ..color = const Color(0xFFA89880)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(cp.ceilL, cp.ceilR, edge);
    canvas.drawLine(cp.floorL, cp.floorR, edge);
    canvas.drawLine(cp.ceilL, cp.floorL, edge);
    canvas.drawLine(cp.ceilR, cp.floorR, edge);
  }

  @override
  bool shouldRepaint(covariant RoomPainter oldDelegate) {
    return oldDelegate.roomImage != roomImage ||
        oldDelegate.imgDraw != imgDraw ||
        oldDelegate.calib != calib ||
        oldDelegate.selectedProducts != selectedProducts ||
        oldDelegate.prodPositions != prodPositions ||
        oldDelegate.withProducts != withProducts;
  }
}
