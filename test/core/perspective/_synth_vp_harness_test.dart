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
import 'package:staff_decor_studio/models/persp_calib.dart';

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

// ---------------------------------------------------------------------------
// EXTENSION PHASE C (brief : "Objectif. Appliquer la règle σ_max ≈ k·θ·L à
// l'inventaire des scènes de démo...") — ajoutée à ce même fichier, PAS un
// nouveau fichier, per l'instruction explicite ("le harnais existant est
// étendu plutôt que dupliqué").
//
// Note de provenance (suite au retour utilisateur sur la première version
// de cette extension) : les scripts Python de pré-validation
// /tmp/synth_vp/point1_pH_sweep.py et point3_inventory.py ont été
// accidentellement supprimés en cours de session (déclaré à l'époque) et
// ne sont plus reproductibles depuis leur source — les chiffres qu'ils
// avaient produits (dispersion 42.857%/0.235%/0.034%) SONT REPRODUITS ICI
// par le harnais Dart lui-même (méthode analytique réelle, pas recopiée) :
// c'est cette reproduction Dart, imprimée par les `print()` ci-dessous, qui
// fait foi désormais, pas les scripts disparus. Nouvelle exploration cette
// session (axe f/largeur-image, jamais balayé avant) pré-validée via
// /tmp/synth_vp/point1_f_sweep.py, point1_kf_over_pH.py, point3_final.py
// (toujours présents sous /tmp, non commités, hors dépôt) avant
// transcription du sweep κ=k·f/pH ci-dessous.
// ---------------------------------------------------------------------------

/// pH (brief Phase C, point 1) : séparation verticale plafond/plancher en
/// pixels, pour une géométrie (H, d) donnée aux mêmes paramètres caméra que
/// le reste du fichier. Calculée à azimut quasi nul (theta=1e-3°, loin de
/// la dégénérescence stricte) — indépendante de la largeur du mur (W=1.0m
/// arbitraire ici : pH ne dépend géométriquement que de H, d, f, cx, cy,
/// heightCamM, jamais de W).
double _pHAt({
  required double wallHeightM,
  required double depthM,
  required double focalPx,
  required double cx,
  required double cy,
  required double heightCamM,
}) {
  final wall = buildSyntheticWall(
    wallWidthM: 1.0,
    wallHeightM: wallHeightM,
    depthM: depthM,
    focalPx: focalPx,
    cx: cx,
    cy: cy,
    heightCamM: heightCamM,
    thetaDeg: 1e-3,
  );
  return wall.floorL.dy - wall.ceilL.dy;
}

/// Version généralisée de la propagation analytique déterministe (moteur
/// commun avec `_analyticalSigmaMax` du groupe "Point 2" ci-dessous, qui
/// délègue à cette fonction) — paramétrée explicitement par (wallHeightM,
/// depthM, focalPx, cx, cy, heightCamM) au lieu des constantes de scène
/// partagées de `main()`, pour permettre le balayage en (H, d) du point 1
/// de la Phase C SANS dupliquer la logique de différences finies.
///
/// Méthode (identique à /tmp/synth_vp/point1_pH_sweep.py::analytical_sigma_max,
/// elle-même identique à /tmp/synth_vp/rule2.py) : 1) gradient de vp.x par
/// rapport aux 8 coordonnées d'entrée, par différences finies sur le VRAI
/// `pg.lineIntersect` ; 2) norme de ce gradient = sigma(vp.x) par unité de
/// sigma d'entrée ; 3) propagation au premier ordre via d(theta)/d(vp.x) ;
/// 4) sigma_max = |theta| / (1.96 * sigma(theta) par unité de sigma).
/// Aucun `math.Random` — déterministe par construction.
double _analyticalSigmaMaxGeneric({
  required double thetaDeg,
  required double wallWidthM,
  required double wallHeightM,
  required double depthM,
  required double focalPx,
  required double cx,
  required double cy,
  required double heightCamM,
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
      if (vp2 == null) {
        throw StateError(
          'lineIntersect dégénéré pendant la différence finie '
          '(theta=$thetaDeg°, H=$wallHeightM, d=$depthM) -- gradient '
          'indéfini, la propagation analytique ne peut pas continuer.',
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

/// Facteur opérationnel (brief Phase C, point 3 : "le seuil opérationnel
/// est plus exigeant... appliquer un facteur de 3 à 5, donc viser θ·L >
/// 1000 à 1 px").
///
/// ⚠️ Reclassification suite au retour utilisateur : ce facteur n'est PAS
/// une grandeur "dérivée" au sens d'une mesure ou d'une propagation
/// analytique — c'est le chiffre rond 1000 (mon propre choix, celui du
/// brief lui-même comme cible explicite) divisé par le seuil brut à 1px
/// de la tranche de référence. Comme 1000 est une CONVENTION (pas une
/// grandeur physique observée), le résultat est une convention lui aussi,
/// pas une déduction. On le garde car il tombe dans [3,5] (vérifié par un
/// test dédié ci-dessous), mais le nom de la fonction et ce commentaire
/// documentent maintenant explicitement sa nature conventionnelle.
double _operationalFactor({
  required double kPrime,
  required double pHRefPhaseB,
}) {
  final rawThresholdAt1pxRef = 1.0 / (kPrime * pHRefPhaseB);
  return 1000.0 / rawThresholdAt1pxRef; // 1000 = convention, pas une mesure.
}

/// Reconstruction de theta (degrés) à partir de vp.x, f, cx — même
/// inversion que `_reconstructThetaDeg` ci-dessus, dupliquée ici sous un
/// nom distinct pour documenter son usage spécifique au Point 3 (theta
/// dérivé de `demoPresets`, pas du générateur synthétique).
double _thetaDegFromVpx(double vpX, double focalPx, double cx) {
  return math.atan(focalPx / (cx - vpX)) * 180.0 / math.pi;
}

/// ============================================================================
/// Point 1 (suite, cette session) : l'axe f/largeur-image jamais balayé
/// (retour utilisateur, point secondaire #1) — "f est resté fixé à 1400 px
/// dans tout le balayage alors que l'inventaire va de 1960 à 2560 px de
/// large... à couvrir avant d'appliquer k' à haussmann".
///
/// Pré-validé en Python (/tmp/synth_vp/point1_kf_over_pH.py) : k/pH SEUL
/// varie de 29.089% quand on balaye f/W∈[0.55,1.1] et W∈{1920,1960,2560}
/// (donnée non attendue, découverte cette session) — MAIS κ = k·f/pH est
/// stable à 0.239% sur exactement le même balayage (H×d×W×f/W = 2880
/// points), et cohérent à 0.0012% avec la tranche de référence Phase B.
/// C'est κ (pas k/pH) le coefficient réellement invariant : la focale
/// n'était pas un axe supplémentaire de variation du coefficient, elle
/// avait simplement été mal isolée (elle se glisse dans pH ET dans le
/// seuil sigma_max de façon telle qu'elle s'annule quand on la multiplie
/// explicitement au numérateur plutôt que de la laisser implicite dans pH
/// seul).
///
/// Cette fonction calcule κ = k·f/pH pour un point donné du balayage
/// (H, d, focalPx, cx, W) — même moteur que `_analyticalSigmaMaxGeneric`/
/// `_pHAt`, aucune duplication de la logique de différences finies.
double _kappaAt({
  required double thetaDeg,
  required double wallWidthM,
  required double wallHeightM,
  required double depthM,
  required double focalPx,
  required double cx,
  required double cy,
  required double heightCamM,
}) {
  final smax = _analyticalSigmaMaxGeneric(
    thetaDeg: thetaDeg,
    wallWidthM: wallWidthM,
    wallHeightM: wallHeightM,
    depthM: depthM,
    focalPx: focalPx,
    cx: cx,
    cy: cy,
    heightCamM: heightCamM,
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
  final pH = _pHAt(
    wallHeightM: wallHeightM,
    depthM: depthM,
    focalPx: focalPx,
    cx: cx,
    cy: cy,
    heightCamM: heightCamM,
  );
  final k = smax / (thetaDeg * chordActual);
  return k * focalPx / pH;
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

    // Note sur l'écart k(Dart)=3.643e-3 vs k(Python)=3.716e-3 (1.96%,
    // cf. assertion plus bas) : c'est ~10x la dispersion interne Python
    // (0.18%), donc PAS du bruit -- un décalage SYSTÉMATIQUE, dans une
    // direction fixe. La cause la plus probable est ici : `np.percentile`
    // (rule2.py) INTERPOLE linéairement entre les deux valeurs encadrantes
    // du percentile demandé, alors que `sorted[(0.025*n).floor()]|
    // ci-dessous prend l'index entier par troncature -- ce qui élargit
    // très légèrement l'intervalle de confiance calculé côté Dart et
    // décale donc le seuil de bissection dans une direction fixe et
    // reproductible. Bénin (cohérent avec le signe observé : IC élargi ->
    // sigma_max légèrement sous-estimé -> k légèrement inférieur), mais
    // c'est une différence de CONVENTION de calcul de percentile, pas une
    // imprécision numérique à corriger en resserrant encore la tolérance.
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
    // Délègue désormais au moteur générique `_analyticalSigmaMaxGeneric`
    // (ajouté en Phase C pour le balayage pH du point 1, cf. plus haut dans
    // ce fichier) — mêmes 4 constantes de scène partagées (wallHeightM,
    // depthM, focalPx, cx, cy, heightCamM) qu'avant le refactor, aucun
    // changement de comportement pour ce groupe.
    double _analyticalSigmaMax({
      required double thetaDeg,
      required double wallWidthM,
    }) {
      return _analyticalSigmaMaxGeneric(
        thetaDeg: thetaDeg,
        wallWidthM: wallWidthM,
        wallHeightM: wallHeightM,
        depthM: depthM,
        focalPx: focalPx,
        cx: cx,
        cy: cy,
        heightCamM: heightCamM,
      );
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
        //
        // Écart observé actuellement : ~1.96% (k_Dart=3.643e-3 vs
        // k_Python=3.716e-3), soit ~10x la dispersion interne Python
        // (0.18%) -- donc un décalage SYSTÉMATIQUE, pas du bruit. Cause
        // identifiée : convention de percentile différente entre
        // `np.percentile` (interpolation linéaire, côté Python) et
        // `sorted[(0.025*n).floor()]` (index entier tronqué, côté Dart,
        // cf. `_ci95ContainsZero` ci-dessus) -- pas une imprécision
        // numérique à chasser en resserrant encore la tolérance.
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

  // ===========================================================================
  // PHASE C — POINT 1 : combler le trou en pH. k = 3,716e-3 a été mesuré à
  // H=2,5m, d=3m FIXES (donc pH≈1167px constant dans toute la table de
  // rule2.py / du groupe "Point 2" ci-dessus). Balayage étendu à H∈[2.2,3.0]
  // et d∈[2,6] (méthode analytique déterministe, PAS de Monte Carlo, comme
  // demandé explicitement) pour trancher : k est-il une constante unique
  // (dispersion <5%), ou dépend-il de pH (dispersion >5%, la règle doit
  // s'écrire k(pH)) ? Pré-validé en Python avant transcription
  // (/tmp/synth_vp/point1_pH_sweep.py — mêmes fonctions que rule2.py) :
  // dispersion de k (constante unique) = 42.857% (>> 5%), dispersion de k/pH
  // = 0.235% (<< 5%) -> la règle DOIT être réécrite avec pH explicite,
  // sous la forme sigma_max ≈ (k/pH)·pH·theta·L, avec k/pH quasi-constant.
  // ===========================================================================
  group(
    'Phase C — Point 1 : k depend de pH (dispersion >>5%), la regle doit '
    "s'ecrire avec pH explicite (k/pH quasi-constant, dispersion <<5%)",
    () {
      // Même balayage que /tmp/synth_vp/point1_pH_sweep.py (pré-validé) :
      // H et d couvrant la plage demandée par le brief, theta et corde
      // couvrant la plage déjà utilisée par le groupe "Point 2" ci-dessus
      // (dont la corde disputée de scandinave, 228px, retenue ici aussi).
      const hsM = [2.2, 2.5, 2.8, 3.0];
      const dsM = [2.0, 3.0, 4.0, 5.0, 6.0];
      const sweepThetasDeg = [0.3, 1.0, 2.8, 5.0];
      const sweepChordsPx = [228.0, 500.0, 1000.0];

      /// Exécute le balayage complet (H x d x theta x corde, 4x5x4x3=240
      /// combinaisons) et retourne pour chaque point : k = sigma_max/(theta*L)
      /// ET pH (séparation plafond/plancher, dépend uniquement de H et d).
      /// Aucun `math.Random` — 100% déterministe, comme dans le groupe
      /// "Point 2" (délègue à `_analyticalSigmaMaxGeneric`/`_pHAt`).
      List<({double k, double pH})> runSweep() {
        final out = <({double k, double pH})>[];
        for (final hM in hsM) {
          for (final dM in dsM) {
            final pH = _pHAt(
              wallHeightM: hM,
              depthM: dM,
              focalPx: focalPx,
              cx: cx,
              cy: cy,
              heightCamM: heightCamM,
            );
            for (final thetaDeg in sweepThetasDeg) {
              for (final chordTarget in sweepChordsPx) {
                final wallWidthM = chordTarget * dM / focalPx;
                final smax = _analyticalSigmaMaxGeneric(
                  thetaDeg: thetaDeg,
                  wallWidthM: wallWidthM,
                  wallHeightM: hM,
                  depthM: dM,
                  focalPx: focalPx,
                  cx: cx,
                  cy: cy,
                  heightCamM: heightCamM,
                );
                final wall = buildSyntheticWall(
                  wallWidthM: wallWidthM,
                  wallHeightM: hM,
                  depthM: dM,
                  focalPx: focalPx,
                  cx: cx,
                  cy: cy,
                  heightCamM: heightCamM,
                  thetaDeg: thetaDeg,
                );
                final chordActual = _dist(wall.ceilL, wall.ceilR);
                out.add((k: smax / (thetaDeg * chordActual), pH: pH));
              }
            }
          }
        }
        return out;
      }

      double _mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
      double _std(List<double> xs, double mean) {
        final variance =
            xs.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
                xs.length;
        return math.sqrt(variance);
      }

      test(
        'dispersion de k (constante UNIQUE, comme mesuré en Phase B) sur '
        'H∈[2.2,3.0] x d∈[2,6] : attendu >> ±5% -- k ne peut PAS être '
        'traité comme une constante universelle',
        () {
          final sweep = runSweep();
          final ks = sweep.map((r) => r.k).toList();
          final kMean = _mean(ks);
          final kStd = _std(ks, kMean);
          final dispersion = kStd / kMean;

          // ignore: avoid_print
          print(
            '[phaseC-point1] k (constante unique) : mean='
            '${kMean.toStringAsExponential(3)}  std='
            '${kStd.toStringAsExponential(3)}  '
            'dispersion=${(dispersion * 100).toStringAsFixed(3)}%  '
            '(min=${ks.reduce(math.min).toStringAsExponential(3)}  '
            'max=${ks.reduce(math.max).toStringAsExponential(3)}, '
            'n=${ks.length})',
          );

          // C'est le résultat qui TRANCHE la question du brief : la
          // dispersion mesurée en Python (42.857%) est reproduite ici côté
          // Dart (méthode analytique réelle, pas recopiée) -- bien au-delà
          // du seuil ±5% fixé par le brief comme critère de décision. On
          // assert donc explicitement que ce seuil est dépassé : c'est le
          // FAIT qui force la réécriture de la règle avec pH explicite
          // ci-dessous, pas une hypothèse qu'on choisit de croire.
          expect(
            dispersion,
            greaterThan(0.05),
            reason:
                'si cette dispersion retombait sous ±5%, la règle Phase B '
                "(k unique) serait en fait valide partout et il n'y aurait "
                'rien à réécrire -- ce test documente que ce N\'EST PAS le '
                'cas (dispersion mesurée ≈42-43%, cf. valeur imprimée '
                'ci-dessus).',
          );
        },
      );

      test(
        'dispersion de k/pH (coefficient CORRIGÉ) sur le même balayage : '
        'attendu << ±5% -- confirme sigma_max ≈ (k/pH)·pH·theta·L',
        () {
          final sweep = runSweep();
          final kOverPh = sweep.map((r) => r.k / r.pH).toList();
          final mean = _mean(kOverPh);
          final std = _std(kOverPh, mean);
          final dispersion = std / mean;

          // ignore: avoid_print
          print(
            '[phaseC-point1] k/pH (coefficient corrigé) : mean='
            '${mean.toStringAsExponential(6)}  std='
            '${std.toStringAsExponential(6)}  '
            'dispersion=${(dispersion * 100).toStringAsFixed(3)}%  '
            '(n=${kOverPh.length})',
          );

          expect(
            dispersion,
            lessThan(0.05),
            reason:
                "k/pH doit être quasi-constant (<<±5%) pour justifier "
                "d'écrire la règle sous forme pH-explicite plutôt que sous "
                "une autre forme fonctionnelle -- dispersion Python "
                "pré-validée : 0.235%.",
          );

          // Contrôle croisé : k/pH mesuré ici doit être cohérent avec
          // k_ref/pH_ref calculé directement à la tranche de référence
          // Phase B (H=2.5m, d=3.0m, k_ref=3.716e-3 -- la valeur DÉJÀ
          // assertée dans le groupe "Point 2" ci-dessus, ±5%). Ce n'est
          // PAS une nouvelle constante indépendante : c'est la même
          // constante, simplement redivisée par pH pour révéler qu'elle
          // n'était valide que sur cette seule tranche.
          const kRefPhaseB = 3.716e-3;
          final pHRefPhaseB = _pHAt(
            wallHeightM: wallHeightM,
            depthM: depthM,
            focalPx: focalPx,
            cx: cx,
            cy: cy,
            heightCamM: heightCamM,
          );
          final kPrimeRef = kRefPhaseB / pHRefPhaseB;
          final relDiff = (kPrimeRef - mean).abs() / mean;

          // ignore: avoid_print
          print(
            '[phaseC-point1] pH_ref(H=$wallHeightM,d=$depthM)='
            '${pHRefPhaseB.toStringAsFixed(2)}px  '
            "k_ref/pH_ref=${kPrimeRef.toStringAsExponential(6)}  "
            'écart relatif vs k/pH moyen du balayage='
            '${(relDiff * 100).toStringAsFixed(3)}%',
          );
          expect(
            relDiff,
            lessThan(0.01),
            reason:
                'le coefficient k/pH dérivé de la référence Phase B seule '
                'doit rester cohérent (<1%) avec la moyenne mesurée sur '
                'tout le balayage H x d -- sinon la tranche de référence '
                "Phase B serait elle-même un cas particulier non "
                'représentatif, ce qui invaliderait la correction.',
          );
        },
      );

      // =========================================================================
      // NOUVEAU cette session, suite au retour utilisateur (point secondaire
      // #1 : "f est resté fixé à 1400 px dans tout le balayage alors que
      // l'inventaire va de 1960 à 2560 px de large... à couvrir avant
      // d'appliquer k' à haussmann"). Aucune image de l'inventaire ne
      // contient de métadonnée EXIF de focale (vérifié via PIL sur les 4
      // JPG démo cette session) -- f est une convention totalement libre,
      // et il fallait vérifier si k/pH restait valide quand on fait varier
      // f/largeur-image (FOV) ET la largeur d'image réelle de l'inventaire
      // (1920/1960/2560px), pas seulement H et d.
      //
      // Résultat (pré-validé /tmp/synth_vp/point1_kf_over_pH.py, reproduit
      // ci-dessous côté Dart) : k/pH SEUL n'est PAS stable sur cet axe
      // (dispersion 29.089%, sérieux, comparable à la dispersion de k seul
      // avant correction) -- mais κ=k·f/pH, lui, EST stable (<0.24%) sur
      // exactement le même balayage étendu (H×d×W×f/W = 2880 points). La
      // correction du Point 1 n'était donc pas fausse, seulement
      // incomplète : il manquait f au numérateur.
      // =========================================================================
      test(
        'axe f/largeur-image (jamais balayé avant cette session) : k/pH '
        'SEUL varie fortement (>>5%) avec f/W et W, mais κ=k·f/pH reste '
        'stable (<<5%) sur le même balayage étendu -- κ, pas k/pH, est le '
        'coefficient réellement invariant',
        () {
          const imageWidthsPx = [1920.0, 1960.0, 2560.0];
          const fOverWRatios = [0.55, 0.729167, 0.9, 1.1];

          final ks = <double>[];
          final kOverPhs = <double>[];
          final kappas = <double>[];

          for (final hM in hsM) {
            for (final dM in dsM) {
              for (final imgW in imageWidthsPx) {
                final cxSweep = imgW / 2.0;
                for (final fw in fOverWRatios) {
                  final f = fw * imgW;
                  final pH = _pHAt(
                    wallHeightM: hM,
                    depthM: dM,
                    focalPx: f,
                    cx: cxSweep,
                    cy: cy,
                    heightCamM: heightCamM,
                  );
                  for (final thetaDeg in sweepThetasDeg) {
                    for (final chordTarget in sweepChordsPx) {
                      final wallWidthM = chordTarget * dM / f;
                      final smax = _analyticalSigmaMaxGeneric(
                        thetaDeg: thetaDeg,
                        wallWidthM: wallWidthM,
                        wallHeightM: hM,
                        depthM: dM,
                        focalPx: f,
                        cx: cxSweep,
                        cy: cy,
                        heightCamM: heightCamM,
                      );
                      final wall = buildSyntheticWall(
                        wallWidthM: wallWidthM,
                        wallHeightM: hM,
                        depthM: dM,
                        focalPx: f,
                        cx: cxSweep,
                        cy: cy,
                        heightCamM: heightCamM,
                        thetaDeg: thetaDeg,
                      );
                      final chordActual = _dist(wall.ceilL, wall.ceilR);
                      final k = smax / (thetaDeg * chordActual);
                      ks.add(k);
                      kOverPhs.add(k / pH);
                      kappas.add(k * f / pH);
                    }
                  }
                }
              }
            }
          }

          final kMean = _mean(ks);
          final kDisp = _std(ks, kMean) / kMean;
          final kphMean = _mean(kOverPhs);
          final kphDisp = _std(kOverPhs, kphMean) / kphMean;
          final kappaMean = _mean(kappas);
          final kappaDisp = _std(kappas, kappaMean) / kappaMean;

          // ignore: avoid_print
          print(
            '[phaseC-point1-fW] n=${ks.length} points (H×d×W×f/W×theta×corde)\n'
            '  k (constante unique)      : dispersion='
            '${(kDisp * 100).toStringAsFixed(3)}%\n'
            '  k/pH (correction Point 1) : dispersion='
            '${(kphDisp * 100).toStringAsFixed(3)}%  <-- PAS stable sur cet axe\n'
            '  κ=k·f/pH (NOUVELLE correction) : mean='
            '${kappaMean.toStringAsExponential(6)}  dispersion='
            '${(kappaDisp * 100).toStringAsFixed(4)}%  <-- stable',
          );

          expect(
            kphDisp,
            greaterThan(0.05),
            reason:
                'k/pH seul doit rester instable (>>5%) sur l\'axe f/W -- '
                'c\'est ce fait qui force à inclure f explicitement, pas '
                'une supposition.',
          );
          expect(
            kappaDisp,
            lessThan(0.01),
            reason:
                'κ=k·f/pH doit être quasi-constant (<<1%, plus strict que '
                'le seuil ±5% du brief car c\'est une correction du '
                'correctif) sur H×d×W×f/W simultanément -- sinon f ne '
                'suffirait pas à expliquer la dérive et il resterait un '
                'axe non identifié.',
          );

          // Cohérence avec la tranche de référence Phase B (H=2.5, d=3.0,
          // f=1400 sur W=1920, soit f/W=0.729167 -- exactement la config
          // partagée en tête de `main()`).
          final kappaRef = _kappaAt(
            thetaDeg: 1.0,
            wallWidthM: 3.0,
            wallHeightM: wallHeightM,
            depthM: depthM,
            focalPx: focalPx,
            cx: cx,
            cy: cy,
            heightCamM: heightCamM,
          );
          final relDiffKappa = (kappaRef - kappaMean).abs() / kappaMean;
          // ignore: avoid_print
          print(
            '[phaseC-point1-fW] κ_ref(tranche Phase B)='
            '${kappaRef.toStringAsExponential(6)}  écart vs moyenne '
            'balayage étendu=${(relDiffKappa * 100).toStringAsFixed(4)}%',
          );
          expect(relDiffKappa, lessThan(0.01));
        },
      );
    },
  );

  // ===========================================================================
  // PHASE C — POINT 2 : σ_placement est le paramètre libre ("le cy de ce
  // brief"). Choix explicite : option (b) du brief -- traiter σ_placement
  // comme une FOURCHETTE [0.5px, 3px] et rendre le verdict sur toute la
  // fourchette, plutôt que l'option (a) (replacer deux fois les 4 points
  // d'une même scène et mesurer la dispersion empirique). Raison du choix :
  // l'option (a) exigerait une NOUVELLE opération de pointage sur une photo
  // réelle -- précisément ce que le point 3 du même brief interdit
  // explicitement pour le tri ("aucune mesure de pixel photo n'est requise
  // et aucune n'est autorisée"), et le critère d'arrêt du brief demande de
  // ne PAS mesurer finement pour trancher un cas ambigu. L'option (b) est
  // la seule des deux qui respecte ces deux contraintes simultanément.
  //
  // Trichotomie du brief : une scène n'est "gardée" que si elle passe même
  // à σ=3px (le cas le plus défavorable, seuil le plus haut) ; "écartée"
  // que si elle échoue même à σ=0.5px (le cas le plus favorable, seuil le
  // plus bas) ; "indécidable" entre les deux -- et l'indécidable DOIT
  // apparaître comme tel, jamais être arbitré silencieusement.
  // ===========================================================================
  group(
    'Phase C — Point 2 : σ_placement traité en fourchette [0.5px,3px], '
    'trichotomie gardée/écartée/indécidable',
    () {
      /// seuil(theta*L) requis pour que le mur reste discernable du
      /// frontal à un niveau de bruit de placement [sigma] donné, pour un
      /// coefficient corrigé [kPrime] (=k/pH) et une géométrie [pH] donnés.
      /// C'est le seuil BRUT (là où l'IC95% touche zéro), PAS le seuil
      /// opérationnel (cf. `_operationalFactor` plus haut dans ce fichier).
      double seuilBrut({
        required double sigma,
        required double kPrime,
        required double pH,
      }) =>
          sigma / (kPrime * pH);

      /// Classification trichotomique stricte du brief : GARDEE seulement
      /// si thetaL clear le seuil le plus dur (sigma=3px, avec le facteur
      /// opérationnel appliqué) ; ECARTEE seulement s'il échoue le seuil le
      /// plus facile (sigma=0.5px, même facteur) ; INDECIDABLE sinon --
      /// jamais résolu arbitrairement dans l'entre-deux.
      String classify({
        required double thetaL,
        required double kPrime,
        required double pH,
        required double operationalFactor,
      }) {
        final seuilFacile =
            seuilBrut(sigma: 0.5, kPrime: kPrime, pH: pH) * operationalFactor;
        final seuilDur =
            seuilBrut(sigma: 3.0, kPrime: kPrime, pH: pH) * operationalFactor;
        if (thetaL > seuilDur) return 'GARDEE';
        if (thetaL <= seuilFacile) return 'ECARTEE';
        return 'INDECIDABLE';
      }

      test(
        'les 3 seuils (sigma=0.5/1.0/3.0px) sont strictement croissants -- '
        'la trichotomie GARDEE/ECARTEE/INDECIDABLE est donc bien définie '
        '(pas de chevauchement ni de trou)',
        () {
          const kPrime = 3.186251e-6;
          const pH = 1000.0;
          final s05 = seuilBrut(sigma: 0.5, kPrime: kPrime, pH: pH);
          final s10 = seuilBrut(sigma: 1.0, kPrime: kPrime, pH: pH);
          final s30 = seuilBrut(sigma: 3.0, kPrime: kPrime, pH: pH);
          // ignore: avoid_print
          print('[phaseC-point2] seuils bruts (kPrime=$kPrime, pH=$pH) : '
              'σ=0.5px->$s05  σ=1.0px->$s10  σ=3.0px->$s30');
          expect(s05, lessThan(s10));
          expect(s10, lessThan(s30));
        },
      );

      test(
        'trichotomie : un thetaL très grand est GARDEE, très petit est '
        'ECARTEE, et une valeur intermédiaire bien choisie est INDECIDABLE '
        '(rapportée comme telle, pas arbitrée)',
        () {
          const kPrime = 3.186251e-6;
          const pH = 1000.0;
          const operationalFactor = 3.716;
          final seuilFacile =
              seuilBrut(sigma: 0.5, kPrime: kPrime, pH: pH) *
                  operationalFactor;
          final seuilDur =
              seuilBrut(sigma: 3.0, kPrime: kPrime, pH: pH) *
                  operationalFactor;

          final verdictGrand = classify(
            thetaL: seuilDur * 10,
            kPrime: kPrime,
            pH: pH,
            operationalFactor: operationalFactor,
          );
          final verdictPetit = classify(
            thetaL: seuilFacile / 10,
            kPrime: kPrime,
            pH: pH,
            operationalFactor: operationalFactor,
          );
          final thetaLMilieu = (seuilFacile + seuilDur) / 2;
          final verdictMilieu = classify(
            thetaL: thetaLMilieu,
            kPrime: kPrime,
            pH: pH,
            operationalFactor: operationalFactor,
          );

          // ignore: avoid_print
          print(
            '[phaseC-point2] seuilFacile(σ=0.5,op)=$seuilFacile  '
            'seuilDur(σ=3.0,op)=$seuilDur  '
            'thetaL_milieu=$thetaLMilieu -> verdict=$verdictMilieu',
          );

          expect(verdictGrand, equals('GARDEE'));
          expect(verdictPetit, equals('ECARTEE'));
          expect(
            verdictMilieu,
            equals('INDECIDABLE'),
            reason:
                'une valeur choisie EXACTEMENT au milieu des deux seuils '
                'doit ressortir INDECIDABLE, jamais silencieusement '
                "arbitrée vers l'un des deux verdicts tranchés -- c'est "
                'exactement la garantie que le brief demande.',
          );
        },
      );
    },
  );

  // ===========================================================================
  // PHASE C — POINT 3 (REFAIT cette session, suite au retour utilisateur) :
  // inventaire assets/demo_scenes/ + tri gardée/écartée/indécidable, tri
  // ARITHMÉTIQUE (aucune mesure de pixel photo nouvelle).
  //
  // Ce qui a changé par rapport à la version précédente, et pourquoi
  // (chaque point correspond à un problème décisif signalé par
  // l'utilisateur) :
  //
  // 1) REPÈRE UNIQUE DÉCLARÉ : ESPACE IMAGE. Tout (corde, pH, σ_placement)
  //    est mesuré/déclaré en pixels de l'image SOURCE (celle dont
  //    `demoPresets` donne les xPct/yPct), jamais en pixels d'un canvas
  //    d'affichage letterboxé. C'est ce qui résout l'écart 228 (affichage,
  //    `imgDraw(dw:1400)` sur une source 1920px, scale=0.729167) vs 313
  //    (image) : 313.0×0.729167=228.2 -- LA MÊME donnée, pas un
  //    désaccord. On utilise donc 313px (espace image) pour scandinave,
  //    plus le pH image-space correspondant (881.3px) -- jamais les deux
  //    dans des repères différents comme la version précédente le faisait.
  //
  // 2) THETA DÉRIVÉ DES PRESETS, PAS "À L'OEIL". `PerspCalib.demoPresets`
  //    contient déjà `ceilL.yPct` ET `ceilR.yPct` (pas seulement les x,
  //    lus/assertés seuls dans la version précédente) -- leur différence
  //    donne la pente de la ligne de plafond, donc vp.x (via le VRAI
  //    `pg.lineIntersect`), donc theta. C'est de l'arithmétique sur
  //    données déjà committées, permise par le brief, et strictement plus
  //    solide qu'un jugement visuel qu'aucun oeil ne peut certifier sous
  //    0.2° (cf. les propres seuils angulaires minimaux de ce tri).
  //
  // 3) f RESTE UN PARAMÈTRE LIBRE (aucun EXIF dans les 4 JPG démo,
  //    vérifié via PIL cette session) -- mais la formule utilisée ici,
  //    sigma_max = κ·pH·L·(180/π)/|cx-vp.x|, ne contient PAS f
  //    explicitement (vérifié analytiquement stable à <0.2% sur
  //    f/W∈[0.4,2.0], bien plus large que la plage réaliste [0.55,1.1]) :
  //    theta et f s'annulent mutuellement dans le produit theta·L au
  //    premier ordre, dès qu'on exprime tout via C=cx-vp.x plutôt que via
  //    theta seul. Ceci répond au point secondaire #1 du retour
  //    utilisateur SANS qu'il faille borner ou deviner f.
  //
  // 4) CAS DÉGÉNÉRÉ (moderne/provencal) TRAITÉ COMME INDÉCIDABLE, PAS
  //    COMME THETA=0 CONFIRMÉ. Leurs presets ont ceilL.yPct==ceilR.yPct
  //    EXACTEMENT (à la précision committée, 3 décimales) -- ce n'est PAS
  //    un jugement visuel (donc pas la même erreur que la version
  //    précédente), mais ce n'est pas non plus une preuve de frontalité
  //    réelle : ça pourrait être un vrai theta=0, OU un angle plus petit
  //    que la précision d'arrondi (±0.0005 sur yPct) peut représenter.
  //    On borne ce cas : la pente cachée la plus grande compatible avec
  //    l'arrondi committé donne un sigma_max pire-cas qui reste sous le
  //    seuil "facile" -- donc l'incertitude d'arrondi seule ne suffit PAS
  //    à faire basculer ces 2 scènes vers GARDEE, mais on les rapporte
  //    explicitement comme INDECIDABLE (donnée dégénérée), jamais comme
  //    ECARTEE par défaut sur un theta non mesuré.
  //
  // 5) FACTEUR OPÉRATIONNEL RELABELLISÉ COMME CONVENTION (voir
  //    `_operationalFactor` plus haut) : 1000×k_ref, mon propre chiffre
  //    rond, pas une grandeur dérivée.
  //
  // 6) CONCLUSION "0/4 -> chemin normal -> vanishing_point.dart en
  //    correction" RETIRÉE (elle reposait entièrement sur le theta=0
  //    visuel, maintenant abandonné). Le constat Phase B point 3
  //    (wallNormal=-camera.forward figeant l'angle plafond/mur à 90° pour
  //    tout theta réel) reste valable et suffisant en soi, SANS cette
  //    béquille.
  // ===========================================================================
  group(
    'Phase C — Point 3 (refait) : theta dérivé des presets (arithmétique, '
    'repère image unique), verdict gardée/écartée/indécidable',
    () {
      // κ=k·f/pH (cf. groupe Point 1 ci-dessus, nouvelle correction cette
      // session) -- PAS k/pH seul (montré instable sur l'axe f/W). Comme
      // sigma_max = κ·pH·theta·L/f et que theta≈(180/π)·f/C au premier
      // ordre pour C=cx-vp.x fixé par les données pixel (indépendant de
      // f), f s'annule : sigma_max ≈ κ·pH·L·(180/π)/|C|. Valeur de κ
      // reprise de la tranche de référence Phase B (cohérence <0.01% avec
      // le balayage complet H×d×W×f/W du groupe Point 1 ci-dessus, déjà
      // vérifiée par un test dédié).
      const kappaRefPhaseB = 4.460933e-3;

      // σ_placement : fourchette [0.5px, 3px], EXPLICITEMENT déclarée ici
      // comme vivant dans le MÊME espace image que corde/pH ci-dessous
      // (pas l'espace d'un canvas d'affichage letterboxé) -- un pixel de
      // placement erroné sur les 8 points de calibration committés dans
      // `demoPresets`/`candidateScandinaveIt1` (exprimés en xPct/yPct de
      // l'image source) se traduit directement en pixels image, sans
      // aucun facteur d'échelle à appliquer.
      const sigmaPlacementLoPx = 0.5;
      const sigmaPlacementHiPx = 3.0;

      // Facteur opérationnel : dérivé via `_operationalFactor` (défini
      // plus haut dans ce fichier, relabellisé comme convention =
      // 1000×k_ref -- 1000 est mon propre chiffre rond, pas une mesure).
      // Appelé ici plutôt qu'un littéral recopié, pour que le lien avec
      // sa définition (et son statut de convention documenté à cet
      // endroit) reste explicite et vérifiable.
      final pHRefForFactor = _pHAt(
        wallHeightM: wallHeightM,
        depthM: depthM,
        focalPx: focalPx,
        cx: cx,
        cy: cy,
        heightCamM: heightCamM,
      );
      final operationalFactor = _operationalFactor(
        kPrime: 3.716e-3 / pHRefForFactor, // k_ref/pH_ref, cf. groupe Point 1
        pHRefPhaseB: pHRefForFactor,
      );

      /// Seuil "facile" (σ=0.5px, le plus permissif pour GARDEE) et seuil
      /// "dur" (σ=3px, le plus permissif pour ECARTEE), tous deux
      /// multipliés par le facteur opérationnel -- ne dépendent QUE de
      /// σ_placement et du facteur, PAS de la scène (contrairement à
      /// seuilBrut(sigma,pH) de la version précédente : maintenant que la
      /// formule f-indépendante ne fait plus intervenir pH séparément du
      /// reste, le seuil est directement sur sigma_max lui-même, en px).
      final seuilFacilePx = sigmaPlacementLoPx * operationalFactor;
      final seuilDurPx = sigmaPlacementHiPx * operationalFactor;

      String classifyOnSigmaMax(double sigmaMaxPx) {
        if (sigmaMaxPx > seuilDurPx) return 'GARDEE';
        if (sigmaMaxPx <= seuilFacilePx) return 'ECARTEE';
        return 'INDECIDABLE';
      }

      test(
        'seuils (facteur opérationnel appliqué à σ_placement=[0.5,3]px) '
        'strictement croissants',
        () {
          // ignore: avoid_print
          print(
            '[phaseC-point3] seuilFacile=$seuilFacilePx px  '
            'seuilDur=$seuilDurPx px  (facteur opérationnel='
            '$operationalFactor, convention=1000×k_ref, PAS une grandeur '
            'dérivée d\'une mesure)',
          );
          expect(seuilFacilePx, lessThan(seuilDurPx));
          expect(operationalFactor, greaterThanOrEqualTo(3.0));
          expect(operationalFactor, lessThanOrEqualTo(5.0));
        },
      );

      test(
        'tableau : dimensions, corde, pH, theta dérivé des presets '
        '(espace image), sigma_max, et verdict pour les 4 scènes démo',
        () {
          // --- Inventaire des 4 scènes (repère image, xPct/yPct×dimensions) ---
          //
          // haussmann/moderne/provencal : ceilL/ceilR/floorL COMPLETS
          // (x ET y désormais, contrairement à la version précédente qui
          // n'assertait que les x) lus depuis `PerspCalib.demoPresets`.
          //
          // scandinave : identification "candidat it1"
          // (`_debug_calib_bench_test.dart` lignes ~299-303, PAS
          // `demoPresets['scandinave']` qui décrit un mur pleine-largeur,
          // une identification différente) -- MÊME repère image que les 3
          // autres (aucune conversion d'échelle depuis le canvas
          // d'affichage 1400px du banc de debug, dont le rôle ici se
          // limite à fournir les 8 points bruts en xPct/yPct).
          const scenes = [
            (
              name: 'haussmann',
              widthPx: 2560.0,
              heightPx: 1783.0,
              ceilLxPct: 0.120,
              ceilRxPct: 0.880,
              ceilLyPct: 0.090,
              ceilRyPct: 0.085,
              floorLyPct: 0.870,
              floorRyPct: 0.860,
            ),
            (
              name: 'moderne',
              widthPx: 1960.0,
              heightPx: 1470.0,
              ceilLxPct: 0.100,
              ceilRxPct: 0.900,
              ceilLyPct: 0.095,
              ceilRyPct: 0.095,
              floorLyPct: 0.720,
              floorRyPct: 0.720,
            ),
            (
              name: 'provencal',
              widthPx: 2560.0,
              heightPx: 1707.0,
              ceilLxPct: 0.100,
              ceilRxPct: 0.900,
              ceilLyPct: 0.140,
              ceilRyPct: 0.140,
              floorLyPct: 0.830,
              floorRyPct: 0.830,
            ),
            (
              name: 'scandinave',
              widthPx: 1920.0,
              heightPx: 1088.0,
              ceilLxPct: 0.830,
              ceilRxPct: 0.993,
              ceilLyPct: 0.0265,
              ceilRyPct: 0.0335,
              floorLyPct: 0.8365,
              floorRyPct: 0.8345,
            ),
          ];

          // Vérification factuelle (ÉTENDUE : x ET y désormais, pas
          // seulement x comme dans la version précédente) que les
          // coordonnées haussmann/moderne/provencal proviennent bien de
          // `PerspCalib.demoPresets`, déjà committé -- pas des valeurs
          // recopiées puis divergentes.
          for (final s in scenes) {
            if (s.name == 'scandinave') continue; // candidat it1, cf. note.
            final preset = PerspCalib.demoPresets[s.name]!;
            expect(preset.ceilL.xPct, closeTo(s.ceilLxPct, 1e-9));
            expect(preset.ceilR.xPct, closeTo(s.ceilRxPct, 1e-9));
            expect(preset.ceilL.yPct, closeTo(s.ceilLyPct, 1e-9));
            expect(preset.ceilR.yPct, closeTo(s.ceilRyPct, 1e-9));
          }

          // ignore: avoid_print
          print(
            '${'scene'.padRight(12)} ${'L_px'.padLeft(8)} '
            '${'pH_px'.padLeft(8)} ${'theta(deg)'.padLeft(11)} '
            '${'sigma_max(px)'.padLeft(14)} verdict',
          );

          final verdictsByScene = <String, String>{};
          for (final s in scenes) {
            final w = s.widthPx, h = s.heightPx;
            final cxImg = w / 2.0;
            final ceilL = Offset(s.ceilLxPct * w, s.ceilLyPct * h);
            final ceilR = Offset(s.ceilRxPct * w, s.ceilRyPct * h);
            final floorL = Offset(s.ceilLxPct * w, s.floorLyPct * h);
            final floorR = Offset(s.ceilRxPct * w, s.floorRyPct * h);

            final chordPx = _dist(ceilL, ceilR);
            final pHPx = floorL.dy - ceilL.dy;

            // Intersection RÉELLE (pg.lineIntersect, pas une reconstruction
            // fermée) des lignes plafond et plancher -- si `null`, la
            // pente est dégénérée (parallèle) DANS LES DONNÉES COMMITTÉES
            // ELLES-MÊMES, pas par jugement visuel.
            final vp = pg.lineIntersect(ceilL, ceilR, floorL, floorR);

            if (vp == null) {
              verdictsByScene[s.name] = 'INDECIDABLE_DEGENERE';
              // ignore: avoid_print
              print(
                '${s.name.padRight(12)} ${chordPx.toStringAsFixed(1).padLeft(8)} '
                '${pHPx.toStringAsFixed(1).padLeft(8)} '
                '${'degenere'.padLeft(11)} ${'--'.padLeft(14)} '
                'INDECIDABLE (donnée dégénérée : ceilL.yPct==ceilR.yPct à la '
                'précision committée -- ni theta=0 confirmé, ni angle réel '
                'exclu)',
              );
              continue;
            }

            final thetaDeg = _thetaDegFromVpx(vp.dx, focalPx, cxImg);
            final absC = (cxImg - vp.dx).abs();
            // sigma_max f-indépendant : κ·pH·L·(180/π)/|C| (cf. commentaire
            // du groupe, dérivé de theta≈(180/π)·f/C au premier ordre).
            final sigmaMaxPx =
                kappaRefPhaseB * pHPx * chordPx * (180.0 / math.pi) / absC;
            final verdict = classifyOnSigmaMax(sigmaMaxPx);
            verdictsByScene[s.name] = verdict;

            // ignore: avoid_print
            print(
              '${s.name.padRight(12)} ${chordPx.toStringAsFixed(1).padLeft(8)} '
              '${pHPx.toStringAsFixed(1).padLeft(8)} '
              '${thetaDeg.toStringAsFixed(4).padLeft(11)} '
              '${sigmaMaxPx.toStringAsFixed(4).padLeft(14)} $verdict',
            );
          }

          // --- Assertions factuelles ---
          //
          // haussmann : theta≈-0.35° dérivé des presets (NON dégénéré,
          // NON nul) -- confirme le contrôle de cohérence attendu (la
          // scène à plus longue corde, donc au seuil angulaire le plus
          // bas, N'EST PAS un zéro visuel comme la version précédente
          // l'affirmait). sigma_max≈2.29px tombe DANS la fourchette
          // opérationnelle [seuilFacile,seuilDur]=[1.858,11.148] ->
          // INDECIDABLE, pas ECARTEE, pas GARDEE.
          expect(
            verdictsByScene['haussmann'],
            equals('INDECIDABLE'),
            reason:
                'haussmann a un theta réel non nul dérivé des presets '
                '(≈-0.35°), mais sigma_max (~2.29px) tombe dans la '
                'fourchette [1.858,11.148]px -- ni assez grand pour '
                'GARDEE au sens le plus dur, ni assez petit pour ECARTEE '
                'au sens le plus facile. Rapportée comme telle, jamais '
                'arbitrée -- et surtout PAS écartée sur un theta=0 qui '
                'n\'a jamais été le cas ici.',
          );

          // scandinave : même conclusion structurelle (theta réel non nul,
          // sigma_max dans la fourchette) -- mais pour une raison DIFFÉRENTE
          // de la version précédente (qui mélangeait corde 228px/espace
          // affichage avec pH 881px/espace image et concluait ECARTEE à
          // 3.5% de marge). En repère image cohérent (corde=313px,
          // pH=881px), le verdict est INDECIDABLE, pas ECARTEE -- la
          // conclusion précédente n'était donc pas seulement mal justifiée
          // dans sa méthode, elle était FAUSSE dans son résultat.
          expect(
            verdictsByScene['scandinave'],
            equals('INDECIDABLE'),
            reason:
                'scandinave (repère image cohérent, corde=313px≈228px '
                'affichage×1/0.729167 -- même mur, deux repères, PAS un '
                'désaccord de données) : sigma_max≈2.45px tombe dans la '
                'fourchette [1.858,11.148]px -- INDECIDABLE, PAS ECARTEE '
                'comme le concluait à tort la version précédente (bug de '
                'mélange de repères).',
          );

          // moderne/provencal : données dégénérées dans les presets
          // eux-mêmes (ceilL.yPct==ceilR.yPct à la précision committée) --
          // borné : la pente cachée la plus grande compatible avec la
          // précision d'arrondi (±0.0005 sur yPct, soit ±0.5 ULP) donne un
          // sigma_max pire-cas de 0.7526px (moderne) / 0.8739px
          // (provencal), tous deux SOUS seuilFacile=1.858px -- donc
          // l'incertitude d'arrondi seule ne peut PAS les faire basculer
          // vers GARDEE ni même vers INDECIDABLE côté haut ; mais on ne
          // peut pas non plus certifier theta=0 EXACT à partir d'un
          // arrondi à 3 décimales -- rapportées comme INDECIDABLE
          // (donnée dégénérée), jamais comme ECARTEE par un theta=0
          // supposé confirmé.
          for (final name in ['moderne', 'provencal']) {
            expect(
              verdictsByScene[name],
              equals('INDECIDABLE_DEGENERE'),
              reason:
                  '$name : ceilL.yPct==ceilR.yPct exactement dans '
                  '`demoPresets` (pas un jugement visuel) -- borne pire-cas '
                  'sous précision d\'arrondi (±0.0005) donne un sigma_max '
                  'max de <1px, sous seuilFacile, mais ceci ne certifie PAS '
                  'theta=0 exact non plus -- INDECIDABLE (donnée '
                  'dégénérée), jamais ECARTEE par défaut.',
            );
          }

          // ignore: avoid_print
          print(
            '\n[phaseC-point3] VERDICT GLOBAL (refait) : 0/4 GARDEE, 0/4 '
            'ECARTEE, 4/4 INDECIDABLE (2 par sigma_max dans la fourchette '
            'opérationnelle, 2 par donnée dégénérée dans les presets). '
            'AUCUNE scène ne peut être triée sans mesure supplémentaire '
            '(critère d\'arrêt du brief : on ne mesure PAS finement pour '
            'trancher -- donc on rapporte l\'indécidabilité telle quelle, '
            'on ne la résout pas arbitrairement).\n'
            '\n'
            '[phaseC-point3] Conclusion retirée : la version précédente '
            'concluait "0/4 gardée -> le frontal est le chemin normal -> '
            'vanishing_point.dart passe en priorité correction" -- cette '
            'conclusion reposait entièrement sur un theta_à_l\'oeil=0 non '
            'mesuré, maintenant abandonné (haussmann et scandinave ont un '
            'theta réel non nul dérivé des presets). Le constat Phase B '
            'point 3 (wallNormal=-camera.forward figeant l\'angle '
            'plafond/mur à 90° pour tout theta réel) reste valable et '
            'suffisant en soi pour justifier le sujet vanishing_point.dart, '
            'SANS cette béquille -- aucune escalade de priorité n\'est '
            'proposée ici à partir du résultat de ce tri.',
          );
        },
      );
    },
  );
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
