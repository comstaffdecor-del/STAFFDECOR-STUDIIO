/// Panneau "Reconnaissance automatique" — P15-IA-DEMO, Volet B.
///
/// Parcours UI du brief : upload image OU "utiliser la scène actuelle" ->
/// "Analyse en cours…" -> résultat (top-3 exploitable OU message
/// d'incertitude), avec dans tous les cas les deux issues de secours
/// toujours visibles ("Voir les 43 modèles validés" / "Choisir
/// manuellement"). Le bouton "Choisir ce modèle" appelle EXACTEMENT
/// [AppState.quickToggleProd] (même mécanisme que `product_strip.dart`),
/// jamais une sélection parallèle.
///
/// Aucune donnée simulée : le score affiché vient de
/// [IaSuggestionGate.rank] (similarité cosinus réellement calculée sur un
/// descripteur déterministe, voir `lib/data/ia_suggestion.dart`), jamais
/// d'un tirage aléatoire ni d'une valeur en dur.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/catalogue_data.dart';
import '../../data/ia_suggestion.dart';
import '../../state/app_state.dart';
import '../common/common_ui.dart';
import 'common_modal.dart';

enum _IaPanelState { idle, analyzing, exploitable, uncertain }

class IaSuggestionPanel extends StatefulWidget {
  final VoidCallback onClose;
  const IaSuggestionPanel({super.key, required this.onClose});

  @override
  State<IaSuggestionPanel> createState() => _IaSuggestionPanelState();
}

class _IaSuggestionPanelState extends State<IaSuggestionPanel> {
  final _picker = ImagePicker();
  _IaPanelState _panelState = _IaPanelState.idle;
  List<IaSuggestionMatch> _matches = const [];
  String? _errorMessage;

  Future<void> _runAnalysis(Uint8List bytes) async {
    setState(() {
      _panelState = _IaPanelState.analyzing;
      _errorMessage = null;
    });

    // Charge (si besoin) la base de référence — mémoïsé, ne relit
    // jamais index.json indépendamment (voir IaSuggestionGate).
    await IaSuggestionGate.instance.ensureLoaded();

    // Délai d'affichage volontaire (brief : "Analyse en cours… 1-2 s") —
    // n'affecte pas le calcul, qui a déjà déterminé le résultat ci-dessus/
    // ci-dessous ; sert uniquement à rendre l'état de chargement visible.
    final started = DateTime.now();
    final result = await IaSuggestionGate.instance.rank(bytes);
    final elapsed = DateTime.now().difference(started);
    const minDelay = Duration(milliseconds: 1200);
    if (elapsed < minDelay) {
      await Future.delayed(minDelay - elapsed);
    }

    if (!mounted) return;
    setState(() {
      if (result.exploitable && result.matches.isNotEmpty) {
        _panelState = _IaPanelState.exploitable;
        _matches = result.matches;
      } else {
        _panelState = _IaPanelState.uncertain;
        _matches = const [];
      }
    });
  }

  Future<void> _pickAndAnalyzeImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await _runAnalysis(bytes);
    } catch (e) {
      // Aucun crash : format non supporté / fichier illisible -> message
      // propre + repli sur le chemin manuel (brief, point 4).
      if (!mounted) return;
      setState(() {
        _panelState = _IaPanelState.uncertain;
        _matches = const [];
        _errorMessage = 'Image illisible ou format non supporté.';
      });
    }
  }

  Future<void> _useCurrentScene() async {
    final state = context.read<AppState>();
    final image = state.roomImage;
    if (image == null) {
      setState(() {
        _panelState = _IaPanelState.uncertain;
        _matches = const [];
        _errorMessage = 'Aucune scène active — importez une photo ou '
            'chargez une pièce démo dans le Studio.';
      });
      return;
    }
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Encodage PNG de la scène active échoué.');
      }
      await _runAnalysis(byteData.buffer.asUint8List());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _panelState = _IaPanelState.uncertain;
        _matches = const [];
        _errorMessage = 'Impossible de lire la scène active.';
      });
    }
  }

  void _goToFullCatalogue() {
    widget.onClose();
    context.read<AppState>().goTo('catalogue');
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
                    'Reconnaissance automatique',
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
              'L\'assistant vous propose des références validées, vous '
              'confirmez. Suggestions calculées par similarité visuelle '
              'parmi les modèles validés présentation — jamais une '
              'confiance IA, toujours une correspondance mesurée.',
              style: TextStyle(color: AppColors.text3, fontSize: 11.5),
            ),
            const SizedBox(height: 16),
            _buildBody(context),
            const SizedBox(height: 18),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            // Toujours visibles, quel que soit l'état (brief, point 4).
            Row(
              children: [
                Expanded(
                  child: BtnOutline(
                    label: 'Voir les 43 modèles validés',
                    icon: FontAwesomeIcons.tableCellsLarge,
                    onTap: _goToFullCatalogue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BtnOutline(
                    label: 'Choisir manuellement',
                    icon: FontAwesomeIcons.handPointer,
                    onTap: widget.onClose,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_panelState) {
      case _IaPanelState.idle:
        return _buildIdle();
      case _IaPanelState.analyzing:
        return _buildAnalyzing();
      case _IaPanelState.exploitable:
        return _buildExploitable();
      case _IaPanelState.uncertain:
        return _buildUncertain();
    }
  }

  Widget _buildIdle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: BtnGold(
                label: 'Importer une photo',
                icon: FontAwesomeIcons.image,
                onTap: _pickAndAnalyzeImage,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BtnOutline(
                label: 'Utiliser la scène actuelle',
                icon: FontAwesomeIcons.houseChimney,
                onTap: _useCurrentScene,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnalyzing() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.gold),
            ),
            SizedBox(height: 10),
            Text('Analyse en cours…', style: TextStyle(color: AppColors.gold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildExploitable() {
    final state = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Suggestions expérimentales',
          style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        ..._matches.map((m) => _MatchTile(
              match: m,
              onChoose: () => state.quickToggleProd(m.ref),
            )),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => setState(() => _panelState = _IaPanelState.idle),
          child: const Text(
            'Nouvelle analyse',
            style: TextStyle(color: AppColors.text3, fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  Widget _buildUncertain() {
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
                  _errorMessage ??
                      'Reconnaissance incertaine — choisissez un modèle '
                          'validé dans le catalogue.',
                  style: const TextStyle(color: AppColors.amber, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() => _panelState = _IaPanelState.idle),
          child: const Text(
            'Réessayer',
            style: TextStyle(color: AppColors.text3, fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  final IaSuggestionMatch match;
  final VoidCallback onChoose;
  const _MatchTile({required this.match, required this.onChoose});

  @override
  Widget build(BuildContext context) {
    final prod = getProdByRef(match.ref);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/profiles/control/${match.ref}.png',
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 52,
                height: 52,
                color: AppColors.bg2,
                alignment: Alignment.center,
                child: const Icon(FontAwesomeIcons.image, size: 16, color: AppColors.text3),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      match.ref,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.green.withValues(alpha: 0.5)),
                      ),
                      child: const Text(
                        'validé présentation',
                        style: TextStyle(
                          color: AppColors.green,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (prod != null) ...[
                  Text(
                    prod.nom,
                    style: const TextStyle(color: AppColors.text2, fontSize: 10.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    prod.famille,
                    style: const TextStyle(color: AppColors.text3, fontSize: 9.5),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  match.scorePercentLabel,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          BtnOutline(label: 'Choisir', small: true, onTap: onChoose),
        ],
      ),
    );
  }
}
