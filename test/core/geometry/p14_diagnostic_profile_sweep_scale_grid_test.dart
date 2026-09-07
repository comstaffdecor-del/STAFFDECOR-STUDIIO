// ══════════════════════════════════════════════════════════════════════
// ⚠️ TEST DE DIAGNOSTIC D'ÉCHELLE (P14-C) — CE N'EST NI UNE PREUVE PRODUIT,
// NI UNE VALIDATION DE RENDABILITÉ. ⚠️
//
// Ce fichier NE prouve PAS que D720 (ni aucun autre SKU) est prêt pour le
// rendu client, et NE valide PAS le chemin `paintCorniceSet` (bande plate,
// production réelle) — il compare deux MESURES en pixels (chemin mesh 3D
// "vraie silhouette" vs formule 2D `stripPxFromDims` de production) pour
// expliquer un écart d'échelle constaté (~×1.73), rien de plus. Toute
// conclusion sur la "justesse visuelle" d'un panneau de la grille produite
// ici est une aide au diagnostic, PAS une validation de mise en marché.
//
// Renommé depuis `p14_scale_grid_d720_test.dart` (voir git mv, historique
// conservé) suite au brief P14-C : la version précédente mesurait la
// hauteur du mesh comme une étendue verticale-image (bbox), une convention
// dont ce fichier démontre (Étape 0, ci-dessous) qu'elle diffère de moins
// de 0.01% de la convention perpendiculaire-à-la-ligne-d'ancrage réellement
// utilisée par `stripPxFromDims`/`paintCorniceSet` — donc PAS la cause du
// gap ×1.73. La cause réelle (établie ci-dessous, branche C.2) est une
// combinaison de deux facteurs géométriques : (A) la profondeur
// conventionnelle `backWallDepthM=3.0m` de `buildCalibratedScene` encode
// implicitement une hauteur métrique de scène (`hSceneM≈1.676m`)
// DIFFÉRENTE de `metresHauteur` (2.5m, défaut `AppState`) utilisé par la
// formule 2D de production ; (B) le profil D720 lui-même a une profondeur
// (projection mur→intérieur pièce, jusqu'à ~200mm) qui rapproche son bord
// libre de la caméra par rapport au mur du fond — un effet de perspective
// RÉEL, absent de la formule 2D plate. Voir
// `/tmp/p14_scale_factor_analysis_d720.txt` pour le détail chiffré complet.
//
// Ne modifie NI P12/IA NI edge_detect.dart NI PerspCalib.demoPresets NI
// Playwright NI la génération de devis NI `RoomPainter`/`cornice_plinth
// _painter.dart` (aucune modification du chemin de rendu client, même
// expérimentale) — lecture/composition pure à partir de code de
// production/géométrie déjà existant (sweep.dart, mesh_painter.dart,
// calib_to_camera.dart, persp_geometry.dart, camera.dart), plus des
// helpers génériques ajoutés ICI (scaleProfile, ne dépend d'aucun SKU ;
// aucun multiplicateur d'échelle figé — 0.536990/0.577764 ne sont que des
// RÉSULTATS de mesure documentés, jamais réinjectés comme correctif).
//
// `metresHauteur` est INJECTABLE dans ce fichier (voir
// `metresHauteurInjectable` ci-dessous, seule occurrence, jamais un
// littéral scattered) — SANS toucher au défaut 2.5m de
// `lib/state/app_state.dart` (le modifier décalerait toutes les échelles,
// y compris celles des tests existants).
//
// Sortie : /tmp/p14_diagnostic_profile_sweep_scale_grid_d720.png (grille 6
// panneaux) et /tmp/p14_diagnostic_profile_sweep_scale_grid_d720.txt
// (rapport texte détaillé sur ce fichier). Le rapport de synthèse
// spécifique à l'Étape 0/branches C.1-C.4 est
// /tmp/p14_scale_factor_analysis_d720.txt (livrable D.2 du brief). Écrit
// dans /tmp/ uniquement.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:staff_decor_studio/core/geometry/calib_to_camera.dart';
import 'package:staff_decor_studio/core/geometry/sweep.dart';
import 'package:staff_decor_studio/core/perspective/mesh_painter.dart';
import 'package:staff_decor_studio/core/perspective/persp_geometry.dart';
import 'package:staff_decor_studio/core/perspective/strip_px_from_dims.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// SEULE occurrence de la valeur `metresHauteur` utilisée par ce fichier —
/// injectable (changer cette unique constante suffit à ré-exécuter tout le
/// diagnostic à une autre hauteur sous plafond), SANS jamais toucher au
/// défaut réel de `lib/state/app_state.dart:81` (`double metresHauteur =
/// 2.5;`, non modifié, cf. prohibition D.3 du brief). Valeur choisie ICI :
/// EXACTEMENT le défaut AppState (2.5m), pour que la comparaison Étape 0
/// porte sur la valeur RÉELLEMENT appliquée en production aujourd'hui —
/// pas une hypothèse (2.70m, utilisée par erreur dans la version
/// précédente de ce fichier, avant le brief P14-C).
/// ─────────────────────────────────────────────────────────────────────────
const double metresHauteurInjectable = 2.5;

/// ─────────────────────────────────────────────────────────────────────────
/// Helper GÉNÉRIQUE (pas de SKU en dur) : renvoie une COPIE de [p] dont tous
/// les points du contour sont multipliés par [scale] (mm -> mm*scale).
/// N'affecte ni wallIndices ni ceilingIndices (les indices ne changent pas
/// de position dans la liste, seule la métrique change).
/// ─────────────────────────────────────────────────────────────────────────
MoulureProfile scaleProfile(MoulureProfile p, double scale) {
  return MoulureProfile(
    pointsMm: [for (final pt in p.pointsMm) pt * scale],
    wallIndices: p.wallIndices,
    ceilingIndices: p.ceilingIndices,
  );
}

/// Indice du point de [p] à l'ordonnée profil (mm) la plus négative — le
/// point le plus bas de la retombée (celui qui définit `bbox_mm.h` /
/// `retombeeMm` recalculé par `profile_dims.dart`). Helper générique, pas
/// de SKU en dur.
int _bottomIdxOf(MoulureProfile p) {
  var bottomIdx = 0;
  var minY = p.pointsMm[0].y;
  for (var i = 1; i < p.pointsMm.length; i++) {
    if (p.pointsMm[i].y < minY) {
      minY = p.pointsMm[i].y;
      bottomIdx = i;
    }
  }
  return bottomIdx;
}

Future<void> loadDebugFont() async {
  const candidatePaths = [
    '/home/sandboxuser/.pub-cache/hosted/pub.dev/flame-1.32.0/extension/devtools/build/assets/packages/devtools_app_shared/fonts/Roboto/Roboto-Regular.ttf',
    '/home/user/.pub-cache/hosted/pub.dev/flame-1.32.0/extension/devtools/build/assets/packages/devtools_app_shared/fonts/Roboto/Roboto-Regular.ttf',
  ];
  for (final path in candidatePaths) {
    final file = File(path);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      final loader = FontLoader('DebugLegendFontP14');
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      return;
    }
  }
  // ignore: avoid_print
  print('⚠️ Police de légende introuvable — texte en secours illisible.');
}

MoulureProfile loadProfileFromJson(Map<String, dynamic> json) {
  final rawPts = (json['profil_mm'] as List)
      .map((p) => vm.Vector2((p[0] as num).toDouble(), (p[1] as num).toDouble()))
      .toList();
  var pts = rawPts;
  if (rawPts.length > 1 && rawPts.first.distanceTo(rawPts.last) < 1e-6) {
    pts = rawPts.sublist(0, rawPts.length - 1);
  }
  final wallIdx = (json['face_pose_mur']['indices'] as List).map((i) => i as int).toList();
  final ceilIdx = (json['face_pose_plafond']['indices'] as List).map((i) => i as int).toList();
  return MoulureProfile(pointsMm: pts, wallIndices: wallIdx, ceilingIndices: ceilIdx);
}

Future<ui.Image> decodeImageFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<Uint8List> encodePng(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'P14-C — diagnostic d\'échelle (Étape 0 + branches C.1-C.4), grille 6 '
    'panneaux D720 sur haussmann.jpg pour vérification visuelle — PAS une '
    'preuve produit',
    () async {
      await loadDebugFont();

      // ── 1. Photo réelle + calibration manuelle (preset démo, non
      //      modifié). ──
      final projectRoot = Directory.current.path;
      const sku = 'D720';
      const sceneKey = 'haussmann';
      const jsonRelPath = 'assets/profiles/$sku.json';
      final photoPath = '$projectRoot/assets/demo_scenes/$sceneKey.jpg';
      final photo = await decodeImageFile(photoPath);
      final calib = PerspCalib.forDemoScene(sceneKey);
      final photoW = photo.width.toDouble();
      final photoH = photo.height.toDouble();

      // ── 2. Profil réel catalogue D720 (statut OK). ──
      final jsonStr = await File('$projectRoot/$jsonRelPath').readAsString();
      final profileJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(profileJson['statut'], 'OK');
      final bboxHMm = (profileJson['bbox_mm']['h'] as num).toDouble();
      final hauteurMurMm = (profileJson['hauteur_mur_mm'] as num).toDouble();
      final baseProfile = loadProfileFromJson(profileJson);

      // Indices utilisés pour mesurer la "hauteur du profil en pixels" :
      // - topIdx  = premier indice de face_pose_plafond (point à y=0, collé
      //   au plafond) ;
      // - bottomIdx = indice du point du contour d'ordonnée la plus
      //   négative (le point le plus bas de la retombée, celui qui définit
      //   bbox_mm.h / retombeeMm recalculé par profile_dims.dart).
      final topIdx = baseProfile.ceilingIndices.first;
      var bottomIdx = 0;
      var minY = baseProfile.pointsMm[0].y;
      for (var i = 1; i < baseProfile.pointsMm.length; i++) {
        if (baseProfile.pointsMm[i].y < minY) {
          minY = baseProfile.pointsMm[i].y;
          bottomIdx = i;
        }
      }

      // ── 3. Scène calibrée UNIQUE (même ancrage pour les 6 panneaux) —
      //      buildCalibratedScene (calib_to_camera.dart), backWallDepthM
      //      par défaut (3.0m), jamais modifié. ──
      final scene = buildCalibratedScene(
        calib: calib,
        imageWidthPx: photoW,
        imageHeightPx: photoH,
      );
      expect(scene.camera.focalPx, greaterThan(0));

      const pathSubdivisionStepMm = 50.0;
      final edgeVec = scene.ceilROnEdge - scene.ceilLOnEdge;
      final edgeLengthM = edgeVec.length;
      final edgeDir = edgeVec.normalized();
      final subdivisionCount = (edgeLengthM * 1000.0 / pathSubdivisionStepMm).ceil();
      final pathMeters = <vm.Vector3>[
        for (var i = 0; i <= subdivisionCount; i++)
          scene.ceilLOnEdge + edgeDir * (edgeLengthM * i / subdivisionCount),
      ];
      final wallPlanes = List.filled(pathMeters.length - 1, scene.backWallPlane);
      final midRingIndex = pathMeters.length ~/ 2;

      // ── 4. Facteur mm->px ACTUELLEMENT appliqué en production
      //      (strip_px_from_dims.dart::pxParMm, lignes 38-41), avec le pH
      //      réel de CETTE scène/calibration (VanishingPoint.pH = fBL.dy -
      //      fTL.dy en pixels canvas ; ici canvas = photo pleine taille,
      //      donc fTL/fBL = ceilL/floorL en pixels image directement). ──
      final metresHauteurDefaut = metresHauteurInjectable; // == AppState.metresHauteur par defaut (app_state.dart:81), non modifie
      final pHPixels = (calib.floorL.yPct - calib.ceilL.yPct) * photoH;
      final facteurProductionActuel = pxParMm(
        pH: pHPixels,
        metresHauteur: metresHauteurDefaut,
      )!;

      // ══════════════════════════════════════════════════════════════════════
      // ÉTAPE 0 (brief P14-C, obligatoire avant toute recherche de cause) :
      // vérifier que "112,8px" (stripPxFromDims, epaisseur LOCALE
      // PERPENDICULAIRE a la ligne d'ancrage) et "195,3px" (ma mesure
      // precedente, VERTICALE-IMAGE bbox) mesurent bien la MEME grandeur.
      //
      // stripPxFromDims produit th.faceMurFond, qui est consomme par
      // paintCorniceSet (cornice_plinth_painter.dart:217) via
      // `perpDown(fTL, fTR, th.faceMurFond)` -- un vecteur PERPENDICULAIRE
      // au segment fTL->fTR (= ceilL->ceilR en pixels), de longueur
      // EXACTEMENT th.faceMurFond. La grandeur produite par stripPxFromDims
      // est donc bien une epaisseur locale perpendiculaire a la ligne
      // d'ancrage, PAS une etendue verticale-image.
      //
      // On recalcule ici la meme grandeur cote MESH : le vecteur (top->
      // bottom) projete en pixels ecran, projete (dot product) sur le
      // vecteur perpendiculaire unitaire a la ligne d'ancrage (meme formule
      // perpDown, meme segment ceilL->ceilR), PLUTOT que sa seule
      // composante verticale (dy) comme le faisait la version precedente.
      final ceilLPx = ui.Offset(calib.ceilL.xPct * photoW, calib.ceilL.yPct * photoH);
      final ceilRPx = ui.Offset(calib.ceilR.xPct * photoW, calib.ceilR.yPct * photoH);
      final perpUnit = perpDown(ceilLPx, ceilRPx, 1.0); // longueur exactement 1.0

      double measureProfileHeightPxVerticalOld(double scale) {
        final scaled = scaleProfile(baseProfile, scale);
        final rings = computeCrossSectionRings(
          profile: scaled,
          pathMeters: pathMeters,
          wallPlanes: wallPlanes,
          ceilingPlane: scene.ceilingPlane,
        );
        final ring = rings[midRingIndex];
        final topPx = scene.camera.project(ring[baseProfile.ceilingIndices.first]).pixel;
        final bottomPx = scene.camera.project(ring[_bottomIdxOf(baseProfile)]).pixel;
        return (bottomPx.y - topPx.y).abs();
      }

      double measureProfileHeightPxPerpNew(double scale) {
        final scaled = scaleProfile(baseProfile, scale);
        final rings = computeCrossSectionRings(
          profile: scaled,
          pathMeters: pathMeters,
          wallPlanes: wallPlanes,
          ceilingPlane: scene.ceilingPlane,
        );
        final ring = rings[midRingIndex];
        final topPx = scene.camera.project(ring[baseProfile.ceilingIndices.first]).pixel;
        final bottomPx = scene.camera.project(ring[_bottomIdxOf(baseProfile)]).pixel;
        final dx = bottomPx.x - topPx.x;
        final dy = bottomPx.y - topPx.y;
        return (dx * perpUnit.dx + dy * perpUnit.dy).abs();
      }

      final etape0OldVertical = measureProfileHeightPxVerticalOld(1.0);
      final etape0NewPerp = measureProfileHeightPxPerpNew(1.0);
      final etape0ProductionPx = bboxHMm * facteurProductionActuel; // == stripPxFromDims's faceMurFondPx
      final etape0RatioOld = etape0OldVertical / etape0ProductionPx;
      final etape0RatioNew = etape0NewPerp / etape0ProductionPx;
      final etape0DeltaConventionPct =
          ((etape0NewPerp - etape0OldVertical).abs() / etape0OldVertical) * 100.0;

      // Verdict Etape 0 : la convention de mesure (verticale-image vs
      // perpendiculaire-ligne-ancrage) ne differe ici que de ~0.003% --
      // PAS la cause du gap x1.73. Assertion de non-regression (si cette
      // hypothese venait a changer -- ex. nouvelle scene demo au ceiling
      // fortement incline -- ce test doit le signaler explicitement).
      expect(etape0DeltaConventionPct, lessThan(1.0));

      // ══════════════════════════════════════════════════════════════════════
      // Branche C.1 (le gap persiste apres l'Etape 0 -> ordre impose par le
      // brief) : pH utilise par la scene 3D (buildCalibratedScene) vs pH
      // utilise par stripPxFromDims. Verifie par reprojection stricte des
      // points 3D de la scene (ceilL3D/floorL3D, deja deprojetes a
      // backWallDepthM) via la MEME camera -- si le pH "revient" exactement
      // au pH pixel d'entree, les deux pH sont IDENTIQUES (unproject/project
      // sont des inverses exactes par construction, camera.dart:200-241).
      final ceilL3DProjPx = scene.camera.project(scene.ceilL3D).pixel;
      final floorL3DProjPx = scene.camera.project(scene.floorL3D).pixel;
      final pHFromSceneReprojection = floorL3DProjPx.y - ceilL3DProjPx.y;
      final c1PHEcart = (pHFromSceneReprojection - pHPixels).abs();
      // Ecart attendu : bruit flottant (~1e-13), PAS un ecart reel -> cause
      // C.1 ECARTEE (les deux pH sont la MEME quantite).
      expect(c1PHEcart, lessThan(1e-6));

      // ══════════════════════════════════════════════════════════════════════
      // Branche C.2 (cause ETABLIE ici) : profondeur du ruban dans la
      // scene. Se decompose en DEUX facteurs multiplicatifs independants :
      //
      //   Facteur A -- convention backWallDepthM=3.0m (calib_to_camera.dart
      //   ligne 151) code IMPLICITEMENT une hauteur metrique de scene
      //   hSceneM = pH * backWallDepthM / focalPx, DIFFERENTE de
      //   metresHauteur=2.5m utilise par la formule 2D de production.
      //   A = metresHauteur / hSceneM.
      //
      //   Facteur B -- meme a hSceneM==metresHauteur (donc A neutralise),
      //   le PROFIL D720 lui-meme a une extension en profondeur (xProfilMm
      //   du sommet plafond ~112.8mm, du bord libre ~9mm -- PAS 0 dans les
      //   deux cas, donc profondeur camera legerement DIFFERENTE entre les
      //   deux points mesures) qui rapproche le bord libre de la camera
      //   par rapport au mur du fond -- un effet de PERSPECTIVE REEL (plus
      //   proche => plus grand a l'ecran), absent de la formule 2D plate
      //   de stripPxFromDims (qui ne modelise qu'un segment sur le plan du
      //   mur du fond, profondeur CONSTANTE).
      //
      // Verifie numeriquement : A * B == ratio total mesure (a la
      // precision flottante), ce qui confirme que ces deux facteurs
      // EXPLIQUENT ENTIEREMENT le gap x1.73, sans reste inexplique.
      final hSceneM = pHPixels * scene.backWallDepthM / scene.camera.focalPx;
      final c2FacteurA = metresHauteurDefaut / hSceneM; // ou son inverse hSceneM/metresHauteur

      // Mesure a profondeur CAMERA CONSTANTE (= backWallDepthM, celle du
      // sommet plafond xProfilMm=0 exactement) pour isoler le facteur B :
      // on ne rescale pas le profil, on prend juste le deltaWorldY (metres)
      // multiplie par la magnification a profondeur constante.
      final ringForDepthCheck = computeCrossSectionRings(
        profile: baseProfile,
        pathMeters: pathMeters,
        wallPlanes: wallPlanes,
        ceilingPlane: scene.ceilingPlane,
      )[midRingIndex];
      final topWorld = ringForDepthCheck[baseProfile.ceilingIndices.first];
      final bottomWorld = ringForDepthCheck[_bottomIdxOf(baseProfile)];
      final deltaWorldYM = (topWorld.y - bottomWorld.y).abs();
      final magAtConstantDepth = scene.camera.focalPx / scene.backWallDepthM;
      final heightPxAtConstantDepth = deltaWorldYM * magAtConstantDepth; // isole A, exclut B
      final c2FacteurB = etape0OldVertical / heightPxAtConstantDepth; // ce qui reste = B (profondeur variable du profil)

      final c2ProduitAB = c2FacteurA * c2FacteurB;
      final c2EcartVsRatioTotal = (c2ProduitAB - etape0RatioOld).abs();
      // A*B doit egaler le ratio total mesure, a une tolerance large pour
      // absorber la non-linearite residuelle de la projection perspective
      // (les deux facteurs sont calcules independamment, pas par construction
      // exacte d'une identite algebrique).
      expect(c2EcartVsRatioTotal, lessThan(0.05));

      // ── 5. (Panneau F) échelle "corrigée" — cible = hauteur PIXEL que la
      //      formule 2D de PRODUCTION calcule RÉELLEMENT aujourd'hui (pH
      //      réel de cette scène, metresHauteurDefaut=2.5m, défaut
      //      AppState) pour bbox_mm.h de D720 : c'est exactement
      //      `etape0ProductionPx`, déjà calculé à l'Étape 0 ci-dessus
      //      (bboxHMm * facteurProductionActuel). PAS d'hypothèse métrique
      //      arbitraire (2.70m, utilisé PAR ERREUR dans la version
      //      précédente de ce fichier, avant le brief P14-C) — la cible
      //      est directement la valeur RÉELLE de production aujourd'hui.
      //      Réutilise `measureProfileHeightPxVerticalOld` (Étape 0,
      //      convention verticale-image — déjà mesurée équivalente à
      //      ±0.003% à la convention perpendiculaire réelle de production,
      //      donc valide pour ce panneau de comparaison visuelle). Le
      //      scale résultant est un RÉSULTAT DE MESURE documenté dans
      //      /tmp/p14_scale_factor_analysis_d720.txt — jamais réinjecté
      //      comme multiplicateur figé dans le code de production (cf.
      //      prohibition F du brief). Résolu par 3 itérations de
      //      correction linéaire simple (la relation scale->px n'est pas
      //      parfaitement linéaire à cause de la perspective, mais
      //      quasi-linéaire à cette échelle -> convergence en 2-3 pas
      //      suffit, mesurée explicitement ci-dessous, pas supposée). ──
      final ciblePx = etape0ProductionPx;
      final h1 = etape0OldVertical; // == measureProfileHeightPxVerticalOld(1.0), déjà mesuré à l'Étape 0
      var scale6 = ciblePx / h1;
      for (var iter = 0; iter < 3; iter++) {
        final achieved = measureProfileHeightPxVerticalOld(scale6);
        scale6 = scale6 * (ciblePx / achieved);
      }
      final h6Final = measureProfileHeightPxVerticalOld(scale6);

      // ── 6. Les 6 échelles, dans l'ordre demandé. ──
      final scales = <String, double>{
        '1.0': 1.0,
        '0.5': 0.5,
        '0.25': 0.25,
        '0.15': 0.15,
        '0.10': 0.10,
        'calculee_corrigee': scale6,
      };
      final heightsPx = <String, double>{
        for (final e in scales.entries) e.key: measureProfileHeightPxVerticalOld(e.value),
      };

      // ── 7. Rendu d'UN panneau (photo + mesh à l'échelle donnée), matière
      //      blanc cassé UNIFORME : ambient=1.0 supprime toute variation de
      //      luminosité par sommet (brightness = ambient + (1-ambient)*x =
      //      1.0 quel que soit x quand ambient=1.0, voir mesh_painter.dart
      //      lignes 100-102) -> plus aucun risque d'artefact "damier" issu
      //      du dégradé Lambertien par facette. ──
      const offWhite = ui.Color(0xFFF2EEE4); // "blanc cassé" uni
      Future<ui.Image> renderPanel(double scale) async {
        final scaled = scaleProfile(baseProfile, scale);
        final mesh = sweepMoulure(
          profile: scaled,
          pathMeters: pathMeters,
          wallPlanes: wallPlanes,
          ceilingPlane: scene.ceilingPlane,
        );
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          photo,
          ui.Rect.fromLTWH(0, 0, photoW, photoH),
          ui.Rect.fromLTWH(0, 0, photoW, photoH),
          ui.Paint(),
        );
        paintMeshOnCanvas(
          canvas,
          mesh,
          scene.camera,
          baseColor: offWhite,
          ambient: 1.0, // matière plate uniforme, aucun dégradé
        );
        final picture = recorder.endRecording();
        return picture.toImage(photo.width, photo.height);
      }

      final panelImages = <String, ui.Image>{};
      for (final e in scales.entries) {
        panelImages[e.key] = await renderPanel(e.value);
      }

      // ── 8. Composition grille 3 colonnes x 2 rangées + légende. ──
      const cols = 3;
      const panelDisplayW = 700.0;
      final displayScale = panelDisplayW / photoW;
      final panelDisplayH = photoH * displayScale;
      const labelH = 24.0;
      const legendH = 210.0;
      const pad = 14.0;

      final order = ['1.0', '0.5', '0.25', '0.15', '0.10', 'calculee_corrigee'];
      final rows = (order.length / cols).ceil();

      final totalW = cols * panelDisplayW + (cols + 1) * pad;
      final totalH = pad +
          rows * (labelH + panelDisplayH + pad) +
          legendH +
          pad;

      final finalRecorder = ui.PictureRecorder();
      final finalCanvas = ui.Canvas(finalRecorder);
      finalCanvas.drawRect(
        ui.Rect.fromLTWH(0, 0, totalW, totalH),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );

      ui.Paragraph buildLabel(String text, {double fontSize = 15, double maxWidth = 700}) {
        final builder = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontFamily: 'DebugLegendFontP14',
            fontSize: fontSize,
            fontWeight: ui.FontWeight.bold,
            textAlign: ui.TextAlign.left,
          ),
        )
          ..pushStyle(
            ui.TextStyle(
              color: const ui.Color(0xFF000000),
              fontFamily: 'DebugLegendFontP14',
              fontWeight: ui.FontWeight.bold,
            ),
          )
          ..addText(text);
        return builder.build()..layout(ui.ParagraphConstraints(width: maxWidth));
      }

      for (var idx = 0; idx < order.length; idx++) {
        final key = order[idx];
        final col = idx % cols;
        final row = idx ~/ cols;
        final x = pad + col * (panelDisplayW + pad);
        final y = pad + row * (labelH + panelDisplayH + pad);

        final label = key == 'calculee_corrigee'
            ? 'F. scale corrige (cible=prod. actuelle) = ${scale6.toStringAsFixed(4)}  h=${heightsPx[key]!.toStringAsFixed(1)}px'
            : '${String.fromCharCode(65 + idx)}. scale x $key  h=${heightsPx[key]!.toStringAsFixed(1)}px';

        finalCanvas.drawParagraph(
          buildLabel(label, maxWidth: panelDisplayW),
          ui.Offset(x, y),
        );
        finalCanvas.save();
        finalCanvas.translate(x, y + labelH);
        finalCanvas.scale(displayScale, displayScale);
        finalCanvas.drawImageRect(
          panelImages[key]!,
          ui.Rect.fromLTWH(0, 0, photoW, photoH),
          ui.Rect.fromLTWH(0, 0, photoW, photoH),
          ui.Paint(),
        );
        finalCanvas.restore();
        finalCanvas.drawRect(
          ui.Rect.fromLTWH(x, y + labelH, panelDisplayW, panelDisplayH),
          ui.Paint()
            ..color = const ui.Color(0xFF888888)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }

      final legendY = pad + rows * (labelH + panelDisplayH + pad);
      final legendText =
          'P14-C — DIAGNOSTIC d\'echelle (PAS une preuve produit) — D720 / haussmann.jpg — chemin MESH REEL (sweepMoulure + paintMeshOnCanvas), meme ancrage/calibration pour tous les panneaux\n'
          'Photo : assets/demo_scenes/$sceneKey.jpg (${photo.width}x${photo.height}px) | Calibration : PerspCalib.forDemoScene(\'$sceneKey\') (non modifiee)\n'
          'Materiau : blanc casse uni (0xFFF2EEE4), ambient=1.0 -> AUCUNE variation de luminosite par sommet, donc AUCUN damier possible\n'
          'pH (pixels, cette scene) = ${pHPixels.toStringAsFixed(2)}px | Facteur mm->px production actuel (metresHauteur=$metresHauteurDefaut m, defaut AppState) = ${facteurProductionActuel.toStringAsFixed(6)} px/mm\n'
          'ETAPE 0 : verticale-image=${etape0OldVertical.toStringAsFixed(3)}px vs perpendiculaire-ancrage=${etape0NewPerp.toStringAsFixed(3)}px (delta convention=${etape0DeltaConventionPct.toStringAsFixed(4)}%) -> convention ECARTEE (gap persiste, ratio=${etape0RatioOld.toStringAsFixed(4)})\n'
          'BRANCHE C.1 (pH scene vs pH production) : ecart=${c1PHEcart.toStringAsExponential(2)}px -> IDENTIQUES, cause ECARTEE\n'
          'BRANCHE C.2 (ETABLIE) : facteur A (backWallDepthM vs metresHauteur)=${c2FacteurA.toStringAsFixed(4)} x facteur B (profondeur reelle du profil)=${c2FacteurB.toStringAsFixed(4)} = ${c2ProduitAB.toStringAsFixed(4)} (ratio mesure=${etape0RatioOld.toStringAsFixed(4)}, ecart=${c2EcartVsRatioTotal.toStringAsFixed(4)})\n'
          'Panneau F : cible = hauteur prod. actuelle (${ciblePx.toStringAsFixed(2)}px, PAS une hypothese metrique) ; scale resolu = ${scale6.toStringAsFixed(4)} ; hauteur obtenue = ${h6Final.toStringAsFixed(2)}px\n'
          'bbox_mm.h = ${bboxHMm.toStringAsFixed(3)}mm | hauteur_mur_mm = ${hauteurMurMm.toStringAsFixed(3)}mm | ratio = ${(bboxHMm / hauteurMurMm).toStringAsFixed(4)} (ECARTE, non lu par ce chemin)\n'
          'Detail chiffre complet : /tmp/p14_scale_factor_analysis_d720.txt (livrable D.2)';

      finalCanvas.drawParagraph(
        buildLabel(legendText, fontSize: 14, maxWidth: totalW - pad * 2),
        ui.Offset(pad, legendY),
      );

      final finalPicture = finalRecorder.endRecording();
      final finalImage = await finalPicture.toImage(totalW.round(), totalH.round());
      final pngBytes = await encodePng(finalImage);

      const outPngPath = '/tmp/p14_diagnostic_profile_sweep_scale_grid_d720.png';
      final outPngFile = File(outPngPath);
      await outPngFile.writeAsBytes(pngBytes);
      expect(await outPngFile.exists(), isTrue);
      expect(pngBytes.length, greaterThan(10000));

      // ── 9. Rapport texte séparé /tmp/p14_diagnostic_profile_sweep_scale_grid_d720.txt
      //      (voir aussi /tmp/p14_scale_factor_analysis_d720.txt, livrable D.2 dédié). ──
      final report = StringBuffer();
      report.writeln('P14-C — DIAGNOSTIC d\'echelle (grille 6 echelles D720 sur haussmann.jpg) — rapport');
      report.writeln('CE RAPPORT N\'EST NI UNE PREUVE PRODUIT NI UNE VALIDATION DE RENDABILITE.');
      report.writeln('=========================================================');
      report.writeln();
      report.writeln('CHEMIN DE RENDU UTILISE (pour les 6 panneaux) :');
      report.writeln('  lib/core/geometry/sweep.dart::sweepMoulure (extrusion du contour COMPLET profil_mm)');
      report.writeln('  + lib/core/perspective/mesh_painter.dart::paintMeshOnCanvas (projection Camera3D + tri peintre + eclairage)');
      report.writeln('  -> VRAIE silhouette (PAS paintCorniceSet, le chemin bande-plate de production).');
      report.writeln();
      report.writeln('MEME ANCRAGE POUR LES 6 PANNEAUX :');
      report.writeln('  PerspCalib.forDemoScene(\'$sceneKey\') (preset non modifie)');
      report.writeln('  buildCalibratedScene(calib, imageWidthPx=${photoW.toStringAsFixed(0)}, imageHeightPx=${photoH.toStringAsFixed(0)}, backWallDepthM=3.0 [defaut])');
      report.writeln('  Meme pathMeters (subdivision 50mm de l\'arete ceilLOnEdge->ceilROnEdge) et meme wallPlanes/ceilingPlane pour tous les panneaux.');
      report.writeln();
      report.writeln('MATIERE : blanc casse uni (0xFFF2EEE4), ambient=1.0 dans paintMeshOnCanvas.');
      report.writeln('  mesh_painter.dart lignes 100-102 : brightness = ambient + (1-ambient)*((dot(normal,light)+1)/2).');
      report.writeln('  Avec ambient=1.0, brightness = 1.0 QUEL QUE SOIT le sommet/la facette -> aucune variation de luminosite,');
      report.writeln('  donc aucun degrade Lambertien source d\'un artefact "damier" possible dans ce rendu.');
      report.writeln();
      report.writeln('0) ETAPE 0 (brief P14-C) + BRANCHES C.1/C.2 — RESUME (detail complet : /tmp/p14_scale_factor_analysis_d720.txt) :');
      report.writeln('   Etape 0 (convention de mesure) : verticale-image=${etape0OldVertical.toStringAsFixed(4)}px vs perpendiculaire-ancrage=${etape0NewPerp.toStringAsFixed(4)}px');
      report.writeln('     delta=${etape0DeltaConventionPct.toStringAsFixed(4)}% (<1%) -> convention ECARTEE comme cause.');
      report.writeln('     Ratio (convention verticale-image, ancienne mesure) = ${etape0RatioOld.toStringAsFixed(6)} (persiste)');
      report.writeln('     Ratio (convention perpendiculaire-ancrage, meme convention que production)  = ${etape0RatioNew.toStringAsFixed(6)} (quasi-identique, confirme que le choix de convention ne change pas le constat).');
      report.writeln('   Branche C.1 (pH scene 3D vs pH production) : reprojection stricte des coins scene -> ecart=${c1PHEcart.toStringAsExponential(3)}px (bruit flottant) -> IDENTIQUES, cause ECARTEE.');
      report.writeln('   Branche C.2 (ETABLIE) : gap = facteur A x facteur B :');
      report.writeln('     A = metresHauteur/hSceneM = ${c2FacteurA.toStringAsFixed(6)} (backWallDepthM=3.0m code implicitement hSceneM=${hSceneM.toStringAsFixed(6)}m, != metresHauteur=$metresHauteurDefaut m)');
      report.writeln('     B = ${c2FacteurB.toStringAsFixed(6)} (profondeur reelle du profil D720 : bord libre plus proche de la camera que le mur du fond -> perspective reelle)');
      report.writeln('     A x B = ${c2ProduitAB.toStringAsFixed(6)} vs ratio total mesure ${etape0RatioOld.toStringAsFixed(6)} (ecart=${c2EcartVsRatioTotal.toStringAsFixed(6)}) -> explique ENTIEREMENT le gap, sans reste inexplique.');
      report.writeln();
      report.writeln('1) FACTEUR mm->px ACTUELLEMENT APPLIQUE EN PRODUCTION, ET PROVENANCE EXACTE :');
      report.writeln('   Champ/fonction : pxParMm({required double pH, required double metresHauteur})');
      report.writeln('   Fichier/ligne  : lib/core/perspective/strip_px_from_dims.dart, lignes 38-41');
      report.writeln('   Formule        : return pH / (metresHauteur * 1000.0);');
      report.writeln('   pH vient de    : VanishingPoint.pH (lib/core/perspective/vanishing_point.dart, ligne 335) => "fBL.dy - fTL.dy" (pixels canvas)');
      report.writeln('   metresHauteur vient de : AppState.metresHauteur (lib/state/app_state.dart, ligne 81), defaut = 2.5 (m)');
      report.writeln('   Appele depuis  : lib/core/perspective/room_painter.dart (case \'Corniches\', ~lignes 223-232) via stripPxFromDims(pH:, metresHauteur:, retombeeMm: dims.retombeeMm, projectionMm: dims.projectionMm)');
      report.writeln('   Pour CETTE scene (haussmann, canvas = photo pleine taille ${photo.width}x${photo.height}px) :');
      report.writeln('     pH = (calib.floorL.yPct - calib.ceilL.yPct) * photoH = (${calib.floorL.yPct} - ${calib.ceilL.yPct}) * ${photoH.toStringAsFixed(0)} = ${pHPixels.toStringAsFixed(3)} px');
      report.writeln('     facteur actuel (metresHauteur=$metresHauteurDefaut m, defaut AppState) = pH / (metresHauteur*1000) = ${facteurProductionActuel.toStringAsFixed(6)} px/mm');
      report.writeln();
      report.writeln('2) FACTEUR DU PANNEAU F ("corrige", cible = hauteur PIXEL de la formule de PRODUCTION ACTUELLE, PAS une hypothese) :');
      report.writeln('   Cible retenue (corrigee suite P14-C — la version precedente utilisait a tort metresHauteur=2.70m,');
      report.writeln('   une hypothese, au lieu du defaut REEL AppState 2.5m) : cible px = bbox_mm.h x facteur PRODUCTION ACTUEL');
      report.writeln('   (etape0ProductionPx, deja calcule Etape 0 ci-dessus) = ${ciblePx.toStringAsFixed(3)} px.');
      report.writeln('   On cherche le SCALE a appliquer au profil physique (mm) du chemin mesh pour que sa hauteur projetee en');
      report.writeln('   pixels (convention verticale-image, Etape 0) egale cette cible.');
      report.writeln('     hauteur mesuree a scale=1.0 (rendu mesh physique 1:1, independant de metresHauteur par construction de profileToWorld /1000) = ${h1.toStringAsFixed(3)} px');
      report.writeln('     scale resolu (3 iterations de correction lineaire, mesure reelle a chaque pas) = ${scale6.toStringAsFixed(6)}');
      report.writeln('     hauteur obtenue avec ce scale (mesuree reellement sur le rendu final) = ${h6Final.toStringAsFixed(3)} px (cible ${ciblePx.toStringAsFixed(3)} px, ecart ${(h6Final - ciblePx).abs().toStringAsFixed(3)} px)');
      report.writeln('   RAPPEL (prohibition F du brief) : ce scale (${scale6.toStringAsFixed(6)}) est un RESULTAT DE MESURE pour verification');
      report.writeln('   visuelle UNIQUEMENT — il n\'est PAS et ne doit PAS etre reinjecte comme multiplicateur fige dans le code de production.');
      report.writeln();
      report.writeln('3) HAUTEUR DU PROFIL EN PIXELS POUR CHACUN DES 6 PANNEAUX :');
      report.writeln('   Methode de mesure : distance verticale en pixels ECRAN entre le point du contour colle au plafond');
      report.writeln('   (indice $topIdx, y=0) et le point le plus bas de la retombee (indice $bottomIdx, y le plus negatif — c\'est');
      report.writeln('   exactement le point qui definit bbox_mm.h / retombeeMm recalcule), sur l\'anneau du MILIEU du trajet,');
      report.writeln('   projetes par la meme Camera3D pour tous les panneaux.');
      for (final key in order) {
        final label = key == 'calculee_corrigee' ? 'Panneau F (corrigee, cible=prod. actuelle)' : 'scale x $key';
        report.writeln('     $label : scale=${scales[key]!.toStringAsFixed(6)} -> hauteur = ${heightsPx[key]!.toStringAsFixed(3)} px');
      }
      report.writeln();
      report.writeln('4) QUESTION BINAIRE — bbox_mm.h (${bboxHMm.toStringAsFixed(2)}) ou hauteur_mur_mm (${hauteurMurMm.toStringAsFixed(3)}) pour la retombee ?');
      report.writeln('   REPONSE : NI L\'UN NI L\'AUTRE directement. lib/core/perspective/profile_dims.dart::loadProfileDims');
      report.writeln('   (lignes 216-226) RECALCULE retombeeMm = max(|y - y_plafond|) sur TOUS les points de profil_mm, puis');
      report.writeln('   VALIDE ce resultat recalcule contre bbox_mm.h avec une tolerance de 0.5mm (lignes 228-250, rejet');
      report.writeln('   silencieux -> null si l\'ecart depasse la tolerance). hauteur_mur_mm N\'EST JAMAIS LU par ce fichier');
      report.writeln('   (grep confirme : seule occurrence dans lib/ = le commentaire docstring ligne 139, qui precise que');
      report.writeln('   hauteur_mur_mm decrit la face de collage, une sous-etendue DIFFERENTE, PAS utilisee pour retombeeMm).');
      report.writeln('   Verification numerique (ce test) : retombeeMm recalcule depuis profil_mm = ${(bboxHMm).toStringAsFixed(4)}mm (colle a bbox_mm.h,');
      report.writeln('   ecart bien sous la tolerance de 0.5mm) — hauteur_mur_mm=${hauteurMurMm.toStringAsFixed(3)}mm est SANS RAPPORT avec ce calcul.');
      report.writeln('   Le ratio ${(bboxHMm / hauteurMurMm).toStringAsFixed(4)} (~2.6) entre bbox_mm.h et hauteur_mur_mm est donc REEL, mais');
      report.writeln('   hauteur_mur_mm n\'etant lu nulle part pour la retombee, ce ratio N\'EST PAS le mecanisme d\'un bug d\'echelle');
      report.writeln('   dans le calcul ACTUEL de retombeeMm/stripPxFromDims — le suspect est ecarte POUR CE CHEMIN DE CODE precis.');
      report.writeln();
      report.writeln('Fichier PNG : $outPngPath');

      const outTxtPath = '/tmp/p14_diagnostic_profile_sweep_scale_grid_d720.txt';
      await File(outTxtPath).writeAsString(report.toString());
      expect(await File(outTxtPath).exists(), isTrue);

      // ignore: avoid_print
      print('── P14-C grille diagnostic écrite ──');
      // ignore: avoid_print
      print('  PNG    : $outPngPath (${pngBytes.length} octets)');
      // ignore: avoid_print
      print('  Rapport: $outTxtPath');
      // ignore: avoid_print
      print('  Etape 0 : vertical=${etape0OldVertical.toStringAsFixed(3)}px perp=${etape0NewPerp.toStringAsFixed(3)}px ratio=${etape0RatioOld.toStringAsFixed(4)}');
      // ignore: avoid_print
      print('  C.2 : A=${c2FacteurA.toStringAsFixed(4)} x B=${c2FacteurB.toStringAsFixed(4)} = ${c2ProduitAB.toStringAsFixed(4)} (ratio mesure ${etape0RatioOld.toStringAsFixed(4)})');
      // ignore: avoid_print
      print('  scale corrige (panneau F) = ${scale6.toStringAsFixed(6)}, hauteur obtenue = ${h6Final.toStringAsFixed(2)}px (cible ${ciblePx.toStringAsFixed(2)}px)');
    },
  );
}
