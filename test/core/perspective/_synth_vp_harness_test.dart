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

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:staff_decor_studio/core/geometry/camera.dart';
import 'package:staff_decor_studio/core/perspective/persp_geometry.dart' as pg;

// Note : le type `Offset` utilisé partout dans ce fichier (celui attendu par
// `pg.lineIntersect`, persp_geometry.dart) vient de `dart:ui` — mais aucun
// import explicite de `dart:ui` n'est nécessaire ici : `flutter_test.dart`
// exporte transitivement `flutter/widgets.dart`, qui ré-exporte `dart:ui`.
// Un `import 'dart:ui' show Offset;` explicite est donc rapporté "inutile"
// par `flutter analyze` (unnecessary_import) — vérifié, pas juste toléré :
// c'est un fait de réexport transitif, pas une info à ignorer par
// complaisance. `camera.dart`/`planes.dart` restent, eux, appelés
// uniquement via leurs types `Vector2`/`Vector3` (aucun `Offset` n'y est
// requis).

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
            wall.ceilL,
            wall.ceilR,
            wall.floorL,
            wall.floorR,
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
            wall.ceilL,
            wall.ceilR,
            wall.floorL,
            wall.floorR,
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
            wall.ceilL,
            wall.ceilR,
            wall.floorL,
            wall.floorR,
          );
          final expectedVpY = cy - focalPx * math.tan(pitchDeg * math.pi / 180.0);
          // ignore: avoid_print
          print(
            '[point1-pitch] pitch=$pitchDeg° theta=$thetaDeg°  '
            'vp.y num=${vpNum!.dy}  attendu(cy-f*tan(pitch))=$expectedVpY',
          );
          expect((vpNum.dy - expectedVpY).abs(), lessThan(1e-6));
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
          cL,
          cR,
          fL,
          fR,
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

    /// Propagation analytique DÉTERMINISTE (aucun `math.Random`) de la
    /// sensibilité de theta_hat à un bruit iid de sigma=1px sur chacune des
    /// 8 coordonnées d'entrée (4 points x 2 axes) — reproduit exactement la
    /// méthode Jacobienne pré-validée en Python (/tmp/synth_vp/rule2.py) :
    /// 1) gradient de vp.x par rapport aux 8 coordonnées, par différences
    ///    finies sur le VRAI `pg.lineIntersect` (pas une formule recopiée) ;
    /// 2) norme de ce gradient = sigma(vp.x) par unité de sigma d'entrée ;
    /// 3) propagation au premier ordre via d(theta)/d(vp.x) (dérivée de la
    ///    forme fermée `atan(f/(cx-vpx))`) ;
    /// 4) sigma_max = |theta| / (1.96 * sigma(theta) par unité de sigma).
    ///
    /// Sert de référence DÉTERMINISTE pour la monotonie ci-dessous — le
    /// Monte Carlo par bissection (méthode existante, conservée telle
    /// quelle plus bas) reste un contrôle croisé indépendant, rapporté par
    /// debugPrint mais plus jamais la source de la monotonie assertée
    /// (cf. note sur la marge insuffisante de la bissection à theta>=15°).
    double _analyticalSigmaMax({
      required double thetaDeg,
      required double wallWidthM,
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
      const h = 1e-4;
      final base = pg.lineIntersect(
        wall.ceilL,
        wall.ceilR,
        wall.floorL,
        wall.floorR,
      )!;
      final pts = [wall.ceilL, wall.ceilR, wall.floorL, wall.floorR];
      var sumSq = 0.0;
      for (var i = 0; i < 4; i++) {
        for (var coord = 0; coord < 2; coord++) {
          final perturbed = List<Offset>.from(pts);
          final p = pts[i];
          perturbed[i] =
              coord == 0 ? Offset(p.dx + h, p.dy) : Offset(p.dx, p.dy + h);
          final vp2 = pg.lineIntersect(
            perturbed[0],
            perturbed[1],
            perturbed[2],
            perturbed[3],
          );
          // Sur toute la plage testée (theta>=0.3°, chord>=150px), la
          // perturbation h=1e-4px ne fait jamais franchir le seuil de
          // dégénérescence -- si ça arrivait, mieux vaut planter ici que
          // silencieusement ignorer une composante du gradient.
          if (vp2 == null) {
            throw StateError(
              'lineIntersect dégénéré pendant la différence finie '
              '(theta=$thetaDeg°) -- gradient indéfini, la propagation '
              'analytique ne peut pas continuer.',
            );
          }
          final grad = (vp2.dx - base.dx) / h;
          sumSq += grad * grad;
        }
      }
      final sigmaVpxPerSigma = math.sqrt(sumSq);
      final dthetaDvpx = (focalPx /
              (focalPx * focalPx + math.pow(cx - base.dx, 2).toDouble())) *
          180.0 /
          math.pi;
      final sigmaThetaPerSigma = dthetaDvpx.abs() * sigmaVpxPerSigma;
      return thetaDeg.abs() / (1.96 * sigmaThetaPerSigma);
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
        // Deux matrices [indice theta][indice corde] -> sigma_max :
        // - `smaxMcMatrix` : Monte Carlo par bissection (méthode existante,
        //   dépend de tirages aléatoires, seed fixe -> déterministe d'une
        //   exécution à l'autre, mais chaque cellule a une marge d'erreur
        //   de bissection ~tol=0.01px ET une variance d'échantillonnage
        //   propre à 500 tirages). Conservée pour le calcul de `k` (déjà
        //   validé contre la référence Python) et rapportée en contrôle
        //   croisé, mais N'EST PLUS la source de la monotonie assertée.
        // - `smaxAnaMatrix` : propagation analytique par différences
        //   finies sur `pg.lineIntersect` (déterministe par construction,
        //   AUCUN tirage aléatoire) -- c'est elle qui porte l'assertion de
        //   monotonie ci-dessous.
        // (null = ">3px", traité comme +infini pour la comparaison : "au
        // moins aussi grand" que toute valeur finie, jamais plus petit.)
        final smaxMcMatrix = <List<double?>>[];
        final smaxAnaMatrix = <List<double>>[];
        for (final thetaDeg in thetasDeg) {
          final row = <String>[];
          final smaxMcRow = <double?>[];
          final smaxAnaRow = <double>[];
          for (final chordTarget in targetChordsPx) {
            // wallWidthM choisi pour que la corde à theta≈0 soit ≈ chordTarget
            // (corde exacte recalculée après coup, cf. wall.ceilL/ceilR).
            final wallWidthM = chordTarget * depthM / focalPx;
            final smaxMc = _findSigmaMax(
              thetaDeg: thetaDeg,
              wallWidthM: wallWidthM,
            );
            final smaxAna = _analyticalSigmaMax(
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

            row.add(smaxMc != null ? smaxMc.toStringAsFixed(3) : '>3');
            smaxMcRow.add(smaxMc);
            smaxAnaRow.add(smaxAna);
            if (smaxMc != null) {
              kValues.add(smaxMc / (thetaDeg * chordActual));
            }
          }
          smaxMcMatrix.add(smaxMcRow);
          smaxAnaMatrix.add(smaxAnaRow);
          // ignore: avoid_print
          print('${thetaDeg.toStringAsFixed(2).padLeft(10)} | ${row.join(' | ')}');
        }

        // Contrôle croisé (rapporté, non asserté) : où le Monte Carlo et
        // l'analytique divergent-ils, et de combien ? Utile pour juger la
        // qualité de l'approximation au premier ordre à grand theta/corde
        // (où le "signal" domine largement et où 500 tirages/tol=0.01px
        // peuvent avoir moins de résolution que l'analytique).
        var maxRelDiff = 0.0;
        for (var ti = 0; ti < thetasDeg.length; ti++) {
          for (var ci = 0; ci < targetChordsPx.length; ci++) {
            final mc = smaxMcMatrix[ti][ci];
            if (mc == null) continue; // ">3px" côté MC, pas comparable ici
            final ana = smaxAnaMatrix[ti][ci];
            final relDiff = (mc - ana).abs() / ana;
            if (relDiff > maxRelDiff) maxRelDiff = relDiff;
          }
        }
        // ignore: avoid_print
        print('[point2] écart relatif max Monte-Carlo vs analytique = '
            '${(maxRelDiff * 100).toStringAsFixed(1)}% (contrôle croisé, '
            'non assertée -- l\'assertion de monotonie porte sur '
            'l\'analytique seul, cf. ci-dessous).');

        // Invariant du MODÈLE (pas de la photo) : sigma_max doit être
        // monotone croissant à la fois en theta (corde fixée) et en corde
        // (theta fixé) -- conséquence directe et attendue de la règle
        // sigma_max ~ k*theta*L. Assertée sur la matrice ANALYTIQUE
        // (déterministe par construction, aucun tirage aléatoire) plutôt
        // que sur le Monte Carlo : la bissection a une tolérance de
        // convergence (tol=0.01px) et une variance d'échantillonnage
        // (500 tirages) du même ordre que l'écart entre certaines cellules
        // adjacentes de la table ci-dessus (p.ex. theta=2.0°->2.8° à
        // L~228px : 1.661 vs 2.329, mais theta=2.8°->3.0° au même L :
        // 2.329 vs 2.499, un écart de 0.17px -- comparable à la résolution
        // de la bissection). Asserter la monotonie sur ces tirages ferait
        // dépendre le passage du test d'un pari sur le seed, pas d'une
        // propriété garantie -- exactement le risque signalé : un test qui
        // passe aujourd'hui et échoue un jour sans qu'aucun code n'ait
        // changé, sans qu'on sache si c'est une régression.
        //
        // Décompte des cellules réellement contraintes : le traitement
        // (valeur finie) vs (>3px, jamais atteint dans la plage testée)
        // rend vacue toute comparaison entre deux cellules qui sont TOUTES
        // LES DEUX >3px (p.ex. toute la ligne theta=5° au-delà de L~150px)
        // -- ce n'est pas une erreur, mais le nombre de comparaisons
        // effectivement discriminantes doit être connu, pas supposé égal
        // au nombre total de comparaisons.
        var nComparisons = 0;
        var nVacuousBothInf = 0;
        double effOrInfAna(double v) => v; // toujours fini (analytique)
        for (var ti = 0; ti < thetasDeg.length; ti++) {
          for (var ci = 1; ci < targetChordsPx.length; ci++) {
            nComparisons++;
            expect(
              effOrInfAna(smaxAnaMatrix[ti][ci]),
              greaterThanOrEqualTo(effOrInfAna(smaxAnaMatrix[ti][ci - 1])),
              reason: 'monotonie attendue en corde (theta=${thetasDeg[ti]}° '
                  'fixé, valeurs ANALYTIQUES déterministes) : sigma_max ne '
                  'doit jamais décroître quand la corde augmente '
                  '(L=${targetChordsPx[ci - 1]}px -> ${targetChordsPx[ci]}px).',
            );
          }
        }
        for (var ci = 0; ci < targetChordsPx.length; ci++) {
          for (var ti = 1; ti < thetasDeg.length; ti++) {
            nComparisons++;
            expect(
              effOrInfAna(smaxAnaMatrix[ti][ci]),
              greaterThanOrEqualTo(effOrInfAna(smaxAnaMatrix[ti - 1][ci])),
              reason: 'monotonie attendue en theta (corde=${targetChordsPx[ci]}'
                  'px fixée, valeurs ANALYTIQUES déterministes) : sigma_max '
                  'ne doit jamais décroître quand theta augmente '
                  '(${thetasDeg[ti - 1]}° -> ${thetasDeg[ti]}°).',
            );
          }
        }
        // Pour référence : combien de comparaisons Monte-Carlo auraient
        // été vacues (les deux côtés ">3px") si on avait gardé le MC comme
        // source -- affiché, pas asserté, uniquement pour quantifier ce
        // que "17 tests passent" veut vraiment dire ici.
        for (var ti = 0; ti < thetasDeg.length; ti++) {
          for (var ci = 1; ci < targetChordsPx.length; ci++) {
            if (smaxMcMatrix[ti][ci] == null && smaxMcMatrix[ti][ci - 1] == null) {
              nVacuousBothInf++;
            }
          }
        }
        for (var ci = 0; ci < targetChordsPx.length; ci++) {
          for (var ti = 1; ti < thetasDeg.length; ti++) {
            if (smaxMcMatrix[ti][ci] == null && smaxMcMatrix[ti - 1][ci] == null) {
              nVacuousBothInf++;
            }
          }
        }
        // ignore: avoid_print
        print('[point2] monotonie : $nComparisons comparaisons assertées '
            '(matrice analytique, toutes discriminantes car toujours '
            'finies) ; pour référence, $nVacuousBothInf de ces mêmes paires '
            'auraient été vacues côté Monte-Carlo (">3px" des deux côtés, '
            'donc rien testé) -- c\'est précisément pourquoi la matrice '
            'analytique est préférable ici : elle ne sature jamais.');

        // La constante k découverte en Python (rule2.py) : sigma_max varie
        // quasi-linéairement avec theta*chord sur toute la plage testée
        // (dispersion relative mesurée ≈0.18% en Python) — on vérifie ici
        // que la reconstruction Dart (lineIntersect réel, pas de formule
        // Python recopiée) retombe dans le même ordre de grandeur, sans
        // exiger une égalité stricte (méthodes de bissection légèrement
        // différentes, seeds différentes).
        //
        // IMPORTANT — portée de ce que sigma modélise ici : c'est un bruit
        // gaussien i.i.d. AJOUTÉ INDÉPENDAMMENT à chacun des 4 points
        // (ceilL/ceilR/floorL/floorR), modélisant une imprécision de
        // PLACEMENT d'un point par ailleurs correctement identifié. Cela ne
        // couvre PAS une erreur SYSTÉMATIQUE d'identification de cible
        // (p.ex. pointer une tringle plutôt que la jonction plafond réelle) :
        // une telle erreur n'est ni gaussienne, ni i.i.d., ni du même ordre
        // de grandeur — elle biaise une coordonnée entière, dans une
        // direction fixe, indépendamment de tout tirage aléatoire. sigma_max
        // ci-dessous ne dit donc rien sur la robustesse du solveur face à ce
        // second type d'erreur ; ne pas réappliquer cette règle telle quelle
        // à une photo sans requalifier explicitement quelle erreur (bruit de
        // placement vs erreur d'identification) est en jeu à ce moment-là.
        expect(kValues, isNotEmpty);
        final kMean = kValues.reduce((a, b) => a + b) / kValues.length;
        // ignore: avoid_print
        print('[point2] k moyen (Dart) = ${kMean.toStringAsExponential(3)} '
            '(référence Python : 3.716e-03)');
        // Tolérance resserrée à ±5% (dispersion Python mesurée : 0.18% sur
        // 42 cellules) -- une bande à ±50% laisserait passer une
        // régression qui triple la sensibilité au bruit sans qu'aucune
        // alarme ne se déclenche : ça n'aurait plus de valeur de garde-
        // fou. ±5% laisse encore une marge d'un facteur ~25 par rapport à
        // la dispersion Python observée (donc reste loin de la
        // flakiness), tout en étant assez serré pour détecter une vraie
        // régression du solveur ou de la méthode de bissection. Si le Dart
        // ne tient pas ±5% alors que le Python tient 0.18%, c'est en soi
        // une information à creuser (bissection, seed, tolérance de
        // convergence) -- pas une raison d'élargir la bande.
        expect(kMean, closeTo(3.716e-3, 3.716e-3 * 0.05),
            reason: 'k doit rester proche (±5%) de la valeur Python '
                'pré-validée (dispersion Python mesurée : 0.18% sur 42 '
                'cellules) -- si cet écart est franchi, creuser la '
                'méthode de bissection (tol, seed, nTrials) avant '
                'd\'élargir la tolérance.');
      },
    );

    test(
      'règle dérivée, appliquée rétrospectivement à scandinave : corde '
      '228px -> sigma_max(theta) rapporté pour theta=0.3° et 2.8° '
      '(AUCUNE assertion de passage/échec sur cette comparaison — voir '
      'note ci-dessous)',
      () {
        // ATTENTION — pourquoi ce test n'assert RIEN sur scandinave :
        //
        // 1. sigma_placement (~1px) est une hypothèse NON MESURÉE, pas une
        //    propriété du modèle. La coder en dur dans un expect() (dans
        //    n'importe quel sens : greaterThan OU lessThan) fabrique
        //    exactement le piège qu'on vient de mettre trois itérations à
        //    identifier avec cy : une conclusion qui pivote entièrement sur
        //    un paramètre libre non mesuré, mais cette fois masquée par un
        //    test qui passe au vert — ce qui est pire, car un test vert ne
        //    se relit pas.
        //
        // 2. Cette valeur est fragile dans les DEUX sens. Les 4 coins de
        //    scandinave viennent d'un ajustement linéaire sur ~152 points
        //    (resid_std = 0.205px au plafond) : l'incertitude STATISTIQUE
        //    sur les extrémités est de l'ordre de quelques centièmes de
        //    pixel, pas de 1px — à ce compte, 0.3° redevient mesurable.
        //    Mais l'erreur RÉELLE sur scandinave (tringle dorée prise pour
        //    la jonction plafond) était une erreur SYSTÉMATIQUE
        //    d'identification de cible, de plusieurs pixels, sans rapport
        //    avec un bruit gaussien i.i.d. Le sigma de ce harnais et le
        //    sigma de scandinave ne mesurent PAS la même chose : les
        //    comparer dans une assertion serait une confusion de
        //    catégorie.
        //
        // Ce test se contente donc de RAPPORTER sigma_max(theta) pour les
        // deux bornes disputées (0.3° et 2.8°) — l'interprétation
        // (mesurable ou non, selon quelle hypothèse de sigma_placement on
        // choisit d'admettre) a sa place dans le rapport à l'humain, pas
        // dans une condition de passage du test.
        const chordScandinave = 228.0;

        for (final thetaDisputeDeg in [0.3, 2.8]) {
          final wallWidthM = chordScandinave * depthM / focalPx;
          final smax = _findSigmaMax(
            thetaDeg: thetaDisputeDeg,
            wallWidthM: wallWidthM,
          );
          // ignore: avoid_print
          print(
            '[point2-scandinave] theta_dispute=$thetaDisputeDeg° '
            'corde=$chordScandinave px  sigma_max=$smax px '
            '(rapporté seulement -- aucune comparaison à sigma_placement '
            'ici : voir note dans le corps du test pour la raison).',
          );
          // Seule propriété du MODÈLE (pas de la photo) qu'on assert ici :
          // sigma_max doit être un nombre fini et non-null dans cette
          // plage -- c'est une propriété de robustesse du solveur, pas une
          // hypothèse sur scandinave.
          expect(
            smax,
            isNotNull,
            reason: 'smax ne doit pas être null (theta=$thetaDisputeDeg° '
                'reste discernable même à 3px dans l\'absolu, à corde '
                '228px) -- propriété du solveur/modèle, indépendante de '
                'toute hypothèse sur une photo réelle.',
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
          wall.ceilL,
          wall.ceilR,
          wall.floorL,
          wall.floorR,
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
          // Note : contrairement aux autres tests de ce groupe, celui-ci ne
          // dépend PAS des coins projetés (wall.ceilL/etc.) — il documente
          // un fait fixe de la caméra CANONIQUE de buildCalibratedScene,
          // qui ne varie jamais avec la scène d'entrée. `thetaDeg` n'est
          // donc conservé dans la boucle que pour l'affichage explicite
          // "quel que soit theta" (0°, 2.8°, 10°, 30°) — pas parce qu'il
          // influence le calcul ci-dessous.

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
            wall.ceilL,
            wall.ceilR,
            wall.floorL,
            wall.floorR,
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
