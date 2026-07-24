/// Modal "Enregistrer le projet" — répond au retour utilisateur : "Les
/// boutons d'enregistrement... des projets ne sont pas instinctifs et
/// surtout ne fonctionnent pas."
///
/// Avant cette correction, aucun bouton "Enregistrer" n'existait dans le
/// Studio : l'auto-save silencieuse ([AppState.save]) ne conservait qu'un
/// seul état "en cours", jamais nommé, jamais listé. Ce modal permet de
/// nommer explicitement le projet courant et de l'ajouter à la liste des
/// projets sauvegardés (visible/rechargeable depuis l'écran Home).
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../common/common_ui.dart';
import 'common_modal.dart';

class SaveProjectModal extends StatefulWidget {
  final VoidCallback onClose;
  const SaveProjectModal({super.key, required this.onClose});

  @override
  State<SaveProjectModal> createState() => _SaveProjectModalState();
}

class _SaveProjectModalState extends State<SaveProjectModal> {
  late final TextEditingController _nameCtrl;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _nameCtrl = TextEditingController(
      text: 'Projet du ${now.day.toString().padLeft(2, '0')}/'
          '${now.month.toString().padLeft(2, '0')}',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(AppState state) async {
    await state.saveCurrentAsProject(_nameCtrl.text);
    if (!mounted) return;
    setState(() => _saved = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final hasProducts = state.selectedProducts.isNotEmpty;

    return ModalSheet(
      onClose: widget.onClose,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(FontAwesomeIcons.floppyDisk, size: 15, color: AppColors.gold),
                const SizedBox(width: 8),
                const Text(
                  'Enregistrer le projet',
                  style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconBtn(icon: FontAwesomeIcons.xmark, size: 28, onTap: widget.onClose),
              ],
            ),
            const SizedBox(height: 14),
            if (!hasProducts)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(FontAwesomeIcons.circleInfo, size: 13, color: AppColors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Aucun produit sélectionné — le projet sera enregistré vide.',
                        style: TextStyle(color: AppColors.text2, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
            if (!hasProducts) const SizedBox(height: 12),
            const Text(
              'Nom du projet',
              style: TextStyle(color: AppColors.text2, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: const TextStyle(color: AppColors.text, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.card2,
                hintText: 'Ex. Salon Haussmannien',
                hintStyle: const TextStyle(color: AppColors.text3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.gold),
                ),
              ),
              onSubmitted: (_) => _save(state),
            ),
            const SizedBox(height: 6),
            Text(
              '${state.nbProds} produit${state.nbProds > 1 ? 's' : ''} dans ce projet — '
              'retrouvez-le ensuite depuis l\'écran d\'accueil ("Mes projets").',
              style: const TextStyle(color: AppColors.text3, fontSize: 11),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: BtnGold(
                label: _saved ? 'Projet enregistré !' : 'Enregistrer',
                icon: _saved ? FontAwesomeIcons.check : FontAwesomeIcons.floppyDisk,
                onTap: _saved ? null : () => _save(state),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
