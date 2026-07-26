/// Thème Flutter — palette "bleu nuit" (retour utilisateur : "Remplace le
/// noir de l'app par du bleu profond (bleu nuit)").
///
/// ⚠️ CORRECTION demande utilisateur (2e passe) : la première passe de
/// bleu nuit (`0xFF0B1220` etc.) a été jugée pas assez sombre ("on
/// attendait un bleu encore plus foncé"). La palette est donc à nouveau
/// resserrée vers le bas — fond quasi noir avec une dominante bleu marine/
/// encre bien plus profonde — tout en conservant à l'identique les
/// accents dorés (`gold`/`goldLight`/`goldDark`) qui portent l'identité
/// visuelle Staff Décor, ainsi que les couleurs sémantiques
/// (`green`/`red`/`amber`) et les teintes de texte (le contraste texte
/// crème / fond bleu nuit reste excellent, voire meilleur car le fond
/// est plus sombre).
library;

import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF050810);
  static const bg2 = Color(0xFF080D1B);
  static const card = Color(0xFF0C1428);
  static const card2 = Color(0xFF101C34);
  static const gold = Color(0xFFC9A96E);
  static const goldLight = Color(0xFFE2C48A);
  static const goldDark = Color(0xFFA07840);
  static const text = Color(0xFFF5EFE3);
  static const text2 = Color(0xFFB0B9CC);
  static const text3 = Color(0xFF6E7A94);
  static const border = Color(0xFF1C2C4C);
  static const platre = Color(0xFFF5F0E8);
  static const green = Color(0xFF4ADE80);
  static const red = Color(0xFFF87171);
  static const amber = Color(0xFFFBBF24);

  /// Fond plein écran derrière le cadre "téléphone" (desktop/large écran)
  /// — équivalent bleu nuit du `body { background:#000 }` d'origine
  /// (quasi noir avec une pointe de bleu marine, encore plus sombre que
  /// [bg] pour garder une sensation de profondeur derrière le cadre
  /// applicatif).
  static const shellBg = Color(0xFF020408);
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    // NOTE : la police d'origine ("Georgia") n'est pas disponible comme
    // asset embarqué — on utilise la police système par défaut pour éviter
    // un fallback silencieux, tout en conservant la palette de couleurs
    // exacte de l'ancien design (c'est la palette qui porte l'identité
    // visuelle Staff Décor, pas la police).
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.gold,
      brightness: Brightness.dark,
      surface: AppColors.bg,
      primary: AppColors.gold,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: AppColors.gold,
        fontSize: 17,
        letterSpacing: 1,
      ),
      iconTheme: IconThemeData(color: AppColors.text2),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text2,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        textStyle: const TextStyle(fontSize: 13),
      ),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.text),
      bodySmall: TextStyle(color: AppColors.text2),
    ),
    dividerColor: AppColors.border,
  );
}
