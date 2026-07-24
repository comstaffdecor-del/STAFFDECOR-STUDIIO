/// Écran Studio — port fidèle de `#screen-studio` (shell.ts), avec le
/// moteur de rendu CORRIGÉ ([RoomPainter]) remplaçant les 3 systèmes de
/// perspective disjoints de l'ancienne version (Bug #5).
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/perspective/product_texture_cache.dart';
import '../../core/perspective/room_painter.dart';
import '../../core/theme.dart';
import '../../models/persp_calib.dart';
import '../../state/app_state.dart';
import '../../widgets/common/common_ui.dart';
import '../../widgets/common/motif_preview.dart';
import '../../widgets/studio/calib_handles.dart';
import '../../widgets/studio/metres_panel.dart';
import '../../widgets/studio/product_modal.dart';
import '../../widgets/studio/product_strip.dart';
import '../../widgets/studio/save_project_modal.dart';

const _demoScenes = {
  'haussmann': ('🏛️', 'Haussmannien'),
  'moderne': ('◼', 'Contemporain'),
  'provencal': ('🌿', 'Provençal'),
  'scandinave': ('❄', 'Scandinave'),
};

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  final _picker = ImagePicker();

  Future<void> _importPhoto() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final state = context.read<AppState>();
    // ⚠️ CORRECTION Bug #1 (photo importée "hors champs" sur desktop) —
    // on utilisait ici `MediaQuery.of(context).size` (taille de la
    // FENÊTRE NAVIGATEUR entière, ex: 1920×1080 sur desktop), alors que
    // la zone photo réellement rendue à l'écran est contrainte par le
    // cadre "téléphone" desktop (voir AppShell, max 430×932) ET par le
    // ratio 62% de hauteur défini juste en dessous dans ce même fichier
    // (`photoZoneSize = Size(constraints.maxWidth, constraints.maxHeight
    // * 0.62)`). Calculer l'`imgDraw` (letterboxing "contain") à partir
    // d'une taille de conteneur FAUSSE produisait un rectangle
    // d'affichage totalement désaligné du canvas réellement dessiné —
    // sur mobile plein écran les deux tailles coïncidaient à peu près
    // (d'où le bug invisible sur mobile), mais sur desktop l'écart était
    // flagrant. On utilise désormais la VRAIE taille de la zone photo,
    // mémorisée en continu par `registerPhotoZoneSize` depuis le
    // `LayoutBuilder` du Studio (voir plus bas dans ce fichier).
    final size = state.lastPhotoZoneSize ??
        Size(
          MediaQuery.of(context).size.width,
          MediaQuery.of(context).size.height * 0.62,
        );
    await state.setRoomImageBytes(
      bytes,
      containerSize: size,
      demo: false,
    );
  }

  void _useDemoRoom() {
    final state = context.read<AppState>();
    state.setDemoRoomMode();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Stack(
      children: [
        Column(
          children: [
            _StudioTopbar(onImport: _importPhoto, onMetres: state.openMetresPanel),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final photoZoneSize = Size(constraints.maxWidth, constraints.maxHeight * 0.62);
                  // Mémorise la taille de la zone photo pour que le
                  // chargement des scènes démo (loadDemoScene) puisse
                  // calculer un imgDraw correct même si l'utilisateur
                  // choisit une scène avant tout premier build layout.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    state.registerPhotoZoneSize(photoZoneSize);
                    // Si le mode démo a été activé avant que la taille de
                    // la zone photo ne soit connue (ex: depuis l'écran
                    // d'accueil), la vraie photo n'a pas encore pu être
                    // chargée — on la charge maintenant que la taille est
                    // disponible.
                    if (state.isDemoRoom &&
                        state.roomImage == null &&
                        !state.demoSceneLoading) {
                      state.loadDemoScene(
                        state.demoScene,
                        containerSize: photoZoneSize,
                      );
                    }
                  });
                  return Column(
                    children: [
                      SizedBox(
                        width: photoZoneSize.width,
                        height: photoZoneSize.height,
                        child: _PhotoZone(size: photoZoneSize, onImport: _importPhoto, onDemo: _useDemoRoom),
                      ),
                      const Expanded(child: CatBar()),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        if (state.productModalRef != null) const Positioned.fill(child: ProductModal()),
        if (state.showMetresPanel)
          Positioned.fill(child: MetresPanel(onClose: state.closeMetresPanel)),
        if (state.showSaveProjectModal)
          Positioned.fill(child: SaveProjectModal(onClose: state.closeSaveProjectModal)),
      ],
    );
  }
}

class _StudioTopbar extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback onMetres;
  const _StudioTopbar({required this.onImport, required this.onMetres});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Nouveau projet',
                  style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Text('Studio photo', style: TextStyle(color: AppColors.text3, fontSize: 10.5)),
              ],
            ),
          ),
          _ToolBtn(icon: FontAwesomeIcons.camera, tip: 'Importer photo', onTap: onImport),
          _ToolBtn(
            icon: FontAwesomeIcons.crosshairs,
            tip: 'Repères de perspective',
            active: state.showCalibHandles,
            onTap: state.toggleShowCalibHandles,
          ),
          if (state.roomImage != null)
            _ToolBtn(
              icon: FontAwesomeIcons.wandMagicSparkles,
              tip: 'Redétecter les arêtes (plafond/sol/murs)',
              active: state.calibAutoDetected,
              onTap: state.edgeDetecting ? null : state.autoDetectEdges,
            ),
          _ToolBtn(
            icon: FontAwesomeIcons.eye,
            tip: 'Afficher/masquer produits',
            active: state.showProductOverlay,
            onTap: state.toggleProductOverlay,
          ),
          _ToolBtn(icon: FontAwesomeIcons.rulerCombined, tip: 'Métrés', onTap: onMetres),
          // ⚠️ CORRECTION retour utilisateur ("les boutons d'enregistrement...
          // des projets... ne fonctionnent pas") — aucun bouton "Enregistrer"
          // n'existait auparavant dans toute l'application. Ouvre le modal de
          // nommage du projet (voir [SaveProjectModal]), qui l'ajoute à la
          // liste "Mes projets" affichée sur l'écran d'accueil.
          _ToolBtn(
            icon: FontAwesomeIcons.floppyDisk,
            tip: 'Enregistrer le projet',
            onTap: state.openSaveProjectModal,
          ),
          _ToolBtn(
            icon: FontAwesomeIcons.fileInvoiceDollar,
            tip: 'Devis',
            onTap: () => state.goTo('devis'),
          ),
        ],
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;
  final bool active;
  const _ToolBtn({required this.icon, required this.tip, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.gold.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: active ? AppColors.gold : AppColors.text2),
        ),
      ),
    );
  }
}

class _PhotoZone extends StatelessWidget {
  final Size size;
  final VoidCallback onImport;
  final VoidCallback onDemo;
  const _PhotoZone({required this.size, required this.onImport, required this.onDemo});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hasPhoto = state.roomImage != null;
    final showPlaceholder = !hasPhoto && !state.isDemoRoom;

    return Container(
      color: AppColors.bg2,
      child: Stack(
        children: [
          Positioned.fill(
            // ⚠️ AJOUT pinch-to-zoom mobile (retour utilisateur : "On ne
            // peut pas zoomer avec les doigts sur téléphone pour agrandir
            // le visuel") — [InteractiveViewer] permet le pinch-to-zoom
            // et le pan tactile natif sur le rendu de la pièce. Désactivé
            // (panEnabled/scaleEnabled = false) pendant l'édition des
            // repères de calibration pour ne pas capter les gestes de
            // drag destinés aux poignées dorées (voir
            // `CalibHandlesOverlay` plus bas, qui doit rester le seul
            // récepteur de gestes dans ce cas).
            child: InteractiveViewer(
              panEnabled: !state.showCalibHandles,
              scaleEnabled: !state.showCalibHandles,
              minScale: 1.0,
              maxScale: 4.0,
              child: ListenableBuilder(
                listenable: ProductTextureCache.instance,
                builder: (context, _) => CustomPaint(
                  painter: RoomPainter(
                    roomImage: state.roomImage,
                    imgDraw: state.imgDraw,
                    calib: state.perspCalib ?? PerspCalib.defaultCalib,
                    selectedProducts: state.selectedProducts,
                    prodPositions: state.prodPositions,
                    withProducts: state.showProductOverlay,
                  ),
                  size: size,
                ),
              ),
            ),
          ),
          if (showPlaceholder)
            Positioned.fill(
              child: Container(
                color: AppColors.bg2,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(FontAwesomeIcons.image, size: 34, color: AppColors.text3),
                    const SizedBox(height: 14),
                    const Text(
                      'Importez une photo de votre pièce',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Visualisez les produits Staff Décor directement dans votre intérieur réel.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.text3, fontSize: 11.5),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        BtnGold(label: 'Importer', icon: FontAwesomeIcons.camera, small: true, onTap: onImport),
                        const SizedBox(width: 8),
                        BtnOutline(label: 'Pièce démo', icon: FontAwesomeIcons.house, small: true, onTap: onDemo),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (state.demoSceneLoading || state.edgeDetecting)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.gold,
                        ),
                      ),
                      if (state.edgeDetecting && !state.demoSceneLoading) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Analyse de la perspective...',
                          style: TextStyle(color: AppColors.gold, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (state.isDemoRoom)
            Positioned(
              left: 10,
              bottom: 10,
              child: _DemoScenePicker(),
            ),
          // Aperçu zoomé du VRAI relief sculpté (Bug B) — la bande dans la
          // photo de pièce est physiquement trop fine pour révéler le
          // détail du motif (feuillages/perles/oves), même en texture-
          // mapping réel ; cette vignette montre le vrai produit net.
          if (state.showProductOverlay)
            Positioned(
              right: 10,
              top: 10,
              child: MotifPreviewBar(selectedProducts: state.selectedProducts),
            ),
          Positioned(
            left: 10,
            top: 10,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                EstimBadge(calibrated: state.isCalibrated),
                if (state.calibAutoDetected) ...[
                  const SizedBox(width: 6),
                  _AutoCalibBadge(confidence: state.edgeDetectConfidence),
                ],
              ],
            ),
          ),
          if (state.showCalibHandles)
            Positioned(
              left: 10,
              right: 10,
              bottom: state.isDemoRoom ? 74 : 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Faites glisser les repères dorés pour ajuster la perspective — plafond ●● sol ●●',
                  style: TextStyle(color: AppColors.gold, fontSize: 10.5),
                ),
              ),
            ),
          // IMPORTANT : les poignées de calibration DOIVENT être le DERNIER
          // enfant du Stack pour recevoir la priorité de hit-testing — sinon
          // les widgets rendus par-dessus (sélecteur de scène démo, barre
          // d'indication en bas) interceptent le geste de drag avant qu'il
          // n'atteigne les GestureDetector des poignées (bug signalé par
          // l'utilisateur : "le drag and drop ne fonctionne pas").
          if (state.showCalibHandles && (hasPhoto || state.isDemoRoom))
            Positioned.fill(child: CalibHandlesOverlay(canvasSize: size)),
        ],
      ),
    );
  }
}

/// Badge indiquant que la perspective a été calée AUTOMATIQUEMENT sur les
/// vraies arêtes détectées dans la photo (plafond/sol/murs), via l'analyse
/// Sobel + Hough ([AppState.autoDetectEdges]) — informe l'utilisateur que
/// le produit épouse la géométrie réelle de sa pièce, pas une calibration
/// générique arbitraire.
class _AutoCalibBadge extends StatelessWidget {
  final double? confidence;
  const _AutoCalibBadge({this.confidence});

  @override
  Widget build(BuildContext context) {
    final pct = confidence != null ? '${(confidence! * 100).round()}%' : '';
    return Tooltip(
      message:
          'Perspective (plafond, sol, murs) détectée automatiquement à '
          'partir de la photo — le produit suit les vraies arêtes de '
          'la pièce. Vous pouvez ajuster finement avec les repères dorés.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FontAwesomeIcons.wandMagicSparkles, size: 9, color: AppColors.green),
            const SizedBox(width: 4),
            Text(
              'Arêtes auto $pct',
              style: const TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoScenePicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _demoScenes.entries.map((e) {
          final active = state.demoScene == e.key;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              onTap: () => state.setDemoScene(e.key),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? AppColors.gold.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: active ? AppColors.gold : Colors.transparent),
                ),
                child: Column(
                  children: [
                    Text(e.value.$1, style: const TextStyle(fontSize: 14)),
                    Text(
                      e.value.$2,
                      style: TextStyle(
                        color: active ? AppColors.gold : Colors.white70,
                        fontSize: 8.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
