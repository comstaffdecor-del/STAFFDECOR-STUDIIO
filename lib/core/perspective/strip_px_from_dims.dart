/// Conversion mm → px des dimensions réelles d'un profil, pour piloter
/// `StripThickness` (`cornice_plinth_painter.dart`) à partir d'une
/// métrique réelle plutôt que des coefficients en dur.
///
/// ⚠️ Fonction PURE, SYNCHRONE, SANS AUCUNE ENTRÉE-SORTIE — volontairement
/// séparée de `loadProfileDims` (async, `rootBundle`), qui ne peut pas être
/// appelée depuis `CustomPainter.paint` (synchrone). Le chargement des
/// dimensions doit se faire en amont et être passé ici comme donnée déjà
/// résolue — le mécanisme d'acheminement async→sync (sur le modèle de
/// `ProductTextureCache`) reste une étape ultérieure distincte, non
/// traitée par ce fichier.
///
/// Ce fichier n'importe ni `dart:ui`, ni `cornice_plinth_painter.dart`, ni
/// `lib/core/geometry/` — aucun couplage au peintre à ce stade.
///
/// AUCUN REPLI EN DUR : contrairement à une version antérieure de ce
/// fichier, `stripPxFromDims` ne porte plus les coefficients
/// `0.055`/`0.140` en constantes locales. Cette duplication (les mêmes
/// nombres existant à la fois ici et dans `StripThickness.corniceDefault`)
/// était exactement le motif ayant produit trois rétractations
/// documentaires (voir `docs/ETAT_MOTEUR_RENDU.md`) : deux sources de
/// vérité pour la même valeur, désynchronisables silencieusement si l'une
/// bouge sans l'autre. La fonction renvoie `null` quand elle ne peut pas
/// calculer ; c'est à l'appelant — qui détient déjà l'instance
/// `StripThickness` — d'appliquer `StripThickness.corniceDefault(pH)`
/// comme défaut dans ce cas.
library;

/// Facteur de conversion millimètres → pixels canvas, dérivé de la
/// hauteur perspective réelle du mur du fond (`pH`, en pixels) et de la
/// hauteur sous plafond saisie par l'utilisateur (`metresHauteur`, en
/// mètres — libellé confirmé "Hauteur plafond" dans
/// `lib/widgets/studio/metres_panel.dart`, ligne 110).
///
/// Renvoie `null` si `metresHauteur` n'est pas strictement positif —
/// jamais de division par zéro ni de facteur négatif silencieusement
/// produit.
double? pxParMm({required double pH, required double metresHauteur}) {
  if (metresHauteur <= 0) return null;
  return pH / (metresHauteur * 1000.0);
}

/// Épaisseurs en pixels canvas pour les quatre faces d'un segment de
/// corniche/plinthe (les quatre champs de `StripThickness`).
typedef StripPxResult = ({
  double faceMurFondPx,
  double faceHorizFondPx,
  double faceMurLatPx,
  double faceHorizLatPx,
});

/// Ratio latéral/fond appliqué pour dériver `faceMurLatPx`/`faceHorizLatPx`
/// à partir de `faceMurFondPx`/`faceHorizFondPx`. Valeurs identiques au
/// rapport entre les coefficients de `StripThickness.corniceDefault`
/// (`cornice_plinth_painter.dart`, lignes 81-86) : `0.080/0.055` pour le
/// mur, `0.200/0.140` pour l'horizontal.
///
/// Pourquoi un facteur fixe plutôt qu'une conversion indépendante de
/// `faceMurLat`/`faceHorizLat` : si fond et latéral sont multipliés par
/// le même facteur d'échelle mm→px, leur RAPPORT reste exactement ce
/// qu'il est aujourd'hui — le comportement à l'angle (continuité ou non
/// entre le segment de fond et le segment latéral) est donc
/// rigoureusement inchangé par cette conversion, indépendamment de ce que
/// ce ratio encode. Une stabilité de ce ratio à ±0,5 % entre la famille
/// corniche et la famille plinthe (1.4545/1.4286 contre 1.4615/1.4348)
/// est une curiosité de plausibilité, PAS la justification du choix — la
/// justification est l'invariance du rapport, qui tient quelle que soit
/// l'origine réelle du nombre.
///
/// ⚠️ Nuance importante, à ne jamais perdre de vue : ce facteur ne dépend
/// pas du produit, il dépend de la SCÈNE. Il représente l'agrandissement
/// apparent moyen des parois latérales, qui fuient vers le point de fuite
/// — ce qui explique pourquoi le code donne à la bande latérale une
/// épaisseur constante alors qu'elle devrait s'amincir en s'éloignant du
/// point de fuite. Convertir en métrique ne rend donc PAS la face
/// latérale géométriquement correcte : cela rescale la même approximation
/// avec, cette fois, une cote réelle côté fond. Les faces latérales ne
/// sont pas cotées par cette fonction — seul le segment de fond l'est.
const double _kRatioLatFondMur = 0.080 / 0.055;
const double _kRatioLatFondHoriz = 0.200 / 0.140;

/// Coefficients par défaut pour une CORNICHE (proportionnels à [pH]),
/// utilisés quand aucune dimension réelle n'est disponible (275 des 283
/// références du catalogue, sans profil JSON).
///
/// ⚠️ Descendus ici depuis `StripThickness.corniceDefault`
/// (`cornice_plinth_painter.dart`) pour la même raison que le reste de ce
/// fichier : une seule source de vérité pour ces quatre coefficients,
/// dans le fichier qui détient déjà `_kRatioLatFondMur`/
/// `_kRatioLatFondHoriz` dont ils dérivent (`0.080/0.055` = 0.080/0.055,
/// `0.200/0.140` = 0.200/0.140 — les deux ratios sont exactement ceux
/// appliqués ci-dessous). `StripThickness.corniceDefault` délègue à cette
/// fonction plutôt que de porter les coefficients en dur ; le peintre
/// IMPORTE cette valeur, il ne la définit plus.
///
/// Ne concerne QUE la corniche — `StripThickness.plintheDefault` reste en
/// dur dans le peintre, hors périmètre de ce déplacement (aucun profil de
/// plinthe n'existe à ce jour dans `assets/profiles/`, voir docstring de
/// `stripPxFromDims`).
StripPxResult corniceDefaultPx(double pH) {
  const faceMurFond = 0.055;
  const faceHorizFond = 0.140;
  final faceMurFondPx = pH * faceMurFond;
  final faceHorizFondPx = pH * faceHorizFond;
  return (
    faceMurFondPx: faceMurFondPx,
    faceHorizFondPx: faceHorizFondPx,
    faceMurLatPx: pH * (faceMurFond * _kRatioLatFondMur),
    faceHorizLatPx: pH * (faceHorizFond * _kRatioLatFondHoriz),
  );
}

/// Calcule les épaisseurs en pixels des quatre faces d'un segment
/// (fond + latéral), à partir des dimensions réelles (mm) d'un profil et
/// du facteur d'échelle courant de la scène (`pH`, `metresHauteur`).
///
/// Renvoie `null` — SANS AUCUN REPLI — si :
/// - `metresHauteur` n'est pas strictement positif (évite toute division
///   par zéro ou facteur négatif) ;
/// - `retombeeMm` OU `projectionMm` est absent (`null` — cas normal pour
///   275 des 283 références du catalogue, qui n'ont pas de profil JSON
///   associé, voir `ProfileDims`). Les deux dimensions viennent du même
///   `ProfileDims` : on ne mélange jamais une dimension réelle avec un
///   repli pour l'autre ;
/// - `retombeeMm` OU `projectionMm` n'est pas un nombre strictement
///   positif ET fini — c'est-à-dire s'il est nul, négatif, `NaN` ou
///   infini.
///   ⚠️ Garde ajouté délibérément à l'entrée de cette fonction, PLUTÔT que
///   de compter sur le fait que la chaîne amont (`loadProfileDims`) rejette
///   déjà ce cas : les 4 refs `ERREUR_SELECTION` du catalogue DXF ont
///   `bbox_mm = {w:0, h:0}` et `loadProfileDims` en renvoie bien `null`
///   aujourd'hui (testé dans `profile_dims_test.dart`), donc aucun chemin
///   connu actuel n'amène un `ProfileDims` invalide jusqu'ici. Mais SANS ce
///   garde, si une telle valeur arrivait un jour malgré tout (bug amont,
///   nouvelle source de données), cette fonction produirait silencieusement
///   une bande invisible — épaisseur nulle pour `0`/négatif, `NaN` pour une
///   coordonnée `NaN` (`Canvas.drawRect` avec `NaN` ne lève pas, elle ne
///   dessine simplement rien), pixels infinis pour `double.infinity`. Ce
///   garde local rend l'invariant vrai indépendamment de la chaîne amont,
///   à coût nul, ici même où il compte le plus : au dernier point avant la
///   conversion en pixels.
///
///   Forme du garde délibérément écrite comme la NÉGATION d'un prédicat
///   positif (`!(x > 0)`) plutôt que comme une liste de cas négatifs
///   (`x <= 0`) : `NaN <= 0` vaut `false` en IEEE 754 (comme toute
///   comparaison impliquant `NaN`), donc une forme `<= 0` laisserait
///   passer `NaN` sans le rejeter — un bug réellement rencontré lors de
///   l'écriture de ce garde, corrigé avant tout usage en production.
///   `!(x > 0)` capture zéro, négatif ET `NaN` d'un seul coup, par
///   construction. `double.infinity` est positif et non couvert par
///   `!(x > 0)` seul ; `isFinite` complète le garde pour ce cas.
///
/// L'appelant DOIT gérer le cas `null` en retombant sur
/// `StripThickness.corniceDefault(pH)` (ou `.plintheDefault(pH)` selon le
/// produit) — c'est ce report qui remplace l'ancien repli en dur
/// dupliqué.
///
/// Plinthe : cette fonction ne distingue pas famille corniche/plinthe et
/// applique le ratio corniche dans tous les cas où elle produit un
/// résultat non-null. Sans conséquence pratique aujourd'hui : aucun des
/// 8 profils JSON du dépôt (`assets/profiles/`) n'est une plinthe — D705,
/// D718, D720 sont des corniches ; 0900 et 1000 des pilastres cannelés ;
/// 1005 un socle de pilastre ; 1145c une cimaise ; 20-54 une demi-colonne
/// (vérifié via `tools/dxf_pipeline/catalogue.csv` et
/// `tools/dxf_pipeline/recoupement_catalogue_vs_profil.csv`). Le jour où
/// un profil de plinthe existera, cette fonction devra être revue pour
/// choisir le ratio propre à cette famille (1.4615/1.4348 plutôt que
/// 1.4545/1.4286) — non traité ici, faute de donnée à convertir.
StripPxResult? stripPxFromDims({
  required double pH,
  required double metresHauteur,
  required double? retombeeMm,
  required double? projectionMm,
}) {
  final factor = pxParMm(pH: pH, metresHauteur: metresHauteur);
  if (factor == null || retombeeMm == null || projectionMm == null) {
    return null;
  }
  if (!(retombeeMm > 0) ||
      !(projectionMm > 0) ||
      !retombeeMm.isFinite ||
      !projectionMm.isFinite) {
    return null;
  }

  final faceMurFondPx = retombeeMm * factor;
  final faceHorizFondPx = projectionMm * factor;

  return (
    faceMurFondPx: faceMurFondPx,
    faceHorizFondPx: faceHorizFondPx,
    faceMurLatPx: faceMurFondPx * _kRatioLatFondMur,
    faceHorizLatPx: faceHorizFondPx * _kRatioLatFondHoriz,
  );
}
