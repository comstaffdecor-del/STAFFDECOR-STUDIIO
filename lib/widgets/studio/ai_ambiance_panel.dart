/// Panneau "Aperçu d'ambiance IA" — P17-VISUEL.
///
/// Parcours UI du brief (point 5) : choix d'un produit parmi les 43
/// refs visibles -> choix d'une scène (scène courante, image uploadée
/// ou scène démo) -> bouton "Générer un aperçu IA" -> "Génération de
/// l'aperçu IA…" -> image affichée en mémoire avec la mention
/// permanente non masquable, OU fallback si indisponible.
///
/// Si [kAiPreviewEnabled] est faux (cas par défaut de cette passe,
/// aucune clé Gemini disponible dans le sandbox) : le bouton "Générer
/// un aperçu IA" reste visible mais GRISÉ, avec le message "fonction
/// bientôt disponible" — jamais un bouton disparu sans explication,
/// jamais une génération simulée.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/ai_ambiance_mock.dart';
import '../../data/catalogue_data.dart';
import '../../data/catalogue_visibility.dart';
import '../../data/ia_ambiance_preview.dart';
import '../../state/app_state.dart';
import '../common/common_ui.dart';
import 'common_modal.dart';

enum _AiScreenState { pickProduct, pickScene, ready, generating, result, fallback }

/// Point d'injection UNIQUEMENT pour les tests (voir
/// `test/widget/ai_ambiance_panel_render_mode_test.dart`) — permet
/// d'observer/remplacer l'appel réseau réel de [generateAiAmbiancePreview]
/// (ex: vérifier le `renderMode` réellement envoyé selon la scène choisie
/// dans l'UI, sans jamais toucher le vrai réseau/proxy/Gemini). `null`
/// par défaut : le comportement de PRODUCTION appelle toujours la vraie
/// fonction réseau — ce hook ne change RIEN pour un utilisateur réel.
@visibleForTesting
Future<AiPreviewResult> Function({
  required Uint8List sceneImageBytes,
  required String ref,
  required String nom,
  required String famille,
  required String renderMode,
})? debugGenerateAiAmbiancePreviewOverride;

/// P21-HYBRIDE (correction revue, brief "sécurisation test hybride") —
/// fonction PURE extraite pour rendre la règle de résolution du
/// `renderMode` testable unitairement, sans passer par un test widget
/// lourd (pompes `pumpAndSettle` autour d'un appel réseau simulé,
/// instable et lent). Règle inchangée : 'refine' uniquement quand la
/// scène provient de [_useComposedScene] (rendu dynamique déjà
/// composé) ; 'add' dans tous les autres cas (comportement historique
/// : photo brute, scène démo, import direct).
@visibleForTesting
String resolveRenderModeForScene({required bool isHybridScene}) {
  return isHybridScene ? 'refine' : 'add';
}

const _demoScenesForAi = {
  'haussmann': 'Haussmannien',
  'moderne': 'Contemporain',
  'provencal': 'Provençal',
  'scandinave': 'Scandinave',
};

/// Contenu du loader affiché pendant [_AiAmbiancePanelState._buildGenerating]
/// — extrait tel quel (inchangé visuellement) pour être réutilisable
/// au-dessus soit d'un fond flouté (scène disponible), soit d'un fond
/// neutre (aucune scène connue, cas résiduel).
class _GeneratingLoader extends StatelessWidget {
  const _GeneratingLoader();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.gold),
          ),
          SizedBox(height: 12),
          Text('Préparation de l\'aperçu…', style: TextStyle(color: AppColors.gold, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class AiAmbiancePanel extends StatefulWidget {
  final VoidCallback onClose;
  const AiAmbiancePanel({super.key, required this.onClose});

  @override
  State<AiAmbiancePanel> createState() => _AiAmbiancePanelState();
}

class _AiAmbiancePanelState extends State<AiAmbiancePanel> {
  final _picker = ImagePicker();
  _AiScreenState _screenState = _AiScreenState.pickProduct;

  String? _selectedRef;
  Uint8List? _sceneBytes;
  String? _sceneLabel;
  // P21-HYBRIDE — vrai uniquement quand [_sceneBytes] provient de
  // [_useComposedScene] (capture RepaintBoundary du rendu déjà composé
  // par le moteur dynamique, corniche déjà placée géométriquement) —
  // pilote le `renderMode` envoyé au proxy dans [_generate] : 'refine'
  // au lieu de 'add'. Remis à false par toute autre sélection de scène
  // (_useCurrentScene / _uploadScene / _useDemoScene / _reset).
  bool _isHybridScene = false;
  Uint8List? _resultBytes;
  // true si _resultBytes provient du mock local (dart:ui, sans réseau),
  // false si une vraie génération via le proxy manobanana a produit le
  // résultat. Distinction OBLIGATOIRE pour ne jamais faire passer un mock
  // pour une vraie IA (demande explicite utilisateur, réponse "oui").
  bool _resultIsMock = false;
  // Message d'erreur COURT à afficher dans l'écran fallback (brief P19 :
  // pas de photo, pas de produit, proxy injoignable, échec génération) --
  // jamais un message technique brut.
  String _lastErrorMessage = kAiPreviewErrorGenerationFailed;

  @override
  void initState() {
    super.initState();
    if (kPresentationFilter) {
      CatalogueVisibilityGate.instance.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      });
    }
    // Court-circuit "Générer aperçu IA" (bouton contextuel Studio) — le
    // produit ET la scène sont déjà connus au moment où ce panneau est
    // ouvert depuis la zone photo (photo importée + SKU sélectionné) :
    // on saute directement les écrans "choix produit"/"choix scène" et,
    // si demandé, on lance la génération réelle (proxy Gemini) sans
    // action supplémentaire de l'utilisateur. N'affecte JAMAIS l'entrée
    // générique depuis l'icône topbar (prefillRef == null dans ce cas).
    final state = context.read<AppState>();
    final prefillRef = state.aiAmbiancePrefillRef;
    final autoGenerate = state.aiAmbianceAutoGenerate;
    // P22-HYBRIDE-AUTO (brief "nouvelle règle produit") — ce panneau
    // peut être ouvert AUTOMATIQUEMENT par
    // [AppState.maybeAutoTriggerHybridAiPreview] (via
    // `state.openAiAmbiancePanel(..., autoGenerateHybrid: true)`,
    // affiché par `studio_screen.dart` exactement comme une ouverture
    // manuelle) : dans ce cas précis, la scène à utiliser n'est PAS la
    // photo brute courante ([_useCurrentScene]) mais la scène DÉJÀ
    // COMPOSÉE par le moteur dynamique, pré-capturée par AppState au
    // moment du déclenchement ([consumePendingHybridAutoScene]) —
    // jamais recapturée ici, pour utiliser exactement le même
    // instantané que celui qui a servi à décider la clé anti-boucle.
    final autoGenerateHybrid = state.aiAmbianceAutoGenerateHybrid;
    if (prefillRef != null) {
      _selectedRef = prefillRef;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (autoGenerateHybrid) {
          final composedBytes = state.consumePendingHybridAutoScene();
          if (composedBytes == null) {
            // Capture indisponible entre-temps (Studio démonté, etc.) —
            // jamais de génération sur une scène absente/périmée.
            return;
          }
          setState(() {
            _sceneBytes = composedBytes;
            _sceneLabel = 'Scène avec produit déjà posé (rendu dynamique)';
            _isHybridScene = true;
            _screenState = _AiScreenState.ready;
          });
          if (!mounted) return;
          await _generate();
          return;
        }
        await _useCurrentScene();
        if (!mounted) return;
        if (autoGenerate && _sceneBytes != null) {
          await _generate();
        }
      });
    }
  }

  List<String> get _visibleRefs {
    final table = CatalogueVisibilityGate.instance.visibleRefsIfLoaded;
    if (table == null) return const [];
    // Ordre stable, dérivé uniquement de index.json — jamais un SKU
    // hors index (brief point 4).
    return table.values.toList()..sort();
  }

  void _selectProduct(String ref) {
    setState(() {
      _selectedRef = ref;
      _screenState = _AiScreenState.pickScene;
    });
  }

  Future<void> _useCurrentScene() async {
    final state = context.read<AppState>();
    final image = state.roomImage;
    if (image == null) {
      _showNoSceneMessage();
      return;
    }
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('encodage échoué');
      setState(() {
        _sceneBytes = byteData.buffer.asUint8List();
        _sceneLabel = 'Scène actuelle du Studio';
        _isHybridScene = false;
        _screenState = _AiScreenState.ready;
      });
    } catch (_) {
      _showNoSceneMessage();
    }
  }

  /// P21-HYBRIDE — capture la scène TELLE QU'AFFICHÉE dans le Studio,
  /// c'est-à-dire déjà composée par le moteur dynamique déterministe
  /// (RoomPainter/cornice_plinth_painter) : la corniche sélectionnée y
  /// est déjà placée géométriquement (bonne ligne plafond/mur, bonne
  /// perspective, bon positionnement), contrairement à [_useCurrentScene]
  /// qui ré-encode la photo BRUTE (sans produit). Utilise
  /// [AppState.captureComposedScene] (RepaintBoundary posé dans
  /// `studio_screen.dart`, jamais une réimplémentation du rendu ici).
  /// En cas d'échec de capture (Studio jamais construit, etc.), retombe
  /// explicitement sur le message d'absence de scène — jamais un
  /// silence qui laisserait l'utilisateur bloqué sur l'écran précédent.
  Future<void> _useComposedScene() async {
    final state = context.read<AppState>();
    if (state.roomImage == null || state.selectedProducts.isEmpty) {
      _showNoSceneMessage();
      return;
    }
    final bytes = await state.captureComposedScene();
    if (!mounted) return;
    if (bytes == null) {
      _showNoSceneMessage();
      return;
    }
    setState(() {
      _sceneBytes = bytes;
      _sceneLabel = 'Scène avec produit déjà posé (rendu dynamique)';
      _isHybridScene = true;
      _screenState = _AiScreenState.ready;
    });
  }

  Future<void> _useDemoScene(String key, String label) async {
    try {
      final data = await DefaultAssetBundle.of(context).load('assets/demo_scenes/$key.jpg');
      setState(() {
        _sceneBytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        _sceneLabel = 'Scène démo — $label';
        _isHybridScene = false;
        _screenState = _AiScreenState.ready;
      });
    } catch (_) {
      _showNoSceneMessage();
    }
  }

  Future<void> _uploadScene() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _sceneBytes = bytes;
        _sceneLabel = 'Photo importée';
        _isHybridScene = false;
        _screenState = _AiScreenState.ready;
      });
    } catch (_) {
      _showNoSceneMessage();
    }
  }

  void _showNoSceneMessage() {
    if (!mounted) return;
    setState(() {
      _screenState = _AiScreenState.pickScene;
    });
    showAppToast(context, 'Image de scène illisible ou indisponible.');
  }

  Future<void> _generate() async {
    final ref = _selectedRef;
    final scene = _sceneBytes;
    if (ref == null) {
      _lastErrorMessage = kAiPreviewErrorNoProduct;
      setState(() => _screenState = _AiScreenState.fallback);
      return;
    }
    if (scene == null) {
      _lastErrorMessage = kAiPreviewErrorNoPhoto;
      setState(() => _screenState = _AiScreenState.fallback);
      return;
    }
    final prod = getProdByRef(ref);

    setState(() => _screenState = _AiScreenState.generating);
    // P20-AUTO : marque une génération en cours au niveau AppState —
    // c'est CETTE garde (et non un état local au panneau, détruit à la
    // fermeture) que consulte maybeAutoTriggerAiPreview pour ne jamais
    // superposer deux générations pour la même scène/produit.
    final appState = context.read<AppState>();
    appState.setAiAmbianceGenerating(true);

    // P21-HYBRIDE — voir docstring de [resolveRenderModeForScene]
    // (fonction pure, testée unitairement dans
    // test/widget/ai_ambiance_panel_render_mode_test.dart).
    final renderMode = resolveRenderModeForScene(isHybridScene: _isHybridScene);

    final AiPreviewResult result;
    try {
      // debugGenerateAiAmbiancePreviewOverride reste null en production
      // (voir docstring) — seul un test peut le renseigner.
      final override = debugGenerateAiAmbiancePreviewOverride;
      result = override != null
          ? await override(
              sceneImageBytes: scene,
              ref: ref,
              nom: prod?.nom ?? ref,
              famille: prod?.famille ?? '',
              renderMode: renderMode,
            )
          : await generateAiAmbiancePreview(
              sceneImageBytes: scene,
              ref: ref,
              nom: prod?.nom ?? ref,
              famille: prod?.famille ?? '',
              renderMode: renderMode,
            );
    } finally {
      appState.setAiAmbianceGenerating(false);
    }

    if (!mounted) return;
    setState(() {
      if (result.success && result.imageBytes != null) {
        _resultBytes = result.imageBytes;
        _resultIsMock = false;
        _screenState = _AiScreenState.result;
      } else {
        _lastErrorMessage = result.errorMessage ?? kAiPreviewErrorGenerationFailed;
        _screenState = _AiScreenState.fallback;
      }
    });

    // Stocke le résultat réussi dans AppState (jamais pour le mock local,
    // voir _generateLocalMock) pour que l'écran Avant/Après (Comparateur)
    // puisse afficher photo originale vs image IA sans relancer Gemini.
    // `scene` est la MÊME photo/scène qui vient d'être envoyée au proxy
    // ci-dessus — c'est bien le "AVANT" correspondant à ce "APRÈS".
    if (result.success && result.imageBytes != null) {
      appState.setLastAiComparisonResult(
        AiComparisonResult(
          originalImageBytes: scene,
          aiImageBytes: result.imageBytes!,
          sku: ref,
          model: result.model,
          usedProductReference: result.usedProductReference,
          productReferencePath: result.productReferencePath,
          renderMode: result.renderMode,
        ),
      );
    }
  }

  /// Effet local de démo (dart:ui, AUCUN appel réseau) — proposé quand la
  /// génération réelle est indisponible (`kAiPreviewEnabled==false` ou clé
  /// absente), sur demande explicite de l'utilisateur ("oui"). Ne doit
  /// jamais être confondu avec une vraie génération IA : bytes marqués
  /// via [_resultIsMock], filigrane gravé dans les pixels eux-mêmes.
  Future<void> _generateLocalMock() async {
    final ref = _selectedRef;
    final scene = _sceneBytes;
    if (ref == null || scene == null) return;

    setState(() => _screenState = _AiScreenState.generating);

    Uint8List? overlayBytes;
    try {
      final data = await DefaultAssetBundle.of(context).load('assets/profiles/control/$ref.png');
      overlayBytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      overlayBytes = null; // pas de forme de substitution inventée
    }

    final mockBytes = await generateLocalMockPreview(
      sceneImageBytes: scene,
      productOverlayBytes: overlayBytes,
    );

    if (!mounted) return;
    setState(() {
      if (mockBytes != null) {
        _resultBytes = mockBytes;
        _resultIsMock = true;
        _screenState = _AiScreenState.result;
      } else {
        _screenState = _AiScreenState.fallback;
      }
    });
  }

  void _reset() {
    setState(() {
      _selectedRef = null;
      _sceneBytes = null;
      _sceneLabel = null;
      _isHybridScene = false;
      _resultBytes = null;
      _resultIsMock = false;
      _screenState = _AiScreenState.pickProduct;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ModalSheet(
      onClose: widget.onClose,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Aperçu d\'ambiance',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(FontAwesomeIcons.xmark, size: 16, color: AppColors.text3),
                  onPressed: widget.onClose,
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Aperçu d\'ambiance non contractuel.',
              style: TextStyle(color: AppColors.text3, fontSize: 11.5),
            ),
            const SizedBox(height: 16),
            _buildBody(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_screenState) {
      case _AiScreenState.pickProduct:
        return _buildPickProduct();
      case _AiScreenState.pickScene:
        return _buildPickScene();
      case _AiScreenState.ready:
        return _buildReady();
      case _AiScreenState.generating:
        return _buildGenerating();
      case _AiScreenState.result:
        return _buildResult();
      case _AiScreenState.fallback:
        return _buildFallback();
    }
  }

  Widget _buildPickProduct() {
    final refs = _visibleRefs;
    if (refs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'Catalogue validé en cours de chargement…',
          style: TextStyle(color: AppColors.text3, fontSize: 12),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choisissez un produit parmi les modèles validés',
          style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 260,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemCount: refs.length,
            itemBuilder: (context, i) {
              final ref = refs[i];
              final prod = getProdByRef(ref);
              return InkWell(
                onTap: () => _selectProduct(ref),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.card2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          'assets/profiles/control/$ref.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            FontAwesomeIcons.image,
                            size: 18,
                            color: AppColors.text3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ref,
                        style: const TextStyle(color: AppColors.text, fontSize: 10.5, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (prod != null)
                        Text(
                          prod.famille,
                          style: const TextStyle(color: AppColors.text3, fontSize: 8.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPickScene() {
    final prod = getProdByRef(_selectedRef ?? '');
    final state = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _selectedProductChip(prod?.nom ?? _selectedRef ?? ''),
        const SizedBox(height: 12),
        const Text(
          'Choisissez une scène',
          style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: BtnOutline(
                label: 'Scène actuelle',
                icon: FontAwesomeIcons.houseChimney,
                onTap: state.roomImage != null ? _useCurrentScene : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BtnOutline(
                label: 'Importer une photo',
                icon: FontAwesomeIcons.image,
                onTap: _uploadScene,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // P21-HYBRIDE — nouvelle option : au lieu d'envoyer la photo
        // BRUTE (l'IA doit alors deviner seule position/échelle/ligne de
        // la corniche, source d'incohérences visuelles), on envoie la
        // scène DÉJÀ COMPOSÉE par le moteur dynamique (corniche déjà
        // placée géométriquement). L'IA n'a plus qu'à en améliorer le
        // réalisme (voir renderMode='refine' dans [_generate]).
        // Grisée si aucune photo/produit n'est encore chargé dans le
        // Studio — jamais un bouton mort sans explication.
        SizedBox(
          width: double.infinity,
          child: BtnOutline(
            label: 'Scène avec produit déjà posé (rendu dynamique)',
            icon: FontAwesomeIcons.layerGroup,
            onTap: (state.roomImage != null && state.selectedProducts.isNotEmpty)
                ? _useComposedScene
                : null,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Recommandé : le moteur dynamique place la corniche, l\'aperçu '
          'améliore uniquement le réalisme (matière, ombres, lumière) — '
          'sans en changer la position.',
          style: TextStyle(color: AppColors.text3, fontSize: 10.5),
        ),
        const SizedBox(height: 10),
        const Text('ou une scène démo :', style: TextStyle(color: AppColors.text3, fontSize: 11)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _demoScenesForAi.entries
              .map((e) => BtnOutline(
                    label: e.value,
                    small: true,
                    onTap: () => _useDemoScene(e.key, e.value),
                  ))
              .toList(),
        ),
        const SizedBox(height: 10),
        // BUG-3-FIX (STOP-CLIENT-RELEASE) : auparavant ce bouton ne
        // changeait QUE `_screenState`, laissant `_resultBytes` /
        // `_lastErrorMessage` / `_isHybridScene` d'un essai précédent
        // potentiellement affichés/actifs derrière un nouvel essai — appel
        // à [_reset] (identique à "Nouvel aperçu"/"Réessayer") pour
        // repartir d'un état intégralement propre à chaque changement de
        // produit, condition nécessaire au support multi-appels successifs
        // dans la même session (D609 → D607 → D610...).
        TextButton(
          onPressed: _reset,
          child: const Text('Changer de produit', style: TextStyle(color: AppColors.text3, fontSize: 11.5)),
        ),
      ],
    );
  }

  Widget _selectedProductChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FontAwesomeIcons.check, size: 10, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppColors.gold, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildReady() {
    final prod = getProdByRef(_selectedRef ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _selectedProductChip(prod?.nom ?? _selectedRef ?? ''),
        const SizedBox(height: 8),
        Text('Scène : ${_sceneLabel ?? ''}', style: const TextStyle(color: AppColors.text2, fontSize: 11.5)),
        const SizedBox(height: 16),
        if (!kAiPreviewEnabled) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(FontAwesomeIcons.circleInfo, size: 14, color: AppColors.text3),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Fonction bientôt disponible.',
                    style: TextStyle(color: AppColors.text3, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: kAiPreviewEnabled ? _generate : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.bg,
              disabledBackgroundColor: AppColors.card2,
              disabledForegroundColor: AppColors.text3,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FontAwesomeIcons.wandMagicSparkles, size: 14),
                SizedBox(width: 8),
                Text('Créer l\'aperçu', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        if (!kAiPreviewEnabled) ...[
          const SizedBox(height: 10),
          const Row(
            children: [
              Expanded(child: Divider(color: AppColors.border)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('ou', style: TextStyle(color: AppColors.text3, fontSize: 11)),
              ),
              Expanded(child: Divider(color: AppColors.border)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _generateLocalMock,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text2,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FontAwesomeIcons.images, size: 13),
                  SizedBox(width: 8),
                  Text(
                    'Voir un aperçu démo local',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Effet de superposition local, sans appel réseau — uniquement '
            'pour illustrer la démo.',
            style: TextStyle(color: AppColors.text3, fontSize: 10.5),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _screenState = _AiScreenState.pickScene),
          child: const Text('Changer de scène', style: TextStyle(color: AppColors.text3, fontSize: 11.5)),
        ),
      ],
    );
  }

  /// BUG-1-FIX (STOP-CLIENT-RELEASE) : auparavant cet écran affichait
  /// uniquement un spinner nu, sans aucun aperçu de la scène source —
  /// écart structurel par rapport à la règle "scène source FLOUTÉE +
  /// loader" pendant l'attente du retour distant (jamais une tentative de
  /// pose locale visible). La scène affichée ici est [_sceneBytes], LA
  /// MÊME image déjà envoyée au proxy dans [_generate] (photo brute ou
  /// scène démo selon le choix fait en amont) — jamais recomposée avec le
  /// produit, jamais le rendu RoomPainter (déjà masqué séparément côté
  /// Studio via `withProducts`, voir `studio_screen.dart`).
  Widget _buildGenerating() {
    final scene = _sceneBytes;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          if (scene != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Image.memory(scene, fit: BoxFit.cover, width: double.infinity, height: 220),
                  ),
                  Container(
                    width: double.infinity,
                    height: 220,
                    color: AppColors.bg.withValues(alpha: 0.35),
                  ),
                  const _GeneratingLoader(),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: _GeneratingLoader(),
            ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final bytes = _resultBytes;
    final isMock = _resultIsMock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Badge "Aperçu prêt" affiché uniquement pour un résultat réel
        // (jamais pour le mock local, qui a son propre badge "DÉMO
        // LOCALE" ci-dessous).
        if (!isMock)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  'Aperçu prêt',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        if (isMock)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.text3.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FontAwesomeIcons.images, size: 10, color: AppColors.text2),
                SizedBox(width: 6),
                Text(
                  'DÉMO LOCALE',
                  style: TextStyle(color: AppColors.text2, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4),
                ),
              ],
            ),
          ),
        if (bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
        const SizedBox(height: 10),
        // Mention permanente, visible et non masquable — brief point 5
        // (résultat IA réel) ou variante mock explicite (demande "oui").
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
          ),
          child: Text(
            isMock ? kAiMockDisclaimer : kAiPreviewDisclaimer,
            style: const TextStyle(color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _reset,
          child: const Text('Nouvel aperçu', style: TextStyle(color: AppColors.text3, fontSize: 11.5)),
        ),
      ],
    );
  }

  Widget _buildFallback() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(FontAwesomeIcons.circleExclamation, size: 16, color: AppColors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _lastErrorMessage,
                  style: const TextStyle(color: AppColors.amber, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _reset,
          child: const Text('Réessayer', style: TextStyle(color: AppColors.text3, fontSize: 11.5)),
        ),
      ],
    );
  }
}
