/// Mock local "aperçu d'ambiance" — P17-VISUEL, effet de démo SANS
/// dépendance externe.
///
/// Contexte : `kAiPreviewEnabled == false` dans ce sandbox (aucune clé
/// Gemini disponible, voir [ia_ambiance_preview.dart]). L'utilisateur a
/// explicitement demandé ("oui") un effet de substitution pour la démo,
/// à condition qu'il :
///   - n'effectue AUCUN appel réseau (compositing 100% local via
///     dart:ui, aucun package HTTP importé ici) ;
///   - ne prétende JAMAIS être une génération IA réelle (watermark
///     "DÉMO — PAS D'IA" gravé directement dans les pixels générés,
///     visible même hors du contexte de l'UI, + libellé dédié
///     [kAiMockDisclaimer] distinct de [kAiPreviewDisclaimer]) ;
///   - ne fabrique aucune géométrie produit : l'unique "overlay produit"
///     utilisé est l'image de contrôle déjà existante et validée
///     (`assets/profiles/control/<ref>.png`), simplement replaquée en
///     surimpression semi-transparente sur la scène — jamais une forme
///     inventée ;
///   - reste strictement en mémoire (retourne un [Uint8List], jamais
///     écrit sur disque, jamais dans assets/).
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

const String kAiMockDisclaimer =
    'Aperçu illustratif LOCAL (démo, sans intelligence artificielle) — '
    'simple superposition d\'image, ne représente ni un rendu IA ni un '
    'rendu technique du produit.';

/// Compose localement une image "scène + surimpression produit +
/// filtre de teinte + filigrane DÉMO", sans aucun appel réseau.
///
/// [sceneImageBytes] : photo de scène (démo, upload, ou capture Studio).
/// [productOverlayBytes] : image de contrôle du produit (optionnelle —
/// si absente ou illisible, seule la scène teintée + filigrane est
/// produite, jamais de géométrie de substitution inventée).
///
/// Retourne les octets PNG en mémoire, ou `null` si le décodage de la
/// scène échoue (aucune exception ne doit s'échapper de cette fonction).
Future<Uint8List?> generateLocalMockPreview({
  required Uint8List sceneImageBytes,
  Uint8List? productOverlayBytes,
}) async {
  try {
    final sceneCodec = await ui.instantiateImageCodec(sceneImageBytes);
    final sceneFrame = await sceneCodec.getNextFrame();
    final sceneImg = sceneFrame.image;

    // Limite raisonnable de taille de sortie (perf + cohérence avec les
    // vignettes déjà utilisées dans le Studio) : on ne dépasse pas
    // 900px sur le plus grand côté.
    const maxSide = 900.0;
    final scale = sceneImg.width > sceneImg.height
        ? maxSide / sceneImg.width
        : maxSide / sceneImg.height;
    final outW = (sceneImg.width * scale).round().clamp(64, 4096);
    final outH = (sceneImg.height * scale).round().clamp(64, 4096);

    ui.Image? overlayImg;
    if (productOverlayBytes != null && productOverlayBytes.isNotEmpty) {
      try {
        final overlayCodec = await ui.instantiateImageCodec(productOverlayBytes);
        overlayImg = (await overlayCodec.getNextFrame()).image;
      } catch (_) {
        overlayImg = null; // pas d'overlay produit -> pas de forme inventée
      }
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    );

    // 1) Scène, avec une teinte chaude/plâtre douce simulant un "rendu
    //    d'ambiance" -- une simple ColorFilter, jamais une IA.
    final scenePaint = ui.Paint()
      ..filterQuality = ui.FilterQuality.medium
      ..colorFilter = const ui.ColorFilter.matrix(<double>[
        1.08, 0.00, 0.00, 0, 6,
        0.00, 1.03, 0.00, 0, 4,
        0.00, 0.00, 0.92, 0, 2,
        0.00, 0.00, 0.00, 1, 0,
      ]);
    canvas.drawImageRect(
      sceneImg,
      ui.Rect.fromLTWH(0, 0, sceneImg.width.toDouble(), sceneImg.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      scenePaint,
    );

    // 2) Surimpression produit (image de contrôle existante), centrée,
    //    semi-transparente -- illustratif uniquement, jamais un rendu
    //    technique ni une pose réelle du moulage.
    if (overlayImg != null) {
      final ovMaxW = outW * 0.42;
      final ovScale = ovMaxW / overlayImg.width;
      final ovW = overlayImg.width * ovScale;
      final ovH = overlayImg.height * ovScale;
      final ovLeft = (outW - ovW) / 2;
      final ovTop = outH * 0.08;
      final overlayPaint = ui.Paint()
        ..filterQuality = ui.FilterQuality.medium
        ..color = const ui.Color.fromRGBO(255, 255, 255, 0.55);
      canvas.saveLayer(
        ui.Rect.fromLTWH(ovLeft, ovTop, ovW, ovH),
        overlayPaint,
      );
      canvas.drawImageRect(
        overlayImg,
        ui.Rect.fromLTWH(0, 0, overlayImg.width.toDouble(), overlayImg.height.toDouble()),
        ui.Rect.fromLTWH(ovLeft, ovTop, ovW, ovH),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      canvas.restore();
    }

    // 3) Filigrane "DÉMO — PAS D'IA" gravé dans les pixels -- garantie
    //    visuelle même si l'image est extraite hors du contexte de
    //    l'app (capture d'écran, partage, etc.).
    _drawWatermark(canvas, outW.toDouble(), outH.toDouble());

    final picture = recorder.endRecording();
    final outImage = await picture.toImage(outW, outH);
    final byteData = await outImage.toByteData(format: ui.ImageByteFormat.png);
    outImage.dispose();
    sceneImg.dispose();
    overlayImg?.dispose();
    if (byteData == null) return null;
    return byteData.buffer.asUint8List();
  } catch (_) {
    // Aucune exception ne doit remonter -- comportement identique au
    // reste de la passe P17 (jamais de crash, fallback uniquement).
    return null;
  }
}

void _drawWatermark(ui.Canvas canvas, double w, double h) {
  const text = 'DÉMO — PAS D\'IA — ILLUSTRATIF';
  final style = ui.TextStyle(
    color: const ui.Color.fromRGBO(255, 255, 255, 0.55),
    fontSize: (w * 0.045).clamp(16.0, 34.0),
    fontWeight: ui.FontWeight.w800,
    letterSpacing: 1.2,
  );
  final paragraphStyle = ui.ParagraphStyle(textAlign: ui.TextAlign.center);
  final builder = ui.ParagraphBuilder(paragraphStyle)
    ..pushStyle(style)
    ..addText(text);
  final paragraph = builder.build()..layout(ui.ParagraphConstraints(width: w * 1.4));

  canvas.save();
  // Deux bandes diagonales pour rendre le filigrane difficile à ignorer
  // ou à recadrer hors de l'image, sans pour autant gêner la lecture.
  for (final dy in [h * 0.32, h * 0.72]) {
    canvas.save();
    canvas.translate(w / 2, dy);
    canvas.rotate(-0.34);
    canvas.translate(-paragraph.width / 2, -paragraph.height / 2);
    canvas.drawParagraph(paragraph, ui.Offset.zero);
    canvas.restore();
  }
  canvas.restore();
}
