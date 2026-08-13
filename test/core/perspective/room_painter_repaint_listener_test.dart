library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/product_texture_cache.dart';
import 'package:staff_decor_studio/core/perspective/room_painter.dart';
import 'package:staff_decor_studio/models/persp_calib.dart';

void main() {
  test(
    'RoomPainter relaie ProductTextureCache.instance en repaint: — un '
    'listener attache via CustomPainter.addListener doit etre notifie '
    'quand ProductTextureCache echoue un chargement (branche notifyListeners '
    'ligne 71 de product_texture_cache.dart)',
    () async {
      final painter = RoomPainter(
        roomImage: null,
        imgDraw: null,
        calib: PerspCalib.defaultCalib,
        selectedProducts: const [],
        prodPositions: const {},
        withProducts: true,
      );

      final completer = Completer<void>();
      void cb() {
        if (!completer.isCompleted) completer.complete();
      }

      // CustomPainter.addListener delegue a _repaint?.addListener(listener)
      // — si RoomPainter ne passe rien a super(repaint: ...), _repaint est
      // null et cb ne sera JAMAIS appele : c'est precisement ce que ce test
      // verifie.
      painter.addListener(cb);

      // Ref improbable pour ne pas interferer avec l'etat partage du
      // singleton ProductTextureCache entre tests (pas de reset() public).
      // Port ferme localement (1) -> connection refused quasi immediat,
      // sans dependance DNS/reseau externe : passe par _load -> catch ->
      // notifyListeners() (ligne 71), jamais par la branche url.isEmpty
      // (ligne 46-49) qui ne notifie pas.
      ProductTextureCache.instance.ensureLoading(
        '__test_repaint_listener_probe__',
        'http://127.0.0.1:1/probe.png',
      );

      await completer.future.timeout(const Duration(seconds: 5));
      painter.removeListener(cb);
    },
  );
}
