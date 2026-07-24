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
import '../../widgets/common/motif_preview.dart';

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
              // ⚠️ CORRECTION Bug #12 : cette icône "envoyer" n'avait
              // jamais eu de comportement (onTap: () {} vide). Elle ouvre
              // désormais le modal de coordonnées, cohérent avec le bouton
              // "Générer le devis" ci-dessous.
              IconBtn(
                icon: FontAwesomeIcons.paperPlane,
                size: 30,
                onTap: state.openContactModal,
              ),
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
            // ⚠️ CORRECTION Bug #14/#22 (retour utilisateur : "il faut
            // RETIRER le prix/devis visible du panneau bas du Comparateur
            // jusqu'à la saisie des coordonnées") — tant que
            // [contactSubmitted] est faux, on masque entièrement les
            // montants (lignes + total) et on affiche un appel à l'action
            // à la place. Une fois les coordonnées soumises, le panneau
            // redevient identique à avant (aucune régression pour
            // l'utilisateur qui a déjà laissé ses coordonnées).
            child: state.contactSubmitted
                ? _PricedPanel(chiffrage: chiffrage, state: state)
                : _LockedPanel(hasProducts: state.selectedProducts.isNotEmpty),
          ),
        ),
      ],
    );
  }
}

/// Panneau chiffrage complet (affiché seulement après coordonnées soumises).
class _PricedPanel extends StatelessWidget {
  final Chiffrage chiffrage;
  final AppState state;
  const _PricedPanel({required this.chiffrage, required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }
}

/// Panneau verrouillé — remplace les montants tant que les coordonnées
/// client n'ont pas été soumises (Bug #14/#22).
class _LockedPanel extends StatelessWidget {
  final bool hasProducts;
  const _LockedPanel({required this.hasProducts});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(FontAwesomeIcons.lock, size: 20, color: AppColors.gold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Estimation masquée',
            style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              hasProducts
                  ? 'Renseignez vos coordonnées pour afficher le chiffrage '
                      'détaillé et être recontacté par un conseiller.'
                  : 'Ajoutez au moins un produit dans le Studio, puis '
                      'renseignez vos coordonnées pour afficher le chiffrage.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.text3, fontSize: 11.5, height: 1.4),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 220,
            child: BtnGold(
              label: 'Voir mon estimation',
              icon: FontAwesomeIcons.unlock,
              onTap: state.openContactModal,
            ),
          ),
        ],
      ),
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
          // Aperçu zoomé du VRAI relief sculpté (Bug B) — voir Studio pour
          // le détail : la bande dans la photo est trop fine pour montrer
          // le motif, même en texture-mapping réel.
          Positioned(
            right: 10,
            top: 10,
            child: MotifPreviewBar(selectedProducts: state.selectedProducts),
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
