/// Extrusion (balayage) d'un profil de moulure 2D le long d'un trajet 3D —
/// production du maillage final affiché à l'écran.
///
/// ⚠️ Ce fichier est **Dart pur** : aucune dépendance UI (`dart:ui`,
/// `package:flutter/...`). Testable en isolation, sans widget. Rien dans
/// `rendering/` ni dans les painters ne doit dépendre de ce fichier tant que
/// les 6 tests dédiés (`sweep_test.dart`) ne passent pas.
///
/// ⚠️ **Source unique de vérité : `geometry/CONVENTIONS.md`.** Ce fichier
/// implémente [profileToWorld] tel que son contrat est fixé par
/// `CONVENTIONS.md` §3 — **aucune base locale (u, v) n'est reconstruite par
/// un autre moyen** ailleurs dans ce fichier.
///
/// ## Contrat (imposé par l'utilisateur)
///
/// - **Entrée** : le JSON de profil (`profil_mm`, faces de pose), une
///   polyline 3D de trajet (mètres), les plans mur/plafond
///   (`geometry/planes.dart`).
/// - **Sortie** : [Mesh] (positions/indices/normales/UV en `Float32List`/
///   `Uint16List`, format prêt pour `drawVertices`/Skia).
///
/// ## Règles dures
///
/// 1. [profileToWorld] est **unique**, celle définie ici conformément à
///    `CONVENTIONS.md` — jamais recalculée par un produit vectoriel
///    ponctuel ailleurs dans ce fichier.
/// 2. **Contrainte de pose** : les sommets `face_pose_mur` du profil
///    d'entrée sont replacés exactement sur le plan mur, ceux de
///    `face_pose_plafond` exactement sur le plan plafond — tolérance
///    0.1mm. C'est la garantie du "s'adapte parfaitement" au gros-œuvre
///    réel (mur/plafond peuvent être légèrement obliques par rapport à la
///    verticale/horizontale idéale du profil source).
/// 3. **Jamais de reconvexification du profil** (règle SPEC.md/
///    CONVENTIONS.md §2.1bis) : le contour `profil_mm` est extrudé
///    exactement tel quel, sommet par sommet, dans l'ordre fourni.
/// 4. **Onglet (jonction d'angle)** : coupe sur le plan bissecteur des deux
///    segments adjacents. Le profil de chaque segment est **projeté** sur
///    ce plan bissecteur le long de la direction du trajet (pas simplement
///    tourné/roté) — valable pour un angle rentrant comme sortant.
/// 5. **UV** : `u` = abscisse curviligne le long du trajet, en
///    **millimètres réels** (pas normalisée 0..1) ; `v` = abscisse le long
///    du contour du profil, en mm. Nécessaire pour que le motif ornemental
///    (period_mm, ex. 42mm) se répète au bon pas physique dans un shader/
///    une texture tuilée.
/// 6. **Normales par facette** (flat shading), jamais lissées entre
///    facettes adjacentes — une moulure a des arêtes vives (les lisser
///    donnerait un aspect "boudin" incorrect).
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart';

import 'planes.dart';

// ---------------------------------------------------------------------------
// Types d'entrée : profil de moulure (miroir Dart du JSON produit par
// dxf2profile.py / solid2profile.py — voir SPEC.md pour le schéma complet).
// ---------------------------------------------------------------------------

/// Profil 2D d'une moulure, tel que décodé depuis le JSON `profil_mm` +
/// `face_pose_mur`/`face_pose_plafond` du pipeline Python (voir `SPEC.md`).
///
/// Convention des coordonnées (voir `CONVENTIONS.md` §2, **non renégociable
/// ici** — ce type ne fait que porter la donnée, il ne la réinterprète pas) :
/// - `points[i].x` = profondeur depuis le mur en mm (0 au mur, croissant).
/// - `points[i].y` = hauteur depuis le plafond en mm (0 au plafond,
///   `y <= 0` en descendant).
/// - Sens horaire (aire signée négative, repère math y-up).
class MoulureProfile {
  /// Sommets du contour fermé, en mm, dans l'ordre fourni par le JSON —
  /// **jamais réordonnés, simplifiés, ni reconvexifiés** (règle dure #3).
  final List<Vector2> pointsMm;

  /// Indices (dans [pointsMm]) des sommets appartenant à la face d'appui
  /// mur. Vide si non détecté automatiquement côté Python.
  final List<int> wallIndices;

  /// Indices (dans [pointsMm]) des sommets appartenant à la face d'appui
  /// plafond. Vide si non détecté automatiquement côté Python.
  final List<int> ceilingIndices;

  const MoulureProfile({
    required this.pointsMm,
    required this.wallIndices,
    required this.ceilingIndices,
  });

  /// Longueur totale du contour (mm), somme des distances entre sommets
  /// consécutifs, **contour fermé** (le dernier segment referme sur le
  /// premier sommet). Utilisée pour la coordonnée `v` des UV (règle #5).
  double get perimeterMm {
    var total = 0.0;
    final n = pointsMm.length;
    for (var i = 0; i < n; i++) {
      total += pointsMm[i].distanceTo(pointsMm[(i + 1) % n]);
    }
    return total;
  }

  /// Abscisse curviligne (mm) du sommet d'indice [i] le long du contour,
  /// mesurée depuis le sommet 0 (premier sommet de [pointsMm]), dans le
  /// sens de parcours du contour tel que fourni (pas de réordonnancement).
  List<double> get cumulativeArcLengthMm {
    final n = pointsMm.length;
    final out = List<double>.filled(n, 0.0);
    for (var i = 1; i < n; i++) {
      out[i] = out[i - 1] + pointsMm[i - 1].distanceTo(pointsMm[i]);
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Type de sortie : maillage plat, prêt pour drawVertices/Skia.
// ---------------------------------------------------------------------------

/// Maillage triangulé résultat de [sweepMoulure], au format attendu par le
/// pipeline de rendu "Option A bis" (`CustomPainter` + `drawVertices`,
/// Skia) — jamais construit ailleurs que par [sweepMoulure].
class Mesh {
  /// Positions des sommets, triplets (x, y, z) consécutifs en **mètres**
  /// (repère monde, voir `CONVENTIONS.md` §1).
  final Float32List positions;

  /// Indices de triangles, triplets consécutifs référençant [positions]
  /// (`positions[indices[3k]*3 .. +3]` = sommet A du triangle k, etc.).
  final Uint16List indices;

  /// Normales par sommet, triplets (x, y, z) consécutifs, **unitaires**,
  /// alignées avec [positions] (même longueur/3). Une normale par
  /// sommet-de-facette (flat shading, règle dure #6) : un même point 3D
  /// physique partagé par deux facettes non coplanaires est dupliqué dans
  /// [positions] avec une normale différente par occurrence — jamais
  /// mutualisé/lissé.
  final Float32List normals;

  /// Coordonnées UV par sommet, paires (u, v) consécutives, alignées avec
  /// [positions]. `u` = abscisse curviligne le long du trajet en mm réels,
  /// `v` = abscisse le long du profil en mm réels (règle dure #5).
  final Float32List uvs;

  const Mesh({
    required this.positions,
    required this.indices,
    required this.normals,
    required this.uvs,
  });

  /// Nombre de sommets (déduit de [positions]).
  int get vertexCount => positions.length ~/ 3;

  /// Nombre de triangles (déduit de [indices]).
  int get triangleCount => indices.length ~/ 3;

  Vector3 positionAt(int vertexIndex) => Vector3(
    positions[vertexIndex * 3],
    positions[vertexIndex * 3 + 1],
    positions[vertexIndex * 3 + 2],
  );

  Vector3 normalAt(int vertexIndex) => Vector3(
    normals[vertexIndex * 3],
    normals[vertexIndex * 3 + 1],
    normals[vertexIndex * 3 + 2],
  );

  Vector2 uvAt(int vertexIndex) =>
      Vector2(uvs[vertexIndex * 2], uvs[vertexIndex * 2 + 1]);
}

// ---------------------------------------------------------------------------
// profileToWorld — UNIQUE fonction de passage profil 2D -> monde 3D.
// Contrat fixé par CONVENTIONS.md §3 : reproduit ICI À L'IDENTIQUE, jamais
// une variante "optimisée" ou recalculée localement.
// ---------------------------------------------------------------------------

/// Convertit un point du profil 2D (`xProfilMm` = profondeur mur en mm,
/// `yProfilMm` = hauteur plafond en mm, voir `CONVENTIONS.md` §2) en un
/// point du repère monde (mètres, voir `CONVENTIONS.md` §1).
///
/// Contrat **fixé par `CONVENTIONS.md` §3** — signature et formule
/// reproduites ici à l'identique, seule implémentation autorisée :
/// - [wallOrigin] : point 3D monde où `xProfil=0` ET `yProfil=0`
///   coïncident avec le mur/plafond réels.
/// - [depthAxis] : direction monde **unitaire** dans laquelle `xProfil`
///   croissant s'éloigne du mur.
/// - [heightAxis] : direction monde **unitaire** dans laquelle `yProfil`
///   décroissant (donc plus négatif) descend depuis le plafond.
/// - [alongAxis] : direction monde **unitaire** de l'axe long du trajet.
/// - [alongOffsetM] : position le long de [alongAxis] (mètres).
///
/// [depthAxis], [heightAxis], [alongAxis] doivent former une base
/// orthonormée directe (main droite) — **non revérifié ici**, à la charge
/// de l'appelant (voir [_frameForSegment] pour la construction utilisée par
/// [sweepMoulure]).
Vector3 profileToWorld({
  required Vector3 wallOrigin,
  required Vector3 depthAxis,
  required Vector3 heightAxis,
  required Vector3 alongAxis,
  required double xProfilMm,
  required double yProfilMm,
  required double alongOffsetM,
}) {
  return wallOrigin +
      depthAxis * (xProfilMm / 1000.0) +
      heightAxis * (yProfilMm / 1000.0) +
      alongAxis * alongOffsetM;
}

// ---------------------------------------------------------------------------
// Construction du repère (depth, height, along, wallOrigin) par segment de
// trajet — PAR ORTHOGONALISATION (Gram-Schmidt) à partir des axes physiques
// réels (normale du mur, normale du plafond, direction du trajet), JAMAIS
// par un produit vectoriel arbitraire reconstruit localement (piège #3 de
// `CONVENTIONS.md` §4 : la base doit toujours dériver d'une SEULE source de
// vérité géométrique — ici, les plans mur/plafond fournis par l'appelant —
// jamais d'une hypothèse indépendante recalculée ailleurs).
// ---------------------------------------------------------------------------

/// Repère 3D complet d'un segment de trajet : les trois axes unitaires
/// nécessaires à [profileToWorld], plus le point d'ancrage [wallOrigin] et
/// la longueur du segment en mètres.
class _SegmentFrame {
  final Vector3 depthAxis;
  final Vector3 heightAxis;
  final Vector3 alongAxis;
  final Vector3 wallOrigin;
  final double lengthM;

  const _SegmentFrame({
    required this.depthAxis,
    required this.heightAxis,
    required this.alongAxis,
    required this.wallOrigin,
    required this.lengthM,
  });
}

/// Orthogonalise [vRaw] par rapport à [others] (Gram-Schmidt successif),
/// puis normalise. Lance [ArgumentError] si le résultat est (quasi) nul
/// (vRaw était colinéaire à l'espace engendré par [others] — configuration
/// géométrique dégénérée, jamais masquée par une valeur NaN).
Vector3 _orthonormalizeAgainst(
  Vector3 vRaw,
  List<Vector3> others,
  String debugLabel,
) {
  var v = vRaw.clone();
  for (final o in others) {
    v = v - o * v.dot(o);
  }
  if (v.length2 < 1e-18) {
    throw ArgumentError(
      '_orthonormalizeAgainst($debugLabel): résultat (quasi) nul après '
      'orthogonalisation — configuration géométrique dégénérée (axe '
      'colinéaire aux autres axes de la base).',
    );
  }
  return v.normalized();
}

/// Direction "vers le bas depuis le plafond" (règle dure : `y` du profil
/// décroît en descendant, voir `CONVENTIONS.md` §2), dérivée de la normale
/// du plan plafond — avec le signe déterminé sans ambiguïté (peu importe le
/// sens dans lequel l'appelant a construit [ceilingPlane], on choisit
/// toujours le sens qui pointe vers le bas du monde, Y monde décroissant).
Vector3 _downFromCeiling(Plane3 ceilingPlane) {
  final n = ceilingPlane.normal;
  return n.y > 0 ? -n : n.clone();
}

/// Construit le repère complet d'un segment de trajet (de [start] à [end]),
/// pour le mur [wallPlane] et le plafond global [ceilingPlane] (fixe pour
/// toute la pièce — un seul plafond, mais potentiellement plusieurs murs,
/// un par segment, voir [sweepMoulure]).
///
/// Étapes (toutes dérivées des plans/direction RÉELS, jamais d'un produit
/// vectoriel arbitraire — voir avertissement en tête de section) :
/// 1. [alongAxis] = direction unitaire de [start] vers [end].
/// 2. [heightAxis] = direction "vers le bas" du plafond ([_downFromCeiling]),
///    orthogonalisée par rapport à [alongAxis] (Gram-Schmidt) — un no-op
///    numérique si le trajet est effectivement horizontal (cas physique
///    normal), mais robuste si de petites erreurs d'entrée existent.
/// 3. [depthAxis] = normale du mur ([wallPlane.normal], en supposant qu'elle
///    pointe vers l'intérieur de la pièce — s'éloigne du mur), orthogonalisée
///    par rapport à [alongAxis] ET [heightAxis].
/// 4. [wallOrigin] = point sur l'arête théorique mur∩plafond
///    ([intersectPlanes]) qui partage la même coordonnée "along" que
///    [start] (projection le long de [alongAxis], PAS une projection
///    orthogonale générique) — garantit que `x=0,y=0` du profil coïncide
///    EXACTEMENT (précision flottante, largement sous la tolérance
///    0.1mm exigée) avec le mur ET le plafond réels à la position de départ
///    du segment, indépendamment d'une éventuelle imprécision de [start]
///    lui-même.
///
/// Lance [ArgumentError] si le mur et le plafond sont (quasi) parallèles
/// (aucune arête d'intersection définie — configuration physiquement
/// impossible pour une pièce réelle, mais on ne masque jamais ce cas par un
/// NaN) ou si [start]==[end] (segment de longueur nulle).
_SegmentFrame _buildSegmentFrame({
  required Vector3 start,
  required Vector3 end,
  required Plane3 wallPlane,
  required Plane3 ceilingPlane,
}) {
  final alongRaw = end - start;
  final lengthM = alongRaw.length;
  if (lengthM < 1e-9) {
    throw ArgumentError(
      '_buildSegmentFrame: start==end, segment de longueur nulle.',
    );
  }
  final alongAxis = alongRaw / lengthM;

  final heightAxis = _orthonormalizeAgainst(
    _downFromCeiling(ceilingPlane),
    [alongAxis],
    'heightAxis',
  );

  final depthAxis = _orthonormalizeAgainst(
    wallPlane.normal,
    [alongAxis, heightAxis],
    'depthAxis',
  );

  final edge = intersectPlanes(wallPlane, ceilingPlane);
  if (edge.isDegenerate) {
    throw ArgumentError(
      '_buildSegmentFrame: mur et plafond (quasi) parallèles, aucune '
      'arête mur∩plafond définie — ${edge.message}',
    );
  }
  final line = edge.line!;
  final denom = line.direction.dot(alongAxis);
  if (denom.abs() < 1e-9) {
    throw ArgumentError(
      '_buildSegmentFrame: l\'arête mur∩plafond est (quasi) '
      'perpendiculaire à la direction du trajet — le trajet ne peut pas '
      'suivre ce mur (configuration géométrique incohérente).',
    );
  }
  final t = (start - line.point).dot(alongAxis) / denom;
  final wallOrigin = line.point + line.direction * t;

  return _SegmentFrame(
    depthAxis: depthAxis,
    heightAxis: heightAxis,
    alongAxis: alongAxis,
    wallOrigin: wallOrigin,
    lengthM: lengthM,
  );
}

// ---------------------------------------------------------------------------
// Anneaux de section (profil -> monde), coupe droite ET coupe d'onglet.
// ---------------------------------------------------------------------------

/// Projette [p] orthogonalement sur [plane] (déplacement le long de
/// `plane.normal` uniquement). Utilisé pour la **contrainte de pose**
/// (règle dure #2) : re-caler explicitement les sommets `face_pose_mur`/
/// `face_pose_plafond` exactement sur le plan réel, sans dépendre
/// implicitement de la précision numérique de [_buildSegmentFrame] (qui,
/// certes, garantit déjà cette propriété pour une entrée idéale — murs
/// verticaux, plafond horizontal, trajet horizontal — mais la garantie
/// dure explicitement demandée par le contrat doit être un re-calage actif,
/// pas seulement une propriété émergente de la construction).
Vector3 _projectOntoPlane(Vector3 p, Plane3 plane) =>
    p - plane.normal * plane.signedDistanceTo(p);

/// Calcule l'anneau de section (un point monde par sommet de [profile])
/// pour une coupe **droite** (perpendiculaire au trajet, pas d'onglet) au
/// décalage [alongOffsetM] le long de [frame].
List<Vector3> _computeStraightRing({
  required MoulureProfile profile,
  required _SegmentFrame frame,
  required double alongOffsetM,
}) {
  return [
    for (final pt in profile.pointsMm)
      profileToWorld(
        wallOrigin: frame.wallOrigin,
        depthAxis: frame.depthAxis,
        heightAxis: frame.heightAxis,
        alongAxis: frame.alongAxis,
        xProfilMm: pt.x,
        yProfilMm: pt.y,
        alongOffsetM: alongOffsetM,
      ),
  ];
}

/// Calcule l'anneau de section **mitré** (jonction d'angle, règle dure #4)
/// au sommet de trajet [corner], entre le segment entrant (dont le repère
/// est [framePrev]) et le segment sortant (dont la direction est
/// [nextAlongAxis]).
///
/// Méthode (voir docstring de tête de fichier, règle #4) :
/// 1. Plan bissecteur = plan passant par [corner], de normale
///    `normalize(framePrev.alongAxis + nextAlongAxis)` — bissectrice des
///    deux directions de trajet adjacentes (construction standard des
///    jonctions d'onglet, valable pour un angle rentrant comme sortant :
///    pour un trajet droit, `alongAxis_prev == nextAlongAxis`, la normale
///    obtenue est simplement `alongAxis_prev` -> coupe perpendiculaire
///    normale, cohérent avec l'absence d'angle).
/// 2. Anneau "plat" non mitré du segment entrant, à la fin de ce segment
///    (`alongOffsetM = framePrev.lengthM`).
/// 3. Chaque sommet de cet anneau plat est **projeté** sur le plan
///    bissecteur le long de `framePrev.alongAxis` (intersection
///    rayon/plan) — PAS tourné, conformément à la règle dure #4.
///
/// Preuve de cohérence (voir notes de session) : pour un trajet dont les
/// virages restent dans le plan horizontal (murs verticaux, plafond
/// horizontal — cas de tous les tests du contrat), la réflexion par
/// rapport au plan bissecteur échange exactement le repère du segment
/// entrant et celui du segment sortant ; projeter depuis le côté "entrant"
/// (fait ici) ou depuis le côté "sortant" donne donc EXACTEMENT le même
/// point — la jonction est automatiquement continue sans qu'il soit
/// nécessaire de calculer deux fois le même anneau.
///
/// Lance [ArgumentError] si le trajet fait un demi-tour quasi complet
/// (180°, plan bissecteur indéfini) ou si la direction de projection est
/// quasi parallèle au plan bissecteur (dénominateur quasi nul).
List<Vector3> _computeMiteredRing({
  required MoulureProfile profile,
  required _SegmentFrame framePrev,
  required Vector3 corner,
  required Vector3 nextAlongAxis,
}) {
  final bisectorRaw = framePrev.alongAxis + nextAlongAxis;
  if (bisectorRaw.length2 < 1e-18) {
    throw ArgumentError(
      '_computeMiteredRing: la trajectoire fait un demi-tour (~180°) au '
      'sommet $corner — plan bissecteur indéfini.',
    );
  }
  final bisectorNormal = bisectorRaw.normalized();
  final bisectorPlane = Plane3.fromPointAndNormal(corner, bisectorNormal);

  final denom = bisectorPlane.normal.dot(framePrev.alongAxis);
  if (denom.abs() < 1e-9) {
    throw ArgumentError(
      '_computeMiteredRing: direction de projection quasi parallèle au '
      'plan bissecteur au sommet $corner — configuration dégénérée.',
    );
  }

  final flatRing = _computeStraightRing(
    profile: profile,
    frame: framePrev,
    alongOffsetM: framePrev.lengthM,
  );

  return [
    for (final p0 in flatRing)
      p0 +
          framePrev.alongAxis *
              (-bisectorPlane.signedDistanceTo(p0) / denom),
  ];
}

/// Applique la **contrainte de pose** (règle dure #2) à un anneau déjà
/// calculé : re-cale explicitement les sommets d'indices
/// `profile.wallIndices` exactement sur [wallPlane], et ceux
/// d'indices `profile.ceilingIndices` exactement sur `ceilingPlane`.
/// Retourne une nouvelle liste (l'anneau d'entrée n'est pas modifié en
/// place).
List<Vector3> _snapPoseVertices({
  required MoulureProfile profile,
  required List<Vector3> ring,
  required Plane3 wallPlane,
  required Plane3 ceilingPlane,
}) {
  final out = List<Vector3>.of(ring, growable: false);
  for (final i in profile.wallIndices) {
    out[i] = _projectOntoPlane(out[i], wallPlane);
  }
  for (final i in profile.ceilingIndices) {
    out[i] = _projectOntoPlane(out[i], ceilingPlane);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Triangulation + normales par facette + UV — assemblage du Mesh final.
// ---------------------------------------------------------------------------

/// Une facette triangulaire "brute" (avant décision d'orientation), portant
/// ses 3 sommets monde, ses 3 UV et l'indice associé (pour retrouver le
/// centroïde après coup). Type interne, jamais exposé.
class _RawTriangle {
  final Vector3 p0;
  final Vector3 p1;
  final Vector3 p2;
  final Vector2 uv0;
  final Vector2 uv1;
  final Vector2 uv2;

  const _RawTriangle({
    required this.p0,
    required this.p1,
    required this.p2,
    required this.uv0,
    required this.uv1,
    required this.uv2,
  });

  Vector3 get centroid => (p0 + p1 + p2) / 3.0;
}

/// Construit les deux triangles du "quad" reliant l'arête de profil `j ->
/// j+1` entre l'anneau `a` (offset curviligne [uA] mm) et l'anneau `b`
/// (offset curviligne [uB] mm). [vJ]/[vNext] = abscisses mm le long du
/// profil aux sommets `j`/`j+1` (avec le raccord de bouclage déjà résolu par
/// l'appelant, voir [sweepMoulure]).
///
/// Découpage `(a0,a1,b1)` + `(a0,b1,b0)` — paramétrisation `(s,t)` standard
/// d'une grille anneau×anneau en triangles ; l'orientation (sens des
/// sommets) n'a **aucune importance à ce stade** : elle est décidée a
/// posteriori dans [sweepMoulure] (règle dure #6 — normale par facette
/// forcée "vers l'extérieur", jamais supposée correcte par construction du
/// winding, pour rester robuste à une éventuelle torsion locale d'un anneau
/// mitré à forte pente).
List<_RawTriangle> _buildQuadTriangles({
  required Vector3 a0,
  required Vector3 a1,
  required Vector3 b0,
  required Vector3 b1,
  required double uA,
  required double uB,
  required double vJ,
  required double vNext,
}) {
  final uvA0 = Vector2(uA, vJ);
  final uvA1 = Vector2(uA, vNext);
  final uvB0 = Vector2(uB, vJ);
  final uvB1 = Vector2(uB, vNext);
  return [
    _RawTriangle(p0: a0, p1: a1, p2: b1, uv0: uvA0, uv1: uvA1, uv2: uvB1),
    _RawTriangle(p0: a0, p1: b1, p2: b0, uv0: uvA0, uv1: uvB1, uv2: uvB0),
  ];
}

/// Résultat intermédiaire partagé entre [computeCrossSectionRings] et
/// [sweepMoulure] : un anneau (liste de sommets monde, même ordre que
/// `profile.pointsMm`) par sommet de [pathMeters], déjà passé par la
/// contrainte de pose (règle #2), plus l'abscisse curviligne (mm) de chaque
/// anneau le long du trajet (pour `u`, règle #5).
class _CrossSections {
  final List<List<Vector3>> rings;
  final List<double> uAtRingMm;

  const _CrossSections({required this.rings, required this.uAtRingMm});
}

/// Calcule, pour chaque sommet de [pathMeters], l'anneau de section (coupe
/// droite aux deux bouts libres, coupe d'onglet sur plan bissecteur à
/// chaque sommet intérieur — règle dure #4) puis lui applique la
/// **contrainte de pose** (règle dure #2, tolérance 0.1mm garantie par
/// [_snapPoseVertices]).
///
/// Factorisation commune à [sweepMoulure] (qui triangule ces anneaux) et à
/// [computeCrossSectionRings] (exposé pour les tests dédiés à la
/// coplanarité — voir `sweep_test.dart`) : **aucune duplication de la
/// logique d'anneau/onglet/pose entre ces deux usages.**
_CrossSections _computeCrossSections({
  required MoulureProfile profile,
  required List<Vector3> pathMeters,
  required List<Plane3> wallPlanes,
  required Plane3 ceilingPlane,
}) {
  if (pathMeters.length < 2) {
    throw ArgumentError(
      '_computeCrossSections: pathMeters doit contenir au moins 2 points '
      '(reçu ${pathMeters.length}).',
    );
  }
  if (wallPlanes.length != pathMeters.length - 1) {
    throw ArgumentError(
      '_computeCrossSections: wallPlanes.length (${wallPlanes.length}) '
      'doit valoir pathMeters.length - 1 (${pathMeters.length - 1}) — un '
      'mur par segment de trajet.',
    );
  }
  if (profile.pointsMm.length < 3) {
    throw ArgumentError(
      '_computeCrossSections: profile.pointsMm doit contenir au moins 3 '
      'sommets (contour fermé, reçu ${profile.pointsMm.length}).',
    );
  }

  final segmentCount = pathMeters.length - 1;

  final frames = <_SegmentFrame>[
    for (var i = 0; i < segmentCount; i++)
      _buildSegmentFrame(
        start: pathMeters[i],
        end: pathMeters[i + 1],
        wallPlane: wallPlanes[i],
        ceilingPlane: ceilingPlane,
      ),
  ];

  final uAtRingMm = List<double>.filled(pathMeters.length, 0.0);
  for (var i = 1; i < pathMeters.length; i++) {
    uAtRingMm[i] = uAtRingMm[i - 1] + frames[i - 1].lengthM * 1000.0;
  }

  final rings = <List<Vector3>>[];
  for (var c = 0; c < pathMeters.length; c++) {
    List<Vector3> ring;
    Plane3 wallForSnap;
    if (c == 0) {
      ring = _computeStraightRing(
        profile: profile,
        frame: frames[0],
        alongOffsetM: 0.0,
      );
      wallForSnap = wallPlanes[0];
    } else if (c == pathMeters.length - 1) {
      ring = _computeStraightRing(
        profile: profile,
        frame: frames[segmentCount - 1],
        alongOffsetM: frames[segmentCount - 1].lengthM,
      );
      wallForSnap = wallPlanes[segmentCount - 1];
    } else {
      ring = _computeMiteredRing(
        profile: profile,
        framePrev: frames[c - 1],
        corner: pathMeters[c],
        nextAlongAxis: frames[c].alongAxis,
      );
      wallForSnap = wallPlanes[c - 1];
    }
    rings.add(
      _snapPoseVertices(
        profile: profile,
        ring: ring,
        wallPlane: wallForSnap,
        ceilingPlane: ceilingPlane,
      ),
    );
  }

  return _CrossSections(rings: rings, uAtRingMm: uAtRingMm);
}

/// Expose, pour un [profile] balayé le long de [pathMeters] (mêmes
/// paramètres que [sweepMoulure]), la liste des anneaux de section
/// **avant triangulation** — un anneau par sommet de trajet, chaque anneau
/// étant une liste de sommets monde dans le **même ordre que
/// `profile.pointsMm`** (donc `ring[i]` correspond exactement à
/// `profile.pointsMm[i]`, ce qui permet de vérifier directement la
/// contrainte de pose via `profile.wallIndices`/`profile.ceilingIndices` —
/// voir `sweep_test.dart`, test 1).
///
/// Cette fonction et [sweepMoulure] partagent la **même** implémentation
/// interne ([_computeCrossSections]) : les anneaux vérifiés ici sont
/// exactement ceux utilisés pour construire le [Mesh] final, aucune
/// divergence possible entre "ce qui est testé" et "ce qui est rendu".
List<List<Vector3>> computeCrossSectionRings({
  required MoulureProfile profile,
  required List<Vector3> pathMeters,
  required List<Plane3> wallPlanes,
  required Plane3 ceilingPlane,
}) {
  return _computeCrossSections(
    profile: profile,
    pathMeters: pathMeters,
    wallPlanes: wallPlanes,
    ceilingPlane: ceilingPlane,
  ).rings;
}

/// Point d'entrée principal : balaie [profile] le long de [pathMeters]
/// (polyline monde, mètres — `pathMeters.length >= 2`), un mur potentiellement
/// différent par segment ([wallPlanes], `wallPlanes.length ==
/// pathMeters.length - 1`), sous un plafond unique [ceilingPlane] (fixe pour
/// toute la pièce).
///
/// Voir la docstring de tête de fichier pour le contrat complet (règles
/// dures 1 à 6) et les sections ci-dessus pour le détail de chaque étape :
/// [_buildSegmentFrame] (repère par segment), [_computeStraightRing]/
/// [_computeMiteredRing] (anneaux, coupe droite/onglet), [_snapPoseVertices]
/// (contrainte de pose, règle #2), [_buildQuadTriangles] (triangulation).
///
/// **Normales** (règle #6) : calculées par facette à partir des sommets 3D
/// réels de chaque triangle (`cross(p1-p0, p2-p0)`), puis **forcées** à
/// pointer loin du centroïde global du maillage (`dot(normal, centroïde
/// facette - centroïde maillage) > 0`) — un choix explicite et robuste,
/// plutôt que de supposer que l'ordre des sommets (winding) est
/// correct par construction (fragile face à une torsion locale d'un anneau
/// mitré à forte pente, ou à une ambiguïté de "main" (handedness) de la
/// base (depthAxis, heightAxis, alongAxis), non garantie explicitement par
/// [_buildSegmentFrame]).
///
/// Lance [ArgumentError] si les tailles de [pathMeters]/[wallPlanes] sont
/// incohérentes, ou si l'une des étapes géométriques internes rencontre une
/// configuration dégénérée (voir les fonctions listées ci-dessus).
Mesh sweepMoulure({
  required MoulureProfile profile,
  required List<Vector3> pathMeters,
  required List<Plane3> wallPlanes,
  required Plane3 ceilingPlane,
}) {
  if (profile.pointsMm.length < 3) {
    throw ArgumentError(
      'sweepMoulure: profile.pointsMm doit contenir au moins 3 sommets '
      '(contour fermé, reçu ${profile.pointsMm.length}).',
    );
  }

  final vertexCountPerRing = profile.pointsMm.length;

  // 1-3. Repère par segment + anneaux (coupe droite/onglet) + contrainte de
  //    pose — factorisé avec [computeCrossSectionRings] (voir sa docstring
  //    et celle de [_computeCrossSections]).
  final sections = _computeCrossSections(
    profile: profile,
    pathMeters: pathMeters,
    wallPlanes: wallPlanes,
    ceilingPlane: ceilingPlane,
  );
  final rings = sections.rings;
  final uAtVertexMm = sections.uAtRingMm;
  final segmentCount = pathMeters.length - 1;

  // 4. Abscisses mm le long du profil, avec le raccord de bouclage résolu
  //    (le dernier sommet vu comme fin de l'arête de fermeture doit valoir
  //    perimeterMm, pas 0, pour ne pas faire "revenir en arrière" les UV).
  final vAtVertexMm = profile.cumulativeArcLengthMm;
  final perimeterMm = profile.perimeterMm;
  double vEndOf(int j) =>
      (j + 1 < vertexCountPerRing) ? vAtVertexMm[j + 1] : perimeterMm;

  // 5. Triangulation anneau-à-anneau, une "bande" de quads par arête de
  //    profil, jamais de reconvexification (règle #3) : on relie
  //    exactement les sommets consécutifs du profil, dans l'ordre fourni.
  final rawTriangles = <_RawTriangle>[];
  for (var s = 0; s < segmentCount; s++) {
    final ringA = rings[s];
    final ringB = rings[s + 1];
    final uA = uAtVertexMm[s];
    final uB = uAtVertexMm[s + 1];
    for (var j = 0; j < vertexCountPerRing; j++) {
      final jNext = (j + 1) % vertexCountPerRing;
      rawTriangles.addAll(
        _buildQuadTriangles(
          a0: ringA[j],
          a1: ringA[jNext],
          b0: ringB[j],
          b1: ringB[jNext],
          uA: uA,
          uB: uB,
          vJ: vAtVertexMm[j],
          vNext: vEndOf(j),
        ),
      );
    }
  }

  // 6. Centroïde global (moyenne des sommets d'anneau — pas des sommets de
  //    triangle dupliqués, pour ne pas sur-pondérer une zone à forte
  //    densité de facettes) — référence pour forcer l'orientation "vers
  //    l'extérieur" des normales (règle #6, voir docstring de la fonction).
  var centroidSum = Vector3.zero();
  var centroidCount = 0;
  for (final ring in rings) {
    for (final p in ring) {
      centroidSum = centroidSum + p;
      centroidCount++;
    }
  }
  final meshCentroid = centroidSum / centroidCount.toDouble();

  // 7. Assemblage final : normale par facette forcée "sortante", sommets
  //    dupliqués par triangle (pas de lissage, règle #6).
  final triangleCount = rawTriangles.length;
  final positions = Float32List(triangleCount * 3 * 3);
  final normals = Float32List(triangleCount * 3 * 3);
  final uvs = Float32List(triangleCount * 3 * 2);
  final indices = Uint16List(triangleCount * 3);

  var vi = 0; // index de sommet courant (avant multiplication par 3/2).
  for (final tri in rawTriangles) {
    var p0 = tri.p0;
    var p1 = tri.p1;
    var p2 = tri.p2;
    var uv0 = tri.uv0;
    var uv1 = tri.uv1;
    var uv2 = tri.uv2;

    var normal = (p1 - p0).cross(p2 - p0);
    if (normal.length2 < 1e-24) {
      throw ArgumentError(
        'sweepMoulure: facette dégénérée (triangle d\'aire quasi nulle) — '
        'p0=$p0, p1=$p1, p2=$p2.',
      );
    }
    normal = normal.normalized();

    final triCentroid = tri.centroid;
    final outwardRef = triCentroid - meshCentroid;
    if (normal.dot(outwardRef) < 0) {
      // Inverse l'orientation (échange p1/p2 ET uv1/uv2 pour rester
      // cohérent) plutôt que de simplement négativer la normale seule —
      // garde un winding cohérent avec la normale stockée.
      final tmpP = p1;
      p1 = p2;
      p2 = tmpP;
      final tmpUv = uv1;
      uv1 = uv2;
      uv2 = tmpUv;
      normal = -normal;
    }

    for (final p in [p0, p1, p2]) {
      positions[vi * 3] = p.x;
      positions[vi * 3 + 1] = p.y;
      positions[vi * 3 + 2] = p.z;
      normals[vi * 3] = normal.x;
      normals[vi * 3 + 1] = normal.y;
      normals[vi * 3 + 2] = normal.z;
      indices[vi] = vi;
      vi++;
    }
    // UV dans le même ordre que les positions ci-dessus (p0,p1,p2 déjà
    // potentiellement permutés) :
    final uvTriple = [uv0, uv1, uv2];
    for (var k = 0; k < 3; k++) {
      final baseVi = vi - 3 + k;
      uvs[baseVi * 2] = uvTriple[k].x;
      uvs[baseVi * 2 + 1] = uvTriple[k].y;
    }
  }

  return Mesh(
    positions: positions,
    indices: indices,
    normals: normals,
    uvs: uvs,
  );
}
