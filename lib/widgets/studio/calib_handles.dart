/// Poignées de calibration draguables — port fidèle de
/// `#perspective-overlay` (studio.js `_renderCalibHandles` / drag logic).
///
/// 8 points au total, tous désormais modifiables par l'utilisateur (brief
/// "Phase 1 moteur dynamique : calibration complète") :
///   - 4 points du mur du fond (ceilL/ceilR/floorL/floorR) — poignées
///     dorées, GRANDES, visibles comme avant. Taille (22px), couleurs
///     (goldLight/goldDark) et opacité (0.85) strictement identiques à la
///     version précédente de ce fichier : aucun changement de comportement
///     pour ces 4 points.
///   - 4 points des murs latéraux (wallTL/wallTR/wallBL/wallBR) — NOUVEAU.
///     `AppState.updateCalibPoint` savait déjà les modifier (switch complet
///     sur les 8 clés, vérifié par lecture directe de `app_state.dart`),
///     mais aucun chemin UI ne les exposait : cette classe ne construisait
///     jusqu'ici que les 4 poignées ci-dessus. Ces 4 points pilotent le
///     [VanishingPoint] de profondeur (`vanishing_point.dart`), consommé
///     par `RoomPainter._paintOverlays` pour TOUTES les familles produit
///     (Corniches, Plinthes, Moulures, Rosaces, ...) — sans eux, aucune
///     photo importée ne peut être corrigée sur sa vraie profondeur de
///     mur latéral, quelle que soit la qualité de la détection auto.
///     Poignées volontairement plus DISCRÈTES (taille réduite 14px,
///     opacité réduite 0.45) pour ne pas surcharger l'UI existante — même
///     mécanique de drag que les points plafond/sol, aucun nouveau mode,
///     aucune nouvelle logique de calibration : seule l'exposition change.
///
/// ⚠️ Ne modifie PAS `PerspCalib` (modèle inchangé, `models/persp_calib.dart`
/// non touché) ni la logique de `AppState.updateCalibPoint` (switch à 8
/// clés déjà complet avant ce changement) — uniquement l'UI qui expose les
/// 4 points manquants.
///
/// Correctif UX (post-implémentation) : les poignées murs latéraux restent
/// visuellement petites/discrètes (cercle 14px) mais leur zone tactile
/// (`GestureDetector`) est élargie à 40px minimum via `_Handle.hitSize` —
/// sans cela le cercle visible seul était trop petit pour être attrapé de
/// façon fiable au doigt/souris. Le cercle reste centré dans cette zone.
/// Ordre de dessin inchangé : murs latéraux d'abord (dessous), plafond/sol
/// ensuite (dessus) — priorité de hit-test conservée aux grosses poignées
/// en cas de chevauchement.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/persp_calib.dart';
import '../../state/app_state.dart';

class CalibHandlesOverlay extends StatelessWidget {
  final Size canvasSize;
  final ImgDraw? imgDraw;
  const CalibHandlesOverlay({super.key, required this.canvasSize, required this.imgDraw});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final calib = state.perspCalib ?? PerspCalib.defaultCalib;

    // Points du mur du fond (plafond/sol) — comportement/apparence
    // strictement inchangés par rapport à la version précédente de ce
    // fichier (mêmes 4 clés, même ordre de construction).
    const backWallKeys = ['ceilL', 'ceilR', 'floorL', 'floorR'];

    // Points des murs latéraux (NOUVEAU, voir docstring de classe).
    const sideWallKeys = ['wallTL', 'wallTR', 'wallBL', 'wallBR'];

    CalibPoint pointFor(String key) {
      switch (key) {
        case 'ceilL':
          return calib.ceilL;
        case 'ceilR':
          return calib.ceilR;
        case 'floorL':
          return calib.floorL;
        case 'floorR':
          return calib.floorR;
        case 'wallTL':
          return calib.wallTL;
        case 'wallTR':
          return calib.wallTR;
        case 'wallBL':
          return calib.wallBL;
        case 'wallBR':
          return calib.wallBR;
      }
      throw ArgumentError(
        'CalibHandlesOverlay: clé de point de calibration inconnue "$key" '
        '— attendu une des 8 clés de PerspCalib.',
      );
    }

    Widget buildHandle(
      String key, {
      required double size,
      required Color color,
      required double opacity,
    }) {
      final p = pointFor(key);
      // Position affichée : alignée sur le rect image letterboxé (imgDraw)
      // quand une photo est chargée — même référentiel que celui utilisé
      // par le rendu réel (calib_canvas.dart:toCanvas). Repli strictement
      // identique à l'ancien comportement (fraction du canvas entier) si
      // imgDraw est null (cas salle démo procédurale).
      final handleX = imgDraw != null
          ? imgDraw!.dx + p.xPct * imgDraw!.dw
          : p.xPct * canvasSize.width;
      final handleY = imgDraw != null
          ? imgDraw!.dy + p.yPct * imgDraw!.dh
          : p.yPct * canvasSize.height;
      return _Handle(
        x: handleX,
        y: handleY,
        size: size,
        // Zone tactile : identique au cercle visible pour les 4 points
        // plafond/sol (comportement inchangé), mais élargie à 40px min.
        // pour les points de mur latéral — le cercle reste petit/discret
        // (14px) mais devient réellement attrapable au doigt/souris (voir
        // brief correction UX post-implémentation).
        hitSize: size < 40 ? 40 : size,
        color: color,
        opacity: opacity,
        onDrag: (dx, dy) {
          // Conversion inverse du delta de drag : doit diviser par la
          // MÊME grandeur que celle utilisée pour la position affichée
          // ci-dessus (imgDraw.dw/dh), sinon la poignée dérive sous le
          // doigt — identique pour les 8 points, plafond/sol ET murs
          // latéraux.
          final newX = imgDraw != null
              ? p.xPct + dx / imgDraw!.dw
              : ((p.xPct * canvasSize.width) + dx) / canvasSize.width;
          final newY = imgDraw != null
              ? p.yPct + dy / imgDraw!.dh
              : ((p.yPct * canvasSize.height) + dy) / canvasSize.height;
          state.updateCalibPoint(
            key,
            CalibPoint(
              xPct: newX.clamp(0.0, 1.0),
              yPct: newY.clamp(0.0, 1.0),
            ),
          );
        },
      );
    }

    return Stack(
      children: [
        // Poignées murs latéraux dessinées EN PREMIER (donc visuellement
        // EN DESSOUS) : discrètes, taille réduite. Placées avant les 4
        // grandes poignées plafond/sol dans le Stack pour que celles-ci
        // gardent la priorité de hit-testing en cas de superposition
        // visuelle proche du coin de l'image (même règle déjà appliquée à
        // ce Stack vis-à-vis des autres widgets de studio_screen.dart :
        // "les poignées de calibration doivent être le DERNIER enfant du
        // Stack" — ici c'est un ordre interne à CE Stack, sans effet sur
        // cette règle externe).
        for (final key in sideWallKeys)
          buildHandle(
            key,
            size: 14,
            color: key.contains('T') ? AppColors.goldLight : AppColors.goldDark,
            opacity: 0.45,
          ),
        // Poignées mur du fond (plafond/sol) — taille (22), couleur
        // (goldLight/goldDark) et opacité (0.85) STRICTEMENT identiques à
        // la version précédente de ce fichier.
        for (final key in backWallKeys)
          buildHandle(
            key,
            size: 22,
            color: key.startsWith('ceil') ? AppColors.goldLight : AppColors.goldDark,
            opacity: 0.85,
          ),
      ],
    );
  }
}

class _Handle extends StatelessWidget {
  final double x, y;
  final double size;
  // Taille de la zone tactile (GestureDetector) — peut être plus grande
  // que [size] (cercle visible) pour rester utilisable au doigt/souris
  // même quand le point est dessiné discret (cas des murs latéraux,
  // cercle 14px / zone tactile 40px). Le cercle visible reste centré
  // dans cette zone : aucun changement visuel pour les points
  // plafond/sol, dont hitSize == size (22 == 22).
  final double hitSize;
  final Color color;
  final double opacity;
  final void Function(double dx, double dy) onDrag;
  const _Handle({
    required this.x,
    required this.y,
    required this.size,
    required this.hitSize,
    required this.color,
    required this.opacity,
    required this.onDrag,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x - hitSize / 2,
      top: y - hitSize / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => onDrag(d.delta.dx, d.delta.dy),
        child: SizedBox(
          width: hitSize,
          height: hitSize,
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: opacity),
                border: Border.all(color: AppColors.bg, width: size >= 20 ? 2 : 1.2),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: opacity * 0.7),
                    blurRadius: size >= 20 ? 8 : 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
