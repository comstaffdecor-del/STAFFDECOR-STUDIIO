/// Modèles pour la calibration de perspective d'une photo de pièce.
///
/// Port fidèle de la structure `_CALIB_DEFAULT` / `STATE.perspCalib` de
/// l'ancienne version JS (studio.js), avec un point capital corrigé par
/// l'audit : un SEUL moteur de perspective doit désormais consommer ces
/// données (Studio ET Comparateur), au lieu des 3 systèmes disjoints
/// identifiés (Bug #5).
library;

/// Un point de calibration exprimé en fraction (0..1) des dimensions
/// de l'image (xPct, yPct).
class CalibPoint {
  final double xPct;
  final double yPct;
  const CalibPoint({required this.xPct, required this.yPct});

  CalibPoint copyWith({double? xPct, double? yPct}) =>
      CalibPoint(xPct: xPct ?? this.xPct, yPct: yPct ?? this.yPct);

  Map<String, double> toJson() => {'xPct': xPct, 'yPct': yPct};

  factory CalibPoint.fromJson(Map<String, dynamic> json) => CalibPoint(
    xPct: (json['xPct'] as num).toDouble(),
    yPct: (json['yPct'] as num).toDouble(),
  );
}

/// Calibration de perspective à 8 points définissant le mur du fond
/// (ceilL/ceilR/floorL/floorR) et les murs latéraux (wallTL/TR/BL/BR).
///
/// Sert de base unique au calcul du point de fuite réel (voir
/// `lib/core/perspective/vanishing_point.dart`), remplaçant les 3 systèmes
/// disjoints de l'ancienne version (bandes plates Corniches/Plinthes,
/// heuristique approximative studio.js, pourcentages fixes comparateur.js).
class PerspCalib {
  final CalibPoint ceilL;
  final CalibPoint ceilR;
  final CalibPoint floorL;
  final CalibPoint floorR;
  final CalibPoint wallTL;
  final CalibPoint wallTR;
  final CalibPoint wallBL;
  final CalibPoint wallBR;

  const PerspCalib({
    required this.ceilL,
    required this.ceilR,
    required this.floorL,
    required this.floorR,
    required this.wallTL,
    required this.wallTR,
    required this.wallBL,
    required this.wallBR,
  });

  /// Calibration par défaut — identique à `_CALIB_DEFAULT` de studio.js.
  /// Utilisée tant qu'aucune calibration IA/manuelle n'a été appliquée
  /// (photo importée par l'utilisateur, sans preset dédié).
  static const PerspCalib defaultCalib = PerspCalib(
    ceilL: CalibPoint(xPct: 0.200, yPct: 0.150),
    ceilR: CalibPoint(xPct: 0.800, yPct: 0.150),
    floorL: CalibPoint(xPct: 0.200, yPct: 0.850),
    floorR: CalibPoint(xPct: 0.800, yPct: 0.850),
    wallTL: CalibPoint(xPct: 0.000, yPct: 0.080),
    wallTR: CalibPoint(xPct: 1.000, yPct: 0.080),
    wallBL: CalibPoint(xPct: 0.000, yPct: 0.920),
    wallBR: CalibPoint(xPct: 1.000, yPct: 0.920),
  );

  /// ⚠️ CORRECTION Bug rendu "angles" (retour utilisateur : "les produits
  /// n'épousent pas comme il faut les angles") — la [defaultCalib]
  /// générique ci-dessus était appliquée IDENTIQUEMENT aux 4 photos de
  /// scènes démo par `AppState.loadDemoScene`, ignorant totalement la
  /// vraie géométrie (ligne de plafond, ligne de sol, angles des murs
  /// latéraux) de chaque photo — d'où des bandes de corniche/plinthe
  /// rendues en diagonale, décrochées de l'architecture réelle visible.
  ///
  /// Les 8 points ci-dessous ont été mesurés à la main, en pourcentage
  /// (xPct/yPct de l'image source), par analyse pixel précise (grilles de
  /// repérage 1%/5%/10% superposées) de chacune des 4 photos réelles
  /// `assets/demo_scenes/*.jpg` :
  ///   - Haussmannien (2560×1783) : plafond mouluré déjà orné dans la
  ///     photo, ligne haute du mur plat ≈ y9%, angles de porte visibles
  ///     à gauche ≈ x9%, fenêtres à droite ≈ x90%, sol/tapis ≈ y88%.
  ///   - Contemporain (1960×1470) : plafond à poutres diagonales,
  ///     jonction mur/plafond ≈ y9-10%, sol/tapis ≈ y72%.
  ///   - Provençal (2560×1707) : poutres apparentes SUR TOUTE LA LARGEUR
  ///     (pas de ligne de plafond plate nette) → on calibre sur la ligne
  ///     basse des poutres (≈ y14%) comme proxy de plafond, sol carrelé
  ///     net ≈ y83%.
  ///   - Scandinave (1920×1088) : plafond blanc uni, ombre de jonction
  ///     mur/plafond ≈ y7-8%, sol/tapis clair ≈ y81%.
  static const Map<String, PerspCalib> demoPresets = {
    'haussmann': PerspCalib(
      ceilL: CalibPoint(xPct: 0.120, yPct: 0.090),
      ceilR: CalibPoint(xPct: 0.880, yPct: 0.085),
      floorL: CalibPoint(xPct: 0.120, yPct: 0.870),
      floorR: CalibPoint(xPct: 0.880, yPct: 0.860),
      wallTL: CalibPoint(xPct: 0.000, yPct: 0.100),
      wallTR: CalibPoint(xPct: 1.000, yPct: 0.095),
      wallBL: CalibPoint(xPct: 0.000, yPct: 0.900),
      wallBR: CalibPoint(xPct: 1.000, yPct: 0.890),
    ),
    'moderne': PerspCalib(
      ceilL: CalibPoint(xPct: 0.100, yPct: 0.095),
      ceilR: CalibPoint(xPct: 0.900, yPct: 0.095),
      floorL: CalibPoint(xPct: 0.100, yPct: 0.720),
      floorR: CalibPoint(xPct: 0.900, yPct: 0.720),
      wallTL: CalibPoint(xPct: 0.000, yPct: 0.105),
      wallTR: CalibPoint(xPct: 1.000, yPct: 0.105),
      wallBL: CalibPoint(xPct: 0.000, yPct: 0.740),
      wallBR: CalibPoint(xPct: 1.000, yPct: 0.740),
    ),
    'provencal': PerspCalib(
      ceilL: CalibPoint(xPct: 0.100, yPct: 0.140),
      ceilR: CalibPoint(xPct: 0.900, yPct: 0.140),
      floorL: CalibPoint(xPct: 0.100, yPct: 0.830),
      floorR: CalibPoint(xPct: 0.900, yPct: 0.830),
      wallTL: CalibPoint(xPct: 0.000, yPct: 0.150),
      wallTR: CalibPoint(xPct: 1.000, yPct: 0.150),
      wallBL: CalibPoint(xPct: 0.000, yPct: 0.850),
      wallBR: CalibPoint(xPct: 1.000, yPct: 0.850),
    ),
    'scandinave': PerspCalib(
      ceilL: CalibPoint(xPct: 0.100, yPct: 0.075),
      ceilR: CalibPoint(xPct: 0.900, yPct: 0.075),
      floorL: CalibPoint(xPct: 0.100, yPct: 0.810),
      floorR: CalibPoint(xPct: 0.900, yPct: 0.810),
      wallTL: CalibPoint(xPct: 0.000, yPct: 0.085),
      wallTR: CalibPoint(xPct: 1.000, yPct: 0.085),
      wallBL: CalibPoint(xPct: 0.000, yPct: 0.830),
      wallBR: CalibPoint(xPct: 1.000, yPct: 0.830),
    ),
  };

  /// Retourne le preset dédié à la scène démo [key], ou [defaultCalib] si
  /// [key] ne correspond à aucun preset connu.
  static PerspCalib forDemoScene(String key) => demoPresets[key] ?? defaultCalib;

  PerspCalib copyWith({
    CalibPoint? ceilL,
    CalibPoint? ceilR,
    CalibPoint? floorL,
    CalibPoint? floorR,
    CalibPoint? wallTL,
    CalibPoint? wallTR,
    CalibPoint? wallBL,
    CalibPoint? wallBR,
  }) {
    return PerspCalib(
      ceilL: ceilL ?? this.ceilL,
      ceilR: ceilR ?? this.ceilR,
      floorL: floorL ?? this.floorL,
      floorR: floorR ?? this.floorR,
      wallTL: wallTL ?? this.wallTL,
      wallTR: wallTR ?? this.wallTR,
      wallBL: wallBL ?? this.wallBL,
      wallBR: wallBR ?? this.wallBR,
    );
  }

  Map<String, dynamic> toJson() => {
    'ceilL': ceilL.toJson(),
    'ceilR': ceilR.toJson(),
    'floorL': floorL.toJson(),
    'floorR': floorR.toJson(),
    'wallTL': wallTL.toJson(),
    'wallTR': wallTR.toJson(),
    'wallBL': wallBL.toJson(),
    'wallBR': wallBR.toJson(),
  };

  factory PerspCalib.fromJson(Map<String, dynamic> json) => PerspCalib(
    ceilL: CalibPoint.fromJson(json['ceilL']),
    ceilR: CalibPoint.fromJson(json['ceilR']),
    floorL: CalibPoint.fromJson(json['floorL']),
    floorR: CalibPoint.fromJson(json['floorR']),
    wallTL: CalibPoint.fromJson(json['wallTL']),
    wallTR: CalibPoint.fromJson(json['wallTR']),
    wallBL: CalibPoint.fromJson(json['wallBL']),
    wallBR: CalibPoint.fromJson(json['wallBR']),
  );
}

/// Géométrie de la photo dessinée en mode "contain" dans sa zone d'affichage
/// (dx, dy = offset du letterboxing, dw/dh = dimensions réelles affichées,
/// scale = ratio image affichée / image source).
///
/// Port fidèle de `STATE.imgDraw` de l'ancienne version.
class ImgDraw {
  final double dx;
  final double dy;
  final double dw;
  final double dh;
  final double scale;

  const ImgDraw({
    required this.dx,
    required this.dy,
    required this.dw,
    required this.dh,
    required this.scale,
  });
}
