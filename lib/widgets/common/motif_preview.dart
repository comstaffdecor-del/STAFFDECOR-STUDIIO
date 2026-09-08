/// Aperçu zoomé du VRAI relief sculpté (feuillages, perles, oves) des
/// corniches/plinthes actuellement placées dans le projet.
///
/// ⚠️ CONTEXTE — Bug B (motifs manquants) : le rendu perspective de la
/// pièce (`RoomPainter`/`drawProfileFace`) mappe désormais la VRAIE photo
/// produit staffdecor.fr sur la bande (voir `ProductTextureCache` +
/// `_drawTexturedFace`), au lieu d'un dégradé procédural générique.
/// MAIS : à l'échelle d'une bande de corniche vue dans une pièce entière
/// (quelques dizaines de pixels de haut sur une photo de plusieurs mètres
/// de large), AUCUNE technique de rendu ne peut faire apparaître le détail
/// fin d'un relief sculpté — même un redimensionnement idéal (LANCZOS) de
/// la photo source à cette hauteur produit des bandes floues, sans motif
/// identifiable (limite de résolution/Nyquist, vérifiée empiriquement, pas
/// un défaut d'implémentation).
///
/// Solution rapide et sûre : un aperçu ZOOMÉ séparé, à côté du rendu pièce,
/// qui montre le vrai relief net (la vraie photo produit, pas de silhouette
/// générique) — sans toucher à la géométrie/perspective déjà validée
/// (Bug A, corrigé précédemment). L'utilisateur voit ainsi concrètement le
/// motif réel du produit choisi, même si la bande dans la photo de pièce
/// reste (normalement, physiquement) trop fine pour le révéler.
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/theme.dart';
import '../../data/catalogue_data.dart';
import '../../models/product.dart';
import '../../models/project_item.dart';

/// Familles pour lesquelles le relief sculpté (photo produit) a un sens —
/// mêmes familles que celles texturées par [ProductTextureCache] dans
/// `RoomPainter`.
///
/// ⚠️ CORRECTION Bug #7 : 'Moulures' ajouté — la vignette "Relief réel"
/// doit désormais suivre le modèle de moulure réellement sélectionné
/// (voir moulure_painter.dart pour le texture-mapping correspondant).
const _kMotifFamilies = {'Corniches', 'Plinthes', 'Moulures'};

/// Bandeau horizontal de vignettes "vrai relief" — une par famille
/// Corniches/Plinthes actuellement dans [selectedProducts] (au plus une de
/// chaque, cohérent avec la règle "1 produit par famille" de [AppState]).
/// Ne s'affiche que si au moins un produit concerné est sélectionné.
class MotifPreviewBar extends StatelessWidget {
  final List<ProjectItem> selectedProducts;
  const MotifPreviewBar({super.key, required this.selectedProducts});

  @override
  Widget build(BuildContext context) {
    final byFam = <String, ProjectItem>{};
    for (final item in selectedProducts) {
      if (_kMotifFamilies.contains(item.famille)) {
        byFam.putIfAbsent(item.famille, () => item);
      }
    }
    if (byFam.isEmpty) return const SizedBox.shrink();

    final chips = byFam.values
        .map((item) => getProdByRef(item.ref))
        .whereType<Produit>()
        .toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final prod in chips) ...[
          _MotifChip(ref: prod.ref),
          const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// Une vignette : vraie photo produit (vignette CAD locale), zoomée sur le
/// centre (là où le relief est visible), avec libellé "Relief réel — {ref}".
///
/// ⚠️ P18-HOTFIX : remplace l'ancien `Image.network(prod.img)` (staffdecor.fr,
/// dépendance réseau, sujette au CORS — voir le diagnostic "vignettes
/// blanches D520/PLIN08M" ci-dessous, désormais obsolète pour ce widget) par
/// un asset LOCAL `assets/profiles/control/<ref>.png` — aucune vérification
/// d'existence synchrone (pas idiomatique Flutter, un asset ne se sonde pas
/// de façon synchrone) : c'est `errorBuilder` qui gère l'absence du fichier
/// pour les refs sans vignette de contrôle (12/43 aujourd'hui : D116, D515,
/// D545, D569, D612, D617, D633, D653, D715, D801, D815, D840 — placeholder
/// neutre affiché pour ces refs, y compris D545 qui EST présent dans la
/// bande). Sensible à la casse : `ref` doit correspondre exactement au nom
/// de fichier PNG (les refs catalogue sont déjà en casse fixe, ex. 'D609',
/// jamais 'd609').
class _MotifChip extends StatelessWidget {
  final String ref;
  const _MotifChip({required this.ref});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Vrai relief sculpté du produit $ref (photo staffdecor.fr) — '
          'zoomé pour être visible, la bande dans la pièce est trop fine '
          'pour révéler ce niveau de détail.',
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 46,
                // card2 (fond sombre) au lieu de platre : les PNG produits
                // sont RGBA majoritairement transparents (76-93 %), le
                // plâtre blanc sur fond platre donne une amplitude ~46-66
                // (invisible) contre ~201-204 sur fond sombre. Voir commit
                // d'obsolescence de 73787af pour le détail de la mesure.
                color: AppColors.card2,
                child: ClipRect(
                  child: Transform.scale(
                    scale: 1.7,
                    child: Image.asset(
                      'assets/profiles/control/$ref.png',
                      fit: BoxFit.cover,
                      // Fallback local (P18-HOTFIX) : 12/43 refs n'ont pas
                      // de vignette control/*.png sur disque — errorBuilder
                      // est le seul mécanisme idiomatique pour ce cas (pas
                      // de vérification d'existence synchrone en Flutter).
                      errorBuilder: (_, __, ___) => const Icon(
                        FontAwesomeIcons.image,
                        size: 14,
                        color: AppColors.text3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Relief réel · $ref',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.gold, fontSize: 8.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
