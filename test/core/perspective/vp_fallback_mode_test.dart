// Point 7b-2 — mesure fonctionnelle des deux modes réels de
// `VpFallbackMode` (`erreurExplicite`, `projectionParallele`), sans
// arbitrage. Trois test() neufs, chacun bouclant sur les 4 presets
// réels via le motif collecteur déjà retenu (accumulation dans une
// liste, un seul `expect(..., isEmpty)` après la boucle — voir
// `docs/logs/errata_etage_a.txt` / commit `d066ddc`) : tous les
// presets sont évalués à chaque exécution, aucun `expect` throwing
// à l'intérieur de la boucle qui masquerait les suivants.
//
// Le miroir 40+4=44 de `vp_frac_degenere_test.dart` N'EST PAS touché
// par ce fichier : il reste épinglé sur `repliHistoriqueCoupleBas`,
// aucune assertion affaiblie, aucun site d'appel existant modifié.
//
// Prédictions consignées avant toute écriture de code (voir
// `docs/ETAT.md`, Point 7b-2) :
//   1. Atteignabilité : la branche à couple unique fini n'est
//      atteinte par AUCUN des 4 presets aux valeurs nominales (les
//      deux couples y sont simultanément finis) — `erreurExplicite`
//      ne lève sur aucun preset nominal, et lève un `ArgumentError`
//      sur la scène dégénérée construite (δ_deg, déjà présente dans
//      `vp_frac_degenere_test.dart`).
//   2. Garde-fou amont : `residualFrac` nominal mesuré sur les 4
//      presets réels ne fournit aucun seuil discriminant sous sa
//      borne basse — mesure seule, aucune décision.
//   3. `projectionParallele` : sur au moins 3 des 4 presets, les
//      deux droites du couple dégénéré (à δ_deg) sont CONFONDUES
//      (distance perpendiculaire nulle), pas seulement parallèles
//      distinctes — mesuré ici par deux grandeurs séparées :
//      colinéarité des directions et distance perpendiculaire entre
//      les deux droites. `projectionParallele` lève un
//      `UnimplementedError`, capturé et compté, jamais un repli
//      arbitraire.
//
// Delta de compte déclaré avant exécution : 229 → 232 (3 test()
// neufs, un par mesure ci-dessus).
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/calib_canvas.dart';
import 'package:staff_decor_studio/core/perspective/persp_geometry.dart' as pg;
import 'package:staff_decor_studio/core/perspective/vanishing_point.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

/// Reproduit exactement `imgDrawFor` de `vp_frac_degenere_test.dart`
/// (même canevas cible 1400×975, même calcul "contain") — dupliqué
/// ici plutôt qu'importé car ce fichier de fonctions/constantes
/// top-level n'est pas exposé comme bibliothèque partagée (fichier de
/// test, pas `lib/`) ; valeurs identiques, aucune divergence
/// introduite.
const double kCanvasW = 1400.0;
const double kCanvasH = 975.0;

const Map<String, (double, double)> kDemoSceneNativeSize = {
  'haussmann': (2560.0, 1783.0),
  'moderne': (1960.0, 1470.0),
  'provencal': (2560.0, 1707.0),
  'scandinave': (1920.0, 1088.0),
};

ImgDraw imgDrawFor(double srcW, double srcH) {
  final scale = (kCanvasW / srcW < kCanvasH / srcH) ? kCanvasW / srcW : kCanvasH / srcH;
  final dw = srcW * scale;
  final dh = srcH * scale;
  return ImgDraw(
    dx: (kCanvasW - dw) / 2,
    dy: (kCanvasH - dh) / 2,
    dw: dw,
    dh: dh,
    scale: scale,
  );
}

CalibCanvasPoints calibPointsFor(String key) {
  final calib = PerspCalib.forDemoScene(key);
  final (srcW, srcH) = kDemoSceneNativeSize[key]!;
  final imgDraw = imgDrawFor(srcW, srcH);
  return CalibCanvasPoints.fromCalib(calib, imgDraw: imgDraw, w: kCanvasW, h: kCanvasH);
}

/// Construit la scène dégénérée à δ_deg=-0.01 pour [key] (couple haut
/// rendu dégénéré/parallèle par translation verticale de wallTL/wallTR)
/// — même construction que le test "discontinuité à δ_deg" de
/// `vp_frac_degenere_test.dart`, reproduite ici car nécessaire aux
/// trois mesures ci-dessous.
CalibCanvasPoints calibPointsAtDeltaDeg(String key) {
  final base = PerspCalib.forDemoScene(key);
  final (srcW, srcH) = kDemoSceneNativeSize[key]!;
  final imgDraw = imgDrawFor(srcW, srcH);
  const deltaDeg = -0.01;
  final calibDeg = base.copyWith(
    wallTL: base.wallTL.copyWith(yPct: base.wallTL.yPct + deltaDeg),
    wallTR: base.wallTR.copyWith(yPct: base.wallTR.yPct + deltaDeg),
  );
  return CalibCanvasPoints.fromCalib(calibDeg, imgDraw: imgDraw, w: kCanvasW, h: kCanvasH);
}

void main() {
  // ===========================================================================
  // Mesure 1 — Atteignabilité de la branche à couple unique fini.
  // ===========================================================================
  test(
    'erreurExplicite : ne lève sur AUCUN des 4 presets nominaux, lève un '
    'ArgumentError sur la scène dégénérée construite (δ_deg) pour chacun — '
    'mesure d\'atteignabilité, motif collecteur',
    () {
      final mismatches = <String>[];

      for (final key in kDemoSceneNativeSize.keys) {
        // --- Volet nominal : les deux couples doivent être finis, donc
        //     la branche à couple unique fini (celle que fallbackMode
        //     gouverne) n'est PAS atteinte — compute() ne doit PAS
        //     lever ici, quel que soit fallbackMode.
        final cpNominal = calibPointsFor(key);
        try {
          final vpNominal = VanishingPoint.compute(
            fTL: cpNominal.ceilL,
            fTR: cpNominal.ceilR,
            fBL: cpNominal.floorL,
            fBR: cpNominal.floorR,
            wallTL: cpNominal.wallTL,
            wallTR: cpNominal.wallTR,
            wallBL: cpNominal.wallBL,
            wallBR: cpNominal.wallBR,
            fallbackMode: VpFallbackMode.erreurExplicite,
          );
          if (vpNominal.residualPx == null) {
            mismatches.add(
              '$key (nominal) : residualPx null — les deux couples ne '
              'sont PAS simultanément finis à δ=0, contrairement à la '
              'prédiction ; erreurExplicite aurait dû lever et n\'a pas '
              'été exercé sur ce chemin.',
            );
          }
          // ignore: avoid_print
          print('[7b-2-atteignabilite] $key (nominal) : erreurExplicite '
              'n\'a PAS levé, residualPx=${vpNominal.residualPx}');
        } catch (e) {
          mismatches.add(
            '$key (nominal) : erreurExplicite a levé de façon inattendue '
            '($e) — la branche à couple unique fini serait atteinte par '
            'une calibration réelle à δ=0, contredisant la prédiction '
            'd\'atteignabilité.',
          );
        }

        // --- Volet dégénéré (δ_deg) : un seul couple (le bas) est fini
        //     par construction — la branche EST atteinte, erreurExplicite
        //     DOIT lever.
        final cpDeg = calibPointsAtDeltaDeg(key);
        try {
          VanishingPoint.compute(
            fTL: cpDeg.ceilL,
            fTR: cpDeg.ceilR,
            fBL: cpDeg.floorL,
            fBR: cpDeg.floorR,
            wallTL: cpDeg.wallTL,
            wallTR: cpDeg.wallTR,
            wallBL: cpDeg.wallBL,
            wallBR: cpDeg.wallBR,
            fallbackMode: VpFallbackMode.erreurExplicite,
          );
          mismatches.add(
            '$key (δ_deg) : erreurExplicite n\'a PAS levé alors que le '
            'couple haut est dégénéré par construction — la branche à '
            'couple unique fini devrait être atteinte ici.',
          );
        } on ArgumentError catch (e) {
          // ignore: avoid_print
          print('[7b-2-atteignabilite] $key (δ_deg) : erreurExplicite a '
              'levé ArgumentError comme prévu : ${e.message}');
        } catch (e) {
          mismatches.add(
            '$key (δ_deg) : erreurExplicite a levé un type d\'exception '
            'inattendu ($e), pas un ArgumentError.',
          );
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason: 'Mesure d\'atteignabilité en échec sur ${mismatches.length} '
            'preset(s) — voir détail : $mismatches',
      );
    },
  );

  // ===========================================================================
  // Mesure 2 — Garde-fou amont (residualFrac sur la baseline non
  // perturbée), sans arbitrage : mesure seule, aucun seuil décidé ici.
  // ===========================================================================
  test(
    'residualFrac nominal sur les 4 presets réels : mesure seule, aucun '
    'seuil discriminant sous la borne basse — pas d\'arbitrage',
    () {
      final mismatches = <String>[];
      final fracs = <String, double>{};

      for (final key in kDemoSceneNativeSize.keys) {
        final cp = calibPointsFor(key);
        final vp = VanishingPoint.compute(
          fTL: cp.ceilL,
          fTR: cp.ceilR,
          fBL: cp.floorL,
          fBR: cp.floorR,
          wallTL: cp.wallTL,
          wallTR: cp.wallTR,
          wallBL: cp.wallBL,
          wallBR: cp.wallBR,
          // Guard sur la baseline NON perturbée, jamais residualPx au
          // moment d'une bascule (où il vaut null par construction) —
          // repliHistoriqueCoupleBas ici uniquement parce que les deux
          // couples sont finis à δ=0 (voir Mesure 1) : ce membre est
          // observationnellement inerte sur ce chemin, seul residualFrac
          // nous intéresse.
          fallbackMode: VpFallbackMode.repliHistoriqueCoupleBas,
        );

        if (vp.residualFrac == null) {
          mismatches.add(
            '$key : residualFrac null en configuration nominale — '
            'contredit la Mesure 1 (les deux couples devraient être '
            'finis à δ=0).',
          );
          continue;
        }
        fracs[key] = vp.residualFrac!;

        // ignore: avoid_print
        print('[7b-2-guardefou] $key : residualFrac='
            '${(vp.residualFrac! * 100).toStringAsFixed(1)}%');
      }

      expect(
        mismatches,
        isEmpty,
        reason: 'Mesure du garde-fou amont en échec : $mismatches',
      );

      // Rapport de la plage mesurée — AUCUNE décision de seuil ici,
      // seulement la constatation qu'un seuil sous la borne basse
      // mesurée déclencherait sur les 4 presets simultanément.
      final minFrac = fracs.values.reduce((a, b) => a < b ? a : b);
      final maxFrac = fracs.values.reduce((a, b) => a > b ? a : b);
      // ignore: avoid_print
      print('[7b-2-guardefou] plage mesurée sur les 4 presets : '
          '[${(minFrac * 100).toStringAsFixed(1)}%, '
          '${(maxFrac * 100).toStringAsFixed(1)}%] — tout seuil de '
          'rejet placé sous ${(minFrac * 100).toStringAsFixed(1)}% '
          'déclencherait sur les 4 presets simultanément, donc ne '
          'discriminerait rien.');

      expect(fracs.length, equals(4),
          reason: 'Les 4 presets doivent tous produire une mesure — '
              'sinon la plage rapportée est incomplète.');
      // Contrôle de sanité seul (pas un seuil de qualité de
      // calibration) : la plage mesurée doit être strictement
      // positive et finie sur les 4 presets, cohérent avec le Groupe 5
      // de vp_frac_degenere_test.dart.
      expect(minFrac > 0, isTrue);
      expect(maxFrac.isFinite, isTrue);
    },
  );

  // ===========================================================================
  // Mesure 3 — projectionParallele : séparation confondues/parallèles
  // distinctes, mesurée preset par preset, motif collecteur. Aucun
  // repli arbitraire : UnimplementedError capturé et compté.
  // ===========================================================================
  test(
    'projectionParallele : mesure confondues vs parallèles distinctes sur '
    'les 4 presets à δ_deg — UnimplementedError capturé, sans trancher',
    () {
      final mismatches = <String>[];
      var nbConfondues = 0;
      var nbParallelesDistinctes = 0;

      for (final key in kDemoSceneNativeSize.keys) {
        final cpDeg = calibPointsAtDeltaDeg(key);

        // Vérifie d'abord que le couple haut est bien dégénéré (précondition
        // de cette mesure — sinon la branche projectionParallele ne serait
        // pas atteinte par cette scène et la mesure serait invalide).
        final vpTopNull = pg.lineIntersect(
          cpDeg.wallTL, cpDeg.ceilL, cpDeg.wallTR, cpDeg.ceilR,
        );
        if (vpTopNull != null) {
          mismatches.add(
            '$key : couple haut NON dégénéré à δ_deg (vpTop=$vpTopNull) — '
            'précondition de la scène construite invalidée.',
          );
          continue;
        }

        // Mesure 1/2 : colinéarité des directions du segment
        // (wallTL→ceilL) et (wallTR→ceilR) — produit vectoriel 2D
        // normalisé, nul si colinéaires (parallèles au sens strict).
        final dirTL = Offset(cpDeg.ceilL.dx - cpDeg.wallTL.dx, cpDeg.ceilL.dy - cpDeg.wallTL.dy);
        final dirTR = Offset(cpDeg.ceilR.dx - cpDeg.wallTR.dx, cpDeg.ceilR.dy - cpDeg.wallTR.dy);
        final lenTL = pg.dist(Offset.zero, dirTL);
        final lenTR = pg.dist(Offset.zero, dirTR);
        final crossDirs = lenTL < 1e-9 || lenTR < 1e-9
            ? 0.0
            : ((dirTL.dx / lenTL) * (dirTR.dy / lenTR) - (dirTL.dy / lenTL) * (dirTR.dx / lenTR)).abs();

        // Mesure 2/2 : distance perpendiculaire entre les deux droites
        // (composante de wallTR-wallTL projetée perpendiculairement à
        // la direction unitaire de la droite gauche) — nulle si les
        // droites sont CONFONDUES, non nulle si parallèles distinctes.
        final ux = dirTL.dx / lenTL, uy = dirTL.dy / lenTL;
        final vx = cpDeg.wallTR.dx - cpDeg.wallTL.dx, vy = cpDeg.wallTR.dy - cpDeg.wallTL.dy;
        final perpDist = (vx * uy - vy * ux).abs();

        final estConfondue = perpDist < 1e-6;
        if (estConfondue) {
          nbConfondues++;
        } else {
          nbParallelesDistinctes++;
        }

        // ignore: avoid_print
        print('[7b-2-projparallele] $key : crossDirs='
            '${crossDirs.toStringAsExponential(3)}  perpDist='
            '${perpDist.toStringAsFixed(4)}px  '
            '${estConfondue ? "CONFONDUES" : "PARALLÈLES DISTINCTES"}');

        // projectionParallele doit lever UnimplementedError dans TOUS
        // les cas ici (implémentation reportée à un tour ultérieur,
        // que les droites soient confondues ou distinctes) — capturé
        // et compté, jamais un repli arbitraire.
        try {
          VanishingPoint.compute(
            fTL: cpDeg.ceilL,
            fTR: cpDeg.ceilR,
            fBL: cpDeg.floorL,
            fBR: cpDeg.floorR,
            wallTL: cpDeg.wallTL,
            wallTR: cpDeg.wallTR,
            wallBL: cpDeg.wallBL,
            wallBR: cpDeg.wallBR,
            fallbackMode: VpFallbackMode.projectionParallele,
          );
          mismatches.add(
            '$key : projectionParallele n\'a PAS levé — attendu '
            'UnimplementedError (non implémenté à ce tour).',
          );
        } on UnimplementedError catch (e) {
          // ignore: avoid_print
          print('[7b-2-projparallele] $key : UnimplementedError capturé '
              'comme prévu : $e');
        } catch (e) {
          mismatches.add(
            '$key : projectionParallele a levé un type d\'exception '
            'inattendu ($e), pas un UnimplementedError.',
          );
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason: 'Mesure projectionParallele en échec : $mismatches',
      );

      // ignore: avoid_print
      print('[7b-2-projparallele] bilan : $nbConfondues confondue(s), '
          '$nbParallelesDistinctes parallèle(s) distincte(s), sur '
          '${kDemoSceneNativeSize.length} presets.');

      // Rapport du fait mesuré — pas un arbitrage : au moins 3 des 4
      // presets doivent être en configuration confondue, conformément
      // à ce qui a déjà été établi (docs/ETAT.md, Point 7b).
      expect(
        nbConfondues,
        greaterThanOrEqualTo(3),
        reason: 'Attendu au moins 3 presets/4 en configuration confondue '
            '(perpDist≈0) à δ_deg — mesuré $nbConfondues. Si ce nombre a '
            'changé, le fait porté depuis le diagnostic précédent doit '
            'être réévalué, pas silencieusement ignoré.',
      );
    },
  );
}
