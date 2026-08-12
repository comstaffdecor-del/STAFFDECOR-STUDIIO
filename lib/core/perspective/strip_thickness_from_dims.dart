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

/// Épaisseurs en pixels canvas pour les deux faces du segment du fond
/// (`faceMurFond`, `faceHorizFond` de `StripThickness`), résultat du
/// calcul mm→px ou du repli sur les coefficients actuels.
typedef StripPxResult = ({double faceMurFondPx, double faceHorizFondPx});

/// Épaisseurs par défaut actuelles pour une CORNICHE (repli), port exact
/// des coefficients de `StripThickness.corniceDefault`
/// (`cornice_plinth_painter.dart`, lignes 81-86) — dupliqués ici en
/// constantes plutôt qu'importés, pour ne créer aucune dépendance de ce
/// fichier vers le peintre.
const double _kFallbackFaceMurFondCoef = 0.055;
const double _kFallbackFaceHorizFondCoef = 0.140;

/// Calcule les épaisseurs en pixels des faces du segment du fond, à
/// partir des dimensions réelles (mm) d'un profil et du facteur d'échelle
/// courant de la scène (`pH`, `metresHauteur`).
///
/// Repli sur les coefficients actuels (`0.055 * pH`, `0.140 * pH`) si :
/// - `metresHauteur` n'est pas strictement positif (évite toute division
///   par zéro ou facteur négatif) ;
/// - `retombeeMm`/`projectionMm` sont absentes (`null` — cas normal pour
///   275/283 références sans profil JSON, voir `ProfileDims`).
StripPxResult strippxFromDims({
  required double pH,
  required double metresHauteur,
  required double? retombeeMm,
  required double? projectionMm,
}) {
  final factor = pxParMm(pH: pH, metresHauteur: metresHauteur);

  if (factor == null || retombeeMm == null || projectionMm == null) {
    return (
      faceMurFondPx: _kFallbackFaceMurFondCoef * pH,
      faceHorizFondPx: _kFallbackFaceHorizFondCoef * pH,
    );
  }

  return (
    faceMurFondPx: retombeeMm * factor,
    faceHorizFondPx: projectionMm * factor,
  );
}
