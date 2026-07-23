/// Modal produit — port fidèle de `#product-modal` (shell.ts).
///
/// Affiche fiche produit + saisie quantité + aperçu prix + actions
/// ajouter/retirer du projet.
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/chiffrage.dart';
import '../../core/theme.dart';
import '../../data/catalogue_data.dart';
import '../../state/app_state.dart';
import 'common_modal.dart';

class ProductModal extends StatefulWidget {
  const ProductModal({super.key});

  @override
  State<ProductModal> createState() => _ProductModalState();
}

class _ProductModalState extends State<ProductModal> {
  late TextEditingController _qteCtrl;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _qteCtrl = TextEditingController(
      text: state.productModalQte.toStringAsFixed(
        state.productModalQte.truncateToDouble() == state.productModalQte ? 0 : 1,
      ),
    );
  }

  @override
  void dispose() {
    _qteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ref = state.productModalRef;
    if (ref == null) return const SizedBox.shrink();
    final prod = getProdByRef(ref);
    if (prod == null) return const SizedBox.shrink();

    final qte = double.tryParse(_qteCtrl.text.replaceAll(',', '.')) ??
        state.productModalQte;
    final preview = calcPrixPreview(qte, prod.famille, state.margeCoupePct);
    final existing = state.getProdInProject(ref);

    return ModalSheet(
      onClose: state.closeProductModal,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prod.ref,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        prod.famille,
                        style: const TextStyle(color: AppColors.text3, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: state.closeProductModal,
                  icon: const Icon(FontAwesomeIcons.xmark, size: 16, color: AppColors.text2),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.card2,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: prod.img.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        prod.img,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const _NoImg(),
                      ),
                    )
                  : const _NoImg(),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetaCell(label: 'Référence', value: prod.ref),
                _MetaCell(label: 'Famille', value: prod.famille),
                _MetaCell(label: 'Unité de vente', value: prod.unite),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'Quantité à poser',
                  style: TextStyle(color: AppColors.text2, fontSize: 12),
                ),
                const Spacer(),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _qteCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppColors.text, fontSize: 14),
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.card2,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    onChanged: (_) {
                      // L'utilisateur saisit une quantité manuellement :
                      // ce n'est plus une estimation par défaut.
                      context.read<AppState>().productModalQteEstimated = false;
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(prod.unite, style: const TextStyle(color: AppColors.text3, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 14),
            if (state.productModalQteEstimated)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(FontAwesomeIcons.circleInfo, size: 14, color: AppColors.gold),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Quantité estimée par défaut — saisissez les métrés de la pièce pour un prix précis.',
                        style: TextStyle(color: AppColors.text2, fontSize: 11, height: 1.3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        state.closeProductModal();
                        state.openMetresPanel();
                      },
                      child: const Text(
                        'Métrés',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.productModalQteEstimated
                              ? 'Estimation (à confirmer)'
                              : 'Estimation indicative HT',
                          style: const TextStyle(color: AppColors.text3, fontSize: 10),
                        ),
                        Text(
                          preview.detail,
                          style: const TextStyle(color: AppColors.text2, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    fmtPrix(preview.ht),
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      state.addToProject(ref, qteOverride: qte);
                      state.closeProductModal();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.bg,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      existing != null ? 'Mettre à jour' : 'Ajouter au projet',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                if (existing != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      state.removeProd(ref);
                      state.closeProductModal();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Icon(FontAwesomeIcons.trash, size: 14),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaCell extends StatelessWidget {
  final String label;
  final String value;
  const _MetaCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 100),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: AppColors.text3, fontSize: 9.5)),
          Text(
            value,
            style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _NoImg extends StatelessWidget {
  const _NoImg();
  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(FontAwesomeIcons.image, size: 26, color: AppColors.text3),
        SizedBox(height: 6),
        Text(
          "Pas d'image disponible",
          style: TextStyle(color: AppColors.text3, fontSize: 11),
        ),
      ],
    );
  }
}
