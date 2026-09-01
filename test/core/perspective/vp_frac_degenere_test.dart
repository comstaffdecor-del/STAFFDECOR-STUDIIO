// Étape 0 (brief "branchement du moteur géométrique réel") — vérifie que
// `VanishingPoint.compute` (vanishing_point.dart) ne retombe PAS, pour les
// 4 presets réels de production (`PerspCalib.demoPresets`), sur l'un des
// TROIS régimes dégénérés diagnostiqués au fil des tours précédents :
//
//   1. Conflation axe horizontal / axe de profondeur (bug racine) :
//      `lineIntersect(fTL,fTR,fBL,fBR)` intersecte deux droites
//      coplanaires du mur du fond (censées être parallèles), et
//      l'ancienne version renvoyait CE point comme "le" VP, utilisé par
//      `toward()`/`frac()` comme s'il portait l'axe de profondeur. Régime
//      reproductible sur le preset 'haussmann' (seul des 4 où les lignes
//      plafond/sol ne sont pas exactement parallèles dans la calibration
//      canvas actuelle — voir groupe 1 ci-dessous).
//
//   2. Repli "milieu de segment" : quand `lineIntersect(fTL,fTR,fBL,fBR)`
//      renvoie `null` (droites parallèles, cas de 'moderne'/'provencal'/
//      'scandinave'), l'ancienne version retombait sur le milieu du
//      segment fTL→fTR — un point qui ne dépend d'AUCUNE des fuyantes
//      latérales (wallTL/wallTR).
//
//   3. VP-centre (commit `47c17eca`, diagnostiqué comme un TROISIÈME
//      régime dégénéré à tour précédent) : VP = centre géométrique des 4
//      coins du mur du fond, terme d'obliquité nul — ne dépend PAS non
//      plus de wallTL/wallTR.
//
// Les régimes 2 et 3 partagent la même signature observable : le VP ne
// RÉAGIT PAS à une perturbation des points de mur latéral. C'est le
// critère de remplacement utilisé ci-dessous (groupe 2) — un critère de
// DÉPENDANCE CAUSALE, pas une comparaison à une valeur numérique
// spécifique (qui serait fragile et, pour ces presets symétriques,
// risquerait d'être vraie "par construction" sans rien prouver — voir la
// mise en garde explicite du brief : `vp.x=700.00` sur 3 presets à
// wallTL.xPct=0.0/wallTR.xPct=1.0 symétriques ne prouve PAS que le moteur
// mesure l'obliquité, seulement que le VP dépend de quelque chose — le
// test de perturbation ci-dessous va plus loin en le prouvant
// explicitement).
//
// ANCIENS CRITÈRES DE CE FICHIER, DISQUALIFIÉS PAR LE BRIEF (retirés, PAS
// simplement supprimés sans remplacement — voir groupes 1/2/3 ci-dessous
// pour ce qui les remplace) :
//   - `frac(ceilL, depthPx) > 0.05` : seuil arbitraire sans justification
//     géométrique, mesurait un symptôme (face plafond trop fine) du
//     régime 1 uniquement, sans jamais tester les régimes 2/3.
//   - `estRepliMilieu isFalse` (comparaison à (ceilL+ceilR)/2) : ne
//     détectait que le régime 2, silencieux sur le régime 3 (VP-centre),
//     qui ne coïncide pas avec le milieu de fTL→fTR mais est tout aussi
//     dégénéré.
//
// Aucun chiffre ci-dessous n'est recopié d'un script jetable ou de /tmp :
// toutes les valeurs numériques citées dans les commentaires ont été
// obtenues par exécution du harnais RÉEL (`flutter test` sur ce fichier
// tel qu'actuellement commité), pas par un calcul externe non versionné.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/calib_canvas.dart';
import 'package:staff_decor_studio/core/perspective/cornice_plinth_painter.dart';
import 'package:staff_decor_studio/core/perspective/persp_geometry.dart' as pg;
import 'package:staff_decor_studio/core/perspective/strip_px_from_dims.dart';
import 'package:staff_decor_studio/core/perspective/vanishing_point.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

/// Reproduit exactement `computeImgDraw` (lib/state/app_state.dart) pour
/// un canevas cible 1400×975 — mêmes valeurs déjà documentées et
/// vérifiées dans test/core/perspective/_debug_calib_bench_test.dart
/// (candidat haussmann/moderne/scandinave), pas des chiffres inventés
/// pour ce test.
const double kCanvasW = 1400.0;
const double kCanvasH = 975.0;

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

/// Dimensions natives réelles des 4 photos démo (vérifiées par `file`,
/// pas devinées) : haussmann 2560x1783, moderne 1960x1470, provencal
/// 2560x1707, scandinave 1920x1088.
const Map<String, (double, double)> kDemoSceneNativeSize = {
  'haussmann': (2560.0, 1783.0),
  'moderne': (1960.0, 1470.0),
  'provencal': (2560.0, 1707.0),
  'scandinave': (1920.0, 1088.0),
};

/// Construit les 8 points de calibration canvas (mur du fond + murs
/// latéraux) pour le preset [key], via le chemin de production réel
/// (`PerspCalib.forDemoScene` → `CalibCanvasPoints.fromCalib`).
CalibCanvasPoints calibPointsFor(String key) {
  final calib = PerspCalib.forDemoScene(key);
  final (srcW, srcH) = kDemoSceneNativeSize[key]!;
  final imgDraw = imgDrawFor(srcW, srcH);
  return CalibCanvasPoints.fromCalib(calib, imgDraw: imgDraw, w: kCanvasW, h: kCanvasH);
}

void main() {
  // =========================================================================
  // GROUPE 1 — Non-conflation axe horizontal / axe de profondeur (bug
  // racine, régime dégénéré #1). Applicable uniquement au preset
  // 'haussmann' : c'est le seul des 4 où `lineIntersect(fTL,fTR,fBL,fBR)`
  // renvoie un point FINI (droites plafond/sol pas exactement
  // parallèles dans la calibration canvas actuelle) — pour les 3 autres
  // presets, cette intersection horizontale est strictement `null`
  // (droites parallèles), donc il n'y a pas de second point fini à
  // comparer, et ce groupe ne s'applique pas.
  // =========================================================================
  group('Groupe 1 — VP de profondeur (compute) distinct du VP horizontal '
      '(lineIntersect brut) quand ce dernier existe', () {
    test(
      'haussmann : VanishingPoint.compute (axe profondeur) doit être un '
      'point DIFFÉRENT de lineIntersect(fTL,fTR,fBL,fBR) (axe horizontal)',
      () {
        const key = 'haussmann';
        final cp = calibPointsFor(key);

        final vpDepth = VanishingPoint.compute(
          fTL: cp.ceilL,
          fTR: cp.ceilR,
          fBL: cp.floorL,
          fBR: cp.floorR,
          wallTL: cp.wallTL,
          wallTR: cp.wallTR,
          wallBL: cp.wallBL,
          wallBR: cp.wallBR,
        );

        final vpHoriz = pg.lineIntersect(cp.ceilL, cp.ceilR, cp.floorL, cp.floorR);
        expect(
          vpHoriz,
          isNotNull,
          reason: 'précondition du groupe : ce test suppose que '
              "lineIntersect(fTL,fTR,fBL,fBR) réussit pour '$key' (droites "
              'plafond/sol non exactement parallèles dans la calibration '
              'canvas actuelle) — si ce n\'est plus le cas, ce groupe ne '
              's\'applique plus à ce preset et doit être retiré ou changé '
              'de preset cible, pas relâché.',
        );

        // ignore: avoid_print
        print('[groupe1] $key : vp_profondeur=${vpDepth.vp}  '
            'vp_horizontal_brut=$vpHoriz');

        final d = (vpDepth.vp - vpHoriz!).distance;
        expect(
          d,
          greaterThan(50.0),
          reason:
              "preset '$key' : VanishingPoint.compute renvoie ${vpDepth.vp}, "
              'trop proche du VP horizontal brut $vpHoriz (distance='
              '${d.toStringAsFixed(1)}px < 50px) — cela suggère une '
              "conflation entre l'axe de profondeur et l'axe horizontal du "
              "mur du fond, exactement le bug racine diagnostiqué : compute() "
              'doit utiliser les fuyantes latérales (wallTL→fTL, wallTR→fTR), '
              'pas les droites coplanaires ceil/floor.',
        );
      },
    );
  });

  // =========================================================================
  // GROUPE 2 — Dépendance causale réelle aux points de mur latéral (le
  // critère de remplacement qui couvre les régimes dégénérés #2 ET #3,
  // là où les anciens critères frac>0.05 / estRepliMilieu ne couvraient
  // que le régime #2 seul).
  //
  // Principe : un VP-centre (moyenne des 4 coins, régime #3) ou un VP
  // "milieu de segment fTL→fTR" (régime #2) NE DÉPEND PAS des points de
  // mur latéral wallTL/wallTR — leur valeur n'entre dans aucun calcul de
  // ces deux régimes dégénérés. Un vrai VP de profondeur, lui, DOIT
  // bouger quand wallTL (ou wallTR) bouge, puisqu'il est défini comme
  // l'intersection de (wallTL→fTL) et (wallTR→fTR).
  //
  // On perturbe wallTL de -20px en y (un déplacement arbitraire mais non
  // négligeable par rapport à l'échelle du canevas 1400×975) et on exige
  // que le VP résultant bouge de plus de 1px — un seuil délibérément bas
  // (par rapport aux déplacements de plusieurs centaines à dizaines de
  // milliers de px réellement observés à l'exécution) pour rester un test
  // de DÉPENDANCE, pas un test de MAGNITUDE (qui serait sur-spécifié et
  // fragile face à des ajustements futurs de calibration).
  // =========================================================================
  group('Groupe 2 — compute() dépend réellement des points de mur latéral '
      '(wallTL/wallTR), pas seulement des coins du mur du fond', () {
    for (final key in kDemoSceneNativeSize.keys) {
      test(
        '$key : perturber wallTL doit déplacer le VP calculé',
        () {
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
          );

          final wallTLPerturbed = Offset(cp.wallTL.dx, cp.wallTL.dy - 20.0);
          final vpPerturbed = VanishingPoint.compute(
            fTL: cp.ceilL,
            fTR: cp.ceilR,
            fBL: cp.floorL,
            fBR: cp.floorR,
            wallTL: wallTLPerturbed,
            wallTR: cp.wallTR,
            wallBL: cp.wallBL,
            wallBR: cp.wallBR,
          );

          // Les deux résultats doivent être des points finis pour que la
          // comparaison de distance ait un sens (voir Groupe 3 pour le
          // cas w=0 séparément, non concerné ici pour ces 4 presets).
          expect(vp.isAtInfinity, isFalse,
              reason: "preset '$key' : VP attendu fini pour cette "
                  'calibration (mur latéral non exactement parallèle au '
                  'mur du fond) — si ce n\'est plus vrai, ce test doit être '
                  'adapté, pas relâché.');
          expect(vpPerturbed.isAtInfinity, isFalse);

          final delta = (vpPerturbed.vp - vp.vp).distance;

          // ignore: avoid_print
          print('[groupe2] $key : vp=${vp.vp}  vp_perturbe=${vpPerturbed.vp}  '
              'delta=${delta.toStringAsFixed(1)}px');

          expect(
            delta,
            greaterThan(1.0),
            reason:
                "preset '$key' : déplacer wallTL de 20px en y ne change le "
                'VP calculé que de ${delta.toStringAsFixed(3)}px — trop peu '
                'pour qu\'une vraie dépendance géométrique existe. Cela '
                'reproduit la signature des régimes dégénérés #2 (repli '
                'milieu de segment) et #3 (VP-centre), qui ne dépendent '
                "d'AUCUN point de mur latéral, seulement des coins du mur "
                'du fond ou de leur moyenne.',
          );
        },
      );
    }
  });

  // =========================================================================
  // GROUPE 3 — Non-coïncidence avec le centre géométrique du mur du fond
  // (cible le régime dégénéré #3 — VP-centre, commit `47c17eca` — en
  // complément du test de dépendance causale du Groupe 2).
  //
  // ⚠️ RÉÉCRITURE (relecture externe, brief "Suite 2" point 6) — l'ancienne
  // version de ce groupe testait `d = (vp.vp - wallCenter).distance >
  // 50.0` : une norme euclidienne globale, avec un seuil de 50px jamais
  // justifié.
  //
  // ⚠️ CORRECTION (relecture externe #2, brief "Suite 2" point 7-prélude) —
  // `closeTo(700.0, 0.5)` était une TROISIÈME récurrence d'une constante
  // recopiée : 700.0 = `kCanvasW / 2` (kCanvasW = 1400.0, voir ligne 70 de
  // ce fichier), pas une grandeur propre au problème géométrique. Corrigé
  // ci-dessous : l'assertion x compare désormais explicitement à
  // `kCanvasW / 2`, jamais au littéral 700.0.
  //
  // CONSTAT PAR LECTURE/EXÉCUTION (log `docs/logs/groupe3_avant_split.txt`,
  // sondes jetables supprimées après usage, chiffres reproduits ci-dessous
  // par le code committé) :
  //   - Sur moderne/provencal/scandinave : vp.x == kCanvasW/2 EXACTEMENT
  //     (dx = 0.0). Toute la "distance" de l'ancien test passait donc PAR
  //     LA SEULE composante verticale (dy) — l'assertion `d > 50.0` ne
  //     prouvait RIEN sur l'axe horizontal pour ces 3 presets.
  //   - Sur haussmann : vp.x = 742.0 ≠ kCanvasW/2. C'est le seul des 4
  //     presets où dx ≠ 0.
  //
  // HYPOTHÈSE TESTÉE ET INFIRMÉE PAR LA MESURE (haussmann) : "les 42px de
  // vp.x viennent d'une asymétrie de wallTL/wallTR par rapport à l'axe
  // médian du canvas". Mesure : (wallTL.dx - kCanvasW/2) +
  // (wallTR.dx - kCanvasW/2) = 0.0 EXACTEMENT (à ~3e-13 de la précision
  // machine, voir le test "haussmann : asymétrie dx de wallTL/wallTR
  // infirmée" ci-dessous) — symétrie parfaite en x. L'asymétrie x de
  // wallTL/wallTR NE PEUT PAS être la source des 42px : elle est nulle par
  // construction, démontré par une assertion PERMANENTE (pas une sonde
  // jetable supprimée).
  //
  // ⚠️ CORRECTION (relecture externe #2) — le mécanisme causal réel
  // (combinaison des pentes ceilL/ceilR et wallTL/wallTR) n'existait
  // auparavant que dans ce commentaire, chiffres recopiés de sondes
  // jetables supprimées (87.75/82.875/97.5/92.625). Corrigé : le test
  // "haussmann : décomposition causale de dx par isolement des pentes"
  // ci-dessous exécute cette décomposition EN PERMANENCE à partir des
  // valeurs réelles de `cp` (aucun chiffre recopié) et vérifie par
  // assertion que (a) aplatir les DEUX pentes simultanément fait
  // s'effondrer vp.x sur kCanvasW/2 exactement, (b) aplatir une seule
  // pente à la fois NE restaure PAS ce centrage — ce qui démontre que la
  // combinaison des deux pentes est nécessaire pour expliquer le
  // décalage, sans prétendre à une décomposition additive précise (non
  // démontrée, non assertionnée).
  //
  // SEUIL DE 50px SUPPRIMÉ, remplacé par : (a) deux assertions séparées
  // x/y, (b) l'écart vertical rapporté en fraction de `pH` (invariant
  // d'échelle — un écart de 300px n'a pas le même sens à pH=600 qu'à
  // pH=6000), avec une borne choisie et documentée comme telle (PAS
  // dérivée), décision de rejet renvoyée au point 7.
  //
  // ⚠️ FALSIFICATION (relecture externe #2, brief "Suite 2" point 7-
  // prélude) — les 4 valeurs dy/pH mesurées tiennent dans 0.5390-0.5640
  // (±2.3%), une plage resserrée qui pourrait suggérer que dy/pH est
  // FORCÉ par construction (identité algébrique déguisée) plutôt qu'une
  // vraie mesure sensible à la calibration. Le conditionnement (Groupe 5)
  // varie lui d'un facteur 13 (98%-121%) sur les mêmes presets — mais
  // conditionnement (angle entre fuyantes, horizontal) et dy/pH (vertical)
  // ne sont pas nécessairement corrélés, donc cette variation ne suffit
  // PAS à trancher.
  //
  // Test tranché par FALSIFICATION DIRECTE (voir test "falsification :
  // dy/pH réagit à une perturbation de yPct" ci-dessous, permanent) :
  // perturber wallTL.yPct et wallTR.yPct de +0.01 (symétrique) sur les 4
  // presets fait BOUGER dy/pH d'une quantité non nulle :
  //   haussmann  : 0.5390 → 0.5796 (Δ=+0.0406)
  //   moderne    : 0.5640 → 0.6280 (Δ=+0.0640)
  //   provencal  : 0.5580 → 0.6159 (Δ=+0.0580)
  //   scandinave : 0.5544 → 0.6088 (Δ=+0.0544)
  // ⚠️ CORRECTION (Point 6bis) — un seul signe de perturbation a été
  // testé ici (+0.01 sur les 4 presets). "Δ positif" sur CE signe
  // d'entrée ne permet PAS de conclure à une proportionnalité générale
  // "delta positif ⇒ dy/pH augmente" pour tout δ : c'est une
  // généralisation non vérifiée (le Groupe 3bis ci-dessous montre que
  // dy/pH est affine en δ sur l'intervalle testé, ce qui est plus fort
  // et plus précis que cette phrase, mais seulement hors du point de
  // bascule de branche δ_deg — voir Groupe 3bis pour la portée exacte).
  // dy/pH N'EST DONC PAS une identité algébrique déguisée : c'est une
  // mesure réelle, sensible à la calibration d'entrée. La borne 0.3
  // choisie ci-dessous a une marge d'environ ×1.8 sur les valeurs
  // observées (0.539/0.3 ≈ 1.80), documentée comme telle — CHOISIE, PAS
  // DÉRIVÉE, décision de rejet renvoyée au point 7.
  group('Groupe 3 — VP vs centre géométrique du mur du fond, composantes '
      'x et y séparées (régime VP-centre)', () {
    for (final key in kDemoSceneNativeSize.keys) {
      test('$key : composante y (verticale) — écart rapporté en '
          'fraction de pH, borne choisie explicitement (pas dérivée)', () {
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
        );
        expect(vp.isAtInfinity, isFalse);
        final pH = vp.pH;
        final wallCenterY =
            (cp.ceilL.dy + cp.ceilR.dy + cp.floorL.dy + cp.floorR.dy) / 4;
        final dy = (vp.vp.dy - wallCenterY).abs();
        final dyOverPh = dy / pH;

        print('[groupe3-y] $key : vp.y=${vp.vp.dy.toStringAsFixed(1)}  '
            'centre_y=${wallCenterY.toStringAsFixed(1)}  '
            'dy=${dy.toStringAsFixed(1)}px  pH=${pH.toStringAsFixed(1)}  '
            'dy/pH=${dyOverPh.toStringAsFixed(4)}');

        // Borne CHOISIE (pas dérivée d'une propriété géométrique) : 0.3·pH
        // — mesuré à 0.54-0.56 sur les 4 presets réels, largement au-delà.
        // Sert de filet de non-régression sur ce test précis, PAS de
        // critère de qualité de calibration (voir point 7 pour cette
        // décision-là).
        expect(
          dyOverPh,
          greaterThan(0.3),
          reason: "preset '$key' : écart vertical VP/centre "
              '(${dyOverPh.toStringAsFixed(4)}·pH) sous la borne choisie '
              '0.3·pH — signature du régime dégénéré #3 (VP-centre) non '
              'détectée sur la composante verticale pour ce preset.',
        );
      });

      test('$key : composante x (horizontale) — assertion POSITIVE de '
          'sous-détermination, pas un skip', () {
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
        );
        final wallCenterX =
            (cp.ceilL.dx + cp.ceilR.dx + cp.floorL.dx + cp.floorR.dx) / 4;

        print('[groupe3-x] $key : vp.x=${vp.vp.dx}  '
            'centre_x=${wallCenterX.toStringAsFixed(1)}');

        final canvasCenterX = kCanvasW / 2;

        if (key == 'haussmann') {
          // Seul preset où vp.x ≠ kCanvasW/2 (742.0, valeur mesurée) —
          // voir le docstring de ce groupe et le test de décomposition
          // causale ci-après : le lien "asymétrie dx de wallTL/wallTR" a
          // été TESTÉ ET INFIRMÉ (dx symétrique à 3e-13 près, assertion
          // permanente ci-dessous). On ne réaffirme donc PAS
          // x==kCanvasW/2 ici, mais on ne prétend pas non plus avoir une
          // décomposition additive précise à assertionner : ce test
          // rapporte seulement la valeur mesurée.
          expect(vp.vp.dx, closeTo(742.0, 0.5), reason: 'valeur mesurée, '
              'source démontrée = combinaison des pentes ceilL/ceilR et '
              'wallTL/wallTR (voir test de décomposition causale '
              'ci-dessous), PAS une asymétrie dx (infirmée par la mesure '
              'permanente : dx de wallTL/wallTR symétrique à 3e-13 près).');
        } else {
          // Assertion POSITIVE affirmant la sous-détermination actuelle :
          // vp.x == kCanvasW/2 (centre canvas imposé par calibration, PAS
          // une mesure d'obliquité) à 0.5px près sur moderne/provencal/
          // scandinave. Volontairement PAS un skip() (un test sauté ne
          // signale rien) : cette assertion devient ROUGE le jour où
          // l'axe horizontal portera enfin de l'information — c'est le
          // comportement attendu, pas un test à "réparer" à ce moment.
          expect(vp.vp.dx, closeTo(canvasCenterX, 0.5), reason: "preset "
              "'$key' : vp.x doit rester égal au centre canvas "
              '(kCanvasW/2 = ${canvasCenterX.toStringAsFixed(1)}) tant '
              "que l'axe horizontal ne porte aucune information de "
              "profondeur pour ce preset -- si cette assertion échoue, "
              "c'est que la calibration a changé et QUE L'AXE HORIZONTAL "
              'PORTE MAINTENANT UNE INFORMATION RÉELLE : ce test doit '
              'alors être retiré, pas relâché.');
        }
      });
    }

    // -----------------------------------------------------------------
    // Décomposition causale de dx sur haussmann (relecture externe #2) :
    // remplace l'ancienne explication qui n'existait que dans un
    // commentaire avec des chiffres recopiés de sondes jetables
    // supprimées. Ici, TOUT est recalculé à partir des points de
    // calibration réels de `cp` — aucun chiffre en dur.
    // -----------------------------------------------------------------
    test('haussmann : asymétrie dx de wallTL/wallTR infirmée comme '
        'source du décalage (assertion permanente, pas une sonde '
        'jetable)', () {
      final cp = calibPointsFor('haussmann');
      final canvasCenterX = kCanvasW / 2;
      final asymSum =
          (cp.wallTL.dx - canvasCenterX) + (cp.wallTR.dx - canvasCenterX);

      print('[groupe3-x-asym] haussmann : wallTL.dx-centre='
          '${(cp.wallTL.dx - canvasCenterX).toStringAsFixed(6)}  '
          'wallTR.dx-centre=${(cp.wallTR.dx - canvasCenterX).toStringAsFixed(6)}  '
          'somme=${asymSum.toStringAsFixed(6)}');

      expect(
        asymSum.abs(),
        lessThan(1e-9),
        reason: "preset 'haussmann' : la somme des écarts (wallTL.dx - "
            'centre) + (wallTR.dx - centre) devrait être exactement '
            'nulle par symétrie de construction si cette assertion '
            'échoue, la calibration a changé et l\'hypothèse '
            "d'asymétrie dx redevient recevable comme source des 42px "
            '- elle est pour l\'instant infirmée par cette mesure.',
      );
    });

    test('haussmann : décomposition causale de dx par isolement des '
        'pentes ceilL/ceilR et wallTL/wallTR (aucun chiffre recopié '
        "d'une sonde supprimée)", () {
      final cp = calibPointsFor('haussmann');
      final canvasCenterX = kCanvasW / 2;

      Offset compute(Offset ceilL, Offset ceilR, Offset wallTL, Offset wallTR) =>
          VanishingPoint.compute(
            fTL: ceilL,
            fTR: ceilR,
            fBL: cp.floorL,
            fBR: cp.floorR,
            wallTL: wallTL,
            wallTR: wallTR,
            wallBL: cp.wallBL,
            wallBR: cp.wallBR,
          ).vp;

      final vpReal = compute(cp.ceilL, cp.ceilR, cp.wallTL, cp.wallTR);

      final avgCeilY = (cp.ceilL.dy + cp.ceilR.dy) / 2;
      final ceilLFlat = Offset(cp.ceilL.dx, avgCeilY);
      final ceilRFlat = Offset(cp.ceilR.dx, avgCeilY);
      final vpCeilFlat = compute(ceilLFlat, ceilRFlat, cp.wallTL, cp.wallTR);

      final avgWallY = (cp.wallTL.dy + cp.wallTR.dy) / 2;
      final wallTLFlat = Offset(cp.wallTL.dx, avgWallY);
      final wallTRFlat = Offset(cp.wallTR.dx, avgWallY);
      final vpWallFlat = compute(cp.ceilL, cp.ceilR, wallTLFlat, wallTRFlat);

      final vpBothFlat = compute(ceilLFlat, ceilRFlat, wallTLFlat, wallTRFlat);

      print('[groupe3-x-decomp] haussmann : reel.x=${vpReal.dx}  '
          'ceilAplati.x=${vpCeilFlat.dx}  wallAplati.x=${vpWallFlat.dx}  '
          'lesDeuxAplatis.x=${vpBothFlat.dx}  '
          'centre=${canvasCenterX.toStringAsFixed(1)}');

      // (a) Aplatir les DEUX pentes simultanément fait s'effondrer vp.x
      // exactement sur le centre canvas.
      expect(
        vpBothFlat.dx,
        closeTo(canvasCenterX, 0.5),
        reason: 'aplatir simultanément ceilL/ceilR.dy ET wallTL/wallTR.dy '
            'devrait ramener vp.x sur le centre canvas — si ce n\'est '
            'plus le cas, la décomposition causale documentée ici n\'est '
            'plus valide.',
      );

      // (b) Aplatir UNE SEULE pente à la fois ne restaure PAS le
      // centrage — preuve que la combinaison des deux est nécessaire,
      // sans affirmer de décomposition additive précise.
      expect(
        vpCeilFlat.dx,
        isNot(closeTo(canvasCenterX, 5.0)),
        reason: 'aplatir seulement la pente du plafond ne doit PAS '
            'suffire à ramener vp.x sur le centre canvas — sinon la '
            'pente du plafond seule expliquerait le décalage, ce qui '
            'contredirait la décomposition causale documentée.',
      );
      expect(
        vpWallFlat.dx,
        isNot(closeTo(canvasCenterX, 5.0)),
        reason: 'aplatir seulement la pente du mur latéral ne doit PAS '
            'suffire à ramener vp.x sur le centre canvas — sinon la '
            'pente du mur seule expliquerait le décalage, ce qui '
            'contredirait la décomposition causale documentée.',
      );
    });

    // -----------------------------------------------------------------
    // Falsification (relecture externe #2) : dy/pH est-il une mesure
    // sensible à la calibration, ou une identité algébrique déguisée qui
    // ne bougerait jamais quel que soit l'input ? Tranché en perturbant
    // wallTL.yPct/wallTR.yPct de +0.01 (symétrique) sur les 4 presets et
    // en vérifiant que dy/pH bouge d'une quantité NON NULLE dans le sens
    // physiquement attendu (perturbation positive vers le bas ⇒ dy/pH
    // augmente). Si dy/pH restait strictement identique à la baseline
    // quel que soit l'input, l'assertion `dyOverPh > 0.3` ci-dessus ne
    // testerait qu'une propriété de la formule, jamais la calibration
    // réelle — ce n'est PAS le cas ici (voir chiffres dans le docstring
    // du groupe, reproduits par ce test).
    // -----------------------------------------------------------------
    for (final key in kDemoSceneNativeSize.keys) {
      test('$key : falsification — dy/pH réagit à une perturbation de '
          'yPct (pas une identité algébrique déguisée)', () {
        final base = PerspCalib.forDemoScene(key);
        final (srcW, srcH) = kDemoSceneNativeSize[key]!;

        double dyOverPhFor(PerspCalib calib) {
          final imgDraw = imgDrawFor(srcW, srcH);
          final cp = CalibCanvasPoints.fromCalib(
            calib,
            imgDraw: imgDraw,
            w: kCanvasW,
            h: kCanvasH,
          );
          final vp = VanishingPoint.compute(
            fTL: cp.ceilL,
            fTR: cp.ceilR,
            fBL: cp.floorL,
            fBR: cp.floorR,
            wallTL: cp.wallTL,
            wallTR: cp.wallTR,
            wallBL: cp.wallBL,
            wallBR: cp.wallBR,
          );
          final wallCenterY =
              (cp.ceilL.dy + cp.ceilR.dy + cp.floorL.dy + cp.floorR.dy) / 4;
          final dy = (vp.vp.dy - wallCenterY).abs();
          return dy / vp.pH;
        }

        final baseline = dyOverPhFor(base);
        const perturbationDelta = 0.01;
        final perturbed = base.copyWith(
          wallTL: base.wallTL.copyWith(
            yPct: base.wallTL.yPct + perturbationDelta,
          ),
          wallTR: base.wallTR.copyWith(
            yPct: base.wallTR.yPct + perturbationDelta,
          ),
        );
        final perturbedValue = dyOverPhFor(perturbed);
        final delta = perturbedValue - baseline;

        print('[groupe3-y-falsification] $key : baseline=$baseline  '
            'perturbe(+$perturbationDelta)=$perturbedValue  delta=$delta');

        expect(
          delta,
          greaterThan(0.001),
          reason: "preset '$key' : perturber wallTL/wallTR.yPct de "
              '+$perturbationDelta ne fait bouger dy/pH que de '
              '${delta.toStringAsFixed(6)} — si ce delta était nul ou '
              'quasi nul, dy/pH serait une identité algébrique déguisée '
              '(forcée par la construction, indépendante de la '
              "calibration réelle), et l'assertion `dyOverPh > 0.3` du "
              'test y ci-dessus devrait être requalifiée comme telle au '
              'lieu de rester présentée comme une mesure de '
              'conditionnement.',
        );
      });
    }
  });

  // =========================================================================
  // GROUPE 3bis — Diagnostic de l'anomalie -78.0px (relecture externe #2,
  // tour suivant) : la falsification ci-dessus semblait montrer un point
  // hors droite à δ=-0.01. Balayage fin exécuté (log
  // `docs/logs/sweep_diagnostic_delta.txt` et
  // `docs/logs/sweep_diagnostic_delta_fin.txt`) : le point n'est PAS une
  // perturbation continue de la géométrie, c'est une BASCULE DE BRANCHE
  // dans `VanishingPoint.compute` (`vanishing_point.dart` ligne 224,
  // `vpFinite = vpTop ?? vpBottom`).
  //
  // Mécanisme, confirmé par exécution, pas supposé : à δ_deg = -0.01
  // EXACTEMENT, sur les 4 presets simultanément, `wallTL.yPct ==
  // ceilL.yPct` (et le pendant droit) — invariant de construction des 4
  // presets démo (`lib/models/persp_calib.dart`), pas un hasard du pas de
  // balayage choisi. `wallTL.dy` et `fTL.dy` coïncident alors exactement
  // dans le canvas.
  //
  // Deux régimes géométriques DISTINCTS à cette coïncidence — vocabulaire
  // tenu strictement selon la mesure, pas par convention :
  //   - moderne/provencal/scandinave (symétriques en x, ceilL.dy ==
  //     ceilR.dy et wallTL.dy == wallTR.dy) : les deux fuyantes
  //     deviennent CONFONDUES (même droite, pas juste parallèles).
  //     `residualPx` décroît de façon monotone et BORNÉE en approchant
  //     δ_deg (moderne : 570.4 à δ=0 → 531.8 à δ=-0.0099), puis s'éteint
  //     d'un coup à δ_deg exact.
  //   - haussmann (asymétrique, ceilL.dy=87.75 ≠ ceilR.dy=82.875) : les
  //     deux fuyantes deviennent PARALLÈLES au sens strict (droites
  //     distinctes, jamais confondues). `residualPx` DIVERGE en
  //     approchant δ_deg (696.5 à δ=0 → 4224.5 à δ=-0.0099), puis
  //     s'éteint d'un coup à δ_deg exact.
  // Dans les deux cas, `lineIntersect` renvoie `null` à δ_deg exact (angle
  // nul entre les deux droites, `denom.abs() < 0.001` dans
  // `persp_geometry.dart`) → `vpTop == null` → replis sur `vpBottom` (qui
  // ne dépend que de wallBL/wallBR/floorL/floorR, jamais perturbés ici,
  // donc constant sur tout le balayage) → `residualPx` devient `null`
  // (un seul couple a produit une intersection, aucun résidu n'est
  // mesurable — pas `0.0`, voir docstring de `residualPx`).
  //
  // Trois causes candidates, tranchées dans l'ordre de coût imposé :
  //   1. Bug de sonde (liste de δ dupliquée / variable capturée) — ÉCARTÉ
  //      : reproduit par une sonde neuve indépendante, comportement
  //      identique sur les 4 presets, expliqué structurellement par (2).
  //   2. `vpTop == null` → repli sur `vpBottom` — CONFIRMÉ : `residualPx`
  //      == null exactement à δ_deg sur les 4 presets, sans exception.
  //   3. Autre cause — sans objet, (2) épuise l'explication.
  //
  // Conséquence pour le Point 7 : aucune garde continue sur `residualFrac`
  // ne peut anticiper cette dégénérescence sur 3 presets/4 (bascule
  // discrète, pas un seuil continu qui se rapprocherait progressivement) ;
  // sur le 4e (haussmann), elle n'avertirait que sur l'axe horizontal déjà
  // établi comme sous-déterminé au Groupe 3.
  //
  // Couverture de la branche w=0 (VP à l'infini) — vérifiée par grep sur
  // tout `test/` (aucune occurrence de `isAtInfinity` suivie de `isTrue`) :
  // AUCUN test n'atteint cette branche aujourd'hui. Le `??` ligne 224 de
  // `vanishing_point.dart` la rend inatteignable dès qu'un seul des deux
  // couples (haut ou bas) est fini — ce qui est le cas sur les 4 presets
  // réels à tout δ testé ici (`vpBottom` est toujours fini). C'est
  // exactement le mécanisme que la voie A du Point 7 (projection
  // parallèle) voudrait utiliser : elle n'est aujourd'hui jamais exercée
  // par la calibration réelle.
  // =========================================================================
  group('Groupe 3bis — affinité de dy/pH (signée) et discontinuité de '
      'branche à δ_deg, diagnostic complet', () {
    for (final key in kDemoSceneNativeSize.keys) {
      // -----------------------------------------------------------------
      // Test 1 — affinité de la grandeur SIGNÉE (vp.dy - wallCenterY)/pH
      // sur δ ∈ [-0.05, 0.05], δ_deg inclus dans l'intervalle balayé.
      // L'exclusion du point dégénéré est pilotée par `residualPx !=
      // null` (jamais par un δ écrit en dur) : c'est la garde qui décide,
      // pas une connaissance a priori de la valeur -0.01.
      //
      // Grandeur SIGNÉE, pas sa valeur absolue : si le signe s'inversait
      // dans l'intervalle, |x| replierait la droite en V et ce test
      // mesurerait un pli au lieu d'une affinité. Assertion de constance
      // du signe ajoutée explicitement sur les pas retenus.
      // -----------------------------------------------------------------
      test('$key : affinité de la grandeur signée (vp.dy-wallCenterY)/pH '
          'en δ, hors point de bascule de branche', () {
        final base = PerspCalib.forDemoScene(key);
        final (srcW, srcH) = kDemoSceneNativeSize[key]!;
        final imgDraw = imgDrawFor(srcW, srcH);

        // (signedRatio, residualPx) pour chaque δ du balayage.
        final points = <double, (double signed, double? residualPx)>{};
        for (int i = -5; i <= 5; i++) {
          final delta = i * 0.01;
          final calib = base.copyWith(
            wallTL: base.wallTL.copyWith(yPct: base.wallTL.yPct + delta),
            wallTR: base.wallTR.copyWith(yPct: base.wallTR.yPct + delta),
          );
          final cp = CalibCanvasPoints.fromCalib(
            calib,
            imgDraw: imgDraw,
            w: kCanvasW,
            h: kCanvasH,
          );
          final vp = VanishingPoint.compute(
            fTL: cp.ceilL,
            fTR: cp.ceilR,
            fBL: cp.floorL,
            fBR: cp.floorR,
            wallTL: cp.wallTL,
            wallTR: cp.wallTR,
            wallBL: cp.wallBL,
            wallBR: cp.wallBR,
          );
          final wallCenterY =
              (cp.ceilL.dy + cp.ceilR.dy + cp.floorL.dy + cp.floorR.dy) / 4;
          final signed = (vp.vp.dy - wallCenterY) / vp.pH;
          points[delta] = (signed, vp.residualPx);
        }

        // Exclusion du point dégénéré PILOTÉE PAR residualPx == null,
        // jamais par un δ écrit en dur (δ_deg n'est lu nulle part ici).
        final retenus = points.entries.where((e) => e.value.$2 != null).toList()
          ..sort((a, b) => a.key.compareTo(b.key));

        expect(
          retenus.length,
          lessThan(points.length),
          reason: "preset '$key' : ce test suppose qu'au moins un δ du "
              'balayage produit residualPx == null (bascule de branche) '
              '— si tous les δ ont un residualPx fini, la garde exclut '
              "zéro point et ce test ne couvre plus l'exclusion qu'il "
              'prétend vérifier.',
        );

        // ignore: avoid_print
        print('[groupe3bis-affine] $key : ${retenus.length}/${points.length} '
            'points retenus (residualPx != null), exclu='
            '${points.entries.where((e) => e.value.$2 == null).map((e) => e.key).toList()}');

        // Constance du signe sur les pas retenus (pas de pli en V).
        final signs = retenus.map((e) => e.value.$1.sign).toSet();
        expect(
          signs.length,
          1,
          reason: "preset '$key' : le signe de (vp.dy-wallCenterY)/pH "
              'change sur les pas retenus ($signs) — la valeur absolue '
              'replierait alors la droite affine en V, ce test doit '
              'utiliser la grandeur signée pour rester valide.',
        );

        // Affinité EXACTE : les pas consécutifs retenus doivent avoir un
        // incrément constant. Tolérance serrée (l'affinité est exacte
        // dans ce modèle, mesurée à 0.0640/pas sur moderne).
        final incs = <double>[];
        for (int i = 1; i < retenus.length; i++) {
          final dDelta = retenus[i].key - retenus[i - 1].key;
          final dSigned = retenus[i].value.$1 - retenus[i - 1].value.$1;
          incs.add(dSigned / dDelta);
        }
        for (final inc in incs) {
          expect(
            inc,
            closeTo(incs.first, 1e-6),
            reason: "preset '$key' : incrément non constant "
                '(${incs.map((v) => v.toStringAsFixed(6)).toList()}) — '
                "l'affinité mesurée dans cette configuration symétrique "
                "ne tient plus, hors du point de bascule de branche.",
          );
        }
      });

      // -----------------------------------------------------------------
      // Test 2 — discontinuité à δ_deg, en golden ASSUMÉ (les valeurs
      // numériques ci-dessous sont mesurées, pas dérivées analytiquement
      // pour tous les presets — seul haussmann a une dérivation propre,
      // voir plus bas).
      //
      // Formulation NON CIRCULAIRE : on ne vérifie PAS `vp == vpBottom`
      // en recalculant `lineIntersect(wallBL, fBL, wallBR, fBR)` (ce
      // serait réimplémenter le chemin de production — défaut du Point
      // 4a). À la place : on déplace le couple haut vers une AUTRE
      // configuration dégénérée (même wallTL/wallTR translatés d'un delta
      // supplémentaire qui préserve wallTL.dy == fTL.dy, donc reste
      // dégénéré) et on vérifie que le résultat est INCHANGÉ — ça
      // démontre que la sortie ne dépend plus que du couple bas, sans
      // jamais recopier son calcul.
      // -----------------------------------------------------------------
      test('$key : discontinuité à δ_deg — residualPx==null, invariant '
          'yPct, et repli sur le couple bas démontré sans réimplémenter '
          "lineIntersect", () {
        final base = PerspCalib.forDemoScene(key);
        final (srcW, srcH) = kDemoSceneNativeSize[key]!;
        final imgDraw = imgDrawFor(srcW, srcH);

        // Invariant structurel des 4 presets démo (persp_calib.dart) :
        // wallTL.yPct - ceilL.yPct == 0.01, et le pendant droit. Tolérance
        // sur la représentation double (0.100-0.090 vaut
        // 0.010000000000000009 en pratique), pas ==.
        //
        // ⚠️ CORRECTION (brief Point 7 §B.4) — `baseCp` (construit ici
        // seulement pour l'ancienne assertion scorie
        // `expect(baseCp.wallTL.dy, isNotNull)`, retirée plus bas) n'est
        // plus utilisé par ce test : supprimé pour éviter un warning
        // `unused_local_variable` (`flutter analyze` à 0 error mais 0
        // warning nouveau non plus, discipline §D).
        expect(
          base.wallTL.yPct - base.ceilL.yPct,
          closeTo(0.01, 1e-12),
          reason: "preset '$key' : invariant wallTL.yPct-ceilL.yPct "
              'attendu ≈0.01 (source de la dégénérescence à δ=-0.01) '
              "absent — si cette calibration a changé, δ_deg n'est plus "
              '-0.01 pour ce preset et ce test doit être adapté.',
        );
        expect(
          base.wallTR.yPct - base.ceilR.yPct,
          closeTo(0.01, 1e-12),
          reason: "preset '$key' : invariant wallTR.yPct-ceilR.yPct "
              'attendu ≈0.01 absent (pendant droit).',
        );

        const deltaDeg = -0.01;
        final calibDeg = base.copyWith(
          wallTL: base.wallTL.copyWith(yPct: base.wallTL.yPct + deltaDeg),
          wallTR: base.wallTR.copyWith(yPct: base.wallTR.yPct + deltaDeg),
        );
        final cpDeg = CalibCanvasPoints.fromCalib(
          calibDeg,
          imgDraw: imgDraw,
          w: kCanvasW,
          h: kCanvasH,
        );
        final vpDeg = VanishingPoint.compute(
          fTL: cpDeg.ceilL,
          fTR: cpDeg.ceilR,
          fBL: cpDeg.floorL,
          fBR: cpDeg.floorR,
          wallTL: cpDeg.wallTL,
          wallTR: cpDeg.wallTR,
          wallBL: cpDeg.wallBL,
          wallBR: cpDeg.wallBR,
        );

        expect(
          vpDeg.residualPx,
          isNull,
          reason: "preset '$key' : à δ_deg=$deltaDeg, residualPx devrait "
              'être null (couple haut dégénéré, un seul couple produit '
              "une intersection finie) — si ce n'est plus le cas, la "
              "calibration de ce preset a changé et δ_deg n'est plus "
              '-0.01.',
        );

        // Preuve NON CIRCULAIRE que le résultat ne dépend plus que du
        // couple bas : on déplace le couple haut vers une configuration
        // dégénérée DIFFÉRENTE (translation horizontale de wallTL/wallTR,
        // qui préserve wallTL.dy==fTL.dy donc reste sur la même droite
        // dégénérée mais change le point de départ du segment) — le
        // résultat de compute() doit rester STRICTEMENT identique, sans
        // jamais recalculer lineIntersect(wallBL,fBL,wallBR,fBR)
        // nous-mêmes pour le vérifier.
        final calibDegShifted = calibDeg.copyWith(
          wallTL: calibDeg.wallTL.copyWith(
            xPct: calibDeg.wallTL.xPct + 0.02,
          ),
          wallTR: calibDeg.wallTR.copyWith(
            xPct: calibDeg.wallTR.xPct - 0.02,
          ),
        );
        final cpDegShifted = CalibCanvasPoints.fromCalib(
          calibDegShifted,
          imgDraw: imgDraw,
          w: kCanvasW,
          h: kCanvasH,
        );
        final vpDegShifted = VanishingPoint.compute(
          fTL: cpDegShifted.ceilL,
          fTR: cpDegShifted.ceilR,
          fBL: cpDegShifted.floorL,
          fBR: cpDegShifted.floorR,
          wallTL: cpDegShifted.wallTL,
          wallTR: cpDegShifted.wallTR,
          wallBL: cpDegShifted.wallBL,
          wallBR: cpDegShifted.wallBR,
        );

        // ignore: avoid_print
        print('[groupe3bis-discontinuite] $key : vp.vp(δ_deg)=${vpDeg.vp}  '
            'vp.vp(δ_deg, wallTL/TR décalés en x)=${vpDegShifted.vp}  '
            'residualPx(décalé)=${vpDegShifted.residualPx}');

        expect(
          vpDegShifted.residualPx,
          isNull,
          reason: "preset '$key' : la configuration décalée doit rester "
              'dégénérée (translation horizontale du mur latéral ne '
              "change pas son ordonnée) — sinon la démonstration n'est "
              'plus valide.',
        );
        expect(
          vpDegShifted.vp,
          equals(vpDeg.vp),
          reason: "preset '$key' : déplacer horizontalement wallTL/wallTR "
              '(tout en gardant la dégénérescence verticale) ne doit '
              'RIEN changer au résultat — cela démontre que compute() ne '
              "dépend plus que du couple bas dans ce régime, sans qu'on "
              'ait besoin de recalculer lineIntersect(wallBL,fBL,wallBR,'
              'fBR) nous-mêmes pour le prouver (ce qui serait circulaire, '
              'défaut du Point 4a).',
        );

        // Non-monotonie de dy/pH autour de δ_deg = signature du CHANGEMENT
        // DE BRANCHE, pas une propriété de dy/pH elle-même — donc AUCUNE
        // assertion de monotonie n'est écrite ici (ni verte, ni rouge) :
        // la non-monotonie n'est pas ce que ce test mesure, c'est ce que
        // le test 1 ci-dessus évite en excluant précisément δ_deg via
        // residualPx != null.
        //
        // ⚠️ CORRECTION (brief Point 7 §B.4) — `expect(baseCp.wallTL.dy,
        // isNotNull)` a été retiré ici : `baseCp.wallTL.dy` est un
        // `double` non nullable (voir `CalibCanvasPoints`, ligne 16 de
        // `calib_canvas.dart`), donc `isNotNull` est TOUJOURS vrai —
        // double non-nullable, assertion scorie sans pouvoir jamais
        // échouer, aucune information testée.
      });
    }

    // -----------------------------------------------------------------
    // ⚠️ RÉÉCRITURE (brief Point 7 §B.1) — les 4 tests par preset
    // ci-dessous (un par élément de `kDemoSceneNativeSize.keys`)
    // FUSIONNENT en CE SEUL test paramétré. Motif : l'ancienne version
    // assertionnait une IDENTITÉ SUR DES DISTANCES
    // (`ecartBaselineRepli == vpBaseline.residualPx!`, comparaison
    // `closeTo` sur un `sqrt`/`hypot`) — une fragilité VOULUE mais non
    // nécessaire : un refactor numériquement meilleur de `dist()` (ex.
    // `math.hypot` au lieu de `sqrt(dx*dx+dy*dy)`, tous deux exacts au
    // même résultat mathématique mais pas nécessairement bit-identiques
    // en float64) casserait ce test par un FAUX POSITIF (l'identité
    // GÉOMÉTRIQUE resterait vraie, seul l'arrondi flottant du `sqrt`
    // changerait), coûtant un cycle de debug pour rien.
    //
    // Périmètre EXACT de ce test (pour que le compte ne redérive pas) :
    // pour CHACUN des 4 presets (`kDemoSceneNativeSize.keys`) et pour
    // CHACUN des 10 δ retenus du balayage i=-5..5 (i*0.01) qui
    // satisfont `residualPx != null` (tous sauf i=-1, δ=-0.01=δ_deg —
    // garde pilotée par la mesure, jamais par un δ écrit en dur) :
    //   (a) `VanishingPoint.compute(...).vp` == `vpTopIndep(δ)`, où
    //       `vpTopIndep` est calculé INDÉPENDAMMENT via
    //       `pg.lineIntersect(wallTL, fTL, wallTR, fTR)` (même paire de
    //       points que celle documentée comme "couple haut" dans
    //       `vanishing_point.dart`, mais un appel SÉPARÉ, pas une
    //       relecture de l'état interne de `compute()`).
    // Puis, une seule fois par preset, au point dégénéré δ_deg=-0.01 :
    //   (b) `VanishingPoint.compute(...).vp` == `vpBottomIndep`, calculé
    //       via `pg.lineIntersect(wallBL, fBL, wallBR, fBR)` (couple
    //       bas), INDÉPENDAMMENT de `compute()`.
    // Égalité DIRECTE sur `Offset` (`equals`, pas `closeTo`) : légitime
    // ici parce que `compute()` renvoie `Offset(x/w, y/w)` avec `w=1.0`
    // EXACTEMENT (division par 1.0 exacte en IEEE 754, aucune perte),
    // et que `vpTopIndep`/`vpBottomIndep` sont calculés par le MÊME
    // `lineIntersect` sur les MÊMES entrées flottantes que celles que
    // `compute()` utilise en interne — déterminisme du flottant ⇒
    // égalité bit à bit garantie, pas une coïncidence numérique.
    //
    // Ce test n'est PAS circulaire au sens du Point 4a : il n'utilise
    // JAMAIS le résultat interne de `compute()` pour se comparer à
    // lui-même — `vpTopIndep`/`vpBottomIndep` sont recalculés depuis les
    // points de calibration bruts, via l'API PUBLIQUE `pg.lineIntersect`
    // (déjà utilisée de la même façon par le Groupe 1 ci-dessus).
    //
    // L'ancienne identité sur les distances
    // (`écart(baseline,repli) == residualPx(0)`, brief initial réfuté
    // par mesure — voir historique dans `docs/ETAT.md`, section Point
    // 6bis) devient un COROLLAIRE qu'on N'ASSERTIONNE PLUS ici : il
    // découle algébriquement de (a)+(b) (`residualPx(0) =
    // dist(vpTop(0), vpBottom(0))` par définition, et `écart(baseline,
    // repli) = dist(vpBaseline.vp, vpRepli.vp) = dist(vpTopIndep(0),
    // vpBottomIndep)` par (a)+(b) — donc les deux distances portent sur
    // des PAIRES DE POINTS IDENTIQUES, ce qui implique l'égalité des
    // distances sans qu'il soit nécessaire de la re-mesurer avec un
    // second `sqrt`).
    //
    // Compte du périmètre, décomposé pour que rien ne se redérive au
    // tour suivant : 4 presets × 10 δ non dégénérés = 40 vérifications
    // de (a), PLUS 4 presets × 1 δ_deg = 4 vérifications de (b) —
    // total 40 + 4 = 44 (`totalPointsVerifies`, verrouillé ci-dessous
    // par `expect(..., equals(44))`, jamais laissé comme nombre nu).
    //
    // ⚠️ Ce test rejoue VOLONTAIREMENT `pg.lineIntersect` sur les MÊMES
    // entrées que celles que `VanishingPoint.compute` utilise en
    // interne (mêmes 8 points de calibration canvas, mêmes paires
    // wallTL/ceilL/wallTR/ceilR et wallBL/floorL/wallBR/floorR) : c'est
    // un MIROIR DÉLIBÉRÉ de l'implémentation actuelle de la sélection
    // de branche (`vpTop ?? vpBottom`), pas une spécification
    // indépendante du comportement attendu. Consequence explicite :
    // ce test CASSERA PAR CONSTRUCTION dès que le Point 7b introduira
    // une troisième branche (`VpFallbackMode.projectionParallele`) ou
    // changera la condition de sélection — ce cassage sera le signe
    // attendu que la sélection de branche a changé, PAS une
    // régression à corriger en modifiant `pg.lineIntersect` pour le
    // faire réussir de nouveau. Quiconque touche la bifurcation au
    // Point 7b doit lire cette note avant de "réparer" ce test.
    // -----------------------------------------------------------------
    test(
      'les 4 presets, sur les 10 δ retenus (residualPx != null) : '
      'VP(δ) == vpTop(δ) (couple haut, calculé indépendamment via '
      'pg.lineIntersect) ; à δ_deg, VP(δ_deg) == vpBottom (couple bas, '
      'idem) — égalité exacte sur Offset, pas une comparaison de '
      'distance',
      () {
        const deltaDeg = -0.01;
        var totalPointsVerifies = 0;

        for (final key in kDemoSceneNativeSize.keys) {
          final base = PerspCalib.forDemoScene(key);
          final (srcW, srcH) = kDemoSceneNativeSize[key]!;
          final imgDraw = imgDrawFor(srcW, srcH);

          for (int i = -5; i <= 5; i++) {
            final delta = i * 0.01;
            final calib = base.copyWith(
              wallTL: base.wallTL.copyWith(yPct: base.wallTL.yPct + delta),
              wallTR: base.wallTR.copyWith(yPct: base.wallTR.yPct + delta),
            );
            final cp = CalibCanvasPoints.fromCalib(
              calib,
              imgDraw: imgDraw,
              w: kCanvasW,
              h: kCanvasH,
            );
            final vp = VanishingPoint.compute(
              fTL: cp.ceilL,
              fTR: cp.ceilR,
              fBL: cp.floorL,
              fBR: cp.floorR,
              wallTL: cp.wallTL,
              wallTR: cp.wallTR,
              wallBL: cp.wallBL,
              wallBR: cp.wallBR,
            );

            if (vp.residualPx == null) {
              // Point dégénéré (δ_deg attendu) — traité séparément
              // ci-dessous via vpBottomIndep, pas ici.
              expect(
                delta,
                closeTo(deltaDeg, 1e-9),
                reason: "preset '$key' : le seul δ pour lequel "
                    'residualPx est null devrait être δ_deg=$deltaDeg '
                    '— si un AUTRE δ du balayage est aussi dégénéré, '
                    "l'hypothèse d'un point unique de bascule par "
                    'preset ne tient plus pour cette calibration.',
              );
              continue;
            }

            final vpTopIndep = pg.lineIntersect(cp.wallTL, cp.ceilL, cp.wallTR, cp.ceilR);
            expect(
              vpTopIndep,
              isNotNull,
              reason: "preset '$key', δ=$delta : residualPx non-null "
                  'implique que le couple haut produit une '
                  'intersection finie — vpTopIndep ne devrait pas '
                  'être null ici.',
            );
            expect(
              vp.vp,
              equals(vpTopIndep),
              reason: "preset '$key', δ=$delta : VanishingPoint.compute"
                  '(...).vp devrait être EXACTEMENT égal à '
                  'pg.lineIntersect(wallTL,fTL,wallTR,fTR) calculé '
                  'indépendamment (couple haut) — sinon compute() ne '
                  'renvoie plus la position du couple haut telle que '
                  'documentée pour ce régime.',
            );
            totalPointsVerifies++;
          }

          // Point dégénéré δ_deg=-0.01 : VP(δ_deg) == vpBottom (couple
          // bas), calculé indépendamment.
          final calibDeg = base.copyWith(
            wallTL: base.wallTL.copyWith(yPct: base.wallTL.yPct + deltaDeg),
            wallTR: base.wallTR.copyWith(yPct: base.wallTR.yPct + deltaDeg),
          );
          final cpDeg = CalibCanvasPoints.fromCalib(
            calibDeg,
            imgDraw: imgDraw,
            w: kCanvasW,
            h: kCanvasH,
          );
          final vpDeg = VanishingPoint.compute(
            fTL: cpDeg.ceilL,
            fTR: cpDeg.ceilR,
            fBL: cpDeg.floorL,
            fBR: cpDeg.floorR,
            wallTL: cpDeg.wallTL,
            wallTR: cpDeg.wallTR,
            wallBL: cpDeg.wallBL,
            wallBR: cpDeg.wallBR,
          );
          expect(
            vpDeg.residualPx,
            isNull,
            reason: "preset '$key' : précondition — à δ_deg=$deltaDeg, "
                'residualPx doit être null (couple haut dégénéré).',
          );

          final vpBottomIndep = pg.lineIntersect(cpDeg.wallBL, cpDeg.floorL, cpDeg.wallBR, cpDeg.floorR);
          expect(
            vpBottomIndep,
            isNotNull,
            reason: "preset '$key' : le couple bas ne doit pas être "
                'dégénéré (repli attendu sur une intersection finie).',
          );

          // ignore: avoid_print
          print('[groupe3bis-identite-fusionnee] $key : '
              'vp(δ_deg)=${vpDeg.vp}  vpBottomIndep=$vpBottomIndep');

          expect(
            vpDeg.vp,
            equals(vpBottomIndep),
            reason: "preset '$key' : à δ_deg=$deltaDeg, "
                'VanishingPoint.compute(...).vp devrait être '
                'EXACTEMENT égal à pg.lineIntersect(wallBL,fBL,wallBR,'
                'fBR) calculé indépendamment (couple bas, repli '
                'attendu) — sinon compute() ne retombe plus sur le '
                'couple bas tel que documenté pour ce régime.',
          );
          totalPointsVerifies++;
        }

        // Sanity de périmètre, décomposée (brief Point 7a) : 4 presets
        // × 10 δ non dégénérés = 40 vérifications de (a), PLUS 4
        // presets × 1 δ_deg = 4 vérifications de (b) — 40 + 4 = 44,
        // jamais laissé comme nombre nu.
        expect(
          totalPointsVerifies,
          equals(44),
          reason: 'périmètre attendu : 40 vérifications de (a) '
              '(4 presets × 10 δ non dégénérés) + 4 vérifications de '
              '(b) (4 presets × 1 δ_deg) = 44 — si ce nombre change, '
              'la garde `residualPx != null` a exclu un nombre '
              'différent de points pour au moins un preset, et le '
              'commentaire de périmètre ci-dessus doit être mis à '
              'jour en conséquence.',
        );
      },
    );
  });

  // =========================================================================
  // GROUPE 4 — Invariant frac() ∈ (0, 1] pour une profondeur de corniche
  // par défaut réaliste, sur les 4 presets (sanity, pas un seuil
  // arbitraire comme l'ancien `> 0.05` — ce groupe vérifie que
  // `VanishingPoint.frac` ne lève PAS l'exception "frac > 1" ajoutée en
  // Étape B/C point 4 pour ces calibrations réelles, et que le résultat
  // reste dans l'intervalle géométriquement valide).
  // =========================================================================
  group('Groupe 4 — frac(ceilL, depthPx par défaut) reste dans (0, 1] '
      'pour les 4 presets réels (aucune exception levée)', () {
    for (final key in kDemoSceneNativeSize.keys) {
      test('$key : frac() ne lève pas et reste dans (0, 1]', () {
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
        );
        final depthPx = corniceDefaultPx(vp.pH).faceHorizFondPx;

        late double frac;
        expect(
          () => frac = vp.frac(cp.ceilL, depthPx),
          returnsNormally,
          reason: "preset '$key' : frac(ceilL, depthPx=$depthPx) a levé une "
              'exception pour une profondeur de corniche par défaut '
              'réaliste — cela indiquerait que cette calibration place le '
              "point ceilL au-delà du VP pour l'épaisseur par défaut, ce "
              'qui serait un problème de calibration, pas seulement un cas '
              'limite théorique.',
        );

        // ignore: avoid_print
        print('[groupe4] $key : depthPx=$depthPx  frac=$frac');

        expect(frac, greaterThan(0.0));
        expect(frac, lessThanOrEqualTo(1.0));
      });
    }
  });

  // =========================================================================
  // GROUPE 5 — Garde de conditionnement (brief "Suite 2" point 3) : mesure
  // du résidu ENTRE LES DEUX ESTIMATIONS INDÉPENDANTES du VP de profondeur
  // (couple haut wallTL→fTL/wallTR→fTR vs couple bas wallBL→fBL/wallBR→
  // fBR), exposée par `VanishingPoint.residualPx`/`.residualFrac` (voir
  // `vanishing_point.dart`, ligne visée à l'origine de ce correctif :
  // l'ancien `final vpFinite = vpTop ?? vpBottom;` qui écrasait
  // silencieusement l'un des deux résultats sans jamais comparer les deux).
  //
  // C'est un résidu géométrique AVEC UNITÉ (pixels canvas, puis fraction de
  // la distance fTL→vp) — pas un angle limite deviné. Sur les 4 presets
  // réels, ce résidu est massif (>90% de la distance au VP) : les deux
  // estimations indépendantes du même point de fuite ne s'accordent
  // presque pas du tout, ce qui est une mesure DIRECTE que ces calibrations
  // ne portent pas l'information de profondeur cohérente que le solveur
  // requiert (même diagnostic que le Groupe 2, par une voie de mesure
  // différente et complémentaire).
  //
  // Contrôle négatif (voir `_synth_vp_harness_test.dart`, groupe "Point
  // 3-bis") : sur une scène SYNTHÉTIQUE bien conditionnée (8 points issus
  // d'une seule projection cohérente), ce même résidu est nul à la
  // précision machine (~1e-13 px, ~1e-15 en fraction) — la distinction
  // entre "calibration cohérente" et "calibration incohérente" est donc
  // sans ambiguïté, aucun seuil à la limite n'est nécessaire pour la
  // démontrer.
  // =========================================================================
  group('Groupe 5 — résidu haut/bas (conditionnement), mesuré sur les 4 '
      'presets réels — sans seuil deviné, juste le rapport de la mesure', () {
    for (final key in kDemoSceneNativeSize.keys) {
      test('$key : residualPx/residualFrac rapportés (pas de seuil ici)', () {
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
        );

        expect(
          vp.residualPx,
          isNotNull,
          reason: "preset '$key' : les deux couples (haut et bas) doivent "
              'produire chacun une intersection finie pour cette '
              'calibration — si `residualPx` est `null`, un seul couple a '
              'réussi et ce test doit être adapté, pas relâché.',
        );

        // ignore: avoid_print
        print('[groupe5-conditionnement] $key : residualPx='
            '${vp.residualPx!.toStringAsFixed(1)}px  '
            'residualFrac=${(vp.residualFrac! * 100).toStringAsFixed(1)}%  '
            'vpTop_utilise=${vp.vp}');

        // Ce test ne fixe PAS de seuil de rejet (ce serait deviner une
        // limite) : il rapporte la mesure et vérifie seulement qu'elle est
        // bien positive et finie (contrôle de sanité sur le calcul
        // lui-même, pas sur la qualité de la calibration).
        expect(vp.residualPx! >= 0, isTrue);
        expect(vp.residualFrac! >= 0, isTrue);
        expect(vp.residualPx!.isFinite, isTrue);
      });
    }
  });

  // =========================================================================
  // GROUPE 6 — brief "Suite 2" point 5 : garantir qu'aujourd'hui, sur les 4
  // presets réels, AUCUN appel de `VanishingPoint.frac(p, depthPx)` ne lève
  // (donc `_safeToward`, dans `cornice_plinth_painter.dart`, n'emprunte
  // aucune de ses branches `on ArgumentError` / `on StateError` en
  // production actuelle).
  //
  // Chemin réel reproduit (voir `room_painter.dart`, cases 'Corniches' /
  // 'Plinthes') : `_drawCorniceStrip`/`_drawPlinthStrip` appellent
  // `_safeToward(vp, p, depthPx)` avec :
  //   - `p` ∈ {fTL, fTR, wallTL, wallTR} pour les corniches (arête haute
  //     des 3 segments : latéral G, fond, latéral D — voir
  //     `paintCorniceSet`) et {fBL, fBR, wallBL, wallBR} pour les plinthes
  //     (`paintPlintheSet`) ;
  //   - `depthPx` = `th.faceHorizFond` ou `th.faceHorizLat` selon le
  //     segment, où `th` vient de `corniceFor(stripPx, pH)` /
  //     `StripThickness.plintheDefault(pH)`. `stripPx` (dimensions réelles
  //     mm→px) est `null` pour 275 des 283 références catalogue (pas de
  //     profil JSON) : c'est donc `StripThickness.corniceDefault(pH)` /
  //     `.plintheDefault(pH)` — les coefficients fixes 0.055/0.140/0.080/
  //     0.200 (corniche) et 0.065/0.115/0.095/0.165 (plinthe) — qui est le
  //     chemin RÉELLEMENT empruntable aujourd'hui pour la quasi-totalité
  //     du catalogue, reproduit ici tel quel plutôt qu'un cas de profil
  //     JSON minoritaire.
  //
  // Note : `frac()` ne dépend PAS de la position de `p` autrement que par
  // sa distance au VP fini (`w=1`) — l'appel est donc bien fait avec les 8
  // points de calibration réels du preset (fTL/fTR/fBL/fBR/wallTL/wallTR/
  // wallBL/wallBR), chacun combiné aux `depthPx` réellement utilisés
  // (fond ET latéral, corniche ET plinthe) pour ce preset.
  //
  // Ce test constate un FAIT PRÉSENT ("aucun frac() ne lève aujourd'hui"),
  // PAS une garantie permanente : le brief le note explicitement — la garde
  // de conditionnement du Groupe 5 ci-dessus, une fois câblée en amont
  // (décision produit, brief "Suite 2" point 7, non tranchée ici), peut
  // changer cette situation en rejetant des presets entiers AVANT que
  // `compute()` ne renvoie même un VP fini. Ce test sert de FILET : s'il
  // devient rouge après une modification future de `frac()`/`compute()`,
  // c'est le signal qu'un des 4 presets réels a changé de régime.
  // Corrections apportees apres relecture externe (3 defauts signales) :
  //   1. _safeToward execute vp.toward(p, vp.frac(p, depthPx)) -- DEUX
  //      appels. toward() accede au getter vp (position x/w, y/w) qui
  //      peut lui-meme lever StateError quand w == 0 (VP a l'infini, voir
  //      vanishing_point.dart), independamment de frac(). La version
  //      precedente de ce test n'appelait que frac() : elle ne couvrait
  //      que la moitie de ce que _safeToward protege. Corrige ci-dessous :
  //      l'expression complete vp.toward(p, vp.frac(p, depthPx)) est
  //      executee dans le try.
  //   2. Les profondeurs de plinthe (pH * 0.115, pH * 0.165) etaient
  //      recopiees en dur depuis cornice_plinth_painter.dart au lieu
  //      d'etre lues depuis StripThickness.plintheDefault(pH) -- un
  //      changement de coefficient dans lib/ aurait laisse ce test vert
  //      sans plus couvrir le chemin reel. Corrige : lecture directe de
  //      StripThickness.plintheDefault(pH).
  //   3. Un faux "// ignore: avoid_print" avait ete pose au-dessus d'un
  //      leves.add(...) qui n'est pas un print -- supprime.
  group('Groupe 6 - aucun des 4 presets reels n emprunte aujourd hui les '
      'branches catch de _safeToward (vp.toward(p, vp.frac(p, depthPx)) '
      'ne leve pour aucun point reel x depthPx reel)', () {
    for (final key in kDemoSceneNativeSize.keys) {
      test('$key : vp.toward(p, vp.frac(p, depthPx)) ne leve pour '
          'aucune combinaison reelle (8 points de calibration x 4 '
          'profondeurs par defaut corniche/plinthe, fond et lateral)', () {
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
        );
        final pH = vp.pH;

        // Profondeurs réellement utilisées par room_painter.dart quand
        // aucun profil JSON n'est en cache (cas majoritaire du catalogue,
        // 275/283 réf. sans profil JSON) : 4 valeurs distinctes
        // (fond/latéral × corniche/plinthe), LUES depuis les mêmes
        // factories que room_painter.dart appelle réellement — pas
        // recopiées en dur.
        final corniceDefault = corniceDefaultPx(pH);
        final plintheDefault = StripThickness.plintheDefault(pH);
        final depthsReels = <String, double>{
          'corniche.faceHorizFond': corniceDefault.faceHorizFondPx,
          'corniche.faceHorizLat': corniceDefault.faceHorizLatPx,
          'plinthe.faceHorizFond': plintheDefault.faceHorizFond,
          'plinthe.faceHorizLat': plintheDefault.faceHorizLat,
        };

        // Les 8 points de calibration réels — mêmes points passés à
        // `compute()` ci-dessus, réutilisés ici comme `p` dans
        // `vp.toward(p, vp.frac(p, depthPx))` (exactement l'expression
        // évaluée par `_safeToward` pour chaque coin de chaque segment
        // de corniche/plinthe).
        final pointsReels = <String, Offset>{
          'fTL': cp.ceilL,
          'fTR': cp.ceilR,
          'fBL': cp.floorL,
          'fBR': cp.floorR,
          'wallTL': cp.wallTL,
          'wallTR': cp.wallTR,
          'wallBL': cp.wallBL,
          'wallBR': cp.wallBR,
        };

        final leves = <String>[];
        for (final pEntry in pointsReels.entries) {
          for (final dEntry in depthsReels.entries) {
            try {
              vp.toward(pEntry.value, vp.frac(pEntry.value, dEntry.value));
            } catch (e) {
              leves.add('${pEntry.key} × ${dEntry.key} : $e');
            }
          }
        }

        expect(
          leves,
          isEmpty,
          reason: "preset '$key' : vp.toward(p, vp.frac(p, depthPx)) a "
              'levé pour au moins une combinaison point×profondeur '
              'réellement utilisée en production ($leves) — cela '
              'signifie qu\'aujourd\'hui, _safeToward emprunte déjà une '
              'de ses branches catch pour ce preset (face plafond/sol '
              'silencieusement absente pour le segment concerné). Ce '
              'n\'est PAS le comportement attendu tant que la garde de '
              'conditionnement (Groupe 5) n\'a pas été câblée en amont '
              'de compute().',
        );
      });
    }
  });
}
