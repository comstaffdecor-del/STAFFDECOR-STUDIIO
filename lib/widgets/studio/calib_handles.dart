/// Poignées de calibration draguables — port fidèle de
/// `#perspective-overlay` (studio.js `_renderCalibHandles` / drag logic).
///
/// 8 points dorés (plafond = gold clair, sol = gold sombre) permettant à
/// l'utilisateur d'ajuster manuellement le [PerspCalib] en glissant.
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

    final points = <String, CalibPoint>{
      'ceilL': calib.ceilL,
      'ceilR': calib.ceilR,
      'floorL': calib.floorL,
      'floorR': calib.floorR,
    };

    return Stack(
      children: points.entries.map((e) {
        final isCeil = e.key.startsWith('ceil');
        // Position affichée : alignée sur le rect image letterboxé
        // (imgDraw) quand une photo est chargée — c'est le même
        // référentiel que celui utilisé par le rendu réel (calib_canvas
        // .dart:toCanvas). Repli strictement identique à l'ancien
        // comportement (fraction du canvas entier) si imgDraw est null
        // (cas salle démo procédurale, non affecté par ce correctif).
        final handleX = imgDraw != null
            ? imgDraw!.dx + e.value.xPct * imgDraw!.dw
            : e.value.xPct * canvasSize.width;
        final handleY = imgDraw != null
            ? imgDraw!.dy + e.value.yPct * imgDraw!.dh
            : e.value.yPct * canvasSize.height;
        return _Handle(
          x: handleX,
          y: handleY,
          color: isCeil ? AppColors.goldLight : AppColors.goldDark,
          onDrag: (dx, dy) {
            // Conversion inverse du delta de drag : doit diviser par la
            // MÊME grandeur que celle utilisée pour la position affichée
            // ci-dessus (imgDraw.dw/dh), sinon la poignée dérive sous le
            // doigt (le déplacement visuel ne correspond plus au delta
            // en fraction xPct/yPct appliqué à la calibration).
            final newX = imgDraw != null
                ? e.value.xPct + dx / imgDraw!.dw
                : ((e.value.xPct * canvasSize.width) + dx) / canvasSize.width;
            final newY = imgDraw != null
                ? e.value.yPct + dy / imgDraw!.dh
                : ((e.value.yPct * canvasSize.height) + dy) / canvasSize.height;
            state.updateCalibPoint(
              e.key,
              CalibPoint(
                xPct: newX.clamp(0.0, 1.0),
                yPct: newY.clamp(0.0, 1.0),
              ),
            );
          },
        );
      }).toList(),
    );
  }
}

class _Handle extends StatelessWidget {
  final double x, y;
  final Color color;
  final void Function(double dx, double dy) onDrag;
  const _Handle({
    required this.x,
    required this.y,
    required this.color,
    required this.onDrag,
  });

  @override
  Widget build(BuildContext context) {
    const size = 22.0;
    return Positioned(
      left: x - size / 2,
      top: y - size / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => onDrag(d.delta.dx, d.delta.dy),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.85),
            border: Border.all(color: AppColors.bg, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
