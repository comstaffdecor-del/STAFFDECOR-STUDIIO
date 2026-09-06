// P10 — sonde de diagnostic de lecture de perspective (permanent, PAS un
// *_tmp_*). Objectif : mesurer, pour chacune des 4 scènes démo, si le
// pipeline Sobel/Hough actuel (`lib/core/perspective/edge_detect.dart`)
// produit assez de lignes diagonales cohérentes pour dégager un point de
// fuite stable — critère de décision explicite du brief P10 : au moins 2
// scènes avec un point de fuite stable ET >= 3 lignes diagonales inliers
// pour continuer vers P10-RANSAC, sinon abandonner Sobel/Hough au profit
// d'une segmentation IA mur/plafond/sol.
//
// AUCUNE modification du rendu : ce fichier consomme uniquement l'API
// publique existante `detectRoomEdges` (non modifiée) et la nouvelle
// fonction diagnostique ADDITIVE `detectRoomEdgesDiagnostic` ajoutée dans
// `edge_detect.dart` (rejoue le même pipeline, `_buildGeometry` appelé
// sans aucune altération). `RoomPainter`, presets, devis, `autoApplyDetection`
// et le choix `xL`/`xR` fixes de `_buildGeometry` ne sont ni lus ni
// modifiés ici.
//
// Aucun `expect` qui échoue : instrument de mesure, pas un test de
// non-régression (même philosophie que P9a/P9b/P9c) — il doit rester vert
// quel que soit le résultat mesuré ; la décision revient à un humain qui
// lit le VERDICT imprimé et les fichiers JSON générés.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:staff_decor_studio/core/perspective/edge_detect.dart';

const List<String> kPresetKeys = [
  'haussmann',
  'moderne',
  'provencal',
  'scandinave',
];

/// Seuil de décision du brief P10 : nombre minimum de lignes diagonales
/// inliers (gauche+droite ayant produit au moins une intersection valide)
/// pour considérer le point de fuite d'une scène comme "stable".
const int kMinInlierDiagonals = 3;

Future<ui.Image> _decodeImageFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'P10 : sonde de lecture image (lignes Hough, VP, inliers, plafond/sol, '
    'PerspCalib, confidence, verdict) sur les 4 scènes démo',
    () async {
      final sceneVerdicts = <String, bool>{};
      final sceneInliers = <String, int>{};
      final sceneHasStableVp = <String, bool>{};

      for (final key in kPresetKeys) {
        final imgPath = 'assets/demo_scenes/$key.jpg';
        final file = File(imgPath);
        if (!file.existsSync()) {
          // ignore: avoid_print
          print('[p10] scene=$key image introuvable path=$imgPath');
          continue;
        }

        final image = await _decodeImageFile(imgPath);
        final diag = await detectRoomEdgesDiagnostic(image);
        image.dispose();

        if (diag == null) {
          // ignore: avoid_print
          print(
            '[p10] scene=$key detectRoomEdgesDiagnostic=null '
            '(exception interne ou image vide) verdict=not usable',
          );
          sceneVerdicts[key] = false;
          sceneInliers[key] = 0;
          sceneHasStableVp[key] = false;
          continue;
        }

        // --- Vérification croisée avec l'API de production non modifiée
        // (detectRoomEdges) : le champ `usable` de la sonde doit refléter
        // exactement le même verdict que l'API réellement utilisée par
        // l'app (même image, même pipeline).
        final image2 = await _decodeImageFile(imgPath);
        final prodResult = await detectRoomEdges(image2);
        image2.dispose();
        final prodUsable = prodResult != null;
        if (prodUsable != diag.usable) {
          // ignore: avoid_print
          print(
            '[p10] scene=$key ATTENTION divergence sonde/prod : '
            'diag.usable=${diag.usable} prod(detectRoomEdges!=null)=$prodUsable',
          );
        }

        final hasStableVp = diag.vpXPct != null &&
            diag.vpYPct != null &&
            diag.inlierDiagonalCount >= kMinInlierDiagonals;
        sceneVerdicts[key] = diag.usable;
        sceneInliers[key] = diag.inlierDiagonalCount;
        sceneHasStableVp[key] = hasStableVp;

        final vpStr = (diag.vpXPct != null && diag.vpYPct != null)
            ? '(${diag.vpXPct!.toStringAsFixed(4)}, '
                  '${diag.vpYPct!.toStringAsFixed(4)})'
            : 'null';
        final ceilYStr = diag.chosenCeiling != null
            ? ((diag.chosenCeiling!.y1Pct + diag.chosenCeiling!.y2Pct) / 2)
                  .toStringAsFixed(4)
            : 'null';
        final floorYStr = diag.chosenFloor != null
            ? ((diag.chosenFloor!.y1Pct + diag.chosenFloor!.y2Pct) / 2)
                  .toStringAsFixed(4)
            : 'null';

        // ignore: avoid_print
        print(
          '[p10] scene=$key nLines=${diag.lines.length} '
          'nIntersections=${diag.diagonalIntersections.length} '
          'inliers=${diag.inlierDiagonalCount} '
          'vp=$vpStr ceiling_y=$ceilYStr floor_y=$floorYStr '
          'confidence=${diag.confidence.toStringAsFixed(4)} '
          'stableVp(>=${kMinInlierDiagonals}inliers)=$hasStableVp '
          'verdict=${diag.usable ? "usable" : "not usable"}',
        );

        // Comptage par classification enrichie (horizontal/vertical/
        // diagonal_left/diagonal_right/ignored) pour visibilité directe
        // dans le log, sans devoir ouvrir le JSON.
        final counts = <String, int>{};
        for (final l in diag.lines) {
          counts[l.classification] = (counts[l.classification] ?? 0) + 1;
        }
        // ignore: avoid_print
        print('[p10] scene=$key classification_counts=$counts');

        // --- Écriture du fichier JSON par scène ---
        final jsonMap = {
          'scene': key,
          'imagePath': imgPath,
          ...diag.toJson(),
          'stableVanishingPoint': hasStableVp,
          'minInlierDiagonalsThreshold': kMinInlierDiagonals,
        };
        final outPath = '/tmp/p10_image_reading_$key.json';
        File(outPath).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(jsonMap),
        );
        // ignore: avoid_print
        print('[p10] scene=$key fichier_json=$outPath');
      }

      // --- Application du critère de décision global du brief P10 ---
      final scenesWithStableVp = sceneHasStableVp.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();
      final decision = scenesWithStableVp.length >= 2
          ? 'CONTINUER P10-RANSAC (>=2 scenes avec VP stable et '
                '>=$kMinInlierDiagonals diagonales inliers : '
                '${scenesWithStableVp.join(", ")})'
          : 'ABANDONNER Sobel/Hough -> pivot segmentation IA '
                'mur/plafond/sol (moins de 2 scenes avec VP stable, '
                'trouvees: ${scenesWithStableVp.isEmpty ? "aucune" : scenesWithStableVp.join(", ")})';

      // ignore: avoid_print
      print(
        '[p10] RESUME scenes_mesurees=${sceneVerdicts.length}/4 '
        'scenes_vp_stable=${scenesWithStableVp.length} '
        'inliers_par_scene=$sceneInliers '
        'verdicts_par_scene=$sceneVerdicts',
      );
      // ignore: avoid_print
      print('[p10] DECISION = $decision');

      // Aucun expect qui échoue : instrument de mesure, jamais rouge par
      // construction, exactement comme P9a/P9b/P9c.
      expect(true, isTrue);
    },
  );
}
