/// Thème Flutter — port fidèle de la palette CSS originale (`base.css`).
///
/// Couleurs identiques à `:root { --bg, --gold, --text, ... }` pour
/// préserver le design existant demandé par l'utilisateur.
library;

import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF1C1714);
  static const bg2 = Color(0xFF231F1A);
  static const card = Color(0xFF2A2420);
  static const card2 = Color(0xFF322B25);
  static const gold = Color(0xFFC9A96E);
  static const goldLight = Color(0xFFE2C48A);
  static const goldDark = Color(0xFFA07840);
  static const text = Color(0xFFF5EFE3);
  static const text2 = Color(0xFFB8A898);
  static const text3 = Color(0xFF7A6A5A);
  static const border = Color(0xFF3D342A);
  static const platre = Color(0xFFF5F0E8);
  static const green = Color(0xFF4ADE80);
  static const red = Color(0xFFF87171);
  static const amber = Color(0xFFFBBF24);
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
