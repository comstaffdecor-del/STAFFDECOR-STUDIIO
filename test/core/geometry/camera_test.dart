// Tests purs Dart (aucun widget, aucun import Flutter UI) pour
// lib/core/geometry/camera.dart.
//
// Convention rappelée (voir camera.dart) : repère monde main droite,
// X droite, Y haut, Z vers la caméra ; mètres ; origine au sol.
//
// Les cas synthétiques ci-dessous ont été pré-validés numériquement en
// Python/numpy (même formules : lookAt main droite, projection pinhole,
// intersection de droites, formule de focale de Caprile-Torre) avant
// d'être transcrits ici, pour garantir que les valeurs attendues sont
// mathématiquement correctes et non un artefact d'une éventuelle erreur
// de traduction Dart.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:staff_decor_studio/core/geometry/camera.dart';

/// Génère un échantillon gaussien N(0, sigma²) par la méthode de
/// Box-Muller — `dart:math`'s `Random` n'expose que des tirages uniformes.
double _gaussianSample(math.Random rng, double sigma) {
  final u1 = rng.nextDouble().clamp(1e-12, 1.0);
  final u2 = rng.nextDouble();
  final z0 = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  return z0 * sigma;
}

Vector2 _jitter(Vector2 p, math.Random rng, double sigma) {
  return Vector2(
    p.x + _gaussianSample(rng, sigma),
    p.y + _gaussianSample(rng, sigma),
  );
}

void main() {
  group('Camera3D.lookingAt — construction', () {
    test('lance une ArgumentError si eye == target', () {
      expect(
        () => Camera3D.lookingAt(
          eye: Vector3(1, 1, 1),
          target: Vector3(1, 1, 1),
          focalPx: 1000,
          principalPoint: Vector2(500, 500),
        ),
        throwsArgumentError,
      );
    });

    test('lance une ArgumentError si worldUp est colinéaire à la visée', () {
      expect(
        () => Camera3D.lookingAt(
          eye: Vector3(0, 5, 0),
          target: Vector3(0, 0, 0),
          worldUp: Vector3(0, 1, 0), // colinéaire à (eye-target)
          focalPx: 1000,
          principalPoint: Vector2(500, 500),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Camera3D.project — point 3D connu', () {
    // Caméra frontale simple, facile à vérifier à la main :
    // eye=(0,0,5), target=(0,0,0) => rotation = identité (right=(1,0,0),
    // up=(0,1,0), back=(0,0,1)).
    // Point (1,2,0) : p_cam = point - eye = (1,2,-5) ; depthCam = 5.
    // x_ndc = 1000*1/5 = 200 ; y_ndc = 1000*2/5 = 400.
    // pixel = (500+200, 500-400) = (700, 100).
    final camera = Camera3D.lookingAt(
      eye: Vector3(0, 0, 5),
      target: Vector3(0, 0, 0),
      focalPx: 1000,
      principalPoint: Vector2(500, 500),
    );

    test('projette un point connu au pixel attendu', () {
      final result = camera.project(Vector3(1, 2, 0));
      expect(result.pixel.x, closeTo(700, 1e-9));
      expect(result.pixel.y, closeTo(100, 1e-9));
      expect(result.depthCam, closeTo(5, 1e-9));
      expect(result.isInFrontOfCamera, isTrue);
    });

    test('un point derrière la caméra n\'est jamais NaN', () {
      final result = camera.project(Vector3(0, 0, 10)); // derrière eye
      expect(result.isInFrontOfCamera, isFalse);
      expect(result.pixel.x.isNaN, isFalse);
      expect(result.pixel.y.isNaN, isFalse);
      expect(result.depthCam.isNaN, isFalse);
    });
  });

  group('Camera3D.project — cube 1 m au sol, cohérence des arêtes', () {
    // Même caméra frontale que ci-dessus (rotation = identité).
    // Cube 1m x 1m x 1m posé au sol (y=0..1), x=0..1, z=-3..-2 (devant la
    // caméra, eye.z=5 => depthCam = 5-z > 0 pour z<5).
    //
    // Propriété vérifiable analytiquement pour CETTE caméra particulière
    // (rotation identité, visée selon -Z) : une arête verticale du cube
    // (x et z fixés, y variant de 0 à 1) a un p_cam.x et un depthCam
    // identiques en bas et en haut (aucun des deux ne dépend de y) donc
    // se projette en un pixel de même abscisse (arête verticale à l'écran,
    // pas de "gauchissement"). C'est le test de "cohérence des arêtes".
    final camera = Camera3D.lookingAt(
      eye: Vector3(0, 0, 5),
      target: Vector3(0, 0, 0),
      focalPx: 1000,
      principalPoint: Vector2(500, 500),
    );

    test('les 8 sommets sont tous devant la caméra', () {
      for (final x in [0.0, 1.0]) {
        for (final y in [0.0, 1.0]) {
          for (final z in [-3.0, -2.0]) {
            final r = camera.project(Vector3(x, y, z));
            expect(r.isInFrontOfCamera, isTrue);
            expect(r.pixel.x.isNaN, isFalse);
            expect(r.pixel.y.isNaN, isFalse);
          }
        }
      }
    });

    test('les arêtes verticales du cube restent verticales à l\'écran', () {
      for (final x in [0.0, 1.0]) {
        for (final z in [-3.0, -2.0]) {
          final bas = camera.project(Vector3(x, 0, z));
          final haut = camera.project(Vector3(x, 1, z));
          expect(
            bas.pixel.x,
            closeTo(haut.pixel.x, 1e-9),
            reason: 'arête verticale x=$x,z=$z devrait avoir un pixel.x '
                'constant entre bas et haut',
          );
          // Cohérence supplémentaire : le haut du cube (y plus grand,
          // Y monde vers le haut) doit apparaître plus haut à l'écran,
          // donc à un pixel.y plus PETIT (Y image vers le bas).
          expect(haut.pixel.y, lessThan(bas.pixel.y));
        }
      }
    });

    test('la face avant (z=-2, plus proche) est projetée plus grande '
        'que la face arrière (z=-3, plus loin)', () {
      final avantBasGauche = camera.project(Vector3(0, 0, -2));
      final avantBasDroite = camera.project(Vector3(1, 0, -2));
      final arriereBasGauche = camera.project(Vector3(0, 0, -3));
      final arriereBasDroite = camera.project(Vector3(1, 0, -3));

      final largeurAvant = (avantBasDroite.pixel.x - avantBasGauche.pixel.x).abs();
      final largeurArriere =
          (arriereBasDroite.pixel.x - arriereBasGauche.pixel.x).abs();

      expect(largeurAvant, greaterThan(largeurArriere));
    });
  });

  group('Camera3D.project — cube 1 m au sol, tangage réel (pitch 12°)', () {
    // Cas typique : photo prise en levant l'appareil vers le plafond
    // (pitch pur, sans yaw). Caméra à eye=(1.5,1.5,5.0), visée inclinée de
    // 12° vers le haut par rapport à l'horizontale -Z.
    // target = eye + 3*(0, sin(12°), -cos(12°)) — validé en Python :
    // target ≈ (1.5, 2.1237350698835788, 2.0655572005359816).
    //
    // Avec un pitch non nul, les arêtes verticales du cube NE restent PAS
    // verticales à l'écran (le test ci-dessus, avec pitch=0, montrait le
    // cas particulier où elles le restent — ce n'est PAS le cas général).
    // Elles doivent converger vers un unique point de fuite vertical
    // cohérent (même VP pour toutes les arêtes verticales, à la précision
    // flottante près) — validé en Python : les deux VP calculés à partir
    // de deux paires d'arêtes différentes coïncident à ~9e-11 près.
    final pitchRad = 12.0 * math.pi / 180.0;
    final eye = Vector3(1.5, 1.5, 5.0);
    final forward = Vector3(0, math.sin(pitchRad), -math.cos(pitchRad));
    final target = eye + forward * 3.0;
    final camera = Camera3D.lookingAt(
      eye: eye,
      target: target,
      focalPx: 1000.0,
      principalPoint: Vector2(500, 500),
    );

    // Cube 1m x=1..2, y=0..1, z=-3..-2 (devant la caméra après le pitch).
    final basGauche3 = Vector3(1.0, 0.0, -3.0);
    final hautGauche3 = Vector3(1.0, 1.0, -3.0);
    final basDroit3 = Vector3(2.0, 0.0, -3.0);
    final hautDroit3 = Vector3(2.0, 1.0, -3.0);
    final basGauche2 = Vector3(1.0, 0.0, -2.0);
    final hautGauche2 = Vector3(1.0, 1.0, -2.0);
    final basDroit2 = Vector3(2.0, 0.0, -2.0);
    final hautDroit2 = Vector3(2.0, 1.0, -2.0);

    test('les arêtes verticales du cube ne restent PAS verticales à '
        'l\'écran (dx significatif entre bas et haut)', () {
      for (final pair in [
        [basGauche3, hautGauche3],
        [basDroit3, hautDroit3],
        [basGauche2, hautGauche2],
        [basDroit2, hautDroit2],
      ]) {
        final bas = camera.project(pair[0]);
        final haut = camera.project(pair[1]);
        expect(bas.isInFrontOfCamera, isTrue);
        expect(haut.isInFrontOfCamera, isTrue);
        final dx = (haut.pixel.x - bas.pixel.x).abs();
        expect(
          dx,
          greaterThan(0.5),
          reason:
              'avec un pitch de 12°, l\'arête verticale $pair devrait '
              'converger perceptiblement (dx=$dx px, attendu > 0.5px) — '
              'si ce test passe avec dx≈0, le modèle de caméra ignore le '
              'pitch (bug), ce qui était précisément le risque signalé.',
        );
      }
    });

    test('les arêtes verticales convergent vers un unique point de fuite '
        'vertical cohérent', () {
      final pixBasG3 = camera.project(basGauche3).pixel;
      final pixHautG3 = camera.project(hautGauche3).pixel;
      final pixBasD3 = camera.project(basDroit3).pixel;
      final pixHautD3 = camera.project(hautDroit3).pixel;
      final pixBasG2 = camera.project(basGauche2).pixel;
      final pixHautG2 = camera.project(hautGauche2).pixel;
      final pixBasD2 = camera.project(basDroit2).pixel;
      final pixHautD2 = camera.project(hautDroit2).pixel;

      // VP vertical = intersection de deux arêtes verticales prolongées.
      final vpA = lineIntersect2D(pixBasG3, pixHautG3, pixBasD3, pixHautD3);
      final vpB = lineIntersect2D(pixBasG2, pixHautG2, pixBasD2, pixHautD2);

      expect(vpA, isNotNull,
          reason: 'un pitch non nul doit produire un VP vertical fini, '
              'pas des arêtes parallèles à l\'écran');
      expect(vpB, isNotNull);

      // Les deux VP calculés à partir de paires d'arêtes différentes
      // doivent coïncider (même point de fuite pour tout le cube) —
      // validé en Python à ~9e-11 ; tolérance large ici (1e-3) pour
      // absorber les différences d'implémentation flottante Dart/Python.
      expect((vpA! - vpB!).length, lessThan(1e-3),
          reason: 'VP vertical incohérent entre deux paires d\'arêtes : '
              'vpA=$vpA vpB=$vpB');

      // Le VP vertical attendu (calculé indépendamment en Python) :
      // environ (500, -4204.63) pour cette configuration précise
      // (eye=(1.5,1.5,5), pitch=12°, focal=1000, pp=(500,500)).
      expect(vpA.x, closeTo(500.0, 1e-2));
      expect(vpA.y, closeTo(-4204.63, 1.0));
    });

    test('tous les sommets du cube restent devant la caméra, sans NaN', () {
      for (final p in [
        basGauche3,
        hautGauche3,
        basDroit3,
        hautDroit3,
        basGauche2,
        hautGauche2,
        basDroit2,
        hautDroit2,
      ]) {
        final r = camera.project(p);
        expect(r.isInFrontOfCamera, isTrue);
        expect(r.pixel.x.isNaN, isFalse);
        expect(r.pixel.y.isNaN, isFalse);
      }
    });
  });

  group('Camera3D.project / unproject — reprojection aller-retour', () {
    // Caméra non-triviale (yaw + pitch), reprise du cas de calibration de
    // focale plus bas — validée numériquement en Python (diff ~1.7e-15).
    final camera = Camera3D.lookingAt(
      eye: Vector3(4.0, 2.2, 4.0),
      target: Vector3(1.5, 1.0, 0.0),
      focalPx: 1400.0,
      principalPoint: Vector2(960, 540), // centre d'une image 1920x1080
    );

    test('un point 3D projeté puis dé-projeté revient au même point '
        '(< 1e-6)', () {
      final original = Vector3(0.3, 1.7, -2.4);
      final proj = camera.project(original);
      expect(proj.isInFrontOfCamera, isTrue);

      final back = camera.unproject(proj.pixel, proj.depthCam);

      expect(back.x, closeTo(original.x, 1e-6));
      expect(back.y, closeTo(original.y, 1e-6));
      expect(back.z, closeTo(original.z, 1e-6));
    });

    test('reprojection aller-retour sur plusieurs points quelconques', () {
      final points = [
        Vector3(1.5, 1.25, -1.0),
        Vector3(0.0, 0.0, -5.0),
        Vector3(2.8, 2.4, -0.5),
        Vector3(-1.0, 3.0, -3.3),
      ];
      for (final p in points) {
        final proj = camera.project(p);
        if (!proj.isInFrontOfCamera) continue; // hors-champ, non pertinent
        final back = camera.unproject(proj.pixel, proj.depthCam);
        expect((back - p).length, lessThan(1e-6),
            reason: 'round-trip a échoué pour $p');
      }
    });
  });

  group('estimateFocalFromBackWallRectangle — cas synthétique connu', () {
    // Caméra placée délibérément avec yaw + pitch (sinon le mur du fond
    // est vu de face et on retombe sur le cas dégénéré — confirmé par le
    // test dédié plus bas). Rectangle mur du fond réel : 3m x 2.5m.
    // Focale réelle connue : 1400 px sur une image 1920x1080.
    // Validé en Python/numpy : f_est ≈ 1399.9999999999982 (erreur
    // ~1.3e-13 %), donc très largement sous la tolérance de 2% demandée.
    final camera = Camera3D.lookingAt(
      eye: Vector3(4.0, 2.2, 4.0),
      target: Vector3(1.5, 1.0, 0.0),
      focalPx: 1400.0,
      principalPoint: Vector2(960, 540),
    );

    const imageWidthPx = 1920.0;
    const imageHeightPx = 1080.0;

    test('retrouve la focale connue à moins de 2% d\'erreur', () {
      final ceilL = camera.project(Vector3(0, 2.5, 0));
      final ceilR = camera.project(Vector3(3, 2.5, 0));
      final floorL = camera.project(Vector3(0, 0, 0));
      final floorR = camera.project(Vector3(3, 0, 0));

      expect(ceilL.isInFrontOfCamera, isTrue);
      expect(ceilR.isInFrontOfCamera, isTrue);
      expect(floorL.isInFrontOfCamera, isTrue);
      expect(floorR.isInFrontOfCamera, isTrue);

      final result = estimateFocalFromBackWallRectangle(
        ceilL: ceilL.pixel,
        ceilR: ceilR.pixel,
        floorL: floorL.pixel,
        floorR: floorR.pixel,
        imageWidthPx: imageWidthPx,
        imageHeightPx: imageHeightPx,
      );

      expect(result.origine, FocaleOrigine.calculee);
      expect(result.focalPx.isNaN, isFalse);
      final erreurPct = (result.focalPx - 1400.0).abs() / 1400.0 * 100;
      expect(erreurPct, lessThan(2.0));
      expect(result.v1, isNotNull);
      expect(result.v2, isNotNull);
    });
  });

  group('estimateFocalFromBackWallRectangle — robustesse au bruit (clic '
      'utilisateur réel)', () {
    // Même caméra/rectangle que le test "cas synthétique connu" ci-dessus,
    // mais on rejoue l'estimation 200 fois avec un jitter gaussien de
    // sigma = 2px sur chacun des 4 coins (modélise l'imprécision d'un clic
    // au doigt sur un écran de téléphone). Validé au préalable en
    // Python/numpy (seed 42) : médiane ≈ 1.51%, écart-type ≈ 1.23%,
    // max observé ≈ 5.43% sur 200 tirages, tous valides (aucun cas
    // dégénéré déclenché par le bruit dans cette configuration).
    final camera = Camera3D.lookingAt(
      eye: Vector3(4.0, 2.2, 4.0),
      target: Vector3(1.5, 1.0, 0.0),
      focalPx: 1400.0,
      principalPoint: Vector2(960, 540),
    );
    const imageWidthPx = 1920.0;
    const imageHeightPx = 1080.0;
    const focalTrue = 1400.0;
    const sigmaPx = 2.0;
    const nTrials = 200;

    test(
      'sigma=2px, 200 tirages : médiane et écart-type de l\'erreur '
      'relative sur f (rapporté, pas de correction silencieuse si > 10%)',
      () {
        final ceilLClean = camera.project(Vector3(0, 2.5, 0)).pixel;
        final ceilRClean = camera.project(Vector3(3, 2.5, 0)).pixel;
        final floorLClean = camera.project(Vector3(0, 0, 0)).pixel;
        final floorRClean = camera.project(Vector3(3, 0, 0)).pixel;

        final rng = math.Random(42); // seed fixe : test reproductible
        final erreursRelatives = <double>[];
        var nDegenere = 0;

        for (var i = 0; i < nTrials; i++) {
          final result = estimateFocalFromBackWallRectangle(
            ceilL: _jitter(ceilLClean, rng, sigmaPx),
            ceilR: _jitter(ceilRClean, rng, sigmaPx),
            floorL: _jitter(floorLClean, rng, sigmaPx),
            floorR: _jitter(floorRClean, rng, sigmaPx),
            imageWidthPx: imageWidthPx,
            imageHeightPx: imageHeightPx,
          );

          expect(result.focalPx.isNaN, isFalse,
              reason: 'aucun NaN attendu, même en cas dégénéré (repli '
                  'explicite)');

          if (result.origine == FocaleOrigine.defaut) {
            nDegenere++;
            continue; // cas dégénéré déclenché par le bruit, hors stats
          }
          erreursRelatives.add(
            (result.focalPx - focalTrue).abs() / focalTrue,
          );
        }

        expect(erreursRelatives, isNotEmpty,
            reason: 'au moins quelques tirages doivent être non-dégénérés '
                'pour que la statistique ait un sens');

        erreursRelatives.sort();
        final n = erreursRelatives.length;
        final mediane = n.isOdd
            ? erreursRelatives[n ~/ 2]
            : (erreursRelatives[n ~/ 2 - 1] + erreursRelatives[n ~/ 2]) / 2;
        final moyenne = erreursRelatives.reduce((a, b) => a + b) / n;
        final variance = erreursRelatives
                .map((e) => (e - moyenne) * (e - moyenne))
                .reduce((a, b) => a + b) /
            n;
        final ecartType = math.sqrt(variance);

        // ignore: avoid_print
        print(
          '[robustesse focale] sigma=${sigmaPx}px, $nTrials tirages '
          '($nDegenere dégénérés exclus) -> '
          'médiane erreur relative = ${(mediane * 100).toStringAsFixed(2)}%, '
          'écart-type = ${(ecartType * 100).toStringAsFixed(2)}%, '
          'max = ${(erreursRelatives.last * 100).toStringAsFixed(2)}%',
        );

        // Constat, pas de "correction" : si la médiane dépasse 10%, ce test
        // échoue volontairement pour forcer une discussion (ajout d'une
        // contrainte EXIF ou saisie manuelle de la focale) plutôt qu'un
        // bricolage silencieux de la formule géométrique.
        expect(
          mediane,
          lessThan(0.10),
          reason:
              'Erreur médiane > 10% avec un jitter réaliste de clic (2px) : '
              'le calcul géométrique par 4 clics n\'est pas assez robuste '
              'seul dans ce cas. Ne pas corriger la formule — ajouter une '
              'contrainte externe (focale EXIF, cf. readFocalFromExif) '
              'comme le veut la priorité déjà en place dans resolveFocal().',
        );
      },
    );
  });

  group('estimateFocalFromBackWallRectangle — cas dégénéré', () {
    // Caméra strictement frontale au mur du fond (aucun yaw/pitch) :
    // les 4 côtés du rectangle restent parallèles à l'image, donc les
    // deux intersections de droites (v1 et v2) sont impossibles
    // (droites parallèles). Validé en Python : v1=None, v2=None.
    final camera = Camera3D.lookingAt(
      eye: Vector3(1.5, 1.25, 5.0),
      target: Vector3(1.5, 1.25, 0.0),
      focalPx: 1400.0,
      principalPoint: Vector2(960, 540),
    );

    const imageWidthPx = 1920.0;
    const imageHeightPx = 1080.0;

    test('retourne explicitement une focale par défaut, sans NaN', () {
      final ceilL = camera.project(Vector3(0, 2.5, 0));
      final ceilR = camera.project(Vector3(3, 2.5, 0));
      final floorL = camera.project(Vector3(0, 0, 0));
      final floorR = camera.project(Vector3(3, 0, 0));

      final result = estimateFocalFromBackWallRectangle(
        ceilL: ceilL.pixel,
        ceilR: ceilR.pixel,
        floorL: floorL.pixel,
        floorR: floorR.pixel,
        imageWidthPx: imageWidthPx,
        imageHeightPx: imageHeightPx,
      );

      expect(result.origine, FocaleOrigine.defaut);
      expect(result.v1, isNull);
      expect(result.v2, isNull);
      expect(result.focalPx.isNaN, isFalse);
      expect(
        result.focalPx,
        closeTo(defaultFocalPx35mmEquivalent(imageWidthPx), 1e-9),
      );
    });

    test('cas dégénéré via produit scalaire positif (v1/v2 existent mais '
        'orthogonalité invalide) : toujours pas de NaN', () {
      // Rectangle "impossible" (non issu d'une vraie perspective de mur)
      // construit à la main pour forcer un produit scalaire positif tout
      // en ayant des intersections de droites valides.
      final result = estimateFocalFromBackWallRectangle(
        ceilL: Vector2(700, 400),
        ceilR: Vector2(1200, 400),
        floorL: Vector2(700, 700),
        floorR: Vector2(1200, 900),
        imageWidthPx: imageWidthPx,
        imageHeightPx: imageHeightPx,
      );

      expect(result.focalPx.isNaN, isFalse);
      if (result.origine == FocaleOrigine.defaut) {
        expect(
          result.focalPx,
          closeTo(defaultFocalPx35mmEquivalent(imageWidthPx), 1e-9),
        );
      }
    });
  });

  group('defaultFocalPx35mmEquivalent', () {
    test('calcule la focale équivalent 35mm proportionnellement à la '
        'largeur image', () {
      // 35mm / 36mm (capteur plein format) * largeur image.
      expect(
        defaultFocalPx35mmEquivalent(1920),
        closeTo(1920 * 35.0 / 36.0, 1e-9),
      );
      expect(
        defaultFocalPx35mmEquivalent(3840),
        closeTo(3840 * 35.0 / 36.0, 1e-9),
      );
    });
  });

  group('lineIntersect2D', () {
    test('retourne null pour deux droites parallèles', () {
      final r = lineIntersect2D(
        Vector2(0, 0),
        Vector2(1, 0),
        Vector2(0, 1),
        Vector2(1, 1),
      );
      expect(r, isNull);
    });

    test('retourne l\'intersection exacte pour deux droites sécantes', () {
      final r = lineIntersect2D(
        Vector2(0, 0),
        Vector2(10, 10),
        Vector2(0, 10),
        Vector2(10, 0),
      );
      expect(r, isNotNull);
      expect(r!.x, closeTo(5, 1e-9));
      expect(r.y, closeTo(5, 1e-9));
    });
  });

  group('readFocalFromExif / resolveFocal — priorité EXIF sur le calcul '
      'géométrique', () {
    // Construit un TIFF minimal valide contenant uniquement les tags EXIF
    // FocalLength (RATIONAL) et FocalLengthIn35mmFilm (SHORT) — assez pour
    // exercer readFocalFromExif sans dépendre d'une vraie photo JPEG.
    Uint8List buildMinimalExifTiff({
      required int focalLengthIn35mmFilm,
      required int focalLengthNumerator,
      required int focalLengthDenominator,
    }) {
      final bytes = ByteData(64);
      var o = 0;
      void u16(int v) {
        bytes.setUint16(o, v, Endian.little);
        o += 2;
      }

      void u32(int v) {
        bytes.setUint32(o, v, Endian.little);
        o += 4;
      }

      // Header TIFF little-endian ('II'), magic 42, offset IFD0 = 8.
      bytes.setUint8(0, 0x49);
      bytes.setUint8(1, 0x49);
      o = 2;
      u16(42);
      u32(8);
      // IFD0 (offset 8) : 1 entrée -> ExifOffset (LONG) pointant vers 26.
      o = 8;
      u16(1);
      u16(0x8769);
      u16(4);
      u32(1);
      u32(26);
      u32(0); // next IFD = 0
      // EXIF IFD (offset 26) : FocalLength (RATIONAL, data à 56),
      // FocalLengthIn35mmFilm (SHORT, valeur inline).
      o = 26;
      u16(2);
      u16(0x920A);
      u16(5);
      u32(1);
      u32(56);
      u16(0xA405);
      u16(3);
      u32(1);
      u16(focalLengthIn35mmFilm);
      u16(0);
      u32(0); // next IFD = 0
      // Données RATIONAL à l'offset 56.
      o = 56;
      u32(focalLengthNumerator);
      u32(focalLengthDenominator);
      return bytes.buffer.asUint8List();
    }

    const imageWidthPx = 1920.0;
    const imageHeightPx = 1080.0;

    test('lit FocalLengthIn35mmFilm et le convertit correctement en '
        'pixels', () async {
      // FocalLengthIn35mmFilm = 28mm -> focalPx = 1920 * 28/36 = 1493.33...
      final blob = buildMinimalExifTiff(
        focalLengthIn35mmFilm: 28,
        focalLengthNumerator: 280,
        focalLengthDenominator: 10, // FocalLength réel = 28mm (non utilisé
        // ici puisque FocalLengthIn35mmFilm est prioritaire)
      );
      final result = await readFocalFromExif(
        blob,
        imageWidthPx: imageWidthPx,
        imageHeightPx: imageHeightPx,
      );
      expect(result, isNotNull);
      expect(result!.origine, FocaleOrigine.exif);
      expect(
        result.focalPx,
        closeTo(imageWidthPx * 28.0 / 36.0, 1e-6),
      );
    });

    test('retourne null si aucun tag EXIF exploitable n\'est présent '
        '(fichier non-image)', () async {
      final notAnImage = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);
      final result = await readFocalFromExif(
        notAnImage,
        imageWidthPx: imageWidthPx,
        imageHeightPx: imageHeightPx,
      );
      expect(result, isNull);
    });

    test('resolveFocal utilise l\'EXIF en priorité même si le calcul '
        'géométrique donnerait un résultat différent', () async {
      // Caméra du cas synthétique connu (focale réelle 1400px), mais on
      // fournit un EXIF qui affirme (à tort, pour le test) une focale
      // équivalent 35mm de 50mm -> focalPx_exif = 1920*50/36 = 2666.67,
      // très différent des ~1400px géométriques. resolveFocal DOIT
      // renvoyer la valeur EXIF, pas la valeur géométrique.
      final camera = Camera3D.lookingAt(
        eye: Vector3(4.0, 2.2, 4.0),
        target: Vector3(1.5, 1.0, 0.0),
        focalPx: 1400.0,
        principalPoint: Vector2(960, 540),
      );
      final ceilL = camera.project(Vector3(0, 2.5, 0)).pixel;
      final ceilR = camera.project(Vector3(3, 2.5, 0)).pixel;
      final floorL = camera.project(Vector3(0, 0, 0)).pixel;
      final floorR = camera.project(Vector3(3, 0, 0)).pixel;

      final exifBlob = buildMinimalExifTiff(
        focalLengthIn35mmFilm: 50,
        focalLengthNumerator: 500,
        focalLengthDenominator: 10,
      );

      final result = await resolveFocal(
        imageBytes: exifBlob,
        ceilL: ceilL,
        ceilR: ceilR,
        floorL: floorL,
        floorR: floorR,
        imageWidthPx: imageWidthPx,
        imageHeightPx: imageHeightPx,
      );

      expect(result.origine, FocaleOrigine.exif);
      expect(result.focalPx, closeTo(imageWidthPx * 50.0 / 36.0, 1e-6));
      // Bien différent de la focale géométrique (~1400px) : confirme que
      // c'est vraiment l'EXIF qui a été retenu, pas un hasard numérique.
      expect((result.focalPx - 1400.0).abs(), greaterThan(500));
    });

    test('resolveFocal retombe sur le calcul géométrique si imageBytes '
        'est null (pas de photo source disponible)', () async {
      final camera = Camera3D.lookingAt(
        eye: Vector3(4.0, 2.2, 4.0),
        target: Vector3(1.5, 1.0, 0.0),
        focalPx: 1400.0,
        principalPoint: Vector2(960, 540),
      );
      final ceilL = camera.project(Vector3(0, 2.5, 0)).pixel;
      final ceilR = camera.project(Vector3(3, 2.5, 0)).pixel;
      final floorL = camera.project(Vector3(0, 0, 0)).pixel;
      final floorR = camera.project(Vector3(3, 0, 0)).pixel;

      final result = await resolveFocal(
        imageBytes: null,
        ceilL: ceilL,
        ceilR: ceilR,
        floorL: floorL,
        floorR: floorR,
        imageWidthPx: imageWidthPx,
        imageHeightPx: imageHeightPx,
      );

      expect(result.origine, FocaleOrigine.calculee);
      final erreurPct = (result.focalPx - 1400.0).abs() / 1400.0 * 100;
      expect(erreurPct, lessThan(2.0));
    });
  });
}
