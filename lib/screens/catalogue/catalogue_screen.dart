/// Écran Catalogue — port fidèle de `#screen-catalogue` (shell.ts).
///
/// Grille des 458 produits GED, filtres famille (pills), recherche,
/// pagination.
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/catalogue_data.dart';
import '../../models/product.dart';
import '../../state/app_state.dart';
import '../../widgets/common/common_ui.dart';
import '../../widgets/studio/product_modal.dart';

// ⚠️ CORRECTION Bug #13 : 'Lambris' et 'Profils LED' ajoutés — mêmes
// familles présentes dans [catalogueGed] mais absentes de ce filtre pills,
// rendant ~30 produits invisibles/inaccessibles depuis le Catalogue.
const _pills = <String, String>{
  'all': 'Tous',
  'Corniches': 'Corniches',
  'Moulures': 'Moulures',
  'Plinthes': 'Plinthes',
  'Parements': 'Parements',
  'Encadrements': 'Rosaces',
  'Colonnes': 'Colonnes',
  'Ornements': 'Ornements',
  'Lambris': 'Lambris',
  'Profils LED': 'Profils LED',
  'with_img': 'Photo',
};

class CatalogueScreen extends StatefulWidget {
  const CatalogueScreen({super.key});

  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final results = filterCatalogue(fam: state.catFam, q: state.catSearch);
    final total = getCatalogueStats().total;

    final perPage = state.catPerPage;
    final pageCount = (results.length / perPage).ceil().clamp(1, 999999);
    final page = state.catPage.clamp(0, pageCount - 1);
    final pageItems = results.skip(page * perPage).take(perPage).toList();

    return Stack(
      children: [
        Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: AppColors.bg,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Catalogue ',
                            style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: '$total réf. GED',
                            style: const TextStyle(color: AppColors.text3, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconBtn(icon: FontAwesomeIcons.xmark, size: 32, onTap: () => state.goTo('home')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Rechercher une référence…',
                  hintStyle: const TextStyle(color: AppColors.text3, fontSize: 12.5),
                  prefixIcon: const Icon(FontAwesomeIcons.magnifyingGlass, size: 14, color: AppColors.text3),
                  filled: true,
                  fillColor: AppColors.card,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
                onChanged: (v) => state.setCatSearch(v),
              ),
            ),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: _pills.entries.map((e) {
                  final active = state.catFam == e.key;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      onTap: () => state.setCatFam(e.key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: active ? AppColors.gold : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: active ? AppColors.gold : AppColors.border),
                        ),
                        child: Text(
                          e.value,
                          style: TextStyle(
                            color: active ? AppColors.bg : AppColors.text2,
                            fontSize: 11.5,
                            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Text(
                    '${results.length} résultat${results.length > 1 ? 's' : ''}',
                    style: const TextStyle(color: AppColors.text3, fontSize: 11),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.78,
                ),
                itemCount: pageItems.length,
                itemBuilder: (context, i) => _ProductCard(prod: pageItems[i]),
              ),
            ),
            if (pageCount > 1)
              Container(
                height: 46,
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconBtn(
                      icon: FontAwesomeIcons.chevronLeft,
                      size: 28,
                      onTap: page > 0 ? () => state.setCatPage(page - 1) : null,
                    ),
                    const SizedBox(width: 12),
                    Text('${page + 1} / $pageCount',
                        style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                    const SizedBox(width: 12),
                    IconBtn(
                      icon: FontAwesomeIcons.chevronRight,
                      size: 28,
                      onTap: page < pageCount - 1 ? () => state.setCatPage(page + 1) : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (state.productModalRef != null) const Positioned.fill(child: ProductModal()),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Produit prod;
  const _ProductCard({required this.prod});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final selected = state.getProdInProject(prod.ref) != null;

    return InkWell(
      onTap: () => state.openProduct(prod.ref),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.gold : AppColors.border, width: selected ? 1.5 : 1),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.card2,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: prod.img.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          prod.img,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) =>
                              const Icon(FontAwesomeIcons.image, size: 16, color: AppColors.text3),
                        ),
                      )
                    : const Icon(FontAwesomeIcons.image, size: 16, color: AppColors.text3),
              ),
            ),
            const SizedBox(height: 6),
            Text(prod.ref,
                style: TextStyle(
                    color: selected ? AppColors.gold : AppColors.text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
            Text('${prod.prix.toStringAsFixed(2)} €/${prod.unite}',
                style: const TextStyle(color: AppColors.text3, fontSize: 9.5)),
          ],
        ),
      ),
    );
  }
}
