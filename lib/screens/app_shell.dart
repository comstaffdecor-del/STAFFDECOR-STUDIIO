/// Shell applicatif — équivalent `#app-shell` (base.css) : conteneur
/// "téléphone" contenant l'écran actif + la barre de navigation basse.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/common/bottom_nav.dart';
import '../widgets/common/contact_modal.dart';
import 'catalogue/catalogue_screen.dart';
import 'comparateur/comparateur_screen.dart';
import 'devis/devis_screen.dart';
import 'home/home_screen.dart';
import 'profil/profil_screen.dart';
import 'studio/studio_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  @override
  void initState() {
    super.initState();
    context.read<AppState>().restore();
    // ⚠️ Chargement de la liste des projets NOMMÉS enregistrés (bouton
    // disquette du Studio) — distinct de l'auto-save silencieux [restore]
    // ci-dessus, voir [AppState.loadSavedProjects].
    context.read<AppState>().loadSavedProjects();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    Widget screen;
    switch (state.currentScreen) {
      case 'studio':
        screen = const StudioScreen();
        break;
      case 'comparateur':
        screen = const ComparateurScreen();
        break;
      case 'catalogue':
        screen = const CatalogueScreen();
        break;
      case 'devis':
        screen = const DevisScreen();
        break;
      case 'profil':
        screen = const ProfilScreen();
        break;
      default:
        screen = const HomeScreen();
    }

    final content = Stack(
      children: [
        Column(
          children: [
            Expanded(child: screen),
            const AppBottomNav(),
          ],
        ),
        // ⚠️ Bug #14/#15/#16/#22 : modal contact global, superposable à
        // n'importe quel écran (déclenché depuis Comparateur/Devis quand
        // l'utilisateur tente de consulter le chiffrage sans coordonnées).
        if (state.showContactModal) const Positioned.fill(child: ContactModal()),
      ],
    );

    return Scaffold(
      // ⚠️ CORRECTION demande utilisateur ("Remplace le noir de l'app par
      // du bleu profond (bleu nuit)") — le fond plein écran derrière le
      // cadre "téléphone" (desktop/large viewport) utilise désormais
      // [AppColors.shellBg] (bleu nuit très sombre) au lieu de noir pur.
      backgroundColor: AppColors.shellBg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          const maxW = 430.0;
          const maxH = 932.0;
          final isNarrowMobile = constraints.maxWidth < 480;

          if (isNarrowMobile) {
            // Vrai mobile (téléphone) : plein écran, comme l'original
            // (pas de contrainte @media(min-width:480px) appliquée).
            return SafeArea(child: content);
          }

          // Desktop / tablette / navigateur large : on reproduit le
          // cadre "app-shell" (max 430×932, coins arrondis, ombre
          // portée) centré sur fond sombre — port fidèle de la règle
          // CSS #app-shell + @media(min-width:480px) de l'ancienne
          // version, qui empêchait l'app de s'étirer sur toute la
          // largeur du navigateur.
          final frameW = constraints.maxWidth < maxW ? constraints.maxWidth : maxW;
          final availH = constraints.maxHeight - 40; // équiv. calc(100vh - 40px)
          final frameH = availH < maxH ? availH : maxH;

          return Center(
            child: Container(
              width: frameW,
              height: frameH,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(40),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xE6000000), // rgba(0,0,0,.9)
                    blurRadius: 100,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                bottom: false,
                child: content,
              ),
            ),
          );
        },
      ),
    );
  }
}
