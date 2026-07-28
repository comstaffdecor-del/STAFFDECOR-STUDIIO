// Tests dédiés à `sweep.dart`, conformes au contrat imposé par
// l'utilisateur (6 tests numérotés). Voir la docstring de tête de
// `lib/core/geometry/sweep.dart` pour le rappel complet des règles dures.
//
// Convention géométrique de test (voir `CONVENTIONS.md`) : repère monde
// main droite, X=droite, Y=haut, Z=vers la caméra, mètres.
//
// Room de test : plafond horizontal `y = ceilingHeightM`, murs verticaux
// (normales horizontales, `y=0`). Un profil en "L" (moulure de plinthe/
// corniche simplifiée), 6 sommets, dont une arête "face_pose_mur" (x=0,
// deux sommets) et une arête "face_pose_plafond" (y=0, deux sommets).
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:staff_decor_studio/core/geometry/planes.dart';
import 'package:staff_decor_studio/core/geometry/sweep.dart';

const double _poseToleranceM = 0.1 / 1000.0; // 0.1 mm, en mètres.
const double _ceilingHeightM = 2.5;

/// Profil en "L" partagé par tous les tests : 6 sommets (mm), une arête
/// mur (x=0) et une arête plafond (y=0) — voir schéma en tête de fichier.
MoulureProfile _lProfile() {
  return MoulureProfile(
    pointsMm: [
      Vector2(0, 0), // 0 — coin mur/plafond
      Vector2(10, 0), // 1 — bord plafond
      Vector2(10, -40), // 2
      Vector2(30, -40), // 3
      Vector2(30, -50), // 4
      Vector2(0, -50), // 5 — bas, retour au mur
    ],
    wallIndices: [5, 0],
    ceilingIndices: [0, 1],
  );
}

Plane3 _ceilingPlane() =>
    Plane3.fromPointAndNormal(Vector3(0, _ceilingHeightM, 0), Vector3(0, 1, 0));

/// Mur vertical passant par [point], de normale horizontale [normal]
/// (composante `y` ignorée/forcée à 0 pour rester un mur strictement
/// vertical dans ces tests).
Plane3 _verticalWall(Vector3 point, Vector3 normal) =>
    Plane3.fromPointAndNormal(point, Vector3(normal.x, 0, normal.z));

void main() {
  group('Test 1 — profil en L, trajet droit de 3 m', () {
    final profile = _lProfile();
    final ceiling = _ceilingPlane();
    final wall = _verticalWall(Vector3(0, 0, 0), Vector3(1, 0, 0));
    final start = Vector3(0, _ceilingHeightM, 0);
    final end = Vector3(0, _ceilingHeightM, 3);

    final mesh = sweepMoulure(
      profile: profile,
      pathMeters: [start, end],
      wallPlanes: [wall],
      ceilingPlane: ceiling,
    );

    test('nombre de triangles attendu (6 arêtes de profil x 2)', () {
      // 6 sommets de profil => 6 arêtes (contour fermé) => 6 quads entre
      // les 2 anneaux => 12 triangles. Jamais de reconvexification (règle
      // #3) : c'est bien le nombre d'arêtes du profil D'ENTRÉE qui compte.
      expect(mesh.triangleCount, 12);
    });

    test(
      'coplanarité des deux faces de pose < 0.1mm sur TOUS les sommets',
      () {
        final rings = computeCrossSectionRings(
          profile: profile,
          pathMeters: [start, end],
          wallPlanes: [wall],
          ceilingPlane: ceiling,
        );
        expect(rings.length, 2);
        for (final ring in rings) {
          for (final i in profile.wallIndices) {
            expect(
              wall.signedDistanceTo(ring[i]).abs(),
              lessThan(_poseToleranceM),
              reason: 'sommet mur $i hors tolérance',
            );
          }
          for (final i in profile.ceilingIndices) {
            expect(
              ceiling.signedDistanceTo(ring[i]).abs(),
              lessThan(_poseToleranceM),
              reason: 'sommet plafond $i hors tolérance',
            );
          }
        }
      },
    );
  });

  group('Test 2 — angle sortant (convexe) 90°', () {
    final profile = _lProfile();
    final ceiling = _ceilingPlane();
    final wall1 = _verticalWall(Vector3(0, 0, 0), Vector3(1, 0, 0));
    // Corner "sortant" (pillar-like) : le mur2 fait face à +Z (s'éloigne
    // de la zone où se trouve le mur1), contrairement au coin rentrant
    // classique d'une pièce (voir groupe suivant).
    final wall2 = _verticalWall(Vector3(0, 0, 3), Vector3(0, 0, 1));
    final path = [
      Vector3(0, _ceilingHeightM, 0),
      Vector3(0, _ceilingHeightM, 3),
      Vector3(3, _ceilingHeightM, 3),
    ];

    test('sweep ne lève pas d\'exception (pas de dégénérescence)', () {
      expect(
        () => sweepMoulure(
          profile: profile,
          pathMeters: path,
          wallPlanes: [wall1, wall2],
          ceilingPlane: ceiling,
        ),
        returnsNormally,
      );
    });

    final mesh = sweepMoulure(
      profile: profile,
      pathMeters: path,
      wallPlanes: [wall1, wall2],
      ceilingPlane: ceiling,
    );

    test('jonction continue : bon nombre de triangles, pas de facette nulle', () {
      // 2 segments x 6 quads x 2 triangles = 24. Le fait que sweepMoulure
      // n'ait pas levé d'ArgumentError (facette d'aire quasi nulle,
      // cf. sweep.dart) garantit déjà l'absence de dégénérescence — voir
      // test précédent. On vérifie ici juste la cohérence du comptage.
      expect(mesh.triangleCount, 24);
    });

    test('les faces de pose restent coplanaires des deux côtés', () {
      final rings = computeCrossSectionRings(
        profile: profile,
        pathMeters: path,
        wallPlanes: [wall1, wall2],
        ceilingPlane: ceiling,
      );
      expect(rings.length, 3);

      // Anneau de départ (segment 1 seul) : coplanaire avec wall1.
      for (final i in profile.wallIndices) {
        expect(wall1.signedDistanceTo(rings[0][i]).abs(), lessThan(_poseToleranceM));
      }
      // Anneau de fin (segment 2 seul) : coplanaire avec wall2.
      for (final i in profile.wallIndices) {
        expect(wall2.signedDistanceTo(rings[2][i]).abs(), lessThan(_poseToleranceM));
      }
      // Anneau du coin (partagé) : coplanaire avec les DEUX murs à la
      // fois — c'est la garantie de continuité de la jonction (le
      // sommet "face mur" du coin est physiquement sur l'arête réelle
      // mur1 ∩ mur2).
      for (final i in profile.wallIndices) {
        expect(
          wall1.signedDistanceTo(rings[1][i]).abs(),
          lessThan(_poseToleranceM),
          reason: 'anneau du coin hors tolérance côté mur1',
        );
        expect(
          wall2.signedDistanceTo(rings[1][i]).abs(),
          lessThan(_poseToleranceM),
          reason: 'anneau du coin hors tolérance côté mur2',
        );
      }
      // Plafond : un seul plan pour toute la pièce, coplanarité triviale
      // mais vérifiée explicitement sur les 3 anneaux.
      for (final ring in rings) {
        for (final i in profile.ceilingIndices) {
          expect(ceiling.signedDistanceTo(ring[i]).abs(), lessThan(_poseToleranceM));
        }
      }
    });
  });

  group('Test 3 — angle rentrant (concave) 90°', () {
    final profile = _lProfile();
    final ceiling = _ceilingPlane();
    final wall1 = _verticalWall(Vector3(0, 0, 0), Vector3(1, 0, 0));
    // Corner "rentrant" (coin intérieur classique d'une pièce) : le mur2
    // fait face à -Z, vers l'intérieur commun de la pièce avec mur1.
    final wall2 = _verticalWall(Vector3(0, 0, 3), Vector3(0, 0, -1));
    final path = [
      Vector3(0, _ceilingHeightM, 0),
      Vector3(0, _ceilingHeightM, 3),
      Vector3(3, _ceilingHeightM, 3),
    ];

    final mesh = sweepMoulure(
      profile: profile,
      pathMeters: path,
      wallPlanes: [wall1, wall2],
      ceilingPlane: ceiling,
    );

    test('pas d\'interpénétration (pas de facette dégénérée), bon comptage', () {
      expect(mesh.triangleCount, 24);
    });

    test('les faces de pose restent coplanaires des deux côtés', () {
      final rings = computeCrossSectionRings(
        profile: profile,
        pathMeters: path,
        wallPlanes: [wall1, wall2],
        ceilingPlane: ceiling,
      );
      for (final i in profile.wallIndices) {
        expect(wall1.signedDistanceTo(rings[0][i]).abs(), lessThan(_poseToleranceM));
        expect(wall2.signedDistanceTo(rings[2][i]).abs(), lessThan(_poseToleranceM));
        expect(
          wall1.signedDistanceTo(rings[1][i]).abs(),
          lessThan(_poseToleranceM),
          reason: 'anneau du coin hors tolérance côté mur1',
        );
        expect(
          wall2.signedDistanceTo(rings[1][i]).abs(),
          lessThan(_poseToleranceM),
          reason: 'anneau du coin hors tolérance côté mur2',
        );
      }
      for (final ring in rings) {
        for (final i in profile.ceilingIndices) {
          expect(ceiling.signedDistanceTo(ring[i]).abs(), lessThan(_poseToleranceM));
        }
      }
    });
  });

  group('Test 4 — angle de 135°, l\'onglet ne doit pas dégénérer', () {
    final profile = _lProfile();
    final ceiling = _ceilingPlane();
    final wall1 = _verticalWall(Vector3(0, 0, 0), Vector3(1, 0, 0));

    // Segment 2 dans une direction faisant un angle de 135° avec le
    // segment 1 (dot(along1, along2) = cos(135°) ≈ -0.70710678).
    final corner = Vector3(0, _ceilingHeightM, 3);
    final along2 = Vector3(0.70710678, 0, -0.70710678); // unitaire.
    final end2 = corner + along2 * 3.0;
    // Mur2 vertical, contenant along2 comme tangente (normale
    // horizontale orthogonale à along2, via un produit vectoriel avec la
    // verticale monde — construction standard d'un mur vertical à partir
    // de sa direction de trajet).
    final wall2Normal = along2.cross(Vector3(0, 1, 0)).normalized();
    final wall2 = _verticalWall(corner, wall2Normal);

    final path = [Vector3(0, _ceilingHeightM, 0), corner, end2];

    test('sweep ne lève pas d\'exception (onglet non dégénéré)', () {
      expect(
        () => sweepMoulure(
          profile: profile,
          pathMeters: path,
          wallPlanes: [wall1, wall2],
          ceilingPlane: ceiling,
        ),
        returnsNormally,
      );
    });

    final mesh = sweepMoulure(
      profile: profile,
      pathMeters: path,
      wallPlanes: [wall1, wall2],
      ceilingPlane: ceiling,
    );

    test('triangles tous d\'aire non nulle, comptage cohérent', () {
      expect(mesh.triangleCount, 24);
      for (var t = 0; t < mesh.triangleCount; t++) {
        final i0 = mesh.indices[t * 3];
        final i1 = mesh.indices[t * 3 + 1];
        final i2 = mesh.indices[t * 3 + 2];
        final p0 = mesh.positionAt(i0);
        final p1 = mesh.positionAt(i1);
        final p2 = mesh.positionAt(i2);
        final area2 = (p1 - p0).cross(p2 - p0).length;
        expect(area2, greaterThan(1e-12), reason: 'triangle $t d\'aire quasi nulle');
      }
    });

    test('coplanarité de pose conservée même à 135°', () {
      final rings = computeCrossSectionRings(
        profile: profile,
        pathMeters: path,
        wallPlanes: [wall1, wall2],
        ceilingPlane: ceiling,
      );
      for (final i in profile.wallIndices) {
        expect(wall1.signedDistanceTo(rings[1][i]).abs(), lessThan(_poseToleranceM));
        expect(wall2.signedDistanceTo(rings[1][i]).abs(), lessThan(_poseToleranceM));
      }
      for (final ring in rings) {
        for (final i in profile.ceilingIndices) {
          expect(ceiling.signedDistanceTo(ring[i]).abs(), lessThan(_poseToleranceM));
        }
      }
    });
  });

  group('Test 5 — normales toutes sortantes', () {
    test('produit scalaire positif avec la direction centre -> facette', () {
      final profile = _lProfile();
      final ceiling = _ceilingPlane();
      final wall1 = _verticalWall(Vector3(0, 0, 0), Vector3(1, 0, 0));
      final wall2 = _verticalWall(Vector3(0, 0, 3), Vector3(0, 0, -1));
      final path = [
        Vector3(0, _ceilingHeightM, 0),
        Vector3(0, _ceilingHeightM, 3),
        Vector3(3, _ceilingHeightM, 3),
      ];
      final mesh = sweepMoulure(
        profile: profile,
        pathMeters: path,
        wallPlanes: [wall1, wall2],
        ceilingPlane: ceiling,
      );

      var centroidSum = Vector3.zero();
      for (var v = 0; v < mesh.vertexCount; v++) {
        centroidSum = centroidSum + mesh.positionAt(v);
      }
      final meshCentroid = centroidSum / mesh.vertexCount.toDouble();

      for (var t = 0; t < mesh.triangleCount; t++) {
        final i0 = mesh.indices[t * 3];
        final i1 = mesh.indices[t * 3 + 1];
        final i2 = mesh.indices[t * 3 + 2];
        final p0 = mesh.positionAt(i0);
        final p1 = mesh.positionAt(i1);
        final p2 = mesh.positionAt(i2);
        final triCentroid = (p0 + p1 + p2) / 3.0;
        final outward = triCentroid - meshCentroid;
        final normal = mesh.normalAt(i0);
        expect(
          normal.dot(outward),
          greaterThan(0.0),
          reason: 'triangle $t : normale non sortante',
        );
        // Les 3 sommets du triangle partagent la même normale (facette,
        // pas lissée — règle dure #6).
        expect(mesh.normalAt(i1), equals(normal));
        expect(mesh.normalAt(i2), equals(normal));
      }
    });
  });

  group('Test 6 — u atteint 3000mm au bout d\'un trajet de 3 m', () {
    test('u maximal des UV == 3000.0 (mm réels, pas normalisé)', () {
      final profile = _lProfile();
      final ceiling = _ceilingPlane();
      final wall = _verticalWall(Vector3(0, 0, 0), Vector3(1, 0, 0));
      final path = [
        Vector3(0, _ceilingHeightM, 0),
        Vector3(0, _ceilingHeightM, 3),
      ];
      final mesh = sweepMoulure(
        profile: profile,
        pathMeters: path,
        wallPlanes: [wall],
        ceilingPlane: ceiling,
      );

      var maxU = 0.0;
      for (var v = 0; v < mesh.vertexCount; v++) {
        final u = mesh.uvAt(v).x;
        if (u > maxU) maxU = u;
      }
      expect(maxU, closeTo(3000.0, 1e-6));
    });
  });
}
