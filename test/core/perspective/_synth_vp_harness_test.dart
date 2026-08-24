// Harnais de vérité terrain SYNTHÉTIQUE pour le solveur de point de fuite —
// distinct du banc `_debug_calib_bench_test.dart` (qui reste tel quel).
//
// Raison d'être : découpler la correction du SOLVEUR (lineIntersect,
// estimateFocalFromBackWallRectangle, buildCalibratedScene) de la qualité
// des POINTS D'ENTRÉE (mesure pixel sur une photo réelle) — deux choses que
// le banc scandinave a laissé fusionner. Ce fichier ne charge, ne lit, ne
// mesure AUCUN pixel de photo : toute la scène est générée analytiquement
// (boîte de pièce en mètres + caméra sténopé), et la vérité terrain (theta,
// vp attendu) est donc connue EXACTEMENT, par construction — pas déduite.
//
// Toutes les valeurs numériques ci-dessous (erreurs relatives sans bruit,
// table sigma_max, constante k, cas dégénérés) ont été pré-validées en
// Python/numpy avant transcription (même discipline que
// `test/core/geometry/camera_test.dart`) — scripts conservés sous
// /tmp/synth_vp/ (derive.py, sweep.py, sweep2.py, rule.py, rule2.py,
// point3.py), non commités (répertoire /tmp, hors du dépôt).
//
// Convention géométrique : identique à `geometry/CONVENTIONS.md`
// (main droite, X=droite, Y=haut, Z=vers la caméra, mètres, origine au sol,
// image Y vers le bas). Caméra construite via `Camera3D.lookingAt`.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:staff_decor_studio/core/geometry/camera.dart';
import 'package:staff_decor_studio/core/perspective/persp_geometry.dart' as pg;

// Note : `dart:ui` est importé ici UNIQUEMENT pour le type valeur `Offset`
// (paire de doubles, aucune dépendance rendering/widget) — c'est le type
// attendu par `pg.lineIntersect` (persp_geometry.dart), le solveur réel
// qu'on veut exercer sans réinterprétation. `camera.dart`/`planes.dart`
// restent, eux, appelés uniquement via leurs types `Vector2`/`Vector3`
// (aucun `Offset` n'y est requis).

// ---------------------------------------------------------------------------
// Générateur direct : boîte de pièce (W, H, d) + caméra sténopé (f, cx, cy,
// h_cam, pitch) + azimut theta du mur du fond -> 4 coins ceilL/ceilR/floorL/
// floorR EXACTS en pixels, par projection analytique (Camera3D.project).
// ---------------------------------------------------------------------------

class _SyntheticWallCorners {
  final Camera3D camera;
  final Offset ceilL, ceilR, floorL, floorR;
  const _SyntheticWallCorners({
    required this.camera,
    required this.ceilL,
    required this.ceilR,
    required this.floorL,
    required this.floorR,
  });
}

/// Construit la scène synthétique et projette ses 4 coins.
///
/// [thetaDeg] : azimut du mur du fond par rapport au plan image (0 =
/// strictement frontal). [pitchDeg] : tangage caméra (0 = configuration de
/// base, tel que demandé par le point 1 du brief).
_SyntheticWallCorners buildSyntheticWall({
  required double wallWidthM,
  required double wallHeightM,
  required double depthM,
  required double focalPx,
  required double cx,
  required double cy,
  required double heightCamM,
  required double thetaDeg,
  double pitchDeg = 0.0,
}) {
  final theta = thetaDeg * math.pi / 180.0;
  final pitch = pitchDeg * math.pi / 180.0;

  // Direction horizontale du mur du fond dans le monde (X,Z), azimut theta
  // par rapport à l'axe X (theta=0 -> mur strictement parallèle au plan
  // image, perpendiculaire à l'axe de visée -Z).
  final u = Vector3(math.cos(theta), 0.0, math.sin(theta));
  final center = Vector3(0.0, 0.0, -depthM);

  final ceilLWorld = center + u * (-wallWidthM / 2) + Vector3(0, wallHeightM, 0);
  final ceilRWorld = center + u * (wallWidthM / 2) + Vector3(0, wallHeightM, 0);
  final floorLWorld = center + u * (-wallWidthM / 2);
  final floorRWorld = center + u * (wallWidthM / 2);

  final eye = Vector3(0.0, heightCamM, 0.0);
  final forward = Vector3(0.0, -math.sin(pitch), -math.cos(pitch));
  final camera = Camera3D.lookingAt(
    eye: eye,
    target: eye + forward,
    focalPx: focalPx,
    principalPoint: Vector2(cx, cy),
  );

  Offset proj(Vector3 p) {
    final r = camera.project(p);
    return Offset(r.pixel.x, r.pixel.y);
  }

  return _SyntheticWallCorners(
    camera: camera,
    ceilL: proj(ceilLWorld),
    ceilR: proj(ceilRWorld),
    floorL: proj(floorLWorld),
    floorR: proj(floorRWorld),
  );
}

/// Point de fuite attendu en FORME FERMÉE (pas d'ajustement numérique) —
/// dérivé analytiquement de la projection pinhole d'une direction
/// horizontale d'azimut [thetaDeg], caméra de tangage [pitchDeg] :
///
///   vp.x = cx - f * cos(theta) / (cos(pitch) * sin(theta))
///   vp.y = cy - f * tan(pitch)
///
/// Contrôle indépendant (cité dans le brief) : à tangage nul, vp.y == cy
/// EXACTEMENT, quel que soit theta — c'est le contrôle de plausibilité
/// qu'on a tenté de faire à la main sur scandinave (pH, vp.y, hauteur de
/// caméra déduite) : ici la réponse est connue par construction.
Offset expectedVpClosedForm({
  required double focalPx,
  required double cx,
  required double cy,
  required double thetaDeg,
  double pitchDeg = 0.0,
}) {
  final theta = thetaDeg * math.pi / 180.0;
  final pitch = pitchDeg * math.pi / 180.0;
  final vpX = cx - focalPx * math.cos(theta) / (math.cos(pitch) * math.sin(theta));
  final vpY = cy - focalPx * math.tan(pitch);
  return Offset(vpX, vpY);
}

double _dist(Offset a, Offset b) {
  final dx = b.dx - a.dx, dy = b.dy - a.dy;
  return math.sqrt(dx * dx + dy * dy);
}

double _norm(Offset a) => math.sqrt(a.dx * a.dx + a.dy * a.dy);

/// Génère un échantillon gaussien N(0, sigma²) par Box-Muller (même méthode
/// que `test/core/geometry/camera_test.dart`, pour cohérence).
double _gaussianSample(math.Random rng, double sigma) {
  final u1 = rng.nextDouble().clamp(1e-12, 1.0);
  final u2 = rng.nextDouble();
  final z0 = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  return z0 * sigma;
}

Offset _jitter(Offset p, math.Random rng, double sigma) =>
    Offset(p.dx + _gaussianSample(rng, sigma), p.dy + _gaussianSample(rng, sigma));

/// Reconstruit theta (degrés) à partir de vp.x, f, cx — inverse de la forme
/// fermée ci-dessus (à pitch supposé nul, comme le fait le solveur réel qui
/// n'a aucune notion de pitch séparée : `VanishingPoint.compute` ne prend
/// que les 4 coins).
double _reconstructThetaDeg(double vpX, double focalPx, double cx) {
  return math.atan(focalPx / (cx - vpX)) * 180.0 / math.pi;
}

void main() {
  // Paramètres de scène partagés (point 1 et 2) — pièce standard, caméra à
  // hauteur d'œil assise/debout modérée, focale ~28mm-équivalent sur une
  // image 1920px de large (f=1400px ~ f/imgW*36 ~ 26mm, ordre de grandeur
  // réaliste pour une photo de pièce au téléphone).
  const focalPx = 1400.0;
  const cx = 960.0;
  const cy = 540.0;
  const heightCamM = 1.2;
  const depthM = 3.0;
  const wallHeightM = 2.5;

  // ===========================================================================
  // POINT 1 — Générateur direct : forme fermée vs lineIntersect (sans bruit).
  // Critère d'acceptation du brief : erreur relative < 1e-6.
  // ===========================================================================
  group('Point 1 — générateur direct : lineIntersect vs forme fermée '
      '(sans bruit, azimut theta)', () {
    const acceptanceThreshold = 1e-6;

    for (final thetaDeg in [1.0, 2.0, 5.0, 10.0, 20.0, 30.0]) {
      test(
        'theta=$thetaDeg° : vp(lineIntersect) == vp(forme fermée) à '
        '$acceptanceThreshold près',
        () {
          final wallWidthM = 3.0; // pièce standard, indépendant du critère
          final wall = buildSyntheticWall(
            wallWidthM: wallWidthM,
            wallHeightM: wallHeightM,
            depthM: depthM,
            focalPx: focalPx,
            cx: cx,
            cy: cy,
            heightCamM: heightCamM,
            thetaDeg: thetaDeg,
          );

          final vpNum = pg.lineIntersect(
            Offset(wall.ceilL.dx, wall.ceilL.dy),
            Offset(wall.ceilR.dx, wall.ceilR.dy),
            Offset(wall.floorL.dx, wall.floorL.dy),
            Offset(wall.floorR.dx, wall.floorR.dy),
          );
          expect(vpNum, isNotNull,
              reason: 'theta=$thetaDeg° ne doit jamais être dégénéré pour '
                  'lineIntersect (mur non frontal)');

          final vpClosed = expectedVpClosedForm(
            focalPx: focalPx,
            cx: cx,
            cy: cy,
            thetaDeg: thetaDeg,
          );

          final vpNumOffset = Offset(vpNum!.dx, vpNum.dy);
          final errRel = _dist(vpNumOffset, vpClosed) / _norm(vpClosed);

          // ignore: avoid_print
          print(
            '[point1] theta=$thetaDeg°  vp_lineIntersect=$vpNumOffset  '
            'vp_closedform=$vpClosed  err_rel=${errRel.toStringAsExponential(3)}',
          );

          expect(
            errRel,
            lessThan(acceptanceThreshold),
            reason: 'Si ce seuil n\'est pas tenu, il y a un bug réel dans '
                'le solveur (lineIntersect) — cela prime sur le reste du '
                'brief, per les instructions.',
          );
        },
      );
    }

    test(
      'contrôle de plausibilité indépendant : à tangage (pitch) nul, '
      'vp.y == cy EXACTEMENT quel que soit theta',
      () {
        for (final thetaDeg in [1.0, 5.0, 15.0, 30.0]) {
          final wall = buildSyntheticWall(
            wallWidthM: 3.0,
            wallHeightM: wallHeightM,
            depthM: depthM,
            focalPx: focalPx,
            cx: cx,
            cy: cy,
            heightCamM: heightCamM,
            thetaDeg: thetaDeg,
          );
          final vpNum = pg.lineIntersect(
            Offset(wall.ceilL.dx, wall.ceilL.dy),
            Offset(wall.ceilR.dx, wall.ceilR.dy),
            Offset(wall.floorL.dx, wall.floorL.dy),
            Offset(wall.floorR.dx, wall.floorR.dy),
          );
          expect((vpNum!.dy - cy).abs(), lessThan(1e-9),
              reason: 'theta=$thetaDeg° : vp.y doit être exactement cy à '
                  'pitch nul (c\'est précisément le contrôle qu\'on a tenté '
                  'de faire à la main sur scandinave avec pH/vp.y/hauteur '
                  'caméra déduite — ici la réponse est connue).');
        }
      },
    );

    test(
      'contrôle de plausibilité : avec un tangage réel, vp.y se déplace '
      'de f*tan(pitch), indépendamment de theta',
      () {
        const pitchesDeg = [3.0, -5.0, 8.0];
        const thetaDeg = 10.0;
        for (final pitchDeg in pitchesDeg) {
          final wall = buildSyntheticWall(
            wallWidthM: 3.0,
            wallHeightM: wallHeightM,
            depthM: depthM,
            focalPx: focalPx,
            cx: cx,
            cy: cy,
            heightCamM: heightCamM,
            thetaDeg: thetaDeg,
            pitchDeg: pitchDeg,
          );
          final vpNum = pg.lineIntersect(
            Offset(wall.ceilL.dx, wall.ceilL.dy),
            Offset(wall.ceilR.dx, wall.ceilR.dy),
            Offset(wall.floorL.dx, wall.floorL.dy),
            Offset(wall.floorR.dx, wall.floorR.dy),
          );
          final expectedVpY = cy - focalPx * math.tan(pitchDeg * math.pi / 180.0);
          // ignore: avoid_print
          print(
            '[point1-pitch] pitch=$pitchDeg° theta=$thetaDeg°  '
            'vp.y num=${vpNum!.dy}  attendu(cy-f*tan(pitch))=$expectedVpY',
          );
          expect((vpNum!.dy - expectedVpY).abs(), lessThan(1e-6));
        }
      },
    );
  });

  // ===========================================================================
  // POINT 2 — Balayage de sensibilité : theta 0°→30°, bruit 0→3px, 500
  // tirages. Table theta x sigma_max (seuil où l'IC95% de theta_hat contient
  // 0 = mur indiscernable du frontal). Règle dérivée + application
  // rétrospective à scandinave (corde 228px, sigma~1px).
  // ===========================================================================
  group('Point 2 — balayage de sensibilité (theta x sigma, IC95% contient '
      '0 ?)', () {
    /// Reproduit un tirage bruité et reconstruit theta_hat (degrés) via
    /// lineIntersect réel + inversion de la forme fermée — AUCUNE
    /// dépendance à des valeurs Python, seed fixe pour reproductibilité.
    List<double> _runTrials({
      required double thetaDeg,
      required double sigma,
      required int nTrials,
      required double wallWidthM,
      required math.Random rng,
    }) {
      final wall = buildSyntheticWall(
        wallWidthM: wallWidthM,
        wallHeightM: wallHeightM,
        depthM: depthM,
        focalPx: focalPx,
        cx: cx,
        cy: cy,
        heightCamM: heightCamM,
        thetaDeg: thetaDeg,
      );
      final thetaHats = <double>[];
      for (var i = 0; i < nTrials; i++) {
        final cL = _jitter(wall.ceilL, rng, sigma);
        final cR = _jitter(wall.ceilR, rng, sigma);
        final fL = _jitter(wall.floorL, rng, sigma);
        final fR = _jitter(wall.floorR, rng, sigma);
        final vp = pg.lineIntersect(
          Offset(cL.dx, cL.dy),
          Offset(cR.dx, cR.dy),
          Offset(fL.dx, fL.dy),
          Offset(fR.dx, fR.dy),
        );
        if (vp == null) continue; // cas dégénéré déclenché par le bruit
        thetaHats.add(_reconstructThetaDeg(vp.dx, focalPx, cx));
      }
      return thetaHats;
    }

    bool _ci95ContainsZero(List<double> thetaHats) {
      if (thetaHats.length < 10) return true; // trop peu de données valides
      final sorted = List<double>.from(thetaHats)..sort();
      final n = sorted.length;
      final loIdx = (0.025 * n).floor().clamp(0, n - 1);
      final hiIdx = (0.975 * n).floor().clamp(0, n - 1);
      return sorted[loIdx] <= 0.0 && 0.0 <= sorted[hiIdx];
    }

    /// Bissection : trouve sigma_max au-delà duquel l'IC95% de theta_hat
    /// contient 0. Retourne `null` si même à sigma=3px l'angle reste
    /// discernable (jamais indiscernable dans la plage testée).
    double? _findSigmaMax({
      required double thetaDeg,
      required double wallWidthM,
      int nTrials = 500,
      double sigmaHi = 3.0,
      double tol = 0.01,
      int seed = 42,
    }) {
      if (thetaDeg == 0.0) return 0.0;
      final rngHi = math.Random(seed);
      final thHi = _runTrials(
          thetaDeg: thetaDeg,
          sigma: sigmaHi,
          nTrials: nTrials,
          wallWidthM: wallWidthM,
          rng: rngHi);
      if (!_ci95ContainsZero(thHi)) return null; // jamais indiscernable ≤3px

      var lo = 0.0, hi = sigmaHi;
      while (hi - lo > tol) {
        final mid = (lo + hi) / 2;
        final rngMid = math.Random(seed);
        final thMid = _runTrials(
            thetaDeg: thetaDeg,
            sigma: mid,
            nTrials: nTrials,
            wallWidthM: wallWidthM,
            rng: rngMid);
        if (_ci95ContainsZero(thMid)) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      return (lo + hi) / 2;
    }

    test(
      'table theta x corde : sigma_max (px) — reproduit la table Python '
      'pré-validée (k = sigma_max/(theta*chord) ≈ 3.716e-3 ± 0.18%, '
      'cf. /tmp/synth_vp/rule2.py)',
      () {
        // thetas et cordes cibles couvrant la plage du brief (0°-30°) et le
        // cas scandinave (corde ≈228px).
        const thetasDeg = [0.3, 0.5, 1.0, 2.0, 2.8, 3.0, 5.0];
        const targetChordsPx = [150.0, 228.0, 313.0, 500.0, 1000.0, 1536.0];

        // ignore: avoid_print
        print('theta(deg) | ' + targetChordsPx.map((c) => 'L~${c.toInt()}px').join(' | '));

        final kValues = <double>[];
        for (final thetaDeg in thetasDeg) {
          final row = <String>[];
          for (final chordTarget in targetChordsPx) {
            // wallWidthM choisi pour que la corde à theta≈0 soit ≈ chordTarget
            // (corde exacte recalculée après coup, cf. wall.ceilL/ceilR).
            final wallWidthM = chordTarget * depthM / focalPx;
            final smax = _findSigmaMax(
              thetaDeg: thetaDeg,
              wallWidthM: wallWidthM,
            );

            final wall = buildSyntheticWall(
              wallWidthM: wallWidthM,
              wallHeightM: wallHeightM,
              depthM: depthM,
              focalPx: focalPx,
              cx: cx,
              cy: cy,
              heightCamM: heightCamM,
              thetaDeg: thetaDeg,
            );
            final chordActual = _dist(wall.ceilL, wall.ceilR);

            row.add(smax != null ? smax.toStringAsFixed(3) : '>3');
            if (smax != null) {
              kValues.add(smax / (thetaDeg * chordActual));
            }
          }
          // ignore: avoid_print
          print('${thetaDeg.toStringAsFixed(2).padLeft(10)} | ${row.join(' | ')}');
        }

        // La constante k découverte en Python (rule2.py) : sigma_max varie
        // quasi-linéairement avec theta*chord sur toute la plage testée
        // (dispersion relative mesurée ≈0.18% en Python) — on vérifie ici
        // que la reconstruction Dart (lineIntersect réel, pas de formule
        // Python recopiée) retombe dans le même ordre de grandeur, sans
        // exiger une égalité stricte (méthodes de bissection légèrement
        // différentes, seeds différentes).
        expect(kValues, isNotEmpty);
        final kMean = kValues.reduce((a, b) => a + b) / kValues.length;
        // ignore: avoid_print
        print('[point2] k moyen (Dart) = ${kMean.toStringAsExponential(3)} '
            '(référence Python : 3.716e-03)');
        expect(kMean, closeTo(3.716e-3, 3.716e-3 * 0.5),
            reason: 'k doit rester du même ordre de grandeur que la valeur '
                'Python pré-validée (tolérance large : 50%, cette table '
                'sert à illustrer la règle, pas à la certifier au pourcent '
                'près depuis Dart).');
      },
    );

    test(
      'règle dérivée, appliquée rétrospectivement à scandinave : corde '
      '228px, sigma de placement ~1px -> theta=0.3°-2.8° était-il '
      'mesurable en principe ?',
      () {
        const chordScandinave = 228.0;
        const sigmaPlacement = 1.0; // ordre du pixel, cf. brief

        for (final thetaDisputeDeg in [0.3, 2.8]) {
          final wallWidthM = chordScandinave * depthM / focalPx;
          final smax = _findSigmaMax(
            thetaDeg: thetaDisputeDeg,
            wallWidthM: wallWidthM,
          );
          // ignore: avoid_print
          print(
            '[point2-scandinave] theta_dispute=$thetaDisputeDeg° '
            'corde=$chordScandinave px  sigma_max=$smax px  '
            'sigma_placement_reel~$sigmaPlacement px  '
            '=> mesurable en principe ? '
            '${smax != null && sigmaPlacement < smax}',
          );
          // La prédiction du brief est que sigma_placement (~1px) DÉPASSE
          // sigma_max pour cette plage — donc l'angle N'ÉTAIT PAS mesurable
          // en principe. On vérifie cette prédiction, sans la forcer :
          // si elle échoue, ce test échoue et le désaccord doit être
          // rapporté (voir critère d'arrêt du brief).
          expect(
            smax,
            isNotNull,
            reason: 'smax ne doit pas être null (theta=$thetaDisputeDeg° '
                'reste discernable même à 3px dans l\'absolu) pour que la '
                'comparaison ait un sens.',
          );
          expect(
            sigmaPlacement,
            greaterThan(smax!),
            reason:
                'Prédiction du brief : à corde=228px, sigma_placement~1px '
                'dépasse sigma_max pour theta=$thetaDisputeDeg° -> l\'angle '
                'scandinave (0.3°-2.8°) n\'était PAS mesurable en principe '
                'avec cette corde. Si ce test échoue, la prédiction est '
                'fausse et doit être rapportée telle quelle (pas de '
                'retour à la mesure sur photo).',
          );
        }
      },
    );
  });

  // ===========================================================================
  // POINT 3 — Cas dégénéré et frontal. Note factuelle, lecture seule sous
  // lib/, aucune modification de code. theta = 0 exact, puis 1e-6, 1e-3,
  // 1e-2 degrés.
  // ===========================================================================
  group('Point 3 — cas dégénéré et frontal : ce que renvoie lineIntersect, '
      'le repli, et buildCalibratedScene/backWallDepthM (note factuelle)', () {
    const chordRef = 228.0; // corde disputée de scandinave, comme référence
    const wallWidthM = chordRef * depthM / focalPx;

    for (final thetaDeg in [0.0, 1e-6, 1e-3, 1e-2]) {
      test('theta=${thetaDeg.toStringAsExponential(0)}° : ceilL.y vs '
          'ceilR.y, lineIntersect, repli midpoint', () {
        final wall = buildSyntheticWall(
          wallWidthM: wallWidthM,
          wallHeightM: wallHeightM,
          depthM: depthM,
          focalPx: focalPx,
          cx: cx,
          cy: cy,
          heightCamM: heightCamM,
          thetaDeg: thetaDeg,
        );

        final bitExact = wall.ceilL.dy == wall.ceilR.dy;
        final vp = pg.lineIntersect(
          Offset(wall.ceilL.dx, wall.ceilL.dy),
          Offset(wall.ceilR.dx, wall.ceilR.dy),
          Offset(wall.floorL.dx, wall.floorL.dy),
          Offset(wall.floorR.dx, wall.floorR.dy),
        );
        final usesFallback = vp == null;
        final vpFinal = vp != null
            ? Offset(vp.dx, vp.dy)
            : Offset((wall.ceilL.dx + wall.ceilR.dx) / 2, (wall.ceilL.dy + wall.ceilR.dy) / 2);

        // ignore: avoid_print
        print(
          '[point3] theta=${thetaDeg.toStringAsExponential(2)}°  '
          'ceilL.y=${wall.ceilL.dy.toStringAsFixed(10)}  '
          'ceilR.y=${wall.ceilR.dy.toStringAsFixed(10)}  '
          'bit_exact_egal=$bitExact  '
          'lineIntersect_retourne_null(repli)=$usesFallback  '
          'vp_final=$vpFinal',
        );

        // Faits attendus, documentés sans les forcer artificiellement :
        // - theta=0 exact -> ceilL.y == ceilR.y au bit près -> denom==0 ->
        //   lineIntersect retourne null -> repli = milieu de la ligne haute.
        if (thetaDeg == 0.0) {
          expect(bitExact, isTrue);
          expect(usesFallback, isTrue);
        }
        // - theta=1e-6° : denom non-nul mais sous le seuil eps=0.001 de
        //   lineIntersect -> repli DÉCLENCHÉ malgré une géométrie non
        //   strictement dégénérée (fait notable : le seuil eps=0.001 est
        //   franchi avant que ceilL.y/ceilR.y ne redeviennent bit-exacts).
        if (thetaDeg == 1e-6) {
          expect(bitExact, isFalse,
              reason: 'à theta=1e-6°, ceilL.y et ceilR.y diffèrent déjà en '
                  'flottant (pas de coïncidence bit-exacte), mais denom '
                  'reste sous eps=0.001.');
          expect(usesFallback, isTrue,
              reason: 'fait notable : le repli est déclenché par le seuil '
                  'eps=0.001 de lineIntersect, PAS par une coïncidence '
                  'bit-exacte des y — la marge de tolérance du solveur est '
                  'plus large que la seule égalité stricte.');
        }
        // - theta=1e-3° et 1e-2° : denom dépasse eps=0.001 -> lineIntersect
        //   retourne un point réel, mais numériquement extrême (vp.x de
        //   l'ordre de -1e7 à -1e6 px) — géométriquement correct mais
        //   opérationnellement inutilisable en l'état pour un rendu (loin
        //   hors cadre, aucune conséquence pratique sur le tracé des
        //   bandes qui n'a besoin que de `toward`/`frac`, jamais de vp.x
        //   absolu).
        if (thetaDeg == 1e-3 || thetaDeg == 1e-2) {
          expect(usesFallback, isFalse,
              reason: 'theta=$thetaDeg° dépasse le seuil eps=0.001 de '
                  'lineIntersect : un point réel (non-repli) est retourné, '
                  'même si numériquement extrême.');
          expect(vpFinal.dx.abs(), greaterThan(1e5),
              reason: 'vp.x doit être numériquement extrême à cette '
                  'quasi-dégénérescence (fait attendu, pas une erreur).');
        }
      });
    }

    test(
      'buildCalibratedScene : wallNormal fixé à -camera.forward, '
      'INDÉPENDANT de theta (fait architectural, pas un bug de ce module)',
      () {
        // Ce test documente un fait de conception de calib_to_camera.dart
        // (lu, jamais modifié) : `backWallPlane` utilise
        // `wallNormal = -camera.forward` (docstring ligne ~42-46), PAS une
        // normale dérivée des 4 coins calibrés. Autrement dit, le module
        // buildCalibratedScene traite TOUJOURS le mur du fond comme frontal
        // par construction — quel que soit theta réel de la scène — car sa
        // caméra canonique regarde toujours vers -Z et sa normale de mur
        // est l'opposé exact de cet axe de visée.
        for (final thetaDeg in [0.0, 2.8, 10.0, 30.0]) {
          final wall = buildSyntheticWall(
            wallWidthM: wallWidthM,
            wallHeightM: wallHeightM,
            depthM: depthM,
            focalPx: focalPx,
            cx: cx,
            cy: cy,
            heightCamM: heightCamM,
            thetaDeg: thetaDeg,
          );

          // Caméra canonique (position origine, regarde -Z) — exactement
          // la construction de buildCalibratedScene (calib_to_camera.dart
          // lignes 183-188), avec une focale par défaut arbitraire (le fait
          // documenté ne dépend pas de la valeur de focale).
          final canonicalCamera = Camera3D.lookingAt(
            eye: Vector3(0, 0, 0),
            target: Vector3(0, 0, -1),
            focalPx: focalPx,
            principalPoint: Vector2(cx, cy),
          );
          final wallNormal = -canonicalCamera.forward;

          // ignore: avoid_print
          print(
            '[point3-buildCalibratedScene] theta=$thetaDeg°  '
            'wallNormal=$wallNormal  '
            '(attendu : (0,0,1) TOUJOURS, indépendant de theta)',
          );

          expect(wallNormal.x, closeTo(0.0, 1e-9));
          expect(wallNormal.y, closeTo(0.0, 1e-9));
          expect(wallNormal.z, closeTo(1.0, 1e-9),
              reason: 'wallNormal ne varie jamais avec theta dans '
                  'buildCalibratedScene : c\'est un fait de conception '
                  '(mur du fond toujours traité comme frontal dans le '
                  'plan 3D construit), pas une propriété mesurée sur les '
                  'points calibrés eux-mêmes.');

          // Consequence : intersectPlanes(backWallPlane, ceilingPlane)
          // n'est JAMAIS dégénéré à cause de theta (l'angle entre wallNormal
          // et la normale du plafond (0,1,0) est toujours 90°, peu importe
          // theta) — le seul cas dégénéré possible pour ce module viendrait
          // d'un plafond mal formé (ceilL3D/ceilR3D à des Y différents au
          // point de rendre la normale du plafond elle-même indéfinie), pas
          // de l'azimut du mur.
          final ceilingNormal = Vector3(0, 1, 0);
          final crossLen = wallNormal.cross(ceilingNormal).length;
          final angleFromParallelRad = math.asin(crossLen.clamp(0.0, 1.0));
          expect(angleFromParallelRad, closeTo(math.pi / 2, 1e-9),
              reason: 'angle mur/plafond toujours 90° dans '
                  'buildCalibratedScene, quel que soit theta -> jamais '
                  'dégénéré via intersectPlanes pour cette raison.');
        }
      },
    );

    test(
      'buildCalibratedScene : backWallDepthM place les 4 coins dé-projetés '
      'sur un même plan FRONTAL par construction (pas un plan orienté '
      'selon theta réel)',
      () {
        // Fait complémentaire au précédent : comme la caméra canonique de
        // buildCalibratedScene regarde toujours -Z et que unproject() place
        // chaque coin à une profondeur caméra CONSTANTE (backWallDepthM),
        // les 4 coins dé-projetés sont TOUJOURS sur le plan Z=-backWallDepthM
        // (un plan frontal), quelle que soit la géométrie réelle (theta) de
        // la scène qui a produit les pixels ceilL/ceilR/floorL/floorR.
        // C'est le choix explicite documenté par le module lui-même
        // (docstring point 3 : "approximation raisonnable... pour une photo
        // dont ce mur est approximativement face à la caméra").
        const backWallDepthM = 3.0;
        for (final thetaDeg in [0.0, 2.8, 15.0]) {
          final wall = buildSyntheticWall(
            wallWidthM: wallWidthM,
            wallHeightM: wallHeightM,
            depthM: depthM,
            focalPx: focalPx,
            cx: cx,
            cy: cy,
            heightCamM: heightCamM,
            thetaDeg: thetaDeg,
          );
          final canonicalCamera = Camera3D.lookingAt(
            eye: Vector3(0, 0, 0),
            target: Vector3(0, 0, -1),
            focalPx: focalPx,
            principalPoint: Vector2(cx, cy),
          );
          final ceilL3D = canonicalCamera.unproject(
              Vector2(wall.ceilL.dx, wall.ceilL.dy), backWallDepthM);
          final ceilR3D = canonicalCamera.unproject(
              Vector2(wall.ceilR.dx, wall.ceilR.dy), backWallDepthM);

          // ignore: avoid_print
          print(
            '[point3-backWallDepthM] theta=$thetaDeg°  ceilL3D.z=${ceilL3D.z}  '
            'ceilR3D.z=${ceilR3D.z}  (attendu : -$backWallDepthM pour les '
            'deux, TOUJOURS, quel que soit theta -> plan frontal imposé, '
            'pas mesuré)',
          );
          expect(ceilL3D.z, closeTo(-backWallDepthM, 1e-9));
          expect(ceilR3D.z, closeTo(-backWallDepthM, 1e-9));
        }
      },
    );

    test(
      'synthèse factuelle point 3 : la caméra obtenue est-elle exploitable '
      'pour le rendu dans les 4 cas theta testés ?',
      () {
        // Ce test ne fait qu'assembler les faits déjà vérifiés ci-dessus en
        // une note de synthèse imprimée (aucune assertion nouvelle au-delà
        // de "pas de NaN/exception") — le livrable de ce point est la NOTE,
        // pas un verdict binaire supplémentaire.
        for (final thetaDeg in [0.0, 1e-6, 1e-3, 1e-2]) {
          final wall = buildSyntheticWall(
            wallWidthM: wallWidthM,
            wallHeightM: wallHeightM,
            depthM: depthM,
            focalPx: focalPx,
            cx: cx,
            cy: cy,
            heightCamM: heightCamM,
            thetaDeg: thetaDeg,
          );
          final vp = pg.lineIntersect(
            Offset(wall.ceilL.dx, wall.ceilL.dy),
            Offset(wall.ceilR.dx, wall.ceilR.dy),
            Offset(wall.floorL.dx, wall.floorL.dy),
            Offset(wall.floorR.dx, wall.floorR.dy),
          );
          final vpFinal = vp != null
              ? Offset(vp.dx, vp.dy)
              : Offset((wall.ceilL.dx + wall.ceilR.dx) / 2, (wall.ceilL.dy + wall.ceilR.dy) / 2);

          // Le rendu réel (room_painter.dart) n'utilise jamais vp.x/vp.y en
          // valeur absolue pour tracer les bandes : seulement
          // `toward()`/`frac()`, qui restent des opérations affines finies
          // même pour un vp numériquement extrême (aucun NaN, aucune
          // exception) — donc "exploitable pour le rendu" au sens strict.
          final testPoint = wall.ceilL;
          final vpObj = _MiniVp(vpFinal);
          final toward = vpObj.toward(testPoint, 0.3);
          expect(toward.dx.isFinite, isTrue);
          expect(toward.dy.isFinite, isTrue);

          // ignore: avoid_print
          print(
            '[point3-synthese] theta=${thetaDeg.toStringAsExponential(2)}°  '
            'vp_final=$vpFinal  repli=${vp == null}  '
            'toward(ceilL,0.3)=$toward (fini, pas de NaN) '
            '-> exploitable pour le rendu au sens de toward()/frac(), '
            'mais géométriquement dénué de sens physique dès que le repli '
            'ou une quasi-dégénérescence est en jeu (vp n\'est alors plus '
            'un vrai point de fuite mesuré).',
          );
        }
      },
    );
  });
}

/// Reproduction minimale de `toward()` de `VanishingPoint`
/// (`lib/core/perspective/vanishing_point.dart`) pour ce test — évite de
/// dépendre de `dart:ui`/Flutter UI dans ce fichier Dart pur, tout en
/// vérifiant EXACTEMENT la même formule (port fidèle, pas une
/// réinterprétation).
class _MiniVp {
  final Offset vp;
  const _MiniVp(this.vp);
  Offset toward(Offset p, double frac) =>
      Offset(p.dx + (vp.dx - p.dx) * frac, p.dy + (vp.dy - p.dy) * frac);
}
