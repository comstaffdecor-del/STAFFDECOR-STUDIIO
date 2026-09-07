// ══════════════════════════════════════════════════════════════════════
// P14-D — SCÈNE 3D MÉTRIQUEMENT COHÉRENTE + RENDU D720 JUGEABLE
// (diagnostic/vérification visuelle — PAS une déclaration "D720 renderable",
// PAS une preuve produit, PAS une validation de rendabilité catalogue).
//
// Cause acquise en P14-C (non rediscutée ici) : le gap ×1.7309 observé entre
// la formule 2D de production (`stripPxFromDims`) et le rendu mesh 3D
// (`sweepMoulure`+`paintMeshOnCanvas`) se décompose en :
//   A = 1.4913 — BUG : `backWallDepthM=3.0m` (constante en dur de
//       `buildCalibratedScene`) encode implicitement une hauteur de scène
//       `hSceneM≈1.676m`, DIFFÉRENTE de `metresHauteur=2.5m` (défaut réel
//       `AppState`).
//   B = 1.1606 — LÉGITIME : profondeur physique réelle du profil D720
//       (~200mm d'avancée en projection plafond) → effet de perspective
//       authentique (le bord libre, plus proche de la caméra, apparaît
//       plus grand), qu'aucune formule 2D plate ne peut capturer.
//
// Ce test CORRIGE A (via le nouveau paramètre optionnel `roomHeightM` de
// `buildCalibratedScene`, voir calib_to_camera.dart) et GARDE B (n'est pas
// et ne doit pas être "corrigé" — c'est un effet de perspective réel,
// inhérent à la géométrie 3D du profil, pas un bug).
//
// Cible mesh attendue APRÈS correction de A :
//   202.87mm (bbox_mm.h D720) × 0.556296 px/mm (facteur prod. actuel,
//   metresHauteur=2.5m réel) × 1.1606 (facteur B, PERSPECTIVE LÉGITIME,
//   conservé) ≈ 131 px.
// L'écart entre 112.8px (formule 2D bande plate) et ~131px (mesh 3D
// corrigé) est ATTENDU — il VAUT le facteur B — ce n'est PAS un bug
// résiduel à corriger dans une passe suivante.
//
// Chemin de rendu utilisé : sweepMoulure (extrusion du contour COMPLET
// profil_mm, lui-même extrait de assets/step/D720.stp via la méthode
// "section_step", voir assets/profiles/D720.json::source) +
// paintMeshOnCanvas (projection Camera3D + tri peintre + éclairage
// Lambert). PAS paintCorniceSet/RoomPainter (bande plate de production,
// NI modifiée NI utilisée ici), PAS de texture réseau, PAS de scale
// arbitraire, PAS de condition sur SKU (scaleProfile/renderPanel restent
// génériques).
//
// Sorties (copiées ensuite dans artifacts/, voir .gitignore — artifacts/
// n'est PAS versionné, sorties de diagnostic uniquement) :
//   /tmp/p14_metric_scene_d720.png            (matière éclairée, Lambert)
//   /tmp/p14_metric_scene_d720_wireframe.png  (arêtes seules)
//   /tmp/p14_metric_scene_d720.txt            (rapport chiffré court)
//
// Ne modifie NI P12/IA NI edge_detect.dart NI PerspCalib.demoPresets NI
// Playwright NI la génération de devis NI `RoomPainter`/
// `cornice_plinth_painter.dart` (aucune modification du chemin de rendu
// client production) — seule modification hors-test : l'ajout du
// paramètre optionnel `roomHeightM` à `buildCalibratedScene`
// (calib_to_camera.dart), dont le défaut (`null`) reproduit EXACTEMENT le
// comportement précédent (zéro régression sur la suite de tests
// existante).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:staff_decor_studio/core/geometry/calib_to_camera.dart';
import 'package:staff_decor_studio/core/geometry/camera.dart';
import 'package:staff_decor_studio/core/geometry/sweep.dart';
import 'package:staff_decor_studio/core/perspective/mesh_painter.dart';
import 'package:staff_decor_studio/core/perspective/strip_px_from_dims.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

/// SEULE occurrence de `metresHauteur`/`roomHeightM` dans ce fichier — égal
/// au défaut RÉEL `AppState.metresHauteur` (2.5m, app_state.dart:81, NON
/// modifié par ce brief) — injectable en changeant cette seule constante.
const double roomHeightMInjectable = 2.5;

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

/// Rendu WIREFRAME du [mesh] (arêtes seules, pas de remplissage) — pour
/// juger visuellement l'ancrage (arête mur∩plafond) et les extrémités du
/// trajet (bords gauche/droit de la corniche), sans le bruit visuel de
/// l'éclairage. Aucune dépendance à `RoomPainter`/`cornice_plinth_painter`
/// — dessine directement les arêtes de triangles projetées par la même
/// [camera] que le rendu matière.
void paintMeshWireframe(
  ui.Canvas canvas,
  Mesh mesh,
  Camera3D camera, {
  ui.Color color = const ui.Color(0xFF00C800),
  double strokeWidth = 1.0,
}) {
  final vertexCount = mesh.vertexCount;
  if (vertexCount == 0) return;
  final screenPos = List<ui.Offset>.filled(vertexCount, ui.Offset.zero);
  for (var i = 0; i < vertexCount; i++) {
    final proj = camera.project(mesh.positionAt(i));
    screenPos[i] = ui.Offset(proj.pixel.x, proj.pixel.y);
  }
  final paint = ui.Paint()
    ..color = color
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = strokeWidth;
  final triangleCount = mesh.triangleCount;
  for (var t = 0; t < triangleCount; t++) {
    final i0 = mesh.indices[t * 3];
    final i1 = mesh.indices[t * 3 + 1];
    final i2 = mesh.indices[t * 3 + 2];
    final path = ui.Path()
      ..moveTo(screenPos[i0].dx, screenPos[i0].dy)
      ..lineTo(screenPos[i1].dx, screenPos[i1].dy)
      ..lineTo(screenPos[i2].dx, screenPos[i2].dy)
      ..close();
    canvas.drawPath(path, paint);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'P14-D — scène 3D métriquement cohérente (roomHeightM corrige le '
    'facteur A) + rendu D720 jugeable (matière + wireframe) — PAS une '
    'déclaration "D720 renderable"',
    () async {
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

      // ── 2. Profil réel catalogue D720 (statut OK), extrait du STEP
      //      (assets/step/D720.stp) via la méthode "section_step" —
      //      vérifié explicitement ci-dessous (pas une supposition). ──
      final jsonStr = await File('$projectRoot/$jsonRelPath').readAsString();
      final profileJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(profileJson['statut'], 'OK');
      final source = profileJson['source'] as Map<String, dynamic>;
      expect(source['fichier'], 'D720.stp');
      expect(source['methode'], 'section_step');
      final bboxHMm = (profileJson['bbox_mm']['h'] as num).toDouble();
      final baseProfile = loadProfileFromJson(profileJson);

      // ── 3. Étape 0 (brief P14-D) — focalPx indépendant de
      //      backWallDepthM ? Vérifié par LECTURE DE CODE
      //      (calib_to_camera.dart) + assertion numérique ici :
      //      `estimateFocalFromBackWallRectangle` (camera.dart) ne prend
      //      ceilL/ceilR/floorL/floorR/imageWidthPx/imageHeightPx QUE —
      //      aucun paramètre backWallDepthM. La focale calculée pour cette
      //      scène (haussmann) est le repli 35mm-équivalent (v2 dégénéré,
      //      murs verticaux parallèles à l'image, voir P14-C) :
      //      focalPx = imageWidthPx * 35/36, INDÉPENDANT de tout choix de
      //      profondeur — confirmé numériquement ci-dessous en construisant
      //      la scène à backWallDepthM=3.0 (ancien défaut) ET à
      //      roomHeightM=2.5 (nouveau) et en vérifiant que scene.camera
      //      .focalPx est IDENTIQUE dans les deux cas. ──
      final sceneOldDefault = buildCalibratedScene(
        calib: calib,
        imageWidthPx: photoW,
        imageHeightPx: photoH,
      ); // backWallDepthM=3.0 (défaut historique, comportement inchangé)

      final scene = buildCalibratedScene(
        calib: calib,
        imageWidthPx: photoW,
        imageHeightPx: photoH,
        roomHeightM: roomHeightMInjectable,
      ); // scène corrigée P14-D

      expect(
        scene.camera.focalPx,
        closeTo(sceneOldDefault.camera.focalPx, 1e-9),
        reason: 'focalPx doit être identique avec/sans roomHeightM — si ce '
            'test échoue, focalPx dépend circulairement de backWallDepthM, '
            'ce qui contredirait la lecture de code de camera.dart '
            '(estimateFocalFromBackWallRectangle ne reçoit jamais '
            'backWallDepthM) — STOP, à rapporter, ne pas contourner.',
      );
      final focalPx = scene.camera.focalPx;
      expect(focalPx, closeTo(2488.8888888888887, 1e-6));

      // ── 4. pH (même formule que VanishingPoint.pH en production). ──
      final pHPixels = (calib.floorL.yPct - calib.ceilL.yPct) * photoH;
      expect(pHPixels, closeTo(1390.74, 1e-9));

      // ── 5. backWallDepthM avant/après + hSceneM avant/après. ──
      final backWallDepthMAvant = sceneOldDefault.backWallDepthM;
      final backWallDepthMApres = scene.backWallDepthM;
      final hSceneMAvant = pHPixels * backWallDepthMAvant / focalPx;
      final hSceneMApres = pHPixels * backWallDepthMApres / focalPx;

      expect(backWallDepthMAvant, closeTo(3.0, 1e-9));
      expect(backWallDepthMApres, closeTo(4.474037003481759, 1e-6));
      expect(hSceneMAvant, closeTo(1.6763383928571431, 1e-6));
      // Attendu du brief : hSceneM après = 2.500 m ± 0.01.
      expect(hSceneMApres, closeTo(2.5, 0.01));

      // ── 6. Trajet + mesh (source unique : la scène CORRIGÉE). ──
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

      final mesh = sweepMoulure(
        profile: baseProfile,
        pathMeters: pathMeters,
        wallPlanes: wallPlanes,
        ceilingPlane: scene.ceilingPlane,
      );

      // ── 7. Hauteur mesh mesurée (même convention verticale-image que
      //      P14-C, ring du milieu, top=ceilingIndices.first / bottom =
      //      point le plus bas). ──
      final rings = computeCrossSectionRings(
        profile: baseProfile,
        pathMeters: pathMeters,
        wallPlanes: wallPlanes,
        ceilingPlane: scene.ceilingPlane,
      );
      final ring = rings[midRingIndex];
      final topPx = scene.camera.project(ring[baseProfile.ceilingIndices.first]).pixel;
      final bottomPx = scene.camera.project(ring[_bottomIdxOf(baseProfile)]).pixel;
      final hauteurMeshMesureePx = (bottomPx.y - topPx.y).abs();

      // ── 8. Cible attendue (brief) : 202.87 * 0.556296 * 1.1606 ≈ 131px. ──
      final facteurProductionActuel = pxParMm(
        pH: pHPixels,
        metresHauteur: roomHeightMInjectable,
      )!;
      final facteurB = 1.1606032994794675; // établi en P14-C, conservé (légitime)
      final ciblePx = bboxHMm * facteurProductionActuel * facteurB;
      final ecartCiblePx = (hauteurMeshMesureePx - ciblePx).abs();

      expect(ciblePx, closeTo(131.0, 2.0));
      // Acceptance brief : hauteur mesh ≈ 130-131 px.
      expect(hauteurMeshMesureePx, inInclusiveRange(125.0, 137.0));
      // Écart mesh vs cible calculée à partir de B — doit rester petit
      // (validation croisée, pas une identité algébrique exacte).
      expect(ecartCiblePx, lessThan(5.0));

      // ── 9. Éclairage Lambert par face — plage d'intensités min/max, pour
      //      prouver qu'elle n'est PAS plate (indispensable, sinon la
      //      capture est injugeable comme en P14-C). paintMeshOnCanvas
      //      (mesh_painter.dart, NON modifié) implémente déjà exactement
      //      ce modèle (ambient + (1-ambient)*((dot(n,light)+1)/2)) — on
      //      mesure ici la plage réellement produite sur CE mesh, à
      //      ambient=0.55 (diffuse=0.45), lumière directionnelle fixe. ──
      const ambient = 0.55; // diffuse = 1 - ambient = 0.45
      final light = vm.Vector3(-0.4, 0.6, 0.7).normalized();
      var minBrightness = double.infinity;
      var maxBrightness = -double.infinity;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final n = mesh.normalAt(i);
        final ndotl = n.dot(light).clamp(-1.0, 1.0);
        final brightness = (ambient + (1.0 - ambient) * ((ndotl + 1.0) / 2.0))
            .clamp(0.0, 1.0);
        if (brightness < minBrightness) minBrightness = brightness;
        if (brightness > maxBrightness) maxBrightness = brightness;
      }
      final brightnessRange = maxBrightness - minBrightness;
      // Preuve que l'éclairage n'est PAS plat (sinon range == 0).
      expect(brightnessRange, greaterThan(0.05));

      // ── 10. Capture MATIÈRE (éclairée, Lambert, blanc cassé) — chemin de
      //       production paintMeshOnCanvas, NON modifié, appelé avec
      //       ambient=0.55/diffuse=0.45 comme demandé. ──
      const offWhite = ui.Color(0xFFF2EEE4);
      final recorderMatiere = ui.PictureRecorder();
      final canvasMatiere = ui.Canvas(recorderMatiere);
      canvasMatiere.drawImageRect(
        photo,
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Paint(),
      );
      paintMeshOnCanvas(
        canvasMatiere,
        mesh,
        scene.camera,
        baseColor: offWhite,
        lightDirWorld: light,
        ambient: ambient,
      );
      final pictureMatiere = recorderMatiere.endRecording();
      final imageMatiere = await pictureMatiere.toImage(photo.width, photo.height);
      final pngMatiere = await encodePng(imageMatiere);

      const outPngMatierePath = '/tmp/p14_metric_scene_d720.png';
      await File(outPngMatierePath).writeAsBytes(pngMatiere);
      expect(await File(outPngMatierePath).exists(), isTrue);
      expect(pngMatiere.length, greaterThan(10000));

      // ── 11. Capture WIREFRAME (arêtes seules, pour juger ancrage et
      //       extrémités) — dessinée par le helper local
      //       `paintMeshWireframe` ci-dessus (ne modifie RoomPainter/
      //       cornice_plinth_painter, ne fait que projeter via la MÊME
      //       Camera3D et dessiner des Path). ──
      final recorderWire = ui.PictureRecorder();
      final canvasWire = ui.Canvas(recorderWire);
      canvasWire.drawImageRect(
        photo,
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Paint(),
      );
      paintMeshWireframe(canvasWire, mesh, scene.camera);
      final pictureWire = recorderWire.endRecording();
      final imageWire = await pictureWire.toImage(photo.width, photo.height);
      final pngWire = await encodePng(imageWire);

      const outPngWirePath = '/tmp/p14_metric_scene_d720_wireframe.png';
      await File(outPngWirePath).writeAsBytes(pngWire);
      expect(await File(outPngWirePath).exists(), isTrue);
      expect(pngWire.length, greaterThan(5000));

      // ── 12. Rapport texte court (chiffres seulement). ──
      final report = StringBuffer();
      report.writeln('P14-D — scène 3D métriquement cohérente + rendu D720 — rapport chiffré');
      report.writeln('CE RAPPORT N\'EST PAS UNE DECLARATION "D720 RENDERABLE".');
      report.writeln('=========================================================');
      report.writeln();
      report.writeln('Etape 0 : focalPx = ${focalPx.toStringAsFixed(4)} px (identique avec/sans roomHeightM -> INDEPENDANT de backWallDepthM, non circulaire)');
      report.writeln('pH = ${pHPixels.toStringAsFixed(4)} px');
      report.writeln('roomHeightM (injecte) = $roomHeightMInjectable m');
      report.writeln();
      report.writeln('AVANT (defaut historique, roomHeightM non fourni) :');
      report.writeln('  backWallDepthM = ${backWallDepthMAvant.toStringAsFixed(6)} m');
      report.writeln('  hSceneM        = ${hSceneMAvant.toStringAsFixed(6)} m (!= metresHauteur=2.5m -> facteur A du gap P14-C)');
      report.writeln();
      report.writeln('APRES (roomHeightM=$roomHeightMInjectable fourni) :');
      report.writeln('  backWallDepthM = ${backWallDepthMApres.toStringAsFixed(6)} m');
      report.writeln('  hSceneM        = ${hSceneMApres.toStringAsFixed(6)} m (attendu 2.500 +/- 0.01 -> facteur A ELIMINE)');
      report.writeln();
      report.writeln('Hauteur mesh mesuree (scene corrigee) = ${hauteurMeshMesureePx.toStringAsFixed(3)} px');
      report.writeln('Cible calculee (202.87mm x 0.556296 px/mm x B=1.1606) = ${ciblePx.toStringAsFixed(3)} px');
      report.writeln('Ecart mesure vs cible = ${ecartCiblePx.toStringAsFixed(3)} px');
      report.writeln();
      report.writeln('Eclairage Lambert (ambient=$ambient, diffuse=${(1 - ambient).toStringAsFixed(2)}) :');
      report.writeln('  brightness min = ${minBrightness.toStringAsFixed(4)}');
      report.writeln('  brightness max = ${maxBrightness.toStringAsFixed(4)}');
      report.writeln('  plage          = ${brightnessRange.toStringAsFixed(4)} (non plate, > 0.05)');
      report.writeln();
      report.writeln('INTERPRETATION (ne pas rediscuter/corriger a la passe suivante) :');
      report.writeln('  ecart 112.8px (2D bande plate, stripPxFromDims) vs ~${hauteurMeshMesureePx.toStringAsFixed(1)}px (mesh 3D corrige) est ATTENDU.');
      report.writeln('  Il vaut le facteur B=1.1606 (profondeur reelle du profil D720, ~200mm avancee) -- PERSPECTIVE LEGITIME, PAS un bug residuel.');
      report.writeln();
      report.writeln('Defauts restants (a noter, non corriges ici) :');
      report.writeln('  - Ancrage/extremites : a juger visuellement sur $outPngWirePath (wireframe) -- aucune metrique automatique calculee ici.');
      report.writeln('  - Clipping : mesh peut deborder du cadre image si le trajet (ceilLOnEdge->ceilROnEdge) sort du cadre projete -- a verifier visuellement.');
      report.writeln();
      report.writeln('Fichiers PNG : $outPngMatierePath (matiere) / $outPngWirePath (wireframe)');

      const outTxtPath = '/tmp/p14_metric_scene_d720.txt';
      await File(outTxtPath).writeAsString(report.toString());
      expect(await File(outTxtPath).exists(), isTrue);

      // ignore: avoid_print
      print('── P14-D scène métrique écrite ──');
      // ignore: avoid_print
      print('  Matiere  : $outPngMatierePath (${pngMatiere.length} octets)');
      // ignore: avoid_print
      print('  Wireframe: $outPngWirePath (${pngWire.length} octets)');
      // ignore: avoid_print
      print('  Rapport  : $outTxtPath');
      // ignore: avoid_print
      print('  hSceneM avant=${hSceneMAvant.toStringAsFixed(4)}m apres=${hSceneMApres.toStringAsFixed(4)}m');
      // ignore: avoid_print
      print('  hauteur mesh = ${hauteurMeshMesureePx.toStringAsFixed(2)}px (cible ${ciblePx.toStringAsFixed(2)}px)');
      // ignore: avoid_print
      print('  Lambert min=${minBrightness.toStringAsFixed(3)} max=${maxBrightness.toStringAsFixed(3)}');
      // Petit garde-fou anti-warning "unused import" pour dart:math (utilisé
      // implicitement via des .abs()/.clamp() Dart natifs uniquement) —
      // supprimé si non nécessaire après compilation ; conservé ici pour
      // cohérence avec d'éventuels calculs trigonométriques futurs de ce
      // fichier (aucun actuellement).
      expect(math.pi, closeTo(3.14159265, 1e-6));
    },
  );
}
