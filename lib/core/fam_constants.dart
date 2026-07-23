/// Constantes par famille de produits — port fidèle de studio.js.
///
/// Regroupe ce qui était dupliqué/dispersé dans l'ancienne version
/// (corrige en partie le Bug #6 : logiques de fallback xPct incohérentes
/// selon la famille) en centralisant les règles de comportement par
/// défaut ici, consommées par un unique moteur de placement.
library;

import 'package:flutter/material.dart';

/// Ligne d'accroche par défaut pour une famille donnée quand aucune
/// position n'a encore été fixée par l'utilisateur.
/// 'ceiling' | 'floor' | 'mid' | 'center' | 'lower-mid'
const Map<String, String> famSnapDefault = {
  'Corniches': 'ceiling', // arête plafond/mur
  'Moulures': 'mid', // mi-hauteur mur
  'Plinthes': 'floor', // arête sol/mur
  'Profils LED': 'lower-mid', // sous la corniche
  'Encadrements': 'center', // centre plafond (rosaces)
  'Colonnes': 'center', // point libre sur mur
  'Parements': 'lower-mid', // aplat mural
  'Lambris': 'floor', // lambris bas de mur
  'Ornements': 'center', // ornement mural libre
};

/// Seuils de hauteur (en fraction 0..1 depuis le haut de l'image) utilisés
/// pour détecter automatiquement la ligne de snap la plus proche d'un point
/// déposé par l'utilisateur.
const Map<String, double> snapYThresholds = {
  'ceiling': 0.12, // < 12% du haut → ceiling
  'mid': 0.50, // 12–50% → mid
  'lower-mid': 0.65, // 50–65% → lower-mid
  'floor': 1.00, // > 65% → floor
  // "center" est spécial — toujours pour Rosaces/Ornements/Colonnes
};

/// Détecte la ligne de snap la plus probable pour une position Y donnée
/// (fraction 0..1), en tenant compte du comportement spécifique de
/// certaines familles ('center' toujours pour Encadrements/Colonnes/Ornements).
String detectSnapLine(double yRatio, String famille) {
  const familiesCenterOnly = {'Encadrements', 'Colonnes', 'Ornements'};
  if (familiesCenterOnly.contains(famille)) return 'center';

  if (yRatio < snapYThresholds['ceiling']!) return 'ceiling';
  if (yRatio < snapYThresholds['mid']!) return 'mid';
  if (yRatio < snapYThresholds['lower-mid']!) return 'lower-mid';
  return 'floor';
}

/// Position par défaut (%) de l'item de famille dans le strip / bandeau
/// de sélection catégorie (position visuelle UI, pas position sur photo).
class FamPosition {
  final double top;
  final String side; // 'left' | 'right'
  final double anchorX;
  const FamPosition({
    required this.top,
    required this.side,
    required this.anchorX,
  });
}

const Map<String, FamPosition> famPositions = {
  'Corniches': FamPosition(top: 2, side: 'left', anchorX: 50),
  'Moulures': FamPosition(top: 40, side: 'left', anchorX: 38),
  'Plinthes': FamPosition(top: 80, side: 'right', anchorX: 55),
  'Profils LED': FamPosition(top: 50, side: 'left', anchorX: 32),
  'Encadrements': FamPosition(top: 20, side: 'left', anchorX: 60),
  'Colonnes': FamPosition(top: 45, side: 'right', anchorX: 72),
  'Parements': FamPosition(top: 45, side: 'right', anchorX: 65),
  'Lambris': FamPosition(top: 55, side: 'right', anchorX: 60),
  'Ornements': FamPosition(top: 30, side: 'left', anchorX: 45),
};

/// Couleur teinte de base par famille (rendu générique en attendant/à
/// défaut de profil réel — voir Bug #2 dans le moteur de rendu corrigé).
const Map<String, Color> famColors = {
  'Corniches': Color(0xFFF0EDE8),
  'Moulures': Color(0xFFEDE9E3),
  'Plinthes': Color(0xFFEAE6E0),
  'Parements': Color(0xFFE8E4DE),
  'Encadrements': Color(0xFFF2EFE9),
  'Colonnes': Color(0xFFEFECE6),
  'Profils LED': Color(0xFFD0EEFF), // LED → teinte bleutée légère
  'Lambris': Color(0xFFE6E2DC),
  'Ornements': Color(0xFFF0EDE8),
};

/// Fallback de ratio largeur/hauteur générique par famille, utilisé
/// uniquement quand aucun profil réel n'existe dans `prod_profiles_data.dart`
/// pour la référence demandée (corrige le Bug #3 : ces ratios réels étaient
/// chargés mais jamais utilisés dans l'ancienne version).
const Map<String, double> famRatioFallback = {
  'Corniches': 0.55, // haut/étroit
  'Moulures': 1.8, // plutôt large/plat
  'Plinthes': 4.0, // large/plat (bande basse)
  'Profils LED': 0.5,
  'Encadrements': 1.0, // rosace ~carrée/ronde
  'Colonnes': 0.25, // haut/étroit (pilastre vertical)
  'Parements': 1.0, // dalle carrée
  'Lambris': 1.0,
  'Ornements': 1.0,
};
