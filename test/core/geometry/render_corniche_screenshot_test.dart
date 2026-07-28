// Test-livrable : rend une corniche réelle (profil `assets/profiles/
// 1000.json`, `sweepMoulure`) posée sur une photo de pièce réelle
// (`assets/demo_scenes/haussmann.jpg`, calibration `PerspCalib.
// demoPresets['haussmann']`), projetée par une `Camera3D` dérivée de la
// calibration via `calib_to_camera.dart`, et sauvegarde le résultat en PNG.
//
// ⚠️ Sortie écrite dans `/tmp/` — JAMAIS dans `assets/` (règle SPEC.md
// "write-once" / anti-suppression, voir tête de SPEC.md).
//
// Ce test est le second des deux livrables bloquants demandés par
// l'utilisateur ("rendering/ et la capture d'écran d'une corniche posée
// sur une photo") : il prouve que la chaîne complète
//   PerspCalib (8 points 2D) -> calib_to_camera.buildCalibratedScene
//     -> MoulureProfile (JSON pipeline Python) -> sweep.sweepMoulure (Mesh)
//     -> mesh_painter.paintMeshOnCanvas (projection Camera3D + tri peintre)
// produit une image cohérente, composée sur la vraie photo.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:staff_decor_studio/core/geometry/calib_to_camera.dart';
import 'package:staff_decor_studio/core/geometry/sweep.dart';
import 'package:staff_decor_studio/core/perspective/mesh_painter.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

/// Charge un profil `MoulureProfile` depuis le JSON produit par le
/// pipeline Python (`assets/profiles/<sku>.json`, schéma `SPEC.md`).
/// Duplique volontairement le décodage minimal nécessaire ici (pas de
/// dépendance à un futur loader `lib/` non encore écrit) — un vrai loader
/// de production (avec gestion `statut != OK`, etc.) reste à écrire
/// séparément quand l'UI consommera de vrais profils.
///
/// ⚠️ Artefact connu de `dxf2profile.py`/tracé DXF : le dernier sommet de
/// `profil_mm` duplique parfois exactement le premier (fermeture explicite
/// du contour côté outil de dessin). `MoulureProfile`/`sweepMoulure`
/// ferment déjà le contour eux-mêmes (accès par modulo, voir
/// `perimeterMm`/`_buildQuadTriangles`) et NE VEULENT PAS de ce doublon —
/// un dernier sommet confondu avec le premier produit une arête de
/// fermeture de longueur nulle -> triangle dégénéré dans `sweepMoulure`.
/// On déduplique donc ici, au chargement (pas une correction du profil
/// lui-même : la donnée source `assets/profiles/1000.json` n'est jamais
/// modifiée, seule cette étape de chargement retire le sommet redondant).
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
    'rend une corniche (profil 1000.json) sur haussmann.jpg et sauvegarde '
    'le PNG dans /tmp/ (jamais dans assets/)',
    () async {
      // ── 1. Photo réelle + calibration réelle du preset démo. ──
      final projectRoot = Directory.current.path;
      final photoPath = '$projectRoot/assets/demo_scenes/haussmann.jpg';
      final photo = await decodeImageFile(photoPath);
      final calib = PerspCalib.forDemoScene('haussmann');

      // ── 2. Pont calibration 2D -> scène 3D (calib_to_camera.dart). ──
      final scene = buildCalibratedScene(
        calib: calib,
        imageWidthPx: photo.width.toDouble(),
        imageHeightPx: photo.height.toDouble(),
      );

      expect(scene.camera.focalPx, greaterThan(0));
      expect(scene.ceilLOnEdge, isNot(equals(scene.ceilROnEdge)));

      // ── 3. Profil réel du pipeline Python (assets/profiles/1000.json,
      //      statut OK, corniche/moulure lisse 230x30mm). ──
      final jsonStr = await File(
        '$projectRoot/assets/profiles/1000.json',
      ).readAsString();
      final profileJson = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(profileJson['statut'], 'OK');
      final profile = loadProfileFromJson(profileJson);

      // ── 4. Trajet le long de l'arête mur∩plafond réelle (ceilLOnEdge ->
      //      ceilROnEdge), un seul mur (mur du fond) sur tout le trajet. ──
      final mesh = sweepMoulure(
        profile: profile,
        pathMeters: [scene.ceilLOnEdge, scene.ceilROnEdge],
        wallPlanes: [scene.backWallPlane],
        ceilingPlane: scene.ceilingPlane,
      );

      expect(mesh.vertexCount, greaterThan(0));
      expect(mesh.triangleCount, greaterThan(0));

      // ── 5. Composition finale : photo + mesh projeté, rasterisé en PNG. ──
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final w = photo.width.toDouble();
      final h = photo.height.toDouble();

      canvas.drawImageRect(
        photo,
        ui.Rect.fromLTWH(0, 0, w, h),
        ui.Rect.fromLTWH(0, 0, w, h),
        ui.Paint(),
      );

      paintMeshOnCanvas(
        canvas,
        mesh,
        scene.camera,
        baseColor: const ui.Color(0xFFEDEAE4),
      );

      final picture = recorder.endRecording();
      final finalImage = await picture.toImage(photo.width, photo.height);
      final pngBytes = await encodePng(finalImage);

      const outPath =
          '/tmp/solid2profile_be_test/rendering_corniche_haussmann.png';
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(pngBytes);

      expect(await outFile.exists(), isTrue);
      // Sanity : le fichier produit n'est pas vide/trivial.
      expect(pngBytes.length, greaterThan(10000));

      // ignore: avoid_print
      print('Capture écrite : $outPath (${pngBytes.length} octets)');
    },
  );
}

