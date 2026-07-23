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
  const CalibHandlesOverlay({super.key, required this.canvasSize});

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
        return _Handle(
          x: e.value.xPct * canvasSize.width,
          y: e.value.yPct * canvasSize.height,
          color: isCeil ? AppColors.goldLight : AppColors.goldDark,
          onDrag: (dx, dy) {
            final newX = ((e.value.xPct * canvasSize.width) + dx) /
                canvasSize.width;
            final newY = ((e.value.yPct * canvasSize.height) + dy) /
                canvasSize.height;
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
