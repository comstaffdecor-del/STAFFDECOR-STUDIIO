/// Widgets UI communs réutilisables — port fidèle des classes CSS
/// `.btn-gold`, `.btn-outline`, `.icon-btn`, `.topbar`, `.section-title`
/// (base.css) pour préserver le design d'origine.
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Bouton doré plein — équivalent `.btn-gold`.
class BtnGold extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool small;
  const BtnGold({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.bg,
        padding: EdgeInsets.symmetric(
          horizontal: small ? 14 : 20,
          vertical: small ? 8 : 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: small ? 13 : 15),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: small ? 12 : 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton contour — équivalent `.btn-outline`.
class BtnOutline extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool small;
  const BtnOutline({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text2,
        side: const BorderSide(color: AppColors.border),
        padding: EdgeInsets.symmetric(
          horizontal: small ? 12 : 18,
          vertical: small ? 7 : 11,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: small ? 12 : 14),
            const SizedBox(width: 7),
          ],
          Text(label, style: TextStyle(fontSize: small ? 11 : 13)),
        ],
      ),
    );
  }
}

/// Bouton icône rond — équivalent `.icon-btn`.
class IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  const IconBtn({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.card2,
          borderRadius: BorderRadius.circular(size / 2),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: size * 0.42, color: AppColors.text2),
      ),
    );
  }
}

/// Barre supérieure générique — équivalent `.topbar`.
class AppTopbar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const AppTopbar({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.text3,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Titre de section — équivalent `.section-title`.
class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.text2,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Toast simple (SnackBar stylée gold-on-charcoal), équivalent `#toast`.
void showAppToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(color: AppColors.text)),
      backgroundColor: AppColors.card2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      duration: const Duration(seconds: 2),
    ),
  );
}

/// Badge estimatif/calibré — équivalent `.mini-badge` / `#calib-badge`.
class EstimBadge extends StatelessWidget {
  final bool calibrated;
  const EstimBadge({super.key, required this.calibrated});

  @override
  Widget build(BuildContext context) {
    final color = calibrated ? AppColors.green : AppColors.amber;
    final label = calibrated ? 'Calibré ±3%' : 'Estimatif ±15%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}
