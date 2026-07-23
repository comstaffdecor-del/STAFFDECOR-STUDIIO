/// Un item du projet en cours : produit sélectionné + quantité + unité.
///
/// Port fidèle de la structure `{ ref, famille, qte, unite }` de
/// `STATE.selectedProducts` (state.js).
class ProjectItem {
  final String ref;
  final String famille;
  final double qte;
  final String unite;

  const ProjectItem({
    required this.ref,
    required this.famille,
    required this.qte,
    required this.unite,
  });

  ProjectItem copyWith({double? qte, String? unite}) => ProjectItem(
    ref: ref,
    famille: famille,
    qte: qte ?? this.qte,
    unite: unite ?? this.unite,
  );

  Map<String, dynamic> toJson() => {
    'ref': ref,
    'famille': famille,
    'qte': qte,
    'unite': unite,
  };

  factory ProjectItem.fromJson(Map<String, dynamic> json) => ProjectItem(
    ref: json['ref'] as String,
    famille: json['famille'] as String,
    qte: (json['qte'] as num).toDouble(),
    unite: json['unite'] as String,
  );
}

/// Position de snap (accroche) d'un produit sur la photo de studio.
///
/// Port fidèle de `STATE.prodPositions[ref] = { snapLine, xPct }`.
class SnapPos {
  /// 'ceiling' | 'floor' | 'mid' | 'center' | 'lower-mid'
  final String snapLine;

  /// Position horizontale en fraction (0..1) de la largeur de l'image
  final double xPct;

  const SnapPos({required this.snapLine, required this.xPct});

  Map<String, dynamic> toJson() => {'snapLine': snapLine, 'xPct': xPct};

  factory SnapPos.fromJson(Map<String, dynamic> json) => SnapPos(
    snapLine: json['snapLine'] as String,
    xPct: (json['xPct'] as num).toDouble(),
  );
}
