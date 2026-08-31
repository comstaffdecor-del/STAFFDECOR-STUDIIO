// Étape 0 — première assertion RED du tableau de critères (brief
// "branchement du moteur géométrique réel") : "frac() de la face plafond,
// par preset | non dégénéré | rouge — à écrire en premier".
//
// CE QUI EST MESURÉ ET POURQUOI : VanishingPoint.compute (vanishing_point.
// dart) intersecte la ligne plafond (fTL→fTR) avec la ligne sol (fBL→fBR).
// Ces deux droites sont coplanaires dans le mur du fond — géométriquement
// elles DEVRAIENT être parallèles, leur intersection n'a aucun sens
// physique. Deux régimes dégénérés observés (diagnostic chiffré, script
// jetable exécuté avant d'écrire ce test, non commité) :
//
//   - haussmann : les 2 droites ne sont PAS exactement parallèles (petit
//     écart de pente réel dans les %), donc `lineIntersect` réussit — mais
//     retourne un point à ~166 000 px du canevas (canevas large de 1400px,
//     soit ~118 largeurs d'image hors cadre). `frac(ceilL, depthPx)` avec
//     depthPx = épaisseur par défaut d'une corniche (~106px) vaut alors
//     0.000641 : la face plafond n'a quasiment AUCUNE profondeur apparente
//     — c'est le "ruban de 12px" que le brief identifie comme la
//     manifestation visuelle de cet effondrement, pas une limite de
//     résolution.
//
//   - moderne / provencal / scandinave : les lignes plafond/sol de leur
//     PerspCalib sont exactement horizontales (mêmes yPct aux deux
//     extrémités) → `lineIntersect` renvoie STRICTEMENT null (droites
//     parallèles) → VanishingPoint.compute retombe sur le milieu de la
//     ligne haute, dont l'abscisse est TOUJOURS exactement le milieu du
//     canevas (560.0 pour une largeur utile de 1120px centrée, mesuré) —
//     signature reconnaissable sans ambiguïté d'un repli, jamais d'un vrai
//     point de fuite. `frac` ne sature PAS à 0.45 dans ce cas précis (le
//     canevas de test est trop étroit pour ça), mais le point lui-même est
//     déjà la preuve du problème : sa position ne dépend d'AUCUNE des deux
//     lignes latérales (wallTL/wallTR), seulement du milieu de la ligne du
//     haut — un vrai point de fuite ne peut pas avoir cette propriété.
//
// MÉTHODE (règle non négociable du brief) : ce test doit être rouge sur
// HEAD. Il l'est — vérifié par exécution avant l'écriture définitive de
// ce fichier (diagnostic imprimé, script jetable supprimé après lecture).
// Il durcit deux signatures numériques précises plutôt qu'un seuil vague
// deviné a priori, pour ne pas produire une assertion accidentellement
// verte par construction (piège explicitement dénoncé par le brief à
// propos de "continuité de l'arête basse < 1px").
//
// CE QUE CE TEST NE FAIT PAS : il ne corrige rien. Il ne fait que
// démontrer, avec les 4 presets réels de production
// (`PerspCalib.demoPresets`) et les dimensions réelles des 4 photos
// (`assets/demo_scenes/*.jpg`, vérifiées via `file` : 2560x1783 /
// 1960x1470 / 2560x1707 / 1920x1088), que `VanishingPoint.compute` ne
// produit un point de fuite exploitable pour AUCUN des 4 presets
// actuels — condition préalable exigée avant toute correction (Étape 1+).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/calib_canvas.dart';
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

void main() {
  group('Étape 0 — frac() de la face plafond, par preset (non dégénéré)', () {
    for (final key in kDemoSceneNativeSize.keys) {
      test('$key : VanishingPoint.compute ne doit pas produire un VP dégénéré', () {
        final calib = PerspCalib.forDemoScene(key);
        final (srcW, srcH) = kDemoSceneNativeSize[key]!;
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
        );
        final depthPx = corniceDefaultPx(vp.pH).faceHorizFondPx;
        final frac = vp.frac(cp.ceilL, depthPx);

        // Signature du régime "VP effondré hors cadre" (haussmann) : la
        // face plafond n'a quasiment aucune profondeur apparente. Un VP
        // géométriquement significatif pour une scène avec un mur du
        // fond à peu près frontal doit rester dans un ordre de grandeur
        // compatible avec une vraie perspective — pas ~1000x plus petit
        // que la valeur de repli utilisée par les 3 autres presets.
        expect(
          frac,
          greaterThan(0.05),
          reason:
              "preset '$key' : frac(ceilL, depthPx)=$frac est quasi nul — "
              'la face plafond n\'a aucune profondeur apparente. Ceci '
              'reproduit le régime dégénéré "VP hors cadre" décrit dans '
              'docs/ETAT_MOTEUR_RENDU.md : lineIntersect(fTL,fTR,fBL,fBR) '
              'intersecte deux droites coplanaires du mur du fond '
              '(géométriquement censées être parallèles), produisant un '
              'point de fuite sans signification physique.',
        );

        // Signature du régime "repli milieu de ligne haute" (moderne,
        // provencal, scandinave) : lineIntersect a renvoyé null (droites
        // plafond/sol exactement parallèles dans le PerspCalib actuel),
        // et VanishingPoint.compute est retombé sur le milieu du segment
        // fTL→fTR — reconnaissable par le fait que le VP calculé est
        // EXACTEMENT au milieu du segment, indépendamment de wallTL/
        // wallTR (les fuyantes latérales, qui devraient pourtant
        // déterminer le vrai VP, n'interviennent pas du tout ici).
        final milieuXAttendu = (cp.ceilL.dx + cp.ceilR.dx) / 2;
        final milieuYAttendu = (cp.ceilL.dy + cp.ceilR.dy) / 2;
        final estRepliMilieu =
            (vp.vp.dx - milieuXAttendu).abs() < 0.01 &&
            (vp.vp.dy - milieuYAttendu).abs() < 0.01;
        expect(
          estRepliMilieu,
          isFalse,
          reason:
              "preset '$key' : VanishingPoint.compute est retombé "
              'exactement sur le milieu de fTL→fTR (${vp.vp}) — signature '
              'du repli lineIntersect==null (lignes plafond/sol du '
              'PerspCalib actuel exactement parallèles). Ce point ne '
              'dépend d\'AUCUNE des fuyantes latérales (wallTL/wallTR) : '
              "ce n'est pas un point de fuite, c'est un milieu de segment.",
        );
      });
    }
  });
}
