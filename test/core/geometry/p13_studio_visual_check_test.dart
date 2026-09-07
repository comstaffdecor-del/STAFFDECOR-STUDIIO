// Test-livrable P13 (Étape 3) : preuve visuelle "profil catalogue réel posé
// sur photo réelle". Ne modifie NI P12 NI l'IA NI edge_detect.dart NI
// PerspCalib.demoPresets NI la génération de devis — lecture/composition
// pure à partir de code de production existant + `sweep.dart`/`mesh_painter
// .dart` déjà présents (aucune modification de ces fichiers non plus).
//
// Produit UNE image PNG à DEUX panneaux, sur la MÊME photo réelle et la
// MÊME calibration manuelle, pour permettre un jugement à l'œil honnête :
//
//   Panneau A — ce que l'utilisateur voit RÉELLEMENT aujourd'hui dans
//     l'écran Studio : `RoomPainter` de production (room_painter.dart),
//     tel qu'instancié par `studio_screen.dart`, avec le produit D720
//     sélectionné en famille 'Corniches'. Ce chemin dessine une bande 2D
//     plate (`paintCorniceSet`/`cornice_plinth_painter.dart`) dont
//     l'épaisseur est dérivée des dimensions bbox_mm du JSON profil
//     (ProfileDimsCache) mais dont le CONTOUR réel (profil_mm) n'est
//     jamais consommé — voir le rapport texte pour le détail de cette
//     conclusion de code-reading (Étape 2 du brief P13).
//
//   Panneau B — le mesh RÉEL du même profil D720 (contour complet
//     `profil_mm`, extrudé par `sweep.dart::sweepMoulure`), projeté par la
//     même caméra calibrée et rendu par `mesh_painter.dart::
//     paintMeshOnCanvas` — chemin qui EXISTE dans le code (déjà exercé par
//     `render_d720_haussmann_dualview_test.dart`/`debug_wireframe_normals
//     _test.dart`) mais qui n'est câblé à AUCUN écran de production
//     aujourd'hui (aucun appelant de `paintMeshOnCanvas` en dehors de
//     `test/core/geometry/`, vérifié par grep).
//
// Sortie : /tmp/p13_studio_visual_check.png (ce fichier) et
// /tmp/p13_studio_visual_check.txt (rapport texte séparé, voir Étape 3 du
// brief). Écrit dans /tmp/ uniquement — jamais sous assets/ (règle
// SPEC.md "ne rien supprimer/ajouter sous assets/ sans validation").
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
import 'package:staff_decor_studio/core/perspective/room_painter.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';
import 'package:staff_decor_studio/models/project_item.dart';

/// Police réelle pour que la légende texte soit lisible dans le PNG (même
/// correctif cosmétique que `render_d720_haussmann_dualview_test.dart` /
/// `debug_wireframe_normals_test.dart`, dupliqué volontairement).
Future<void> loadDebugFont() async {
  const candidatePaths = [
    '/home/sandboxuser/.pub-cache/hosted/pub.dev/flame-1.32.0/extension/devtools/build/assets/packages/devtools_app_shared/fonts/Roboto/Roboto-Regular.ttf',
    '/home/user/.pub-cache/hosted/pub.dev/flame-1.32.0/extension/devtools/build/assets/packages/devtools_app_shared/fonts/Roboto/Roboto-Regular.ttf',
  ];
  for (final path in candidatePaths) {
    final file = File(path);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      final loader = FontLoader('DebugLegendFontP13');
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
    'P13 — capture visuelle : D720 (statut OK, section_step) posé sur '
    'haussmann.jpg (calibration manuelle = preset démo) — Panneau A '
    '(RoomPainter production, bande plate) vs Panneau B (mesh réel '
    'sweepMoulure/paintMeshOnCanvas)',
    () async {
      await loadDebugFont();

      // ── 1. Photo réelle + calibration manuelle (preset démo jugé
      //      visuellement correct sur cette photo — lecture non modifiée
      //      de PerspCalib.demoPresets, interdiction respectée). ──
      final projectRoot = Directory.current.path;
      const sku = 'D720';
      const sceneKey = 'haussmann';
      const jsonRelPath = 'assets/profiles/$sku.json';
      final photoPath = '$projectRoot/assets/demo_scenes/$sceneKey.jpg';
      final photo = await decodeImageFile(photoPath);
      final calib = PerspCalib.forDemoScene(sceneKey);
      final photoW = photo.width.toDouble();
      final photoH = photo.height.toDouble();

      // ── 2. Profil réel catalogue, statut OK, extraction STEP. ──
      final jsonStr = await File('$projectRoot/$jsonRelPath').readAsString();
      final profileJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(profileJson['statut'], 'OK');
      final bboxWMm = (profileJson['bbox_mm']['w'] as num).toDouble();
      final bboxHMm = (profileJson['bbox_mm']['h'] as num).toDouble();

      // ── 3. PANNEAU A — RoomPainter de production, EXACTEMENT comme
      //      studio_screen.dart l'instancie (mêmes paramètres nommés),
      //      avec D720 sélectionné en famille 'Corniches'. imgDraw=null
      //      + roomImage=null bascule sur `_paintDemoRoom` (générique) ;
      //      on veut ici la VRAIE photo, donc on fournit roomImage=photo
      //      et un imgDraw "plein cadre" (mode contain sur un canvas de
      //      même taille que la photo, donc dx=dy=0, dw/dh=taille photo,
      //      scale=1 — pas de letterboxing pour cette capture). ──
      const metresHauteur = 2.5; // valeur par défaut AppState.metresHauteur
      final imgDraw = ImgDraw(dx: 0, dy: 0, dw: photoW, dh: photoH, scale: 1);
      final selectedProducts = const [
        ProjectItem(ref: sku, famille: 'Corniches', qte: 2.0, unite: 'ml'),
      ];
      final roomPainter = RoomPainter(
        roomImage: photo,
        imgDraw: imgDraw,
        calib: calib,
        selectedProducts: selectedProducts,
        prodPositions: const {},
        withProducts: true,
        metresHauteur: metresHauteur,
      );

      final panelARecorder = ui.PictureRecorder();
      final panelACanvas = ui.Canvas(panelARecorder);
      roomPainter.paint(panelACanvas, ui.Size(photoW, photoH));
      final panelAPicture = panelARecorder.endRecording();
      final panelAImage = await panelAPicture.toImage(
        photo.width,
        photo.height,
      );

      // ── 4. PANNEAU B — mesh RÉEL (contour complet profil_mm) balayé le
      //      long de l'arête mur∩plafond réelle de la même scène calibrée,
      //      rendu par le chemin `sweep.dart`/`mesh_painter.dart` déjà
      //      existant (jamais appelé en production, voir Étape 2). ──
      final scene = buildCalibratedScene(
        calib: calib,
        imageWidthPx: photoW,
        imageHeightPx: photoH,
      );
      expect(scene.camera.focalPx, greaterThan(0));

      final profile = loadProfileFromJson(profileJson);
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

      final mesh = sweepMoulure(
        profile: profile,
        pathMeters: pathMeters,
        wallPlanes: wallPlanes,
        ceilingPlane: scene.ceilingPlane,
      );
      expect(mesh.vertexCount, greaterThan(0));
      expect(mesh.triangleCount, greaterThan(0));

      final panelBRecorder = ui.PictureRecorder();
      final panelBCanvas = ui.Canvas(panelBRecorder);
      panelBCanvas.drawImageRect(
        photo,
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Paint(),
      );
      paintMeshOnCanvas(
        panelBCanvas,
        mesh,
        scene.camera,
        baseColor: const ui.Color(0xFFEDEAE4),
        lightDirWorld: vm.Vector3(0.5, 0.7, 0.7),
        ambient: 0.20,
      );
      final panelBPicture = panelBRecorder.endRecording();
      final panelBImage = await panelBPicture.toImage(
        photo.width,
        photo.height,
      );

      // ── 5. Composition finale : A au-dessus, B en dessous, légende. ──
      const displayW = 1400.0;
      final displayScale = displayW / photoW;
      final displayH = photoH * displayScale;
      const labelBandH = 34.0;
      const legendH = 170.0;
      const pad = 16.0;

      final totalW = displayW + pad * 2;
      final totalH = pad +
          labelBandH +
          displayH +
          pad +
          labelBandH +
          displayH +
          pad +
          legendH +
          pad;

      final finalRecorder = ui.PictureRecorder();
      final finalCanvas = ui.Canvas(finalRecorder);
      finalCanvas.drawRect(
        ui.Rect.fromLTWH(0, 0, totalW, totalH),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );

      ui.Paragraph buildLabel(String text, {double fontSize = 20}) {
        final builder = ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontFamily: 'DebugLegendFontP13',
            fontSize: fontSize,
            fontWeight: ui.FontWeight.bold,
            textAlign: ui.TextAlign.left,
          ),
        )
          ..pushStyle(
            ui.TextStyle(
              color: const ui.Color(0xFF000000),
              fontFamily: 'DebugLegendFontP13',
              fontWeight: ui.FontWeight.bold,
            ),
          )
          ..addText(text);
        return builder.build()
          ..layout(ui.ParagraphConstraints(width: totalW - pad * 2));
      }

      var cursorY = pad;

      finalCanvas.drawParagraph(
        buildLabel(
          'A. PRODUCTION — RoomPainter (paintCorniceSet, bande 2D plate '
          'texturée) — $sku famille Corniches',
        ),
        ui.Offset(pad, cursorY),
      );
      cursorY += labelBandH;
      finalCanvas.save();
      finalCanvas.translate(pad, cursorY);
      finalCanvas.scale(displayScale, displayScale);
      finalCanvas.drawImageRect(
        panelAImage,
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Paint(),
      );
      finalCanvas.restore();
      finalCanvas.drawRect(
        ui.Rect.fromLTWH(pad, cursorY, displayW, displayH),
        ui.Paint()
          ..color = const ui.Color(0xFF888888)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      cursorY += displayH + pad;

      finalCanvas.drawParagraph(
        buildLabel(
          'B. MESH RÉEL (non câblé en production) — sweepMoulure + '
          'paintMeshOnCanvas — contour profil_mm complet — $sku',
        ),
        ui.Offset(pad, cursorY),
      );
      cursorY += labelBandH;
      finalCanvas.save();
      finalCanvas.translate(pad, cursorY);
      finalCanvas.scale(displayScale, displayScale);
      finalCanvas.drawImageRect(
        panelBImage,
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Paint(),
      );
      finalCanvas.restore();
      finalCanvas.drawRect(
        ui.Rect.fromLTWH(pad, cursorY, displayW, displayH),
        ui.Paint()
          ..color = const ui.Color(0xFF888888)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      cursorY += displayH + pad;

      final legendText =
          'Photo : assets/demo_scenes/$sceneKey.jpg (${photo.width}x${photo.height}px, reelle)\n'
          'SKU : $sku   |   JSON : $jsonRelPath   |   statut=OK, source.methode=section_step\n'
          'Bbox profil (mm) : ${bboxWMm.toStringAsFixed(1)} x ${bboxHMm.toStringAsFixed(1)} (largeur x hauteur)\n'
          'Calibration : PerspCalib.forDemoScene(\'$sceneKey\') — preset manuel existant, non modifie\n'
          'Panneau A : dimensions bbox_mm -> px via stripPxFromDims (metresHauteur=$metresHauteur m), '
          'CONTOUR profil_mm NON consomme, assets.height NON consomme (null pour ce SKU)\n'
          'Panneau B : contour profil_mm COMPLET extrude (sweepMoulure), '
          'triangles=${mesh.triangleCount}, sommets=${mesh.vertexCount}, '
          'chemin absent de tout ecran de production (aucun appelant paintMeshOnCanvas hors test/)';

      final legendBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          fontFamily: 'DebugLegendFontP13',
          fontSize: 15,
          textAlign: ui.TextAlign.left,
        ),
      )
        ..pushStyle(
          ui.TextStyle(
            color: const ui.Color(0xFF000000),
            fontFamily: 'DebugLegendFontP13',
          ),
        )
        ..addText(legendText);
      final legendPara = legendBuilder.build()
        ..layout(ui.ParagraphConstraints(width: totalW - pad * 2));
      finalCanvas.drawParagraph(legendPara, ui.Offset(pad, cursorY));

      final finalPicture = finalRecorder.endRecording();
      final finalImage = await finalPicture.toImage(
        totalW.round(),
        totalH.round(),
      );
      final pngBytes = await encodePng(finalImage);

      const outPath = '/tmp/p13_studio_visual_check.png';
      final outFile = File(outPath);
      await outFile.writeAsBytes(pngBytes);
      expect(await outFile.exists(), isTrue);
      expect(pngBytes.length, greaterThan(10000));

      // ── 6. Rapport texte séparé (Étape 3 du brief). ──
      final reportText =
          'P13 — Étape 3 — rapport de capture visuelle\n'
          '=============================================\n\n'
          'Photo utilisée      : assets/demo_scenes/$sceneKey.jpg (réelle, ${photo.width}x${photo.height}px)\n'
          'SKU sélectionné      : $sku\n'
          'Type de géométrie    : contour 2D fermé (profil_mm, ${profile.pointsMm.length} sommets), '
          'extraction STEP (source.methode=section_step), statut=OK\n'
          '                       assets.height = null pour ce SKU (motif=null, pas de mouluration ornée '
          '-> pas de height map attendue, cohérent avec le schéma SPEC.md)\n'
          'Source calibration   : PerspCalib.forDemoScene(\'$sceneKey\') — preset manuel existant '
          '(PerspCalib.demoPresets, NON modifié ce tour), jugé visuellement correct sur cette photo '
          '(déjà utilisé et validé par render_d720_haussmann_dualview_test.dart)\n\n'
          'Panneau A (PRODUCTION RÉELLE) :\n'
          '  - Classe : RoomPainter (lib/core/perspective/room_painter.dart), instanciée exactement '
          'comme le fait lib/screens/studio/studio_screen.dart\n'
          '  - Chemin de dessin pour famille "Corniches" : paintCorniceSet (cornice_plinth_painter.dart)\n'
          '  - Donnée métrique consommée : UNIQUEMENT bbox_mm (via ProfileDimsCache -> stripPxFromDims), '
          'convertie en épaisseur de bande pixel (StripThickness)\n'
          '  - Le CONTOUR réel (profil_mm, ${profile.pointsMm.length} sommets) N\'EST PAS consommé par ce '
          'chemin — la bande dessinée est un quad plat texturé (photo produit staffdecor.fr en repli '
          'procédural), pas la silhouette réelle de la moulure\n'
          '  - assets.height N\'EST CONSOMMÉ NULLE PART dans ce chemin\n\n'
          'Panneau B (MESH RÉEL, non câblé en production) :\n'
          '  - Fonctions : sweep.dart::sweepMoulure (extrusion du contour complet le long de l\'arête '
          'mur∩plafond réelle) + mesh_painter.dart::paintMeshOnCanvas (projection Camera3D réelle + tri '
          'peintre + éclairage directionnel)\n'
          '  - Triangles : ${mesh.triangleCount}   Sommets : ${mesh.vertexCount}\n'
          '  - AUCUN appelant de paintMeshOnCanvas en dehors de test/core/geometry/ (vérifié par grep '
          'sur tout lib/) — ce chemin existe et fonctionne (déjà exercé par debug_wireframe_normals_test'
          '.dart, render_corniche_screenshot_test.dart, render_d720_haussmann_dualview_test.dart) mais '
          'n\'est branché à AUCUN écran utilisateur aujourd\'hui\n\n'
          'Problèmes visibles à contrôler à l\'œil sur le PNG (à confirmer par inspection humaine, '
          'aucune affirmation de qualité n\'est faite ici avant cette inspection) :\n'
          '  - Échelle relative Panneau A vs Panneau B : les deux utilisent la même conversion '
          'mm->pixels dérivée de metresHauteur=$metresHauteur m et de la même hauteur perspective '
          'du mur du fond (pH) — à vérifier si les deux bandes semblent de même épaisseur apparente\n'
          '  - Orientation/perspective : Panneau A suit uniquement les 4 points ceilL/ceilR/wallTL/wallTR '
          'de la calibration (convergence VP simple) ; Panneau B suit la projection caméra 3D complète '
          '(focale + rotation résolues par buildCalibratedScene) — à vérifier si les deux bandes suivent '
          'visuellement la même arête plafond/mur de la photo\n'
          '  - Fidélité du galbe : Panneau A n\'a par construction AUCUN galbe (quad plat) ; Panneau B '
          'montre la vraie silhouette du profil D720 (bbox ${bboxWMm.toStringAsFixed(1)}x'
          '${bboxHMm.toStringAsFixed(1)}mm) — à vérifier si ce galbe est visuellement crédible posé sur '
          'la photo (angle de vue, taille apparente, cohérence avec l\'architecture réelle visible)\n\n'
          'Fichier PNG : $outPath\n';

      const reportPath = '/tmp/p13_studio_visual_check.txt';
      await File(reportPath).writeAsString(reportText);
      expect(await File(reportPath).exists(), isTrue);

      // ignore: avoid_print
      print('── P13 capture écrite ──');
      // ignore: avoid_print
      print('  PNG    : $outPath (${pngBytes.length} octets)');
      // ignore: avoid_print
      print('  Rapport: $reportPath');
    },
  );
}
