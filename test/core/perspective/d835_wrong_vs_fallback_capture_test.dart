// Capture Étape 3 (brief de câblage, reformulée par l'utilisateur après
// la découverte "56 -> 31 restriction, pas 8 -> 31 extension") :
// démonstration du "rendu faux qui a l'air presque juste" contre lequel
// le contrôle de cohérence bbox_mm existe.
//
// D835 (`assets/profiles/D835.json`, `statut: OK`, `statut_gate:
// SUSPECT_GEOMETRIE`, motif `DEBORD_PLAN_MUR (ecart=39.865mm)`) :
//   - `bbox_mm.w` = 104.962 mm (largeur réelle du profil)
//   - `projectionMm` recalculé depuis `profil_mm` = 65.097 mm
// L'ancien mécanisme (pré-Étape-0, `assert()` absent des builds
// RELEASE) aurait rendu la bande avec `projectionMm=65.097` — une
// profondeur de projection 38% trop étroite pour la largeur réelle du
// profil (104.962mm), tout en restant visuellement plausible (pas une
// silhouette aberrante, juste "un peu fine"). C'est exactement le
// risque que le contrôle de cohérence bbox_mm/profil_mm neutralise
// aujourd'hui — pas un cas où le rendu était grossièrement cassé.
//
// Production SANS build release ni assert désactivé (méthode demandée
// explicitement) : deux bandes construites directement, côte à côte,
// dans un seul widget test —
//   AVANT : `StripThickness.fromPx(stripPxFromDims(... retombeeMm:
//           168.0, projectionMm: 65.097))` — les valeurs EXACTES que
//           `loadProfileDims` aurait retournées pour D835 avant que le
//           contrôle de rejet silencieux existe (aucun appel à
//           `loadProfileDims` réel ici : celui-ci rejette désormais
//           D835 par construction (voir `profile_dims_contract_reject
//           _test.dart` pour l'équivalent D614/D888) — on reconstruit
//           donc l'objet directement avec les deux nombres cités par
//           l'utilisateur, pour représenter fidèlement ce que l'ancien
//           chemin (fail-open) aurait produit).
//   APRÈS : `StripThickness.corniceDefault(pH)` — repli ratio pixels
//           honnête, exactement ce que `corniceFor(null, pH)` produit
//           aujourd'hui quand `ProfileDimsCache.getIfLoaded('D835')`
//           renvoie `null` (ce qui est le cas réel, vérifiable par
//           `ProfileDimsCache.instance.hasFailed('D835') == true`).
//
// Ce fichier ASSERTE d'abord les invariants numériques (pas seulement
// une capture visuelle) : l'écart 38% cité par l'utilisateur est vérifié
// arithmétiquement avant toute production d'image.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/cornice_plinth_painter.dart';
import 'package:staff_decor_studio/core/perspective/profile_dims.dart';
import 'package:staff_decor_studio/core/perspective/profile_dims_cache.dart';
import 'package:staff_decor_studio/core/perspective/strip_px_from_dims.dart';
import 'package:staff_decor_studio/core/perspective/vanishing_point.dart';

/// Charge une police réelle (Roboto, présente dans le cache pub.dev local)
/// pour que les libellés de la capture s'affichent correctement dans le
/// PNG -- sans ce chargement explicite, `flutter test` (VM headless, pas
/// de polices système) rend tout texte en glyphes de secours illisibles.
/// Même pattern que `test/core/geometry/debug_wireframe_normals_test.dart`
/// (`loadDebugFont`), déjà présent dans ce dépôt -- réutilisé ici plutôt
/// que réinventé. Purement cosmétique : aucun rapport avec la géométrie
/// des bandes (déjà validée arithmétiquement par les tests précédents).
Future<void> _loadCaptureLabelFont() async {
  const candidatePaths = [
    '/home/sandboxuser/.pub-cache/hosted/pub.dev/flame-1.32.0/extension/devtools/build/assets/packages/devtools_app_shared/fonts/Roboto/Roboto-Regular.ttf',
    '/home/user/.pub-cache/hosted/pub.dev/provider-6.1.5+1/extension/devtools/build/assets/packages/devtools_app_shared/fonts/Roboto/Roboto-Regular.ttf',
  ];
  for (final path in candidatePaths) {
    final file = File(path);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      final loader = FontLoader('CaptureLabelFont');
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      return;
    }
  }
  // ignore: avoid_print
  print(
    '⚠️ Aucune police trouvée pour les libellés -- le texte du PNG sera '
    'illisible (glyphes de secours). Purement cosmétique, sans impact sur '
    "les invariants numériques vérifiés par les tests précédents.",
  );
}

/// Valeurs de `assets/profiles/D835.json`, vérifiées par lecture directe
/// du fichier dans cette session : `bbox_mm = {w: 104.962, h: 168.0}`,
/// `profil_mm` recalculé -> `projectionMm (maxdx) = 65.0971`,
/// `retombeeMm (maxdy) = 168.0`.
const double _d835BboxWidthMm = 104.962; // largeur réelle (verite bbox_mm)
const double _d835WrongProjectionMm = 65.097; // ancien calcul, fail-open
const double _d835RetombeeMm = 168.0; // inchange (h coherent, pas en cause)

const double _pH = 900.0; // hauteur perspective mur du fond (px canvas)
const double _metresHauteur = 2.5;

Future<Uint8List> _encodePng(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'D835 est bien rejete par le VRAI ProfileDimsCache aujourd\'hui '
    '(precondition de cette capture : le repli "APRES" n\'est pas '
    'invente, c\'est ce qui se passe reellement pour cette ref)',
    () async {
      ProfileDimsCache.instance.resetForTesting();
      final dims = await loadProfileDims('D835');
      expect(
        dims,
        isNull,
        reason:
            'D835 doit etre rejete par le controle bbox_mm '
            '(SUSPECT_GEOMETRIE, hors index.json) -- si ce test echoue, '
            'la precondition de la capture ci-dessous n\'est plus vraie.',
      );
    },
  );

  test(
    'invariant numerique : la projection FAUSSE (65.097mm) est bien '
    '~38% plus etroite que la largeur reelle bbox_mm (104.962mm) -- '
    'verifie arithmetiquement AVANT toute production d\'image, pour ne '
    'pas s\'appuyer seulement sur une capture visuelle',
    () {
      final ratio = _d835WrongProjectionMm / _d835BboxWidthMm;
      final ecartRelatif = 1.0 - ratio;
      expect(
        ecartRelatif,
        closeTo(0.38, 0.01),
        reason:
            'ratio=$ratio, ecart=$ecartRelatif -- attendu ~38% (0.38), '
            'valeur citee dans le brief de cablage.',
      );
    },
  );

  test(
    'CAPTURE : deux bandes de corniche cote a cote -- AVANT (D835, '
    'ProfileDims(retombeeMm:168.0, projectionMm:65.097) tel que l\'ancien '
    'code fail-open l\'aurait produit) vs APRES (StripThickness '
    '.corniceDefault(pH), repli honnete reellement utilise aujourd\'hui '
    'pour cette ref) -- rendu via paintCorniceSet reel, memes primitives '
    'que RoomPainter.paint()',
    () async {
      await _loadCaptureLabelFont();

      // ── Calcul "AVANT" : reconstruction directe des valeurs que
      //    loadProfileDims aurait renvoyees pour D835 SANS le controle
      //    de rejet silencieux (aucun appel a loadProfileDims reel ici,
      //    qui rejette D835 par construction depuis l'Etape 0 -- voir
      //    le test precedent). ──
      final wrongStripPx = stripPxFromDims(
        pH: _pH,
        metresHauteur: _metresHauteur,
        retombeeMm: _d835RetombeeMm,
        projectionMm: _d835WrongProjectionMm,
      );
      expect(wrongStripPx, isNotNull);
      final wrongTh = StripThickness.fromPx(wrongStripPx!);

      // ── Calcul "APRES" : repli reel, identique a corniceFor(null, pH)
      //    -- le chemin exact pris par room_painter.dart:227 quand
      //    ProfileDimsCache.getIfLoaded('D835') renvoie null (cas reel,
      //    verifie par le test precedent). ──
      final afterTh = corniceFor(null, _pH);
      expect(afterTh.faceHorizFond, StripThickness.corniceDefault(_pH).faceHorizFond);

      // ── Comparaison numerique explicite avant le rendu : la face
      //    "profondeur" (faceHorizFond, celle pilotee par projectionMm)
      //    de la bande AVANT doit etre visiblement plus etroite -- pas
      //    forcement 38% de moins que APRES (les deux chemins de calcul
      //    sont independants, corniceDefault n'est pas cense reproduire
      //    la vraie geometrie), mais le calcul lui-meme, compare a un
      //    calcul fait avec la VRAIE largeur bbox_mm (104.962), doit
      //    montrer l'ecart de 38% (deja verifie ci-dessus a l'echelle
      //    mm ; ici on verifie que la conversion mm->px preserve ce
      //    ratio -- une simple multiplication par un facteur constant
      //    ne peut pas le changer, mais on le verifie explicitement
      //    plutot que de le supposer). ──
      final truthStripPx = stripPxFromDims(
        pH: _pH,
        metresHauteur: _metresHauteur,
        retombeeMm: _d835RetombeeMm,
        projectionMm: _d835BboxWidthMm,
      );
      expect(truthStripPx, isNotNull);
      final pxRatio = wrongTh.faceHorizFond / truthStripPx!.faceHorizFondPx;
      expect(
        1.0 - pxRatio,
        closeTo(0.38, 0.01),
        reason:
            'La conversion mm->px est une simple multiplication par un '
            'facteur constant (pxParMm) : le ratio 65.097/104.962 doit '
            'donc survivre a l\'identique en pixels -- pxRatio=$pxRatio.',
      );

      // ── Rendu cote a cote, deux bandes independantes, geometrie
      //    frontale simple (pas de mur lateral, hasLatG/hasLatD=false
      //    par construction : wallTL==fTL, wallTR==fTR, dist=0<8px) --
      //    suffisant pour comparer visuellement l'epaisseur du segment
      //    de FOND, seul segment concerne par cette demonstration. ──
      const canvasW = 1200.0;
      const canvasH = 620.0;
      const halfW = canvasW / 2;
      const bandTop = 260.0;
      const margin = 60.0;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, canvasW, canvasH),
        Paint()..color = const Color(0xFFFFFFFF),
      );

      // VP loin en dessous du canvas -> perspective quasi nulle sur une
      // bande aussi courte, la face plafond reste un fin ruban degrade
      // au lieu d'un vrai effet de profondeur -- suffisant ici, seul le
      // segment de FOND (faceMurFond/faceHorizFond) porte la
      // demonstration, pas l'onglet lateral (absent par construction).
      final vpLeft = VanishingPoint(
        vp: const Offset(halfW / 2, canvasH + 4000),
        fTL: const Offset(margin, bandTop),
        fTR: const Offset(halfW - margin, bandTop),
        fBL: const Offset(margin, canvasH),
        fBR: const Offset(halfW - margin, canvasH),
      );
      paintCorniceSet(
        canvas,
        vpLeft,
        fTL: const Offset(margin, bandTop),
        fTR: const Offset(halfW - margin, bandTop),
        wallTL: const Offset(margin, bandTop), // == fTL -> hasLatG=false
        wallTR: const Offset(halfW - margin, bandTop), // == fTR -> hasLatD=false
        th: wrongTh,
        ratio: 1.0,
      );

      final vpRight = VanishingPoint(
        vp: const Offset(halfW + halfW / 2, canvasH + 4000),
        fTL: Offset(halfW + margin, bandTop),
        fTR: const Offset(canvasW - margin, bandTop),
        fBL: Offset(halfW + margin, canvasH),
        fBR: Offset(canvasW - margin, canvasH),
      );
      paintCorniceSet(
        canvas,
        vpRight,
        fTL: Offset(halfW + margin, bandTop),
        fTR: const Offset(canvasW - margin, bandTop),
        wallTL: Offset(halfW + margin, bandTop),
        wallTR: const Offset(canvasW - margin, bandTop),
        th: afterTh,
        ratio: 1.0,
      );

      // Separateur + libelles.
      canvas.drawLine(
        const Offset(halfW, 0),
        const Offset(halfW, canvasH),
        Paint()
          ..color = const Color(0xFFCCCCCC)
          ..strokeWidth = 1.5,
      );

      void label(String text, Offset pos, Color color, {double fontSize = 22}) {
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              fontFamily: 'CaptureLabelFont',
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout(maxWidth: halfW - 2 * margin);
        tp.paint(canvas, pos);
      }

      label(
        'AVANT (fail-open pré-Étape 0)\n'
        'D835 : ProfileDims(retombée=168.0mm,\n'
        'projection=65.097mm) — FAUX vs bbox_mm.w=104.962mm\n'
        'bande ~38% trop étroite, plausible à l\'œil',
        const Offset(margin, 20),
        const Color(0xFFB00020),
      );
      label(
        'APRÈS (Étape 0, ce commit)\n'
        'D835 rejeté par le contrôle bbox_mm\n'
        '-> StripThickness.corniceDefault(pH)\n'
        'repli ratio pixels, honnête, non-métrique',
        Offset(halfW + margin, 20),
        const Color(0xFF1B5E20),
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(canvasW.round(), canvasH.round());
      final bytes = await _encodePng(image);

      final outDir = Directory('/tmp/captures');
      outDir.createSync(recursive: true);
      final outPath = '${outDir.path}/d835_wrong_vs_fallback.png';
      File(outPath).writeAsBytesSync(bytes);

      // ignore: avoid_print
      print(
        'Capture ecrite: $outPath (${bytes.length} octets, '
        '${canvasW.round()}x${canvasH.round()})\n'
        '  AVANT faceHorizFond (px) = ${wrongTh.faceHorizFond.toStringAsFixed(2)}\n'
        '  APRES faceHorizFond (px) = ${afterTh.faceHorizFond.toStringAsFixed(2)}',
      );

      expect(File(outPath).existsSync(), isTrue);
    },
  );
}
