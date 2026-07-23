/// Écran Comparateur — port fidèle de `#screen-comparateur` (shell.ts).
///
/// Avant/Après avec divider draguable. Utilise le MÊME [RoomPainter] que
/// le Studio (image + calibration identiques) — corrige le Bug #5 (le 3e
/// système disjoint `comparateur.js/_perspPoints` à % fixes est supprimé,
/// remplacé par le même VP réel).
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/chiffrage.dart';
import '../../core/perspective/product_texture_cache.dart';
import '../../core/perspective/room_painter.dart';
import '../../core/theme.dart';
import '../../models/persp_calib.dart';
import '../../state/app_state.dart';
import '../../widgets/common/common_ui.dart';

class ComparateurScreen extends StatelessWidget {
  const ComparateurScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chiffrage = calcChiffrage(
      selectedProducts: state.selectedProducts,
      margeCoupePct: state.margeCoupePct,
      isCalibrated: state.isCalibrated,
    );

    return Column(
      children: [
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            color: AppColors.bg,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Avant / Après',
                  style: TextStyle(color: AppColors.gold, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              IconBtn(icon: FontAwesomeIcons.download, size: 30, onTap: () {}),
              const SizedBox(width: 6),
              IconBtn(icon: FontAwesomeIcons.paperPlane, size: 30, onTap: () {}),
            ],
          ),
        ),
        Expanded(
          flex: 55,
          child: LayoutBuilder(
            builder: (context, c) => _CompZone(size: Size(c.maxWidth, c.maxHeight)),
          ),
        ),
        Expanded(
          flex: 45,
          child: Container(
            color: AppColors.bg,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Devis estimatif',
                      style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    EstimBadge(calibrated: state.isCalibrated),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: chiffrage.lignes.isEmpty
                      ? const Center(
                          child: Text(
                            'Aucun produit sélectionné',
                            style: TextStyle(color: AppColors.text3, fontSize: 12),
                          ),
                        )
                      : ListView.separated(
                          itemCount: chiffrage.lignes.length,
                          separatorBuilder: (_, __) => const Divider(height: 12, color: AppColors.border),
                          itemBuilder: (context, i) {
                            final l = chiffrage.lignes[i];
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(l.ref,
                                          style: const TextStyle(
                                              color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w600)),
                                      Text('${fmtN(l.qteCom)} ${l.unite}',
                                          style: const TextStyle(color: AppColors.text3, fontSize: 10.5)),
                                    ],
                                  ),
                                ),
                                Text(fmtPrix(l.totalHt),
                                    style: const TextStyle(color: AppColors.gold, fontSize: 12.5, fontWeight: FontWeight.w600)),
                              ],
                            );
                          },
                        ),
                ),
                const Divider(color: AppColors.border),
                Row(
                  children: [
                    const Text('Total estimé (TTC)',
                        style: TextStyle(color: AppColors.text2, fontSize: 13)),
                    const Spacer(),
                    Text(fmtPrix(chiffrage.totalTtc),
                        style: const TextStyle(color: AppColors.gold, fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: BtnGold(
                    label: 'Générer le devis',
                    icon: FontAwesomeIcons.fileInvoiceDollar,
                    onTap: () => state.goTo('devis'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CompZone extends StatelessWidget {
  final Size size;
  const _CompZone({required this.size});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final calib = state.perspCalib ?? PerspCalib.defaultCalib;
    final dividerX = size.width * (state.compPos / 100);

    return Container(
      color: AppColors.bg2,
      child: Stack(
        children: [
          // APRÈS (fond, pleine largeur, avec produits) — [ListenableBuilder]
          // repaint dès que la vraie photo produit (motifs) termine de
          // charger via [ProductTextureCache] (voir Studio pour détail).
          Positioned.fill(
            child: ListenableBuilder(
              listenable: ProductTextureCache.instance,
              builder: (context, _) => CustomPaint(
                painter: RoomPainter(
                  roomImage: state.roomImage,
                  imgDraw: state.imgDraw,
                  calib: calib,
                  selectedProducts: state.selectedProducts,
                  prodPositions: state.prodPositions,
                  withProducts: true,
                ),
              ),
            ),
          ),
          // AVANT (clip à gauche du divider, sans produits)
          Positioned.fill(
            child: ClipRect(
              clipper: _LeftClipper(dividerX),
              child: CustomPaint(
                painter: RoomPainter(
                  roomImage: state.roomImage,
                  imgDraw: state.imgDraw,
                  calib: calib,
                  selectedProducts: state.selectedProducts,
                  prodPositions: state.prodPositions,
                  withProducts: false,
                ),
              ),
            ),
          ),
          Positioned(
            left: dividerX - 14,
            top: 0,
            bottom: 0,
            width: 28,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanUpdate: (d) {
                final newX = (dividerX + d.delta.dx).clamp(0.0, size.width);
                state.setCompPos(newX / size.width * 100);
              },
              child: Center(
                child: Container(
                  width: 2,
                  color: AppColors.gold,
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: AppColors.gold,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(FontAwesomeIcons.arrowsLeftRight, size: 12, color: AppColors.bg),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: _CompLabel('AVANT'),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: _CompLabel('APRÈS'),
          ),
        ],
      ),
    );
  }
}

class _CompLabel extends StatelessWidget {
  final String text;
  const _CompLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, letterSpacing: 1)),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  final double x;
  const _LeftClipper(this.x);
  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, x, size.height);
  @override
  bool shouldReclip(covariant _LeftClipper oldClipper) => oldClipper.x != x;
}
