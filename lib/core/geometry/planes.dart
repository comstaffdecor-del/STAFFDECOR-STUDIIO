/// Plans 3D (mur, plafond, sol...) et intersection analytique de deux plans
/// en une arête (droite 3D) — brique géométrique intermédiaire entre
/// [Camera3D] (`camera.dart`) et l'extrusion de profil (`sweep.dart`,
/// livraison suivante).
///
/// ⚠️ Ce fichier est **Dart pur** : aucune dépendance UI (`dart:ui`,
/// `package:flutter/...`). Testable en isolation, sans widget.
///
/// ## Convention géométrique (imposée, valable pour tout `geometry/`)
///
/// ⚠️ **Source unique de vérité : `geometry/CONVENTIONS.md`.** Le résumé
/// ci-dessous n'est qu'un rappel pour ce fichier.
///
/// - **Repère monde** : main droite, **X = droite**, **Y = haut**,
///   **Z = vers la caméra** — voir `camera.dart` pour le détail complet
///   (même convention, non répétée ici).
/// - **Unités** : mètres.
/// - Un [Plane3] est défini par un [Plane3.normal] **unitaire** et une
///   [Plane3.constant] tels que pour tout point `p` du plan :
///   `normal · p + constant == 0` (convention identique à
///   `vector_math`'s `Plane`, mais ce fichier n'utilise PAS
///   `Plane.intersection` — voir [intersectPlanes] pour la justification).
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// Une droite 3D non bornée : un point de passage + une direction
/// **normalisée** (longueur 1). Ne porte aucune borne de segment — les
/// bornes viendront du tracé utilisateur (via la calibration/l'UI), pas de
/// la géométrie pure.
class Line3 {
  /// Un point quelconque de la droite.
  final Vector3 point;

  /// Direction de la droite, **normalisée** (longueur 1). Le sens
  /// (direction vs son opposé) n'a pas de signification géométrique propre
  /// à une droite infinie ; il est simplement déterminé par l'ordre des
  /// plans passés à [intersectPlanes] (produit vectoriel `nA × nB`), pour
  /// rester déterministe et testable.
  final Vector3 direction;

  const Line3({required this.point, required this.direction});

  @override
  String toString() => 'Line3(point: $point, direction: $direction)';
}

/// Un plan 3D défini par une normale **unitaire** et une constante, selon
/// la convention `normal · p + constant == 0` pour tout point `p` du plan.
///
/// Distinct de `vector_math`'s `Plane` : ce type est volontairement minimal
/// (immutable, normale garantie unitaire à la construction) et sert de
/// support à [intersectPlanes], qui n'utilise **pas**
/// `vector_math`'s `Plane.intersection` (intersection de **trois** plans en
/// un point — mauvais outil ici : on veut l'intersection de **deux** plans
/// en une **droite**).
class Plane3 {
  /// Normale du plan, **unitaire** (garanti par le constructeur nommé
  /// [Plane3.fromPointAndNormal], qui normalise [normalRaw]).
  final Vector3 normal;

  /// Constante `d` telle que `normal · p + d == 0` pour tout point `p` du
  /// plan.
  final double constant;

  const Plane3._(this.normal, this.constant);

  /// Construit un plan passant par [point], de normale [normalRaw]
  /// (normalisée automatiquement — ne pas passer un vecteur nul).
  ///
  /// Lance [ArgumentError] si [normalRaw] est (quasi) nul : un plan sans
  /// normale définie n'a pas de sens, mieux vaut échouer explicitement que
  /// produire un [Plane3] avec une normale NaN.
  factory Plane3.fromPointAndNormal(Vector3 point, Vector3 normalRaw) {
    final len2 = normalRaw.length2;
    if (len2 < 1e-18) {
      throw ArgumentError(
        'Plane3.fromPointAndNormal: normale (quasi) nulle, plan indéfini.',
      );
    }
    final n = normalRaw.normalized();
    final d = -n.dot(point);
    return Plane3._(n, d);
  }

  /// Distance signée de [p] au plan (positive du côté de la normale).
  double signedDistanceTo(Vector3 p) => normal.dot(p) + constant;

  @override
  String toString() => 'Plane3(normal: $normal, constant: $constant)';
}

/// Résultat de [intersectPlanes].
///
/// Deux cas exclusifs :
/// - non-dégénéré : [line] est non-nul, [isDegenerate] = `false`.
/// - dégénéré (plans quasi-parallèles) : [line] = `null`,
///   [isDegenerate] = `true`, [message] explique pourquoi. **Jamais de
///   NaN** — le cas dégénéré est un résultat explicite, pas une erreur
///   silencieuse.
class PlaneIntersectionResult {
  final Line3? line;
  final bool isDegenerate;
  final String? message;

  /// Angle (radians, dans `[0, pi/2]`) entre les deux normales, mesuré par
  /// rapport à la configuration "plans parallèles" (0 = parallèles,
  /// pi/2 = perpendiculaires). Toujours exposé (même si dégénéré), pour
  /// transparence/debug.
  final double angleFromParallelRad;

  const PlaneIntersectionResult.ok(this.line, this.angleFromParallelRad)
    : isDegenerate = false,
      message = null;

  const PlaneIntersectionResult.degenerate(
    this.message,
    this.angleFromParallelRad,
  ) : isDegenerate = true,
      line = null;

  @override
  String toString() => isDegenerate
      ? 'PlaneIntersectionResult(dégénéré: $message, '
            'angle: $angleFromParallelRad rad)'
      : 'PlaneIntersectionResult(line: $line, '
            'angle: $angleFromParallelRad rad)';
}

/// Intersecte deux plans [a] et [b] et retourne la droite 3D résultante.
///
/// **Méthode** (volontairement différente de `vector_math`'s
/// `Plane.intersection`, qui prend TROIS plans et donne un POINT — pas
/// l'outil adapté ici) :
///
/// 1. La direction de la droite d'intersection est `direction =
///    normalize(a.normal × b.normal)` — orthogonale aux deux normales,
///    donc contenue dans les deux plans.
/// 2. Un point de la droite est obtenu en résolvant le système 2×2 formé
///    par les deux équations de plan, **restreint à l'axe dominant** de
///    `direction` (celui de plus grande valeur absolue) fixé à 0 — c'est
///    l'axe sur lequel il est numériquement le plus stable de "sacrifier"
///    une coordonnée, car c'est celui où la droite varie le plus (donc où
///    la contrainte est la moins bien conditionnée si on la choisissait à
///    la place). Sur les deux axes restants, le système 2×2 :
///    `nA[i]·u + nA[j]·v = -dA`
///    `nB[i]·u + nB[j]·v = -dB`
///    a pour déterminant `nA[i]·nB[j] - nA[j]·nB[i]`, qui est exactement la
///    composante `k` (l'axe dominant) de `a.normal × b.normal` — donc
///    maximale en valeur absolue par construction, ce qui garantit la
///    meilleure stabilité numérique possible pour ce système.
///
/// **Cas dégénéré — jamais de NaN** : si l'angle entre les deux normales
/// (mesuré par rapport à la configuration parallèle, via
/// `asin(|a.normal × b.normal|)`, robuste même pour des normales
/// quasi-parallèles OU quasi-anti-parallèles) est strictement inférieur à
/// [epsilonRad], les plans sont considérés parallèles : la fonction
/// retourne un [PlaneIntersectionResult.degenerate] explicite, sans
/// tenter de calculer une droite.
PlaneIntersectionResult intersectPlanes(
  Plane3 a,
  Plane3 b, {
  double epsilonRad = 1e-4,
}) {
  final cross = a.normal.cross(b.normal);
  final crossLen = cross.length;

  // asin(|a×b|) = angle par rapport à la config. parallèle (0..pi/2),
  // robuste aussi pour des normales anti-parallèles (a.normal ≈ -b.normal)
  // car |cross| est petit dans les deux cas (parallèle ET anti-parallèle).
  final angleFromParallelRad = math.asin(crossLen.clamp(0.0, 1.0));

  if (angleFromParallelRad < epsilonRad) {
    return PlaneIntersectionResult.degenerate(
      'Plans (quasi-)parallèles : angle entre les normales '
      '${angleFromParallelRad.toStringAsFixed(6)} rad < seuil '
      '$epsilonRad rad. Aucune droite d\'intersection définie.',
      angleFromParallelRad,
    );
  }

  final direction = cross / crossLen;

  // Axe dominant de `direction` = composante de plus grande valeur
  // absolue de `cross` (direction et cross sont colinéaires, donc même
  // axe dominant) — le plus stable numériquement pour fixer une
  // coordonnée à 0, voir doc ci-dessus.
  final absCross = [cross.x.abs(), cross.y.abs(), cross.z.abs()];
  var k = 0;
  if (absCross[1] >= absCross[k]) k = 1;
  if (absCross[2] >= absCross[k]) k = 2;
  final i = (k + 1) % 3;
  final j = (k + 2) % 3;

  final det = cross[k]; // = nA[i]*nB[j] - nA[j]*nB[i], maximal en |.|
  final nA = a.normal;
  final nB = b.normal;
  final dA = a.constant;
  final dB = b.constant;

  final u = (-dA * nB[j] + dB * nA[j]) / det;
  final v = (-nA[i] * dB + nB[i] * dA) / det;

  final point = Vector3.zero();
  point[i] = u;
  point[j] = v;
  point[k] = 0.0;

  return PlaneIntersectionResult.ok(
    Line3(point: point, direction: direction),
    angleFromParallelRad,
  );
}
