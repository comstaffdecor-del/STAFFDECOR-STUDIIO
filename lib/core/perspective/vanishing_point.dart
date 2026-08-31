/// Modèle de point de fuite (VP) — perspective à 1 point de fuite,
/// axe de PROFONDEUR (celui utilisé par [toward]/[frac] pour faire reculer
/// une face plafond/sol de corniche/plinthe vers l'intérieur de la pièce).
///
/// Le VP est calculé par intersection des deux droites qui portent
/// RÉELLEMENT l'axe de profondeur dans l'image : la ligne mur-latéral-
/// gauche → coin-haut-gauche-du-fond (wallTL→fTL) et son symétrique côté
/// droit (wallTR→fTR) — ces deux droites sont les images de deux droites
/// parallèles du monde réel (toutes deux orientées selon l'axe qui
/// s'enfonce dans la pièce, perpendiculairement au mur du fond), donc leur
/// intersection est, par construction géométrique (pas une approximation),
/// le point de fuite de CET axe. Le couple bas (wallBL→fBL / wallBR→fBR)
/// donne la même droite de fuite et sert de repli si le couple haut est
/// dégénéré.
///
/// Représentation en coordonnées homogènes `(x, y, w)` : `w = 1` pour un
/// point fini (cas courant, mur du fond avec un angle réel même faible),
/// `w = 0` pour un point à l'infini (mur strictement frontal : les deux
/// droites ci-dessus sont exactement parallèles dans l'image — cas normal
/// de la perspective, pas une erreur). Dans ce dernier cas, `(x, y)` porte
/// la DIRECTION unitaire de l'axe de profondeur (plutôt que des
/// coordonnées de position), et [toward] devient une simple translation
/// selon cette direction au lieu d'une interpolation vers un point fini.
library;

import 'dart:ui';
import 'persp_geometry.dart' show dist, lineIntersect;

/// Point de fuite réel + repères architecturaux dérivés de la
/// calibration (mur du fond en pixels canvas).
class VanishingPoint {
  /// Coordonnées homogènes du VP : position finie si [w] == 1
  /// (`vp == Offset(x, y)`), direction unitaire de l'axe de profondeur si
  /// [w] == 0 (point à l'infini — mur strictement frontal).
  final double x;
  final double y;
  final double w;

  final Offset fTL, fTR, fBL, fBR;

  const VanishingPoint._({
    required this.x,
    required this.y,
    required this.w,
    required this.fTL,
    required this.fTR,
    required this.fBL,
    required this.fBR,
  });

  /// Construction directe à partir d'un point FINI (`w = 1`) — pour les
  /// sites d'appel (tests, démonstrations) qui connaissent déjà la
  /// position du VP sans passer par [compute].
  VanishingPoint({required Offset vp, required this.fTL, required this.fTR, required this.fBL, required this.fBR})
    : x = vp.dx,
      y = vp.dy,
      w = 1.0;

  /// Position du VP en coordonnées cartésiennes — valide seulement si
  /// [w] != 0 (point fini). Lève une [StateError] explicite sinon : un
  /// point à l'infini n'a pas de position, seulement une direction
  /// ([direction]) — accéder à [vp] dans ce cas serait un bug d'appelant,
  /// jamais silencieusement transformé en NaN/Infinity.
  Offset get vp {
    if (w == 0) {
      throw StateError(
        'VanishingPoint.vp : ce point de fuite est à l\'infini (w=0, mur '
        'strictement frontal) — il n\'a pas de position finie, seulement '
        'une direction (VanishingPoint.direction). Utiliser toward()/frac() '
        'directement : ils gèrent nativement les deux cas (fini/infini).',
      );
    }
    return Offset(x / w, y / w);
  }

  /// Direction unitaire de l'axe de profondeur — valide seulement si
  /// [w] == 0 (point à l'infini). Pour un point fini, la direction locale
  /// dépend du point de départ (voir [toward]) : pas de direction globale
  /// unique, donc pas d'accesseur ici dans ce cas.
  Offset get direction {
    if (w != 0) {
      throw StateError(
        'VanishingPoint.direction : ce point de fuite est fini (w=$w) — '
        'il n\'a pas de direction globale unique, utiliser toward()/frac() '
        'qui calculent la direction locale (vers vp) point par point.',
      );
    }
    return Offset(x, y);
  }

  /// `true` si ce VP est un point à l'infini (mur strictement frontal —
  /// cas normal de la perspective, pas un cas d'erreur).
  bool get isAtInfinity => w == 0;

  /// Calcule le VP de PROFONDEUR par intersection des deux droites qui
  /// portent réellement cet axe dans l'image : (wallTL→fTL) et
  /// (wallTR→fTR) pour le couple haut, (wallBL→fBL) et (wallBR→fBR) pour
  /// le couple bas (utilisé en repli si le couple haut est dégénéré). Ces
  /// quatre points de mur latéral sont l'ENTRÉE DE PROFONDEUR requise :
  /// [compute] ne peut renvoyer un VP de profondeur sans eux (contrairement
  /// à l'ancienne version qui prenait la moyenne des 4 coins du mur du
  /// fond — VP de l'axe horizontal conflaté avec celui de profondeur, ou
  /// centre géométrique sans aucune fuyante réelle, voir historique dans
  /// `docs/logs/` pour le diagnostic complet).
  ///
  /// Lève un [ArgumentError] explicite si [wallTL]/[wallTR]/[wallBL]/
  /// [wallBR] sont tous `null` (aucune entrée de profondeur fournie —
  /// impossible de déterminer ni une position, ni même une direction).
  ///
  /// Lève un [ArgumentError] si une entrée de profondeur est fournie mais
  /// que les deux couples (haut ET bas) sont dégénérés par coïncidence de
  /// points (mur latéral de longueur nulle des deux côtés à la fois haut
  /// ET bas — aucune direction n'est alors déductible, ce n'est pas un
  /// point à l'infini valide, c'est une absence totale d'information de
  /// profondeur malgré la présence des paramètres).
  ///
  /// Si les droites sont parallèles (mur strictement frontal, cas non
  /// dégénéré et fréquent) : retourne un VP à l'infini (`w = 0`) portant
  /// la direction unitaire de l'axe de profondeur.
  factory VanishingPoint.compute({
    required Offset fTL,
    required Offset fTR,
    required Offset fBL,
    required Offset fBR,
    Offset? wallTL,
    Offset? wallTR,
    Offset? wallBL,
    Offset? wallBR,
  }) {
    if (wallTL == null || wallTR == null || wallBL == null || wallBR == null) {
      throw ArgumentError(
        'VanishingPoint.compute : aucune entrée de profondeur fournie '
        '(wallTL/wallTR/wallBL/wallBR requis, tous non-null) — sans ces '
        'points de mur latéral, ni la position ni la direction de l\'axe '
        'de profondeur ne peuvent être déterminées. Passer les 8 points '
        'de la calibration complète (voir CalibCanvasPoints.fromCalib).',
      );
    }

    // Couple haut, puis repli sur le couple bas si dégénéré (parallèles).
    final vpTop = lineIntersect(wallTL, fTL, wallTR, fTR);
    final vpBottom = lineIntersect(wallBL, fBL, wallBR, fBR);
    final vpFinite = vpTop ?? vpBottom;
    if (vpFinite != null) {
      return VanishingPoint._(x: vpFinite.dx, y: vpFinite.dy, w: 1.0, fTL: fTL, fTR: fTR, fBL: fBL, fBR: fBR);
    }

    // Les deux couples sont parallèles (ou dégénérés) : tenter de
    // reconstruire une direction à partir de l'un des deux segments
    // latéraux (haut ou bas), le premier de longueur non nulle.
    final dirTop = _directionOf(wallTL, fTL);
    if (dirTop != null) {
      return VanishingPoint._(x: dirTop.dx, y: dirTop.dy, w: 0.0, fTL: fTL, fTR: fTR, fBL: fBL, fBR: fBR);
    }
    final dirBottom = _directionOf(wallBL, fBL);
    if (dirBottom != null) {
      return VanishingPoint._(x: dirBottom.dx, y: dirBottom.dy, w: 0.0, fTL: fTL, fTR: fTR, fBL: fBL, fBR: fBR);
    }

    throw ArgumentError(
      'VanishingPoint.compute : entrée de profondeur fournie mais '
      'totalement dégénérée — wallTL coïncide avec fTL ET wallBL coïncide '
      'avec fBL (segments latéraux de longueur nulle des deux côtés) : '
      'aucune direction de profondeur n\'est déductible. Ce n\'est pas un '
      'point à l\'infini valide (qui nécessite une direction connue), '
      'c\'est une absence de calibration de mur latéral exploitable.',
    );
  }

  /// Direction unitaire de `a`→`b`, ou `null` si `a` et `b` coïncident
  /// (segment de longueur nulle, aucune direction déductible).
  static Offset? _directionOf(Offset a, Offset b) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len = dist(a, b);
    if (len < 1e-9) return null;
    return Offset(dx / len, dy / len);
  }

  /// Hauteur perspective réelle du mur du fond (repère d'échelle pour
  /// dimensionner tous les produits, indépendant du letterboxing).
  double get pH => fBL.dy - fTL.dy;

  /// Projette [p] vers le VP d'une fraction [frac] (0 = p, 1 = VP pour un
  /// point fini). Pour un VP à l'infini (`w = 0`), devient une TRANSLATION
  /// pure de [p] selon la direction de l'axe de profondeur, sur une
  /// distance de [frac] pixels (voir [VanishingPoint.frac], qui renvoie
  /// alors directement `depthPx`, pas un ratio positionnel) — c'est la
  /// projection parallèle correcte pour un mur strictement frontal (les
  /// lignes de profondeur y sont réellement parallèles dans l'image, pas
  /// convergentes).
  Offset toward(Offset p, double frac) {
    if (w == 0) {
      return Offset(p.dx + x * frac, p.dy + y * frac);
    }
    final vpPos = Offset(x / w, y / w);
    return Offset(p.dx + (vpPos.dx - p.dx) * frac, p.dy + (vpPos.dy - p.dy) * frac);
  }

  /// Convertit une profondeur en pixels canvas en fraction de convergence
  /// vers le VP — port de `vpFrac`, SANS le plafonnement à 0.45 de
  /// l'ancienne version (artefact d'origine, retiré : rien dans la
  /// géométrie ne justifie de tronquer la convergence à cette valeur
  /// précise, voir brief définitif Étapes B/C point 7).
  ///
  /// Suppression du plafond 0.45 SANS remplacement créerait une NOUVELLE
  /// dégénérescence à la place de l'ancienne (brief "Suite" point 4) :
  /// `frac > 1` place le point résultant AU-DELÀ du point de fuite sur la
  /// droite (p → vp) — géométriquement impossible pour une face qui doit
  /// reculer VERS l'intérieur de la pièce, et produirait un rendu de
  /// corniche/plinthe inversé (face repliée en miroir derrière le VP). Ce
  /// cas lève donc un [StateError] EXPLICITE — jamais un clamp silencieux
  /// (`??`, `.clamp(0,1)`) qui masquerait une entrée de calibration
  /// invalide (profondeur demandée trop grande vis-à-vis de la distance
  /// réelle du point au VP) derrière un résultat numérique plausible mais
  /// faux.
  ///
  /// Pour un VP à l'infini (`w = 0`), il n'y a pas de "distance au VP"
  /// (infinie par définition, donc pas de notion de "dépasser" le VP) :
  /// la valeur renvoyée est directement [depthPx], interprétée par
  /// [toward] comme une magnitude de translation en pixels selon la
  /// direction de l'axe de profondeur — c'est la sémantique de projection
  /// parallèle attendue pour un mur strictement frontal. Mais l'exigence
  /// de garde explicite s'applique ICI AUSSI (brief "Suite" point 4,
  /// "même exigence sur la branche w=0") : une profondeur négative n'a de
  /// sens géométrique dans AUCUN des deux cas (reculer d'une distance
  /// négative n'est pas une opération valide sur une face de corniche),
  /// donc ce cas est également rejeté explicitement, plutôt que de
  /// produire silencieusement une translation dans le mauvais sens.
  double frac(Offset p, double depthPx) {
    if (depthPx < 0) {
      throw ArgumentError(
        'VanishingPoint.frac : depthPx=$depthPx négatif — une profondeur '
        'de recul ne peut pas être négative (ni pour un VP fini, ni pour '
        'un VP à l\'infini). Vérifier le calcul amont de depthPx.',
      );
    }
    if (w == 0) return depthPx;

    final vpPos = Offset(x / w, y / w);
    final d = dist(p, vpPos);
    if (d < 1e-9) {
      throw StateError(
        'VanishingPoint.frac : le point p=$p coïncide avec le VP fini '
        '$vpPos (distance ${d.toStringAsExponential(2)} < 1e-9) — aucune '
        'fraction de convergence n\'est définissable (division par une '
        'distance quasi nulle). Ce n\'est pas un cas valide de '
        'calibration : p doit être un point du mur du fond, distinct du '
        'VP par construction.',
      );
    }
    final result = depthPx / d;
    if (result > 1.0) {
      throw StateError(
        'VanishingPoint.frac : depthPx=$depthPx à distance $d du VP '
        'fini $vpPos donne frac=$result > 1 — la face demandée reculerait '
        'AU-DELÀ du point de fuite, ce qui est géométriquement impossible '
        '(donnerait une corniche/plinthe inversée). Plafonner '
        'silencieusement (comme le faisait l\'ancienne borne à 0.45) '
        'masquerait une profondeur de calibration incohérente avec la '
        'géométrie réelle de la scène : réduire depthPx, ou vérifier la '
        'calibration (mur latéral trop proche de fTL/fTR, ou point de '
        'vue incompatible avec la profondeur demandée).',
      );
    }
    return result;
  }
}
