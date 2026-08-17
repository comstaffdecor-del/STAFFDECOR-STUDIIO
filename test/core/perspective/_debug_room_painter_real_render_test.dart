// Script de diagnostic TEMPORAIRE — PAS commité ce tour (consigne
// explicite). Objectif : produire, pour la toute première fois dans ce
// projet, une image de la lignée RÉELLEMENT affichée à l'écran
// (RoomPainter / cornice_plinth_painter.dart), avec des entrées réelles
// (photo assets/demo_scenes/haussmann.jpg, calibration
// PerspCalib.forDemoScene('haussmann')) — PAS la lignée 3D
// (core/geometry/) déjà couverte par les scripts _debug_*  de 0deed35.
//
// Technique de capture PNG reprise de
// test/core/geometry/_debug_whitebg_overlay_test.dart (0deed35) :
// PictureRecorder, toByteData(ImageByteFormat.png), fond blanc — RIEN
// D'AUTRE n'est repris de ce fichier (ni caméra, ni sweep, ni profil
// chargé à la main : ici c'est RoomPainter.paint() qui est appelé tel
// quel, exactement comme studio_screen.dart/comparateur_screen.dart le
// font en production).
//
// Deux rendus produits, sur la même scène (haussmann) pour comparaison :
//   1. Corniche D720 (assets/profiles/D720.json existe -> dimensions
//      réelles mm->px, pas le repli StripThickness.corniceDefault).
//   2. Plinthe PLIN08 (aucun profil JSON de plinthe n'existe à ce jour
//      -> StripThickness.plintheDefault(pH) systématiquement, c'est le
//      comportement réel documenté dans room_painter.dart, pas une
//      limitation de ce script).
//
// Sortie : /tmp/diag_room_painter/cornice_d720.png,
//          /tmp/diag_room_painter/plinthe_plin08.png
//
// Ce fichier n'est PAS un test au sens propre (aucune assertion sur le
// contenu visuel — un humain doit regarder les PNG). Il utilise
// `test()`/`flutter_test` uniquement pour bénéficier de
// TestWidgetsFlutterBinding (rootBundle pour ProfileDimsCache, dart:ui
// pour l'encodage PNG), exactement comme les autres fichiers `_debug_*`
// de ce projet.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Canvas, Paint, Color, Rect, Size;
import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/profile_dims_cache.dart';
import 'package:staff_decor_studio/core/perspective/room_painter.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';
import 'package:staff_decor_studio/models/project_item.dart';

Future<Uint8List> encodePng(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// Attend que [ref] soit résolu dans ProfileDimsCache (cache ou échec),
/// via le même patron Completer+listener que
/// profile_dims_cache_test.dart — pour être sûr que le rendu capturé
/// utilise les VRAIES dimensions mm, pas le repli de première frame.
Future<void> waitForProfileDims(String ref) async {
  if (ProfileDimsCache.instance.getIfLoaded(ref) != null ||
      ProfileDimsCache.instance.hasFailed(ref)) {
    return;
  }
  final completer = Completer<void>();
  void cb() {
    if (ProfileDimsCache.instance.getIfLoaded(ref) != null ||
        ProfileDimsCache.instance.hasFailed(ref)) {
      if (!completer.isCompleted) completer.complete();
    }
  }

  ProfileDimsCache.instance.addListener(cb);
  ProfileDimsCache.instance.ensureLoading(ref);
  await completer.future.timeout(const Duration(seconds: 5));
  ProfileDimsCache.instance.removeListener(cb);
}

Future<void> renderAndSave(
  RoomPainter painter,
  Size size,
  String outPath,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // Fond blanc — technique reprise telle quelle de 0deed35, pour
  // isoler visuellement tout ce que RoomPainter dessine par-dessus
  // (utile même si la photo remplit tout le cadre en mode "contain"
  // sans marge ici, car la taille de canvas est calée sur l'aspect
  // ratio réel de la photo).
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.width, size.height),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  final bytes = await encodePng(image);
  File(outPath).writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('Ecrit: $outPath (${bytes.length} octets, ${size.width.round()}x${size.height.round()})');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'diagnostic (non commité) : rend RoomPainter reel (D720 + PLIN08, scene haussmann)',
    () async {
      final projectRoot = Directory.current.path;
      final photoPath = '$projectRoot/assets/demo_scenes/haussmann.jpg';
      final photoFile = File(photoPath);

      expect(
        photoFile.existsSync(),
        isTrue,
        reason: 'Scene demo reelle introuvable: $photoPath',
      );

      final bytes = await photoFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final roomImage = frame.image;

      final srcW = roomImage.width.toDouble();
      final srcH = roomImage.height.toDouble();
      // ignore: avoid_print
      print('Photo haussmann.jpg decodee: ${srcW.round()}x${srcH.round()}');

      // Canvas calé exactement sur l'aspect ratio de la photo réelle —
      // mode "contain" sans marge, dx=dy=0, comme computeImgDraw()
      // (app_state.dart) le ferait pour un conteneur de même ratio.
      const canvasW = 1400.0;
      final canvasH = canvasW * srcH / srcW;
      final size = Size(canvasW, canvasH);
      final imgDraw = ImgDraw(dx: 0, dy: 0, dw: canvasW, dh: canvasH, scale: canvasW / srcW);

      final calib = PerspCalib.forDemoScene('haussmann');
      // Verifie que 'haussmann' est bien couverte par demoPresets (pas un
      // repli silencieux sur defaultCalib) — sinon la calibration ne
      // serait pas "reelle" au sens de la consigne.
      expect(
        identical(calib, PerspCalib.demoPresets['haussmann']),
        isTrue,
        reason:
            "PerspCalib.forDemoScene('haussmann') doit renvoyer l'entree "
            'demoPresets reelle, pas defaultCalib — sinon la calibration '
            'ne serait pas la vraie calibration mesuree de cette scene.',
      );

      const metresHauteur = 2.5;

      ProfileDimsCache.instance.resetForTesting();

      Directory('/tmp/diag_room_painter').createSync(recursive: true);

      // ── 1. Corniche D720 — profil JSON reel existant. ──
      const corniceItem = ProjectItem(
        ref: 'D720',
        famille: 'Corniches',
        qte: 2.0,
        unite: 'ml',
      );
      await waitForProfileDims('D720');
      final d720Dims = ProfileDimsCache.instance.getIfLoaded('D720');
      expect(
        d720Dims,
        isNotNull,
        reason:
            'D720 doit resoudre vers des dimensions reelles (assets/profiles/'
            'D720.json) avant capture, sinon le rendu capturerait le repli '
            'StripThickness.corniceDefault au lieu des dimensions reelles.',
      );
      // ignore: avoid_print
      print('D720 dims reelles chargees: $d720Dims');

      final corniceePainter = RoomPainter(
        roomImage: roomImage,
        imgDraw: imgDraw,
        calib: calib,
        selectedProducts: const [corniceItem],
        prodPositions: const {},
        metresHauteur: metresHauteur,
      );
      await renderAndSave(
        corniceePainter,
        size,
        '/tmp/diag_room_painter/cornice_d720.png',
      );

      // ── 2. Plinthe PLIN08 — aucun profil JSON de plinthe n'existe :
      //      StripThickness.plintheDefault(pH) sera utilise, c'est le
      //      comportement reel de production, pas une limitation de ce
      //      script. Pas d'attente de ProfileDimsCache ici (le chemin
      //      'Plinthes' de room_painter.dart ne l'appelle pas).
      const plintheItem = ProjectItem(
        ref: 'PLIN08',
        famille: 'Plinthes',
        qte: 2.0,
        unite: 'ml',
      );
      final plinthePainter = RoomPainter(
        roomImage: roomImage,
        imgDraw: imgDraw,
        calib: calib,
        selectedProducts: const [plintheItem],
        prodPositions: const {},
        metresHauteur: metresHauteur,
      );
      await renderAndSave(
        plinthePainter,
        size,
        '/tmp/diag_room_painter/plinthe_plin08.png',
      );
    },
  );
}
