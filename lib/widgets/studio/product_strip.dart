/// Bandeau catégories + strip produits horizontal — port fidèle de
/// `#cat-bar` / `#cat-tabs` / `#product-strip` (shell.ts / studio.js).
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/catalogue_data.dart';
import '../../state/app_state.dart';

// ⚠️ CORRECTION Bug #13 (retour utilisateur : "produits Lambris non
// indexés/accessibles") — 'Lambris' et 'Profils LED' existent bien dans
// [catalogueGed] (voir catalogue_data.dart, `familles`) et sont déjà
// rendus par [RoomPainter], mais n'apparaissaient jamais dans ce bandeau
// d'onglets Studio : impossible d'y accéder autrement que par appel direct
// à `setCatTabStudio`. Ajoutés ici avec des icônes dédiées.
const _famTabIcons = {
  'Corniches': FontAwesomeIcons.archway,
  'Moulures': FontAwesomeIcons.minus,
  'Plinthes': FontAwesomeIcons.gripLines,
  'Encadrements': FontAwesomeIcons.circleNotch,
  'Colonnes': FontAwesomeIcons.tableColumns,
  'Ornements': FontAwesomeIcons.leaf,
  'Parements': FontAwesomeIcons.borderAll,
  'Lambris': FontAwesomeIcons.bars,
  'Profils LED': FontAwesomeIcons.lightbulb,
};

const _famTabLabels = {
  'Encadrements': 'Rosaces',
};

class CatBar extends StatelessWidget {
  const CatBar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      color: AppColors.bg2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                ..._famTabIcons.entries.map((e) {
                  final active = state.catTabStudio == e.key;
                  return _CatTab(
                    icon: e.value,
                    label: _famTabLabels[e.key] ?? e.key,
                    active: active,
                    onTap: () => state.setCatTabStudio(e.key),
                  );
                }),
                _CatTab(
                  icon: FontAwesomeIcons.tableCellsLarge,
                  label: 'Tout',
                  active: false,
                  onTap: () => state.goTo('catalogue'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 92,
            child: _ProductStrip(famille: state.catTabStudio),
          ),
        ],
      ),
    );
  }
}

class _CatTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _CatTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? AppColors.gold : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 11, color: active ? AppColors.bg : AppColors.text2),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? AppColors.bg : AppColors.text2,
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Petit badge ✓ doré affiché sur la vignette produit lorsque celui-ci est
/// déjà dans le projet — donne un retour visuel immédiat et évident au
/// tap court (sélection instantanée), en plus du contour doré du Container.
class _SelectedCheckBadge extends StatelessWidget {
  const _SelectedCheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: const BoxDecoration(
        color: AppColors.gold,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(FontAwesomeIcons.check, size: 9, color: AppColors.bg),
    );
  }
}

class _ProductStrip extends StatelessWidget {
  final String famille;
  const _ProductStrip({required this.famille});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final prods = getProdsByFamille(famille);

    if (prods.isEmpty) {
      return const Center(
        child: Text(
          'Aucun produit dans cette famille',
          style: TextStyle(color: AppColors.text3, fontSize: 11),
        ),
      );
    }

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: prods.length,
      itemBuilder: (context, i) {
        final p = prods[i];
        final selected = state.getProdInProject(p.ref) != null;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InkWell(
            // Port fidèle de l'UX legacy (app.js `_quickToggleProd`) : un
            // TAP COURT sélectionne/désélectionne le produit INSTANTANÉMENT
            // (ajout/retrait direct du projet, visible immédiatement par le
            // contour doré + rendu sur la photo) — c'était le bug signalé
            // par l'utilisateur ("le clic ne sélectionne pas le produit"),
            // car un simple tap ouvrait la modal au lieu de sélectionner.
            // Un APPUI LONG ouvre la fiche produit détaillée (quantité, prix).
            onTap: () => state.quickToggleProd(p.ref),
            onLongPress: () => state.openProduct(p.ref),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 68,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppColors.gold : AppColors.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.card2,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            child: p.img.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      p.img,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        FontAwesomeIcons.image,
                                        size: 14,
                                        color: AppColors.text3,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    FontAwesomeIcons.image,
                                    size: 14,
                                    color: AppColors.text3,
                                  ),
                          ),
                        ),
                        // Badge check + bouton info (fiche détaillée), pour
                        // conserver un accès explicite à la modal en plus
                        // de l'appui long (meilleure découvrabilité souris).
                        if (selected)
                          const Positioned(
                            top: 2,
                            left: 2,
                            child: _SelectedCheckBadge(),
                          ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => state.openProduct(p.ref),
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: AppColors.bg.withValues(alpha: 0.75),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                FontAwesomeIcons.info,
                                size: 9,
                                color: AppColors.gold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    p.ref,
                    style: TextStyle(
                      color: selected ? AppColors.gold : AppColors.text2,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
