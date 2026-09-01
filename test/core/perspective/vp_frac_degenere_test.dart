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
  // (cible le régime dégénéré #3 spécifiquement — VP-centre, commit
  // `47c17eca` — de façon directe et nommée, en complément du test de
  // dépendance causale du Groupe 2).
  // =========================================================================
  group('Groupe 3 — compute() ne doit pas coïncider avec le centre '
      'géométrique des 4 coins du mur du fond (régime VP-centre)', () {
    for (final key in kDemoSceneNativeSize.keys) {
      test(
        '$key : VP calculé ≠ centre géométrique de (ceilL,ceilR,floorL,floorR)',
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
          expect(vp.isAtInfinity, isFalse);

          final wallCenter = Offset(
            (cp.ceilL.dx + cp.ceilR.dx + cp.floorL.dx + cp.floorR.dx) / 4,
            (cp.ceilL.dy + cp.ceilR.dy + cp.floorL.dy + cp.floorR.dy) / 4,
          );
          final d = (vp.vp - wallCenter).distance;

          // ignore: avoid_print
          print('[groupe3] $key : vp=${vp.vp}  centre_mur_fond=$wallCenter  '
              'distance=${d.toStringAsFixed(1)}px');

          expect(
            d,
            greaterThan(50.0),
            reason:
                "preset '$key' : VanishingPoint.compute (${vp.vp}) est à "
                'seulement ${d.toStringAsFixed(1)}px du centre géométrique '
                'des 4 coins du mur du fond ($wallCenter) — signature du '
                'régime dégénéré #3 (VP-centre, diagnostiqué au commit '
                '47c17eca comme un correctif insuffisant : terme '
                "d'obliquité nul, VP indépendant de la géométrie réelle "
                'des murs latéraux).',
          );
        },
      );
    }
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
  group('Groupe 6 — aucun des 4 presets réels n\'emprunte aujourd\'hui les '
      'branches catch de _safeToward (frac() ne lève pour aucun point '
      'réel × depthPx réel)', () {
    for (final key in kDemoSceneNativeSize.keys) {
      test('$key : frac(p, depthPx) ne lève pour aucune combinaison '
          'réelle (8 points de calibration × 4 profondeurs par défaut '
          'corniche/plinthe, fond et latéral)', () {
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
        // voir corniceDefaultPx/StripThickness.plintheDefault) : 4
        // valeurs distinctes (fond/latéral × corniche/plinthe).
        final corniceDefault = corniceDefaultPx(pH);
        final depthsReels = <String, double>{
          'corniche.faceHorizFond': corniceDefault.faceHorizFondPx,
          'corniche.faceHorizLat': corniceDefault.faceHorizLatPx,
          'plinthe.faceHorizFond': pH * 0.115,
          'plinthe.faceHorizLat': pH * 0.165,
        };

        // Les 8 points de calibration réels — mêmes points passés à
        // `compute()` ci-dessus, réutilisés ici comme `p` dans
        // `frac(p, depthPx)` (exactement ce que fait `_safeToward` pour
        // chaque coin de chaque segment de corniche/plinthe).
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
              vp.frac(pEntry.value, dEntry.value);
            } catch (e) {
              // ignore: avoid_print
              leves.add('${pEntry.key} × ${dEntry.key} : $e');
            }
          }
        }

        expect(
          leves,
          isEmpty,
          reason: "preset '$key' : frac() a levé pour au moins une "
              'combinaison point×profondeur réellement utilisée en '
              'production ($leves) — cela signifie qu\'aujourd\'hui, '
              '_safeToward emprunte déjà une de ses branches catch pour '
              'ce preset (face plafond/sol silencieusement absente pour '
              'le segment concerné). Ce n\'est PAS le comportement '
              'attendu tant que la garde de conditionnement (Groupe 5) '
              'n\'a pas été câblée en amont de compute().',
        );
      });
    }
  });
}
