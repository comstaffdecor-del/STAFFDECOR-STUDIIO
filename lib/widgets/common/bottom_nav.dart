/// Barre de navigation basse — port fidèle de `#bottom-nav` (shell.ts).
///
/// 5 boutons : Home / Démo (spécial, sans écran propre) / Studio (avec
/// badge nb produits) / Avant-Après (comparateur) / Catalogue.
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final current = state.currentScreen;

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.bg2,
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _NavBtn(
            icon: FontAwesomeIcons.house,
            label: 'Home',
            active: current == 'home',
            onTap: () => state.goTo('home'),
          ),
          _NavBtn(
            icon: FontAwesomeIcons.cube,
            label: 'Démo',
            active: false,
            onTap: () {
              state.isDemoRoom = true;
              state.goTo('studio');
            },
          ),
          _NavBtn(
            icon: FontAwesomeIcons.cameraRetro,
            label: 'Studio',
            active: current == 'studio',
            badge: state.nbProds > 0 ? '${state.nbProds}' : null,
            onTap: () => state.goTo('studio'),
          ),
          _NavBtn(
            icon: FontAwesomeIcons.tableColumns,
            label: 'Avant/Après',
            active: current == 'comparateur',
            onTap: () => state.goTo('comparateur'),
          ),
          _NavBtn(
            icon: FontAwesomeIcons.tableCellsLarge,
            label: 'Catalogue',
            active: current == 'catalogue',
            onTap: () => state.goTo('catalogue'),
          ),
        ],
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final String? badge;
  final VoidCallback onTap;

  const _NavBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.gold : AppColors.text3;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 18, color: color),
                if (badge != null)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: AppColors.bg,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
