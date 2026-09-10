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

const _demoScenesForAi = {
  'haussmann': 'Haussmannien',
  'moderne': 'Contemporain',
  'provencal': 'Provençal',
  'scandinave': 'Scandinave',
};

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
        _screenState = _AiScreenState.ready;
      });
    } catch (_) {
      _showNoSceneMessage();
    }
  }

  Future<void> _useDemoScene(String key, String label) async {
    try {
      final data = await DefaultAssetBundle.of(context).load('assets/demo_scenes/$key.jpg');
      setState(() {
        _sceneBytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        _sceneLabel = 'Scène démo — $label';
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

    final result = await generateAiAmbiancePreview(
      sceneImageBytes: scene,
      ref: ref,
      nom: prod?.nom ?? ref,
      famille: prod?.famille ?? '',
    );

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
                    'Aperçu d\'ambiance IA',
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
              'Illustration d\'ambiance générée par IA, uniquement pour '
              'visualiser un produit validé dans un décor — jamais un '
              'rendu technique.',
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
        TextButton(
          onPressed: () => setState(() => _screenState = _AiScreenState.pickProduct),
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
                Text('Générer un aperçu IA', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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
                    'Voir un aperçu démo (local, sans IA)',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Effet de superposition local, sans appel réseau ni intelligence '
            'artificielle — uniquement pour illustrer la démo.',
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

  Widget _buildGenerating() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Column(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.gold),
            ),
            SizedBox(height: 12),
            Text('Génération de l\'aperçu IA…', style: TextStyle(color: AppColors.gold, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final bytes = _resultBytes;
    final isMock = _resultIsMock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                  'DÉMO LOCALE — PAS D\'IA',
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
