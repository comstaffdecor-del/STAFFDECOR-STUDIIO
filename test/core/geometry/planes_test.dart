import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/geometry/planes.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  group('Plane3.fromPointAndNormal', () {
    test('normalise automatiquement la normale fournie', () {
      final plane = Plane3.fromPointAndNormal(
        Vector3(3, 0, 0),
        Vector3(5, 0, 0), // non-unitaire volontairement
      );
      expect(plane.normal.length, closeTo(1.0, 1e-12));
      expect(plane.normal.x, closeTo(1.0, 1e-12));
      // Le point d'origine doit vérifier l'équation du plan.
      expect(plane.signedDistanceTo(Vector3(3, 0, 0)), closeTo(0.0, 1e-12));
    });

    test('lance ArgumentError si la normale est (quasi) nulle', () {
      expect(
        () => Plane3.fromPointAndNormal(Vector3.zero(), Vector3.zero()),
        throwsArgumentError,
      );
      expect(
        () => Plane3.fromPointAndNormal(
          Vector3.zero(),
          Vector3(1e-10, 1e-10, 1e-10),
        ),
        throwsArgumentError,
      );
    });

    test('signedDistanceTo est cohérent (positif du côté de la normale)', () {
      final plane = Plane3.fromPointAndNormal(Vector3(0, 0, 0), Vector3(0, 1, 0));
      expect(plane.signedDistanceTo(Vector3(0, 2, 0)), closeTo(2.0, 1e-12));
      expect(plane.signedDistanceTo(Vector3(0, -2, 0)), closeTo(-2.0, 1e-12));
      expect(plane.signedDistanceTo(Vector3(5, 0, -5)), closeTo(0.0, 1e-12));
    });
  });

  group('intersectPlanes — cas perpendiculaire simple (mur x=3, plafond y=2.5)', () {
    test('donne l\'arête verticale attendue (0,0,1), point (3,2.5,0)', () {
      final mur = Plane3.fromPointAndNormal(Vector3(3, 0, 0), Vector3(1, 0, 0));
      final plafond = Plane3.fromPointAndNormal(
        Vector3(0, 2.5, 0),
        Vector3(0, 1, 0),
      );
      final result = intersectPlanes(mur, plafond);

      expect(result.isDegenerate, isFalse);
      expect(result.angleFromParallelRad, closeTo(math.pi / 2, 1e-9));
      final line = result.line!;
      // Direction attendue : ±Z (perpendiculaire à x et y).
      expect(line.direction.length, closeTo(1.0, 1e-9));
      expect(line.direction.x.abs(), closeTo(0.0, 1e-9));
      expect(line.direction.y.abs(), closeTo(0.0, 1e-9));
      expect(line.direction.z.abs(), closeTo(1.0, 1e-9));
      // Le point retourné doit être sur les deux plans.
      expect(mur.signedDistanceTo(line.point), closeTo(0.0, 1e-9));
      expect(plafond.signedDistanceTo(line.point), closeTo(0.0, 1e-9));
      expect(line.point.x, closeTo(3.0, 1e-9));
      expect(line.point.y, closeTo(2.5, 1e-9));
    });

    test('un second point sur la droite (point + t*direction) reste sur les deux plans', () {
      final mur = Plane3.fromPointAndNormal(Vector3(3, 0, 0), Vector3(1, 0, 0));
      final plafond = Plane3.fromPointAndNormal(
        Vector3(0, 2.5, 0),
        Vector3(0, 1, 0),
      );
      final line = intersectPlanes(mur, plafond).line!;
      final p2 = line.point + line.direction * 7.3;
      expect(mur.signedDistanceTo(p2), closeTo(0.0, 1e-9));
      expect(plafond.signedDistanceTo(p2), closeTo(0.0, 1e-9));
    });
  });

  group('intersectPlanes — cas générique oblique (validé numériquement en Python/numpy)', () {
    test('point et direction attendus, résidus nuls sur les deux équations de plan', () {
      final a = Plane3.fromPointAndNormal(Vector3(1, 0, 0), Vector3(1, 2, 3));
      final b = Plane3.fromPointAndNormal(Vector3(0, 2, 0), Vector3(3, -1, 2));
      final result = intersectPlanes(a, b);

      expect(result.isDegenerate, isFalse);
      final line = result.line!;

      // Valeurs de référence calculées indépendamment en Python/numpy.
      expect(line.point.x, closeTo(-0.42857143, 1e-6));
      expect(line.point.y, closeTo(0.71428571, 1e-6));
      expect(line.point.z, closeTo(0.0, 1e-9));
      expect(line.direction.x, closeTo(0.57735027, 1e-6));
      expect(line.direction.y, closeTo(0.57735027, 1e-6));
      expect(line.direction.z, closeTo(-0.57735027, 1e-6));

      expect(a.signedDistanceTo(line.point), closeTo(0.0, 1e-9));
      expect(b.signedDistanceTo(line.point), closeTo(0.0, 1e-9));

      final p2 = line.point + line.direction * 3.7;
      expect(a.signedDistanceTo(p2), closeTo(0.0, 1e-9));
      expect(b.signedDistanceTo(p2), closeTo(0.0, 1e-9));
    });
  });

  group('intersectPlanes — couverture des 3 axes dominants', () {
    test('axe dominant Z : normales quasi dans le plan XY', () {
      final a = Plane3.fromPointAndNormal(Vector3.zero(), Vector3(1, 0.1, 0));
      final b = Plane3.fromPointAndNormal(Vector3.zero(), Vector3(0.1, 1, 0));
      final line = intersectPlanes(a, b).line!;
      expect(line.direction.z.abs(), closeTo(1.0, 1e-6));
      expect(a.signedDistanceTo(line.point), closeTo(0.0, 1e-9));
      expect(b.signedDistanceTo(line.point), closeTo(0.0, 1e-9));
    });

    test('axe dominant X : normales quasi dans le plan YZ', () {
      final a = Plane3.fromPointAndNormal(Vector3.zero(), Vector3(0, 1, 0.1));
      final b = Plane3.fromPointAndNormal(Vector3.zero(), Vector3(0, 0.1, 1));
      final line = intersectPlanes(a, b).line!;
      expect(line.direction.x.abs(), closeTo(1.0, 1e-6));
      expect(a.signedDistanceTo(line.point), closeTo(0.0, 1e-9));
      expect(b.signedDistanceTo(line.point), closeTo(0.0, 1e-9));
    });

    test('axe dominant Y : normales quasi dans le plan XZ', () {
      final a = Plane3.fromPointAndNormal(Vector3.zero(), Vector3(1, 0, 0.1));
      final b = Plane3.fromPointAndNormal(Vector3.zero(), Vector3(0.1, 0, 1));
      final line = intersectPlanes(a, b).line!;
      expect(line.direction.y.abs(), closeTo(1.0, 1e-6));
      expect(a.signedDistanceTo(line.point), closeTo(0.0, 1e-9));
      expect(b.signedDistanceTo(line.point), closeTo(0.0, 1e-9));
    });
  });

  group('intersectPlanes — cas dégénéré (plans parallèles), jamais de NaN', () {
    test('plans strictement parallèles (mêmes normales) -> dégénéré explicite', () {
      final a = Plane3.fromPointAndNormal(Vector3(3, 0, 0), Vector3(1, 0, 0));
      final b = Plane3.fromPointAndNormal(Vector3(5, 0, 0), Vector3(1, 0, 0));
      final result = intersectPlanes(a, b);
      expect(result.isDegenerate, isTrue);
      expect(result.line, isNull);
      expect(result.message, isNotNull);
      expect(result.angleFromParallelRad, closeTo(0.0, 1e-12));
    });

    test('plans anti-parallèles (normales opposées) -> dégénéré explicite '
        '(même mesure de "parallèle" indépendamment du sens de la normale)', () {
      final a = Plane3.fromPointAndNormal(Vector3(3, 0, 0), Vector3(1, 0, 0));
      final b = Plane3.fromPointAndNormal(Vector3(5, 0, 0), Vector3(-1, 0, 0));
      final result = intersectPlanes(a, b);
      expect(result.isDegenerate, isTrue);
      expect(result.line, isNull);
      expect(result.angleFromParallelRad, closeTo(0.0, 1e-12));
    });

    test('angle juste sous le seuil (5e-5 rad < défaut 1e-4 rad) -> dégénéré', () {
      final tiny = 5e-5;
      final a = Plane3.fromPointAndNormal(Vector3.zero(), Vector3(1, 0, 0));
      final b = Plane3.fromPointAndNormal(
        Vector3.zero(),
        Vector3(math.cos(tiny), math.sin(tiny), 0),
      );
      final result = intersectPlanes(a, b);
      expect(result.isDegenerate, isTrue);
      expect(result.angleFromParallelRad, lessThan(1e-4));
    });

    test('angle juste au-dessus du seuil (2e-4 rad > défaut 1e-4 rad) -> non-dégénéré', () {
      final tiny = 2e-4;
      final a = Plane3.fromPointAndNormal(Vector3.zero(), Vector3(1, 0, 0));
      final b = Plane3.fromPointAndNormal(
        Vector3.zero(),
        Vector3(math.cos(tiny), math.sin(tiny), 0),
      );
      final result = intersectPlanes(a, b);
      expect(result.isDegenerate, isFalse);
      expect(result.line, isNotNull);
      expect(result.angleFromParallelRad, greaterThan(1e-4));
      // Direction attendue ~ Z (les deux normales sont quasi dans XY).
      expect(result.line!.direction.z.abs(), closeTo(1.0, 1e-3));
    });

    test('seuil personnalisé (epsilonRad) est bien pris en compte', () {
      final tiny = 5e-5;
      final a = Plane3.fromPointAndNormal(Vector3.zero(), Vector3(1, 0, 0));
      final b = Plane3.fromPointAndNormal(
        Vector3.zero(),
        Vector3(math.cos(tiny), math.sin(tiny), 0),
      );
      // Avec le seuil par défaut (1e-4), ce cas est dégénéré (vérifié
      // ci-dessus). Avec un seuil plus permissif, il ne doit plus l'être.
      final result = intersectPlanes(a, b, epsilonRad: 1e-6);
      expect(result.isDegenerate, isFalse);
    });

    test('aucun NaN/Infinity produit, ni dans le résultat dégénéré ni dans un cas limite', () {
      final a = Plane3.fromPointAndNormal(Vector3(3, 0, 0), Vector3(1, 0, 0));
      final b = Plane3.fromPointAndNormal(Vector3(5, 0, 0), Vector3(1, 0, 0));
      final result = intersectPlanes(a, b);
      expect(result.isDegenerate, isTrue);
      expect(result.line, isNull);
      expect(result.angleFromParallelRad.isNaN, isFalse);
      expect(result.angleFromParallelRad.isFinite, isTrue);
    });
  });

  group('intersectPlanes — robustesse numérique (200 paires de plans aléatoires)', () {
    test('résidu sur les équations de plan toujours < 1e-9 quand non-dégénéré', () {
      final rng = math.Random(7);
      var checked = 0;
      double maxResidual = 0.0;
      for (var i = 0; i < 200; i++) {
        final pa = Vector3(
          rng.nextDouble() * 10 - 5,
          rng.nextDouble() * 10 - 5,
          rng.nextDouble() * 10 - 5,
        );
        final na = Vector3(
          rng.nextDouble() * 2 - 1,
          rng.nextDouble() * 2 - 1,
          rng.nextDouble() * 2 - 1,
        );
        final pb = Vector3(
          rng.nextDouble() * 10 - 5,
          rng.nextDouble() * 10 - 5,
          rng.nextDouble() * 10 - 5,
        );
        final nb = Vector3(
          rng.nextDouble() * 2 - 1,
          rng.nextDouble() * 2 - 1,
          rng.nextDouble() * 2 - 1,
        );
        if (na.length2 < 1e-6 || nb.length2 < 1e-6) continue;

        final a = Plane3.fromPointAndNormal(pa, na);
        final b = Plane3.fromPointAndNormal(pb, nb);
        final result = intersectPlanes(a, b);
        if (result.isDegenerate) continue; // exclu, pas l'objet de ce test

        checked++;
        final line = result.line!;
        expect(line.direction.length, closeTo(1.0, 1e-9));
        expect(line.point.x.isNaN, isFalse);
        expect(line.point.y.isNaN, isFalse);
        expect(line.point.z.isNaN, isFalse);

        final r1 = a.signedDistanceTo(line.point).abs();
        final r2 = b.signedDistanceTo(line.point).abs();
        final p2 = line.point + line.direction * 1.3;
        final r3 = a.signedDistanceTo(p2).abs();
        final r4 = b.signedDistanceTo(p2).abs();
        final localMax = <double>[
          r1,
          r2,
          r3,
          r4,
        ].reduce((double x, double y) => x > y ? x : y);
        if (localMax > maxResidual) maxResidual = localMax;
      }
      // On s'attend à ce que la quasi-totalité des 200 tirages soient
      // non-dégénérés (deux normales aléatoires colinéaires par hasard :
      // probabilité quasi nulle).
      expect(checked, greaterThan(190));
      expect(maxResidual, lessThan(1e-9));
    });
  });
}
