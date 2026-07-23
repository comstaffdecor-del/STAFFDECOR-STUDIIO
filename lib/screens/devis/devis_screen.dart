/// Écran Devis — port fidèle de `#screen-devis` (shell.ts).
///
/// Table complète du chiffrage (8 colonnes équivalent), sélecteur de marge,
/// avertissement légal (Annexe C).
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/chiffrage.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../widgets/common/common_ui.dart';

class DevisScreen extends StatelessWidget {
  const DevisScreen({super.key});

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
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            color: AppColors.bg,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Mon Devis', style: TextStyle(color: AppColors.gold, fontSize: 15, fontWeight: FontWeight.w600)),
                    Text('Estimation indicative', style: TextStyle(color: AppColors.text3, fontSize: 10.5)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.card2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Text('Marge', style: TextStyle(color: AppColors.text3, fontSize: 10.5)),
                    const SizedBox(width: 6),
                    DropdownButton<double>(
                      value: state.margeCoupePct,
                      dropdownColor: AppColors.card2,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(color: AppColors.gold, fontSize: 12),
                      items: const [0.05, 0.10, 0.15, 0.20]
                          .map((v) => DropdownMenuItem(value: v, child: Text('${(v * 100).toStringAsFixed(0)}%')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) state.setMargeCoupePct(v);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconBtn(icon: FontAwesomeIcons.arrowLeft, size: 32, onTap: () => state.goTo('comparateur')),
            ],
          ),
        ),
        Expanded(
          child: chiffrage.lignes.isEmpty
              ? const Center(
                  child: Text('Aucun produit dans le projet', style: TextStyle(color: AppColors.text3, fontSize: 13)),
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: const [
                              Expanded(flex: 3, child: Text('Réf.', style: TextStyle(color: AppColors.text3, fontSize: 10.5))),
                              Expanded(flex: 2, child: Text('Qté nette', style: TextStyle(color: AppColors.text3, fontSize: 10.5), textAlign: TextAlign.right)),
                              Expanded(flex: 2, child: Text('Qté com.', style: TextStyle(color: AppColors.text3, fontSize: 10.5), textAlign: TextAlign.right)),
                              Expanded(flex: 2, child: Text('PU HT', style: TextStyle(color: AppColors.text3, fontSize: 10.5), textAlign: TextAlign.right)),
                              Expanded(flex: 2, child: Text('Total HT', style: TextStyle(color: AppColors.text3, fontSize: 10.5), textAlign: TextAlign.right)),
                            ],
                          ),
                          const Divider(color: AppColors.border),
                          ...chiffrage.lignes.map((l) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(l.ref, style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600)),
                                          Text(l.famille, style: const TextStyle(color: AppColors.text3, fontSize: 9.5)),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text('${fmtN(l.qteNette)} ${l.unite}',
                                          style: const TextStyle(color: AppColors.text2, fontSize: 11), textAlign: TextAlign.right),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        l.nbBarres != null ? '${l.nbBarres} barre${l.nbBarres! > 1 ? 's' : ''}' : '${fmtN(l.qteCom)} ${l.unite}',
                                        style: const TextStyle(color: AppColors.text2, fontSize: 11),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(fmtPrix(l.puHt), style: const TextStyle(color: AppColors.text2, fontSize: 11), textAlign: TextAlign.right),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(fmtPrix(l.totalHt),
                                          style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w600),
                                          textAlign: TextAlign.right),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.card2,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _totalRow('Total HT', fmtPrix(chiffrage.totalHt)),
                          _totalRow('TVA (20%)', fmtPrix(chiffrage.tva)),
                          const Divider(color: AppColors.border),
                          _totalRow('Total TTC', fmtPrix(chiffrage.totalTtc), big: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(FontAwesomeIcons.circleInfo, size: 14, color: AppColors.amber),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ordre de prix indicatif : cette estimation ne constitue pas un devis contractuel. '
                              'Contactez votre conseiller Staff Décor pour un devis détaillé.',
                              style: TextStyle(color: AppColors.text2, fontSize: 10.5, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _totalRow(String label, String value, {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: AppColors.text2, fontSize: big ? 13 : 12))),
          Text(value,
              style: TextStyle(
                  color: big ? AppColors.gold : AppColors.text,
                  fontSize: big ? 18 : 13,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
