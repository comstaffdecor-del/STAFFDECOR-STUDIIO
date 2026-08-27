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
          _MotifChip(ref: prod.ref, imgUrl: prod.img),
          const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// Une vignette : vraie photo produit, zoomée sur le centre (là où le
/// relief est visible), avec libellé "Relief réel — {ref}".
class _MotifChip extends StatelessWidget {
  final String ref;
  final String imgUrl;
  const _MotifChip({required this.ref, required this.imgUrl});

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
                child: imgUrl.isEmpty
                    ? const Icon(FontAwesomeIcons.image, size: 14, color: AppColors.text3)
                    : ClipRect(
                        child: Transform.scale(
                          scale: 1.7,
                          child: Image.network(
                            imgUrl,
                            fit: BoxFit.cover,
                            // ⚠️ Fallback CORS (diagnostic vignettes blanches
                            // D520/PLIN08M — détail complet dans le message de
                            // commit) : bascule sur un <img> HTML, hors CORS
                            // strict du fetch CanvasKit, UNIQUEMENT si le
                            // fetch échoue ; inerte sinon.
                            // ⚠️ Ce widget est composé DANS le RepaintBoundary
                            // exporté par ComparateurScreen
                            // ._downloadComparisonImage — un <img> HTML n'y
                            // est pas capturé (vide au lieu de l'icône
                            // d'erreur actuelle, pas une régression). NE PAS
                            // reproduire sur les 3 autres sites Image.network
                            // du dépôt sans revérifier leur exposition à un
                            // export RepaintBoundary.
                            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                            errorBuilder: (_, __, ___) => const Icon(
                              FontAwesomeIcons.image,
                              size: 14,
                              color: AppColors.text3,
                            ),
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Center(
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 1.6),
                                ),
                              );
                            },
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
