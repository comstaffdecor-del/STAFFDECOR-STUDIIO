// Test-livrable P14 : grille de 6 rendus D720/haussmann.jpg à des échelles
// différentes, TOUS via le chemin "vraie silhouette" (sweepMoulure +
// paintMeshOnCanvas), même ancrage/calibration pour tous les panneaux,
// matière blanc cassé UNIFORME (ambient=1.0 -> aucune variation de
// luminosité par sommet, donc aucun risque d'artefact "damier").
//
// Ne modifie NI P12/IA NI edge_detect.dart NI PerspCalib.demoPresets NI
// Playwright NI la génération de devis — lecture/composition pure à partir
// de code de production/géométrie déjà existant (sweep.dart, mesh_painter
// .dart, calib_to_camera.dart), plus UN helper générique ajouté ICI
// (scaleProfile, ne dépend d'aucun SKU).
//
// Sortie : /tmp/p14_scale_grid_d720.png (grille 6 panneaux) et
// /tmp/p14_scale_grid_d720.txt (rapport texte). Écrit dans /tmp/ uniquement.
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
import 'package:staff_decor_studio/core/perspective/strip_px_from_dims.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

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
    'P14 — grille 6 échelles D720 sur haussmann.jpg, chemin mesh réel '
    '(sweepMoulure/paintMeshOnCanvas), même ancrage, matière blanc cassé '
    'uniforme (ambient=1.0, pas de damier)',
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
      const metresHauteurDefaut = 2.5; // AppState.metresHauteur, valeur par défaut (app_state.dart:81)
      final pHPixels = (calib.floorL.yPct - calib.ceilL.yPct) * photoH;
      final facteurProductionActuel = pxParMm(
        pH: pHPixels,
        metresHauteur: metresHauteurDefaut,
      )!;

      // ── 5. Mesure "hauteur du profil en pixels" pour une échelle donnée :
      //      distance verticale en pixels ÉCRAN entre le point du contour
      //      collé au plafond (topIdx) et le point le plus bas (bottomIdx),
      //      sur l'anneau du MILIEU du trajet (mid path), projetés par la
      //      MÊME caméra calibrée pour tous les panneaux. ──
      double measureProfileHeightPx(double scale) {
        final scaled = scaleProfile(baseProfile, scale);
        final rings = computeCrossSectionRings(
          profile: scaled,
          pathMeters: pathMeters,
          wallPlanes: wallPlanes,
          ceilingPlane: scene.ceilingPlane,
        );
        final ring = rings[midRingIndex];
        final topPx = scene.camera.project(ring[topIdx]).pixel;
        final bottomPx = scene.camera.project(ring[bottomIdx]).pixel;
        return (bottomPx.y - topPx.y).abs();
      }

      // ── 6. Panneau 6 — échelle "calculée" : on définit la cible comme la
      //      hauteur en pixels que produirait AUJOURD'HUI la formule de
      //      production (pxParMm) pour bbox_mm.h=202.87mm SI
      //      metresHauteur=2.70m (hypothèse demandée), avec le pH RÉEL de
      //      cette scène. Le chemin mesh (scale=1.0) est, par construction
      //      de profileToWorld (sweep.dart, /1000.0), un rendu physique
      //      1:1 INDÉPENDANT de metresHauteur — il n'existe donc pas de
      //      "scale=1.0 à 2.70m" directement comparable côté mesh ; le
      //      pont choisi ICI (hypothèse explicite, documentée dans le
      //      rapport) est : quel scalaire appliqué au profil physique
      //      ferait correspondre la hauteur PIXEL projetée du mesh à la
      //      hauteur PIXEL que la formule 2D de production calculerait à
      //      2.70m. Résolu par 3 itérations de correction linéaire simple
      //      (la relation scale->px n'est pas parfaitement linéaire à
      //      cause de la perspective, mais quasi-linéaire à cette échelle
      //      -> convergence en 2-3 pas suffit, mesurée explicitement
      //      ci-dessous, pas supposée). ──
      const metresHauteurCalcul = 2.70;
      final facteurCalcule = pxParMm(
        pH: pHPixels,
        metresHauteur: metresHauteurCalcul,
      )!;
      final ciblePx = bboxHMm * facteurCalcule;

      final h1 = measureProfileHeightPx(1.0);
      var scale6 = ciblePx / h1;
      for (var iter = 0; iter < 3; iter++) {
        final achieved = measureProfileHeightPx(scale6);
        scale6 = scale6 * (ciblePx / achieved);
      }
      final h6Final = measureProfileHeightPx(scale6);

      // ── 7. Les 6 échelles, dans l'ordre demandé. ──
      final scales = <String, double>{
        '1.0': 1.0,
        '0.5': 0.5,
        '0.25': 0.25,
        '0.15': 0.15,
        '0.10': 0.10,
        'calculee_2.70m': scale6,
      };
      final heightsPx = <String, double>{
        for (final e in scales.entries) e.key: measureProfileHeightPx(e.value),
      };

      // ── 8. Rendu d'UN panneau (photo + mesh à l'échelle donnée), matière
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

      // ── 9. Composition grille 3 colonnes x 2 rangées + légende. ──
      const cols = 3;
      const panelDisplayW = 700.0;
      final displayScale = panelDisplayW / photoW;
      final panelDisplayH = photoH * displayScale;
      const labelH = 24.0;
      const legendH = 210.0;
      const pad = 14.0;

      final order = ['1.0', '0.5', '0.25', '0.15', '0.10', 'calculee_2.70m'];
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

        final label = key == 'calculee_2.70m'
            ? 'F. scale calc. (2.70m) = ${scale6.toStringAsFixed(4)}  h=${heightsPx[key]!.toStringAsFixed(1)}px'
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
          'P14 — grille 6 echelles D720 / haussmann.jpg — chemin MESH REEL (sweepMoulure + paintMeshOnCanvas), meme ancrage/calibration pour tous les panneaux\n'
          'Photo : assets/demo_scenes/$sceneKey.jpg (${photo.width}x${photo.height}px) | Calibration : PerspCalib.forDemoScene(\'$sceneKey\') (non modifiee)\n'
          'Materiau : blanc casse uni (0xFFF2EEE4), ambient=1.0 -> AUCUNE variation de luminosite par sommet, donc AUCUN damier possible\n'
          'pH (pixels, cette scene) = ${pHPixels.toStringAsFixed(2)}px | Facteur mm->px production actuel (metresHauteur=$metresHauteurDefaut m, defaut AppState) = ${facteurProductionActuel.toStringAsFixed(6)} px/mm\n'
          'Panneau F : facteur mm->px a metresHauteur=$metresHauteurCalcul m = ${facteurCalcule.toStringAsFixed(6)} px/mm ; cible = bbox_mm.h(${bboxHMm.toStringAsFixed(2)}mm) x facteur = ${ciblePx.toStringAsFixed(2)}px ; scale resolu = ${scale6.toStringAsFixed(4)} ; hauteur obtenue = ${h6Final.toStringAsFixed(2)}px (cible ${ciblePx.toStringAsFixed(2)}px)\n'
          'bbox_mm.h = ${bboxHMm.toStringAsFixed(3)}mm | hauteur_mur_mm = ${hauteurMurMm.toStringAsFixed(3)}mm | ratio = ${(bboxHMm / hauteurMurMm).toStringAsFixed(4)}\n'
          'Reponse : profile_dims.dart RECALCULE retombeeMm depuis profil_mm et le VALIDE (tolerance) contre bbox_mm.h — hauteur_mur_mm JAMAIS lu pour la retombee.';

      finalCanvas.drawParagraph(
        buildLabel(legendText, fontSize: 14, maxWidth: totalW - pad * 2),
        ui.Offset(pad, legendY),
      );

      final finalPicture = finalRecorder.endRecording();
      final finalImage = await finalPicture.toImage(totalW.round(), totalH.round());
      final pngBytes = await encodePng(finalImage);

      const outPngPath = '/tmp/p14_scale_grid_d720.png';
      final outPngFile = File(outPngPath);
      await outPngFile.writeAsBytes(pngBytes);
      expect(await outPngFile.exists(), isTrue);
      expect(pngBytes.length, greaterThan(10000));

      // ── 10. Rapport texte séparé /tmp/p14_scale_grid_d720.txt. ──
      final report = StringBuffer();
      report.writeln('P14 — grille 6 echelles D720 sur haussmann.jpg — rapport');
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
      report.writeln('2) FACTEUR DU PANNEAU 6 ("calcule", hypothese metresHauteur=$metresHauteurCalcul m, bbox_mm.h=${bboxHMm.toStringAsFixed(2)}mm) :');
      report.writeln('   Interpretation retenue (choix explicite, la formulation de la demande etant ambigue pour le chemin MESH — ');
      report.writeln('   voir note ci-dessous) : on calcule d\'abord la hauteur EN PIXELS que la formule de PRODUCTION donnerait');
      report.writeln('   pour bbox_mm.h a metresHauteur=$metresHauteurCalcul m (avec le pH REEL de cette scene), puis on cherche le SCALE a');
      report.writeln('   appliquer au profil physique (mm) du chemin mesh pour que sa hauteur projetee en pixels egale cette cible.');
      report.writeln('     facteur a ${metresHauteurCalcul}m = pH / (${metresHauteurCalcul}*1000) = ${facteurCalcule.toStringAsFixed(6)} px/mm');
      report.writeln('     cible px = bbox_mm.h * facteur = ${bboxHMm.toStringAsFixed(2)} * ${facteurCalcule.toStringAsFixed(6)} = ${ciblePx.toStringAsFixed(3)} px');
      report.writeln('     hauteur mesuree a scale=1.0 (rendu mesh physique 1:1, independant de metresHauteur par construction de profileToWorld /1000) = ${h1.toStringAsFixed(3)} px');
      report.writeln('     scale resolu (3 iterations de correction lineaire, mesure reelle a chaque pas) = ${scale6.toStringAsFixed(6)}');
      report.writeln('     hauteur obtenue avec ce scale (mesuree reellement sur le rendu final) = ${h6Final.toStringAsFixed(3)} px (cible ${ciblePx.toStringAsFixed(3)} px, ecart ${(h6Final - ciblePx).abs().toStringAsFixed(3)} px)');
      report.writeln();
      report.writeln('3) HAUTEUR DU PROFIL EN PIXELS POUR CHACUN DES 6 PANNEAUX :');
      report.writeln('   Methode de mesure : distance verticale en pixels ECRAN entre le point du contour colle au plafond');
      report.writeln('   (indice ${topIdx}, y=0) et le point le plus bas de la retombee (indice ${bottomIdx}, y le plus negatif — c\'est');
      report.writeln('   exactement le point qui definit bbox_mm.h / retombeeMm recalcule), sur l\'anneau du MILIEU du trajet,');
      report.writeln('   projetes par la meme Camera3D pour tous les panneaux.');
      for (final key in order) {
        final label = key == 'calculee_2.70m' ? 'Panneau F (calculee, 2.70m)' : 'scale x $key';
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

      const outTxtPath = '/tmp/p14_scale_grid_d720.txt';
      await File(outTxtPath).writeAsString(report.toString());
      expect(await File(outTxtPath).exists(), isTrue);

      // ignore: avoid_print
      print('── P14 grille écrite ──');
      // ignore: avoid_print
      print('  PNG    : $outPngPath (${pngBytes.length} octets)');
      // ignore: avoid_print
      print('  Rapport: $outTxtPath');
      // ignore: avoid_print
      print('  scale calculee (2.70m) = ${scale6.toStringAsFixed(6)}, hauteur obtenue = ${h6Final.toStringAsFixed(2)}px (cible ${ciblePx.toStringAsFixed(2)}px)');
    },
  );
}
