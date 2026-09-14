/// Écran Comparateur — port fidèle de `#screen-comparateur` (shell.ts).
///
/// Avant/Après avec divider draguable. Utilise le MÊME [RoomPainter] que
/// le Studio (image + calibration identiques) — corrige le Bug #5 (le 3e
/// système disjoint `comparateur.js/_perspPoints` à % fixes est supprimé,
/// remplacé par le même VP réel).
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/chiffrage.dart';
import '../../core/perspective/product_texture_cache.dart';
import '../../core/perspective/room_painter.dart';
import '../../core/theme.dart';
import '../../data/ia_ambiance_preview.dart' show kAiPreviewDisclaimer;
import '../../models/persp_calib.dart';
import '../../state/app_state.dart';
import '../../widgets/common/common_ui.dart';
import '../../widgets/common/motif_preview.dart';

class ComparateurScreen extends StatefulWidget {
  const ComparateurScreen({super.key});

  @override
  State<ComparateurScreen> createState() => _ComparateurScreenState();
}

class _ComparateurScreenState extends State<ComparateurScreen> {
  // ⚠️ CORRECTION retour utilisateur ("le bouton de téléchargement... ne
  // fonctionne pas") — cette icône `download` n'avait JAMAIS eu de
  // comportement (`onTap: () {}` vide, présent depuis la création de
  // l'écran). On lui donne désormais une action concrète et instinctive :
  // capturer l'image Avant/Après affichée (via [RepaintBoundary]) et
  // proposer son téléchargement/partage (galerie photo sur mobile,
  // téléchargement de fichier sur Web) via `share_plus`, qui gère
  // nativement le fallback "téléchargement" sur Web quand aucune feuille
  // de partage système n'est disponible.
  final GlobalKey _compZoneKey = GlobalKey();
  bool _exporting = false;

  // ⚠️ AJOUT Avant/Après IA (retour utilisateur : "Avant/Après ne
  // fonctionne pas" — diagnostic confirmé : l'image IA générée dans
  // AiAmbiancePanel restait locale à ce widget, jamais transmise à cet
  // écran). Deux modes de comparatif désormais possibles, choisis par
  // l'utilisateur, JAMAIS mélangés :
  //  - false (défaut) : comparatif TECHNIQUE existant, inchangé —
  //    RoomPainter avec/sans produit (moteur dynamique déterministe) ;
  //  - true : comparatif AMBIANCE IA — vraie photo AVANT vs image
  //    Gemini APRÈS, lues depuis [AppState.lastAiComparisonResult],
  //    SANS jamais relancer de génération depuis cet écran.
  bool _showAiComparison = false;

  Future<void> _downloadComparisonImage() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final boundary = _compZoneKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('zone de rendu introuvable');
      }
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('encodage PNG échoué');
      }
      final bytes = byteData.buffer.asUint8List();
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              name: 'staff-decor-avant-apres.png',
              mimeType: 'image/png',
            ),
          ],
          subject: 'Staff Décor — Visualisation Avant/Après',
          text: 'Ma visualisation Staff Décor Studio',
        ),
      );
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          'Téléchargement impossible — réessayez dans quelques secondes.',
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

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
              Tooltip(
                message: 'Télécharger l\'image Avant/Après',
                child: _exporting
                    ? const SizedBox(
                        width: 30,
                        height: 30,
                        child: Padding(
                          padding: EdgeInsets.all(6),
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                        ),
                      )
                    : IconBtn(
                        icon: FontAwesomeIcons.download,
                        size: 30,
                        // Le téléchargement capture toujours la zone
                        // AFFICHÉE (RepaintBoundary englobe les deux
                        // modes) — cohérent que ce soit le comparatif
                        // technique ou le comparatif IA.
                        onTap: _downloadComparisonImage,
                      ),
              ),
              const SizedBox(width: 6),
              // ⚠️ CORRECTION Bug #12 : cette icône "envoyer" n'avait
              // jamais eu de comportement (onTap: () {} vide). Elle ouvre
              // désormais le modal de coordonnées, cohérent avec le bouton
              // "Générer le devis" ci-dessous.
              Tooltip(
                message: 'Envoyer mon projet à Staff Décor',
                child: IconBtn(
                  icon: FontAwesomeIcons.paperPlane,
                  size: 30,
                  onTap: state.openContactModal,
                ),
              ),
            ],
          ),
        ),
        // ⚠️ AJOUT Avant/Après IA — bascule explicite entre les deux
        // comparatifs (jamais fusionnés, jamais l'un à la place de
        // l'autre par défaut) : "Rendu technique" reste le comportement
        // EXISTANT et INCHANGÉ (RoomPainter, sélectionné par défaut) ;
        // "Aperçu IA" affiche le dernier résultat Gemini stocké dans
        // AppState (voir _AiCompZone plus bas), sans jamais relancer de
        // génération depuis cet écran.
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: const BoxDecoration(
            color: AppColors.bg,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _CompModeToggle(
                  label: 'Rendu technique',
                  icon: FontAwesomeIcons.rulerCombined,
                  active: !_showAiComparison,
                  onTap: () => setState(() => _showAiComparison = false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CompModeToggle(
                  label: 'Aperçu IA',
                  icon: FontAwesomeIcons.wandMagicSparkles,
                  active: _showAiComparison,
                  onTap: () => setState(() => _showAiComparison = true),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 55,
          child: RepaintBoundary(
            key: _compZoneKey,
            child: _showAiComparison
                ? _AiCompZone(result: state.lastAiComparisonResult)
                : LayoutBuilder(
              builder: (context, c) {
                final roomImage = state.roomImage;
                final localImgDraw = roomImage == null
                    ? null
                    : computeImgDraw(
                        roomImage.width.toDouble(),
                        roomImage.height.toDouble(),
                        c.maxWidth,
                        c.maxHeight,
                      );
                return _CompZone(
                  size: Size(c.maxWidth, c.maxHeight),
                  localImgDraw: localImgDraw,
                );
              },
            ),
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
  final ImgDraw? localImgDraw;
  const _CompZone({required this.size, required this.localImgDraw});

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
                  imgDraw: localImgDraw,
                  calib: calib,
                  selectedProducts: state.selectedProducts,
                  prodPositions: state.prodPositions,
                  withProducts: true,
                  metresHauteur: state.metresHauteur,
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
                  imgDraw: localImgDraw,
                  calib: calib,
                  selectedProducts: state.selectedProducts,
                  prodPositions: state.prodPositions,
                  withProducts: false,
                  metresHauteur: state.metresHauteur,
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

/// Bascule "Rendu technique" / "Aperçu IA" — voir commentaire dans
/// [ComparateurScreen.build].
class _CompModeToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _CompModeToggle({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.gold.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppColors.gold : AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: active ? AppColors.gold : AppColors.text2),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? AppColors.gold : AppColors.text2,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Comparatif "Aperçu IA" — AVANT = vraie photo/scène envoyée au proxy,
/// APRÈS = image Gemini générée, toutes deux lues depuis
/// [AppState.lastAiComparisonResult] (voir [AiComparisonResult]).
/// N'appelle JAMAIS le proxy ni [generateAiAmbiancePreview] — affichage
/// pur d'un résultat déjà obtenu ailleurs (Studio → panneau IA).
class _AiCompZone extends StatelessWidget {
  final AiComparisonResult? result;
  const _AiCompZone({required this.result});

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      // Aucun aperçu IA généré pour l'instant — message explicite,
      // jamais un écran vide silencieux (brief : "Générez d'abord un
      // aperçu IA depuis le Studio.").
      return Container(
        color: AppColors.bg2,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(FontAwesomeIcons.wandMagicSparkles, size: 30, color: AppColors.text3),
            const SizedBox(height: 12),
            const Text(
              'Générez d\'abord un aperçu IA depuis le Studio.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Importez une photo et sélectionnez un produit dans le '
              'Studio : l\'aperçu d\'ambiance IA se génère automatiquement, '
              'puis apparaît ici en comparatif avant/après.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text3, fontSize: 11.5, height: 1.4),
            ),
          ],
        ),
      );
    }

    return Consumer<AppState>(
      builder: (context, state, _) {
        return LayoutBuilder(
          builder: (context, c) {
            final size = Size(c.maxWidth, c.maxHeight);
            final x = size.width * (state.compPos / 100);
            return Container(
              color: AppColors.bg2,
              child: Stack(
                children: [
                  // APRÈS (fond, pleine largeur) — image IA générée.
                  Positioned.fill(
                    child: Image.memory(r.aiImageBytes, fit: BoxFit.contain),
                  ),
                  // AVANT (clip à gauche du divider) — vraie photo
                  // d'origine envoyée au proxy pour cette génération.
                  Positioned.fill(
                    child: ClipRect(
                      clipper: _LeftClipper(x),
                      child: Image.memory(r.originalImageBytes, fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    left: x - 14,
                    top: 0,
                    bottom: 0,
                    width: 28,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (d) {
                        final newX = (x + d.delta.dx).clamp(0.0, size.width);
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
                  const Positioned(left: 10, bottom: 10, child: _CompLabel('AVANT')),
                  const Positioned(right: 10, bottom: 10, child: _CompLabel('APRÈS')),
                  // Mention non-contractuelle permanente — cohérente avec
                  // AiAmbiancePanel, jamais masquée sur un rendu IA.
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        kAiPreviewDisclaimer,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.gold, fontSize: 10.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
