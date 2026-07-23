/// Modèle de donnée d'un produit du catalogue Staff Décor.
///
/// Miroir exact de la structure JS d'origine (catalogue.js) :
/// { ref, nom, img, famille, sfam, unite, barre, prix, dwg }
class Produit {
  /// Référence unique du produit (ex: 'D520', 'PLIN10A')
  final String ref;

  /// Nom / désignation commerciale
  final String nom;

  /// URL de l'image produit (staffdecor.fr ou ged.staffdecor.fr)
  final String img;

  /// Famille du produit (une des 9 familles : Corniches, Moulures, ...)
  final String famille;

  /// Sous-famille (ex: 'Classiques', 'Contemporaines', 'LED', ...)
  final String sfam;

  /// Unité de vente : 'ml' (mètre linéaire), 'm²' (surface) ou 'pce' (pièce)
  final String unite;

  /// Longueur de barre en mètres pour les produits linéaires (null sinon)
  final double? barre;

  /// Prix unitaire HT (€)
  final double prix;

  /// URL de téléchargement du plan DWG (optionnel, souvent absent)
  final String? dwg;

  const Produit({
    required this.ref,
    required this.nom,
    required this.img,
    required this.famille,
    required this.sfam,
    required this.unite,
    required this.barre,
    required this.prix,
    this.dwg,
  });

  /// Vrai si le produit se vend au mètre linéaire (avec longueur de barre)
  bool get isLineaire => unite == 'ml';

  /// Vrai si le produit se vend en surface (m²)
  bool get isSurface => unite == 'm²';

  /// Vrai si le produit se vend à la pièce
  bool get isPiece => unite == 'pce';

  @override
  String toString() => 'Produit($ref, $nom, $famille/$sfam, $prix€/$unite)';

  @override
  bool operator ==(Object other) => other is Produit && other.ref == ref;

  @override
  int get hashCode => ref.hashCode;
}
