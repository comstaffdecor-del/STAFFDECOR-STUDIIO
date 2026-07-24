/// Écran Home — port fidèle de `#screen-home` (shell.ts).
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../widgets/common/common_ui.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Column(
      children: [
        AppTopbar(
          title: 'Staff Décor',
          subtitle: 'Studio',
          trailing: IconBtn(
            icon: FontAwesomeIcons.user,
            onTap: () => state.goTo('profil'),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                child: Column(
                  children: [
                    Column(
                      children: const [
                        Text(
                          'Staff Décor',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Studio',
                          style: TextStyle(
                            color: AppColors.goldLight,
                            fontSize: 26,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Visualisation décorative',
                          style: TextStyle(
                            color: AppColors.text3,
                            fontSize: 12,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: _HomeCta(
                            icon: FontAwesomeIcons.camera,
                            label: 'Importer\nune photo',
                            onTap: () => state.goTo('studio'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _HomeCta(
                            icon: FontAwesomeIcons.cube,
                            label: 'Pièce\ndémo',
                            onTap: () {
                              state.setDemoRoomMode();
                              state.goTo('studio');
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _HomeCta(
                            icon: FontAwesomeIcons.tableCellsLarge,
                            label: 'Catalogue\nGED',
                            onTap: () => state.goTo('catalogue'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SectionTitle('Mes projets'),
              // ⚠️ CORRECTION retour utilisateur ("les boutons... ne
              // fonctionnent pas") — cette section affichait auparavant
              // DEUX cartes 100% factices (texte codé en dur "Salon
              // Haussmannien"/"Chambre Parentale", AUCUN `onTap`) : un
              // bouton qui ne mène nulle part. Elle affiche désormais les
              // VRAIS projets enregistrés par l'utilisateur (bouton
              // disquette du Studio, voir [SaveProjectModal]), avec un
              // vrai chargement au tap et une suppression possible.
              _SavedProjectsList(state: state),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: InkWell(
                  onTap: () => state.goTo('studio'),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.border,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(FontAwesomeIcons.plus, size: 14, color: AppColors.text2),
                          SizedBox(width: 8),
                          Text(
                            'Nouveau projet',
                            style: TextStyle(color: AppColors.text2, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HomeCta extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HomeCta({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.gold, size: 20),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.text2, fontSize: 11, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Liste des VRAIS projets enregistrés (voir [AppState.savedProjects]) —
/// remplace les deux cartes factices d'origine. Tap = charger le projet
/// dans le Studio ; icône corbeille = supprimer (avec confirmation).
class _SavedProjectsList extends StatelessWidget {
  final AppState state;
  const _SavedProjectsList({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.savedProjects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: const [
              Icon(FontAwesomeIcons.folderOpen, size: 16, color: AppColors.text3),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Aucun projet enregistré pour l\'instant. Dans le Studio, '
                  'utilisez l\'icône disquette pour enregistrer votre projet en cours.',
                  style: TextStyle(color: AppColors.text3, fontSize: 11.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: state.savedProjects
          .map((p) => _ProjectCard(
                icon: p.isDemoRoom ? FontAwesomeIcons.cube : FontAwesomeIcons.image,
                name: p.name,
                meta: '${p.selectedProducts.length} produit${p.selectedProducts.length > 1 ? 's' : ''} · '
                    '${p.createdAt.day.toString().padLeft(2, '0')}/'
                    '${p.createdAt.month.toString().padLeft(2, '0')}/'
                    '${p.createdAt.year}',
                onTap: () => state.loadProject(p.id),
                onDelete: () => _confirmDelete(context, state, p.id, p.name),
              ))
          .toList(),
    );
  }

  void _confirmDelete(BuildContext context, AppState state, String id, String name) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Supprimer le projet ?', style: TextStyle(color: AppColors.text)),
        content: Text(
          '« $name » sera définitivement supprimé.',
          style: const TextStyle(color: AppColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler', style: TextStyle(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () {
              state.deleteProject(id);
              Navigator.of(ctx).pop();
            },
            child: const Text('Supprimer', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final IconData icon;
  final String name;
  final String meta;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _ProjectCard({
    required this.icon,
    required this.name,
    required this.meta,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.card2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.gold, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      style: const TextStyle(color: AppColors.text3, fontSize: 11),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(16),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(FontAwesomeIcons.trashCan, size: 14, color: AppColors.text3),
                ),
              ),
              const Icon(FontAwesomeIcons.chevronRight, size: 12, color: AppColors.text3),
            ],
          ),
        ),
      ),
    );
  }
}
