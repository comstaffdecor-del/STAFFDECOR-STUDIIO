/// Écran Profil — port fidèle de `#screen-profil` (shell.ts).
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/catalogue_data.dart';
import '../../state/app_state.dart';
import '../../widgets/common/common_ui.dart';

class ProfilScreen extends StatelessWidget {
  const ProfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final total = getCatalogueStats().total;

    return Column(
      children: [
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            color: AppColors.bg,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Mon Profil', style: TextStyle(color: AppColors.gold, fontSize: 15, fontWeight: FontWeight.w600)),
                    Text('Staff Décor Studio', style: TextStyle(color: AppColors.text3, fontSize: 10.5)),
                  ],
                ),
              ),
              IconBtn(icon: FontAwesomeIcons.arrowLeft, size: 32, onTap: () => state.goTo('home')),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                    child: const Text('F', style: TextStyle(color: AppColors.bg, fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Florence Joubrel',
                            style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600)),
                        const Text('florence.joubrel@gmail.com',
                            style: TextStyle(color: AppColors.text3, fontSize: 11.5)),
                        const SizedBox(height: 4),
                        Row(
                          children: const [
                            Icon(FontAwesomeIcons.star, size: 10, color: AppColors.gold),
                            SizedBox(width: 4),
                            Text('Compte Professionnel',
                                style: TextStyle(color: AppColors.gold, fontSize: 10.5, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _StatBox(num: '2', label: 'Projets'),
                  const SizedBox(width: 8),
                  _StatBox(num: '${state.nbProds}', label: 'Produits'),
                  const SizedBox(width: 8),
                  _StatBox(num: '$total', label: 'Réf. GED'),
                ],
              ),
              const SizedBox(height: 16),
              _PrefCard(
                icon: FontAwesomeIcons.database,
                title: 'Connexion GED',
                rows: const [],
                children: [
                  _gedLine('Connecté à ged.staffdecor.fr'),
                  _gedLine('$total références catalogue'),
                ],
              ),
              const SizedBox(height: 12),
              _PrefCard(
                icon: FontAwesomeIcons.sliders,
                title: 'Paramètres chiffrage',
                rows: [
                  ('Marge de coupe', '${(state.margeCoupePct * 100).toStringAsFixed(0)}%'),
                  ('TVA', '20%'),
                  ('Calibrage actif', state.isCalibrated ? 'Calibré' : 'Non calibré'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _gedLine(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(FontAwesomeIcons.circleCheck, size: 11, color: AppColors.green),
          const SizedBox(width: 7),
          Text(text, style: const TextStyle(color: AppColors.text2, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String num, label;
  const _StatBox({required this.num, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(num, style: const TextStyle(color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.text3, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}

class _PrefCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<(String, String)> rows;
  final List<Widget> children;
  const _PrefCard({required this.icon, required this.title, required this.rows, this.children = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppColors.gold),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(r.$1, style: const TextStyle(color: AppColors.text2, fontSize: 12))),
                    Text(r.$2, style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
