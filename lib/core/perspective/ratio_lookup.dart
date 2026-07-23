/// Résolution du ratio largeur/hauteur réel d'un produit pour le rendu.
///
/// ⚠️ CORRECTION Bug #3 (audit) : priorité au vrai ratio `PROD_PROFILES`
/// (283 entrées extraites des PDF GED) — jamais consommé dans le rendu
/// de l'ancienne version. Fallback sur [famRatioFallback] uniquement
/// si aucune entrée réelle n'existe pour la référence.
library;

import '../../data/prod_profiles_data.dart';
import '../fam_constants.dart';

double resolveProfileRatio(String ref, String famille) {
  final real = getProfileRatio(ref);
  if (real != null) return real;
  return famRatioFallback[famille] ?? 1.0;
}
