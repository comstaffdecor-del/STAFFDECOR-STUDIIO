/// Chargement des dimensions métriques réelles d'un profil produit, depuis
/// `assets/profiles/<ref>.json` (pipeline `tools/dxf_pipeline/`, voir
/// `docs/ETAT_MOTEUR_RENDU.md` section 5 pour la traçabilité complète des
/// sources et de l'unité).
///
/// ⚠️ Ce fichier n'importe rien de `lib/core/geometry/` (lignée 3D
/// jamais branchée) et n'est importé par aucun painter à ce stade — c'est
/// un loader isolé, testé seul. Le branchement de `cornice_plinth_painter.dart`
/// et la conversion mm→px sont des étapes ultérieures distinctes.
///
/// ## Définition de `retombeeMm` et `projectionMm`
///
/// Volontairement définies comme des **distances** aux plans de pose
/// (`face_pose_plafond`/`face_pose_mur`, indices explicites du JSON), et
/// non comme des coordonnées signées :
/// - `retombeeMm` = écart max entre les points du contour et le plan
///   plafond (= `max(|y - y_plafond|)` sur tout `profil_mm`).
/// - `projectionMm` = écart max entre les points du contour et le plan
///   mur (= `max(|x - x_mur|)` sur tout `profil_mm`).
///
/// Cette formulation est **insensible au signe de l'axe** : `D705` a son
/// contour en `y >= 0` alors que `D718`/`D720` l'ont en `y <= 0`
/// (`CONVENTIONS.md` §2), et les trois donnent pourtant la bonne valeur
/// sans aucune étape de normalisation ni aucun test de signe — voir la
/// session de lecture ayant établi ce fait (comparaison `profil_mm` vs
/// `bbox_mm` sur les 3 profils STEP pilotes). La question de l'orientation
/// du contour (miroir potentiel sur `D705`) reste entière et devra être
/// tranchée le jour où `sweep.dart` consommera ces fichiers — hors
/// périmètre de ce loader, qui ne s'intéresse qu'à l'étendue, pas à
/// l'orientation.
///
/// ## Pourquoi pas `bbox_mm` directement
///
/// `bbox_mm` est un champ dérivé (min/max arrondi à 3 décimales, résidus
/// observés de 0.0000 à 0.0005 mm sur les 3 pilotes) — recalculer
/// l'étendue depuis `profil_mm` évite de dépendre d'un champ qui
/// pourrait désynchroniser un jour. `bbox_mm` sert ici uniquement de
/// **contrôle de cohérence en assertion debug** (pas de rejet) : si
/// l'écart dépasse 0.001 mm, c'est qu'un profil déborde derrière le plan
/// mur ou au-dessus du plan plafond — cas qui ne s'est pas présenté sur
/// les 3 pilotes.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;

/// Dimensions métriques réelles (mm) d'un profil produit, dérivées de
/// `assets/profiles/<ref>.json`. Valeur immuable.
class ProfileDims {
  final String ref;

  /// Retombée réelle (mm) — écart max des points du contour au plan
  /// plafond (`face_pose_plafond`), c'est la hauteur totale de la bande
  /// visible sur le mur, PAS `hauteur_mur_mm` (qui décrit la face de
  /// collage, une sous-étendue distincte — voir `ETAT_MOTEUR_RENDU.md`).
  final double retombeeMm;

  /// Projection réelle (mm) — écart max des points du contour au plan
  /// mur (`face_pose_mur`), c'est la profondeur totale de la face
  /// visible au plafond, PAS `projection_plafond_mm` (idem, sous-étendue
  /// de collage).
  final double projectionMm;

  const ProfileDims({
    required this.ref,
    required this.retombeeMm,
    required this.projectionMm,
  });

  @override
  String toString() =>
      'ProfileDims(ref: $ref, retombeeMm: $retombeeMm, projectionMm: $projectionMm)';
}

/// Charge les dimensions réelles du profil [ref] depuis
/// `assets/profiles/<ref>.json`, ou renvoie `null` — jamais d'exception —
/// si le fichier n'existe pas (275 références sur 283 n'en ont pas, ce
/// n'est jamais une erreur applicative), si le JSON est malformé, ou si
/// `statut` n'est pas `"OK"` (voie DXF en `ERREUR_SELECTION`, `profil_mm`
/// vide).
Future<ProfileDims?> loadProfileDims(String ref) async {
  String raw;
  try {
    raw = await rootBundle.loadString('assets/profiles/$ref.json');
  } catch (_) {
    // Asset absent (cas normal pour 275/283 références) ou toute autre
    // erreur de chargement — jamais remonté à l'appelant.
    return null;
  }

  Map<String, dynamic> data;
  try {
    data = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }

  if (data['statut'] != 'OK') {
    return null;
  }

  final profilMm = data['profil_mm'];
  if (profilMm is! List || profilMm.isEmpty) {
    return null;
  }

  final facePoseMur = data['face_pose_mur'];
  final facePosePlafond = data['face_pose_plafond'];
  if (facePoseMur is! Map || facePosePlafond is! Map) {
    return null;
  }
  final wallIdx = facePoseMur['indices'];
  final ceilIdx = facePosePlafond['indices'];
  if (wallIdx is! List || wallIdx.isEmpty || ceilIdx is! List || ceilIdx.isEmpty) {
    return null;
  }

  final points = <List<double>>[];
  for (final p in profilMm) {
    if (p is! List || p.length < 2) return null;
    points.add([(p[0] as num).toDouble(), (p[1] as num).toDouble()]);
  }

  // Plan mur : x du premier indice de face_pose_mur (les deux sommets de
  // cette face partagent le même x, garanti par la contrainte de pose du
  // pipeline d'extraction — pas revérifié ici, cohérent avec le rôle de
  // ce champ dans step2profile.py/dxf2profile.py).
  final wallX = points[(wallIdx.first as num).toInt()][0];
  final ceilY = points[(ceilIdx.first as num).toInt()][1];

  double maxAbsDx = 0.0;
  double maxAbsDy = 0.0;
  for (final p in points) {
    final dx = (p[0] - wallX).abs();
    final dy = (p[1] - ceilY).abs();
    if (dx > maxAbsDx) maxAbsDx = dx;
    if (dy > maxAbsDy) maxAbsDy = dy;
  }

  final retombeeMm = maxAbsDy;
  final projectionMm = maxAbsDx;

  // Contrôle de cohérence contre bbox_mm : assertion en debug uniquement,
  // jamais de rejet — un écart > 0.001 mm signalerait un profil qui
  // déborde derrière le plan mur ou au-dessus du plan plafond (non
  // observé sur les 3 pilotes STEP à la rédaction de ce loader).
  if (kDebugMode) {
    final bbox = data['bbox_mm'];
    if (bbox is Map) {
      final bboxW = (bbox['w'] as num?)?.toDouble();
      final bboxH = (bbox['h'] as num?)?.toDouble();
      if (bboxW != null) {
        assert(
          (bboxW - projectionMm).abs() < 0.001,
          'ProfileDims[$ref]: bbox_mm.w ($bboxW) diverge de projectionMm '
          '($projectionMm) au-delà de 0.001mm — profil potentiellement '
          'débordant du plan mur.',
        );
      }
      if (bboxH != null) {
        assert(
          (bboxH - retombeeMm).abs() < 0.001,
          'ProfileDims[$ref]: bbox_mm.h ($bboxH) diverge de retombeeMm '
          '($retombeeMm) au-delà de 0.001mm — profil potentiellement '
          'débordant du plan plafond.',
        );
      }
    }
  }

  return ProfileDims(
    ref: ref,
    retombeeMm: retombeeMm,
    projectionMm: projectionMm,
  );
}
