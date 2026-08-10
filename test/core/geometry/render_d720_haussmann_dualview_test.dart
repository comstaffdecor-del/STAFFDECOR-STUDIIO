// Test-livrable (Point 3) : rend la vraie corniche D720 (profil STEP réel,
// `assets/profiles/D720.json`, `statut: "OK"`, extraction `section_step`
// — voir Point 2/commit `f5b6e5d`) posée sur la photo réelle
// `assets/demo_scenes/haussmann.jpg`, et produit UNE SEULE image PNG
// contenant DEUX vues :
//   1. Vue d'ensemble — la photo complète avec la corniche composée le
//      long de l'arête mur∩plafond du mur du fond.
//   2. Crop ×4 — zoom numérique ×4 sur exactement 40 cm (400 mm) d'arête
//      plafond, centré au milieu du trajet. C'est CE panneau qui permet de
//      juger de l'aspect réel de la corniche (le panneau 1 est trop petit
//      à l'échelle de la photo pour voir le galbe).
//
// Éclairage (demande explicite, CORRIGÉE en cours de session — voir §5
// "Direction de lumière" ci-dessous) : terme ambiant réduit à 0,20 (au lieu
// du défaut historique 0,45 de `mesh_painter.dart`, désormais paramétrable
// via [paintMeshOnCanvas]'s `ambient`), lumière directionnelle
// (0.5, 0.7, 0.7) normalisée — choisie non pas pour "venir d'un côté de la
// photo", mais parce qu'elle a une composante significative dans le plan
// perpendiculaire à l'axe de balayage de la corniche (monde +X pour cette
// scène, voir CONVENTIONS.md §5 "Direction de lumière et axe de balayage").
// PAS depuis l'axe caméra (qui serait une direction proche de +Z monde,
// cam.back, quasi inefficace ici pour la même raison géométrique).
//
// ⚠️ Sortie écrite dans `/tmp/` — JAMAIS dans `assets/` (règle SPEC.md
// "write-once" / anti-suppression) avant validation humaine explicite.
//
// ⚠️ Ce test NE MODIFIE AUCUNE géométrie (`sweep.dart` inchangé) : seul
// `mesh_painter.dart::paintMeshOnCanvas` a reçu un nouveau paramètre
// optionnel `ambient` (défaut 0.45 = comportement historique identique
// pour tout appelant existant, dont `render_corniche_screenshot_test.dart`
// et `debug_wireframe_normals_test.dart`, non modifiés).
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
import 'package:staff_decor_studio/models/persp_calib.dart';

/// Charge une police réelle (Roboto) pour que la légende s'affiche
/// correctement — sans ce chargement explicite, `flutter test` (VM
/// headless, pas de polices système) rend tout texte en rectangles noirs
/// pleins (glyphes de secours), illisibles. Duplication volontaire du
/// même correctif déjà appliqué dans
/// `debug_wireframe_normals_test.dart::loadDebugFont` — purement
/// cosmétique, aucun rapport avec la géométrie/l'éclairage.
Future<void> loadDebugFont() async {
  const candidatePaths = [
    '/home/sandboxuser/.pub-cache/hosted/pub.dev/flame-1.32.0/extension/devtools/build/assets/packages/devtools_app_shared/fonts/Roboto/Roboto-Regular.ttf',
  ];
  for (final path in candidatePaths) {
    final file = File(path);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      final loader = FontLoader('DebugLegendFont');
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      return;
    }
  }
  // ignore: avoid_print
  print(
    '⚠️ Aucune police trouvée pour la légende — le texte du PNG sera '
    'illisible (rectangles de secours). Purement cosmétique.',
  );
}

/// Charge un profil `MoulureProfile` depuis le JSON produit par le pipeline
/// Python — duplication volontaire de
/// `render_corniche_screenshot_test.dart::loadProfileFromJson` (pas de
/// loader `lib/` de production encore écrit, voir sa docstring pour la
/// justification complète du dédoublonnage de sommet).
MoulureProfile loadProfileFromJson(
  Map<String, dynamic> json, {
  double dedupToleranceMm = 1e-6,
}) {
  final rawPts = (json['profil_mm'] as List)
      .map((p) => vm.Vector2((p[0] as num).toDouble(), (p[1] as num).toDouble()))
      .toList();

  var pts = rawPts;
  if (rawPts.length > 1 &&
      rawPts.first.distanceTo(rawPts.last) < dedupToleranceMm) {
    pts = rawPts.sublist(0, rawPts.length - 1);
  }

  final wallIdx = (json['face_pose_mur']['indices'] as List)
      .map((i) => i as int)
      .toList();
  final ceilIdx = (json['face_pose_plafond']['indices'] as List)
      .map((i) => i as int)
      .toList();
  return MoulureProfile(
    pointsMm: pts,
    wallIndices: wallIdx,
    ceilingIndices: ceilIdx,
  );
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
    'rend D720.json (corniche réelle STEP) sur haussmann.jpg — vue '
    'd\'ensemble + crop ×4 sur 40cm d\'arête plafond, éclairage corrigé '
    '(ambiante 0.20, directionnelle (0.5,0.7,0.7) perpendiculaire à l\'axe '
    'de balayage)',
    () async {
      await loadDebugFont();

      // ── 1. Photo réelle + calibration réelle du preset démo. ──
      final projectRoot = Directory.current.path;
      const sku = 'D720';
      const jsonRelPath = 'assets/profiles/$sku.json';
      final photoPath = '$projectRoot/assets/demo_scenes/haussmann.jpg';
      final photo = await decodeImageFile(photoPath);
      final calib = PerspCalib.forDemoScene('haussmann');

      // ── 2. Pont calibration 2D -> scène 3D. ──
      final scene = buildCalibratedScene(
        calib: calib,
        imageWidthPx: photo.width.toDouble(),
        imageHeightPx: photo.height.toDouble(),
      );
      expect(scene.camera.focalPx, greaterThan(0));

      // ── 3. Profil réel D720 (pipeline STEP, statut OK — voir commit
      //      f5b6e5d, section_step, origine_unite=step_header). ──
      final jsonStr = await File('$projectRoot/$jsonRelPath').readAsString();
      final profileJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(profileJson['statut'], 'OK');
      final profile = loadProfileFromJson(profileJson);
      final bboxWMm = (profileJson['bbox_mm']['w'] as num).toDouble();
      final bboxHMm = (profileJson['bbox_mm']['h'] as num).toDouble();

      // ── 4. Balayage le long de l'arête mur∩plafond réelle (un seul mur,
      //      le mur du fond, sur tout le trajet).
      //
      // ⚠️ Trajet SUBDIVISÉ (contrairement à
      // `render_corniche_screenshot_test.dart` qui ne passe que les 2
      // extrémités) : avec seulement 2 points de trajet, `sweepMoulure`
      // ne produit que 2 anneaux, donc `mesh.uvAt(i).x` (abscisse
      // curviligne `u`, mm réels) ne prend que 2 valeurs possibles (0 et
      // la longueur totale) — aucun sommet n'existerait dans la fenêtre de
      // 40cm centrée nécessaire à l'étape 7 (crop). On insère donc des
      // points intermédiaires tous les 50mm le long du même segment droit
      // (le mur du fond reste un seul plan pour tout le trajet, donc
      // `wallPlanes` répète `scene.backWallPlane` pour chaque segment
      // inséré) — voir Point 4 de la demande utilisateur ("mesh non
      // subdivisé"), résolu ici pour ce cas d'usage précis (crop
      // localisé), sans toucher `sweep.dart`. ──
      const pathSubdivisionStepMm = 50.0;
      final edgeVec = scene.ceilROnEdge - scene.ceilLOnEdge;
      final edgeLengthM = edgeVec.length;
      final edgeDir = edgeVec.normalized();
      final subdivisionCount =
          (edgeLengthM * 1000.0 / pathSubdivisionStepMm).ceil();
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

      // ── 5. Direction de lumière — CORRIGÉE (voir CONVENTIONS.md §5). ──
      //
      // ⚠️ Direction initialement testée ici, (0.85, 0.28, 0.45) — choisie
      // sur l'hypothèse "camera-right = +X monde = côté fenêtres de la
      // photo" — était géométriquement quasi inopérante : le mur du fond
      // de cette scène s'étend selon l'axe monde X (c'est aussi l'axe de
      // balayage `alongAxis` du sweep, voir `sweep.dart::
      // _buildSegmentFrame`), donc TOUTES les normales de facette du
      // maillage ont une composante X quasi nulle (vérifié : 27 normales
      // distinctes, aucune avec |x| significatif). La composante X d'une
      // direction de lumière est donc sans effet sur le contraste de cette
      // corniche, quelle que soit son amplitude — d'où le relief plat
      // observé avec la première direction, malgré ambient=0.20.
      //
      // Direction retenue : (0.5, 0.7, 0.7) normalisée — sélectionnée par
      // l'utilisateur parmi 6 candidats testés (spread dot-produit
      // max-min sur les 27 normales distinctes = 1.523, le meilleur du
      // lot), précisément parce qu'elle a une composante significative
      // dans le plan Y/Z, perpendiculaire à l'axe de balayage +X — voir la
      // règle générale désormais consignée dans CONVENTIONS.md §5.
      final lightDirWorld = vm.Vector3(0.5, 0.7, 0.7);
      const ambient = 0.20;

      // ── 6. Composition "vue d'ensemble" : photo + mesh projeté. ──
      final overviewRecorder = ui.PictureRecorder();
      final overviewCanvas = ui.Canvas(overviewRecorder);
      final photoW = photo.width.toDouble();
      final photoH = photo.height.toDouble();
      overviewCanvas.drawImageRect(
        photo,
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Paint(),
      );
      paintMeshOnCanvas(
        overviewCanvas,
        mesh,
        scene.camera,
        baseColor: const ui.Color(0xFFEDEAE4),
        lightDirWorld: lightDirWorld,
        ambient: ambient,
      );
      final overviewPicture = overviewRecorder.endRecording();
      final overviewImage = await overviewPicture.toImage(
        photo.width,
        photo.height,
      );

      // ── 7. Détermination du rectangle de crop — 40 cm (400 mm) RÉELS
      //      d'arête plafond, centrés au milieu du trajet.
      //
      // Utilise `mesh.uvAt(i).x` = abscisse curviligne le long du trajet
      // en mm RÉELS (règle dure #5 de `sweep.dart` : `u` n'est jamais
      // normalisée 0..1) — sélection géométrique exacte des sommets dans
      // la fenêtre [uCenter-200mm, uCenter+200mm], PAS une estimation à
      // l'œil sur l'image finale. ──
      final totalLengthMm =
          (scene.ceilROnEdge - scene.ceilLOnEdge).length * 1000.0;
      expect(
        totalLengthMm,
        greaterThan(400.0),
        reason:
            'Le trajet mur∩plafond (${totalLengthMm.toStringAsFixed(0)}mm) '
            'doit être plus long que les 400mm de la fenêtre de crop.',
      );
      final uCenterMm = totalLengthMm / 2.0;
      const halfWindowMm = 200.0; // 40cm total
      final uMinMm = uCenterMm - halfWindowMm;
      final uMaxMm = uCenterMm + halfWindowMm;

      double minX = double.infinity;
      double maxX = -double.infinity;
      double minY = double.infinity;
      double maxY = -double.infinity;
      for (var i = 0; i < mesh.vertexCount; i++) {
        final u = mesh.uvAt(i).x;
        if (u < uMinMm || u > uMaxMm) continue;
        final proj = scene.camera.project(mesh.positionAt(i));
        if (proj.pixel.x < minX) minX = proj.pixel.x;
        if (proj.pixel.x > maxX) maxX = proj.pixel.x;
        if (proj.pixel.y < minY) minY = proj.pixel.y;
        if (proj.pixel.y > maxY) maxY = proj.pixel.y;
      }
      expect(
        minX.isFinite && maxX.isFinite && minY.isFinite && maxY.isFinite,
        isTrue,
        reason:
            'Aucun sommet du maillage dans la fenêtre de 40cm centrée '
            '(uCenterMm=$uCenterMm) — vérifier le trajet/UV.',
      );

      // Marge : un peu de contexte visuel (mur au-dessus, plafond/pièce en
      // dessous de l'arête) autour du bbox projeté strict de la corniche.
      final bboxPxW = maxX - minX;
      final bboxPxH = maxY - minY;
      final marginX = bboxPxW * 0.15;
      final marginYAbove = bboxPxH * 0.5; // un peu de mur au-dessus
      final marginYBelow = bboxPxH * 1.1; // plus de pièce en dessous
      final cropLeft = (minX - marginX).clamp(0.0, photoW);
      final cropRight = (maxX + marginX).clamp(0.0, photoW);
      final cropTop = (minY - marginYAbove).clamp(0.0, photoH);
      final cropBottom = (maxY + marginYBelow).clamp(0.0, photoH);
      final cropW = cropRight - cropLeft;
      final cropH = cropBottom - cropTop;
      expect(cropW, greaterThan(0));
      expect(cropH, greaterThan(0));

      // ── 8. Panneau crop ×4 — zoom numérique ×4 de la région recadrée de
      //      l'image DÉJÀ composée (photo + mesh), pas un second rendu
      //      géométrique séparé (le contenu doit être visuellement
      //      identique à la vue d'ensemble, juste agrandi). ──
      const zoomFactor = 4.0;
      final cropCanvasW = cropW * zoomFactor;
      final cropCanvasH = cropH * zoomFactor;
      final cropRecorder = ui.PictureRecorder();
      final cropCanvas = ui.Canvas(cropRecorder);
      cropCanvas.drawImageRect(
        overviewImage,
        ui.Rect.fromLTWH(cropLeft, cropTop, cropW, cropH),
        ui.Rect.fromLTWH(0, 0, cropCanvasW, cropCanvasH),
        ui.Paint(),
      );
      final cropPicture = cropRecorder.endRecording();
      final cropImage = await cropPicture.toImage(
        cropCanvasW.round(),
        cropCanvasH.round(),
      );

      // ── 9. Composition finale : vue d'ensemble (redimensionnée à une
      //      largeur d'affichage raisonnable) au-dessus, crop ×4 en
      //      dessous, légende texte en bas. ──
      const displayW = 1400.0; // largeur d'affichage cible pour la vue 1
      final overviewScale = displayW / photoW;
      final overviewDisplayH = photoH * overviewScale;

      final cropDisplayScale = (displayW / cropCanvasW).clamp(0.0, 1.0);
      final cropDisplayW = cropCanvasW * cropDisplayScale;
      final cropDisplayH = cropCanvasH * cropDisplayScale;

      const labelBandH = 34.0;
      const legendH = 150.0;
      const pad = 16.0;

      final totalW = displayW + pad * 2;
      final totalH = pad +
          labelBandH +
          overviewDisplayH +
          pad +
          labelBandH +
          cropDisplayH +
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
            fontFamily: 'DebugLegendFont',
            fontSize: fontSize,
            fontWeight: ui.FontWeight.bold,
            textAlign: ui.TextAlign.left,
          ),
        )
          ..pushStyle(
            ui.TextStyle(
              color: const ui.Color(0xFF000000),
              fontFamily: 'DebugLegendFont',
              fontWeight: ui.FontWeight.bold,
            ),
          )
          ..addText(text);
        return builder.build()
          ..layout(ui.ParagraphConstraints(width: totalW - pad * 2));
      }

      var cursorY = pad;

      // Étiquette + panneau 1 (vue d'ensemble).
      finalCanvas.drawParagraph(
        buildLabel(
          '1. VUE D\'ENSEMBLE — corniche $sku sur haussmann.jpg',
        ),
        ui.Offset(pad, cursorY),
      );
      cursorY += labelBandH;
      finalCanvas.save();
      finalCanvas.translate(pad, cursorY);
      finalCanvas.scale(overviewScale, overviewScale);
      finalCanvas.drawImageRect(
        overviewImage,
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Rect.fromLTWH(0, 0, photoW, photoH),
        ui.Paint(),
      );
      finalCanvas.restore();
      finalCanvas.drawRect(
        ui.Rect.fromLTWH(pad, cursorY, displayW, overviewDisplayH),
        ui.Paint()
          ..color = const ui.Color(0xFF888888)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      cursorY += overviewDisplayH + pad;

      // Étiquette + panneau 2 (crop ×4).
      finalCanvas.drawParagraph(
        buildLabel(
          '2. CROP ×4 — 40cm (400mm reels) d\'arete plafond, centre sur le trajet',
        ),
        ui.Offset(pad, cursorY),
      );
      cursorY += labelBandH;
      finalCanvas.save();
      finalCanvas.translate(pad, cursorY);
      finalCanvas.scale(cropDisplayScale, cropDisplayScale);
      finalCanvas.drawImageRect(
        cropImage,
        ui.Rect.fromLTWH(0, 0, cropCanvasW, cropCanvasH),
        ui.Rect.fromLTWH(0, 0, cropCanvasW, cropCanvasH),
        ui.Paint(),
      );
      finalCanvas.restore();
      finalCanvas.drawRect(
        ui.Rect.fromLTWH(pad, cursorY, cropDisplayW, cropDisplayH),
        ui.Paint()
          ..color = const ui.Color(0xFF888888)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      cursorY += cropDisplayH + pad;

      // Légende texte — SKU, chemin JSON, bbox, triangles, lumière.
      final lightNorm = lightDirWorld.normalized();
      final legendText =
          'SKU : $sku   |   JSON : $jsonRelPath\n'
          'Bbox profil (source dxf2profile/step2profile) : '
          '${bboxWMm.toStringAsFixed(1)} x ${bboxHMm.toStringAsFixed(1)} mm '
          '(largeur x hauteur)\n'
          'Triangles maillage (sweepMoulure) : ${mesh.triangleCount}   |   '
          'Sommets maillage : ${mesh.vertexCount}\n'
          'Eclairage : ambiante = ${ambient.toStringAsFixed(2)}   |   '
          'directionnelle (vers la source, repere monde X=droite/Y=haut/'
          'Z=camera) = '
          '(${lightDirWorld.x.toStringAsFixed(2)}, '
          '${lightDirWorld.y.toStringAsFixed(2)}, '
          '${lightDirWorld.z.toStringAsFixed(2)}) normalisee '
          '(${lightNorm.x.toStringAsFixed(3)}, '
          '${lightNorm.y.toStringAsFixed(3)}, '
          '${lightNorm.z.toStringAsFixed(3)}) — composante Y/Z dominante, '
          'perpendiculaire a l\'axe de balayage +X (voir CONVENTIONS.md)\n'
          'Crop : centre u=${uCenterMm.toStringAsFixed(0)}mm, fenetre '
          '[${uMinMm.toStringAsFixed(0)}, ${uMaxMm.toStringAsFixed(0)}]mm, '
          'zoom x${zoomFactor.toStringAsFixed(0)}   |   trajet total '
          '${totalLengthMm.toStringAsFixed(0)}mm';

      final legendBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          fontFamily: 'DebugLegendFont',
          fontSize: 16,
          textAlign: ui.TextAlign.left,
        ),
      )
        ..pushStyle(
          ui.TextStyle(
            color: const ui.Color(0xFF000000),
            fontFamily: 'DebugLegendFont',
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

      const outPath =
          '/tmp/step2profile_pilot_test/render_d720_haussmann_dualview.png';
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(pngBytes);

      expect(await outFile.exists(), isTrue);
      expect(pngBytes.length, greaterThan(10000));

      // ignore: avoid_print
      print('── PNG double-vue écrit ──');
      // ignore: avoid_print
      print('  Chemin      : $outPath');
      // ignore: avoid_print
      print('  Taille      : ${pngBytes.length} octets');
      // ignore: avoid_print
      print('  Dimensions  : ${totalW.round()}x${totalH.round()} px');
      // ignore: avoid_print
      print('  SKU         : $sku');
      // ignore: avoid_print
      print('  JSON        : $jsonRelPath');
      // ignore: avoid_print
      print(
        '  Bbox profil : ${bboxWMm.toStringAsFixed(1)} x '
        '${bboxHMm.toStringAsFixed(1)} mm',
      );
      // ignore: avoid_print
      print(
        '  Triangles   : ${mesh.triangleCount}   Sommets : '
        '${mesh.vertexCount}',
      );
      // ignore: avoid_print
      print(
        '  Lumiere     : ambient=$ambient dir='
        '(${lightDirWorld.x}, ${lightDirWorld.y}, ${lightDirWorld.z}) '
        'normalisee (${lightNorm.x.toStringAsFixed(3)}, '
        '${lightNorm.y.toStringAsFixed(3)}, '
        '${lightNorm.z.toStringAsFixed(3)})',
      );
      // ignore: avoid_print
      print(
        '  Crop        : centre u=${uCenterMm.toStringAsFixed(0)}mm '
        'fenetre=[${uMinMm.toStringAsFixed(0)}, '
        '${uMaxMm.toStringAsFixed(0)}]mm trajet_total='
        '${totalLengthMm.toStringAsFixed(0)}mm '
        'cropPx=${cropW.toStringAsFixed(0)}x${cropH.toStringAsFixed(0)} '
        'zoom=x${zoomFactor.toStringAsFixed(0)}',
      );
    },
  );
}
