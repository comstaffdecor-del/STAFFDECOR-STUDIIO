/// Écran Devis — port fidèle de `#screen-devis` (shell.ts).
///
/// Table complète du chiffrage (8 colonnes équivalent), sélecteur de marge,
/// avertissement légal (Annexe C).
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/chiffrage.dart';
import '../../core/theme.dart';
import '../../data/quote_send.dart';
import '../../state/app_state.dart';
import '../../widgets/common/common_ui.dart';

class DevisScreen extends StatelessWidget {
  const DevisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chiffrage = calcChiffrage(
      selectedProducts: state.selectedProducts,
      margeCoupePct: state.margeCoupePct,
      isCalibrated: state.isCalibrated,
    );

    // ⚠️ CORRECTION Bug #14/#22 : l'écran Devis complet (table détaillée +
    // totaux) reste réservé aux utilisateurs ayant soumis leurs
    // coordonnées — même logique de verrouillage que le panneau bas du
    // Comparateur (voir _LockedPanel/comparateur_screen.dart).
    if (!state.contactSubmitted) {
      return _DevisLocked(state: state);
    }

    return Column(
      children: [
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 14),
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
                    Text('Mon Devis', style: TextStyle(color: AppColors.gold, fontSize: 15, fontWeight: FontWeight.w600)),
                    Text('Estimation indicative', style: TextStyle(color: AppColors.text3, fontSize: 10.5)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.card2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Text('Marge', style: TextStyle(color: AppColors.text3, fontSize: 10.5)),
                    const SizedBox(width: 6),
                    DropdownButton<double>(
                      value: state.margeCoupePct,
                      dropdownColor: AppColors.card2,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(color: AppColors.gold, fontSize: 12),
                      items: const [0.05, 0.10, 0.15, 0.20]
                          .map((v) => DropdownMenuItem(value: v, child: Text('${(v * 100).toStringAsFixed(0)}%')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) state.setMargeCoupePct(v);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconBtn(icon: FontAwesomeIcons.arrowLeft, size: 32, onTap: () => state.goTo('comparateur')),
            ],
          ),
        ),
        Expanded(
          child: chiffrage.lignes.isEmpty
              ? const Center(
                  child: Text('Aucun produit dans le projet', style: TextStyle(color: AppColors.text3, fontSize: 13)),
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: const [
                              Expanded(flex: 3, child: Text('Réf.', style: TextStyle(color: AppColors.text3, fontSize: 10.5))),
                              Expanded(flex: 2, child: Text('Qté nette', style: TextStyle(color: AppColors.text3, fontSize: 10.5), textAlign: TextAlign.right)),
                              Expanded(flex: 2, child: Text('Qté com.', style: TextStyle(color: AppColors.text3, fontSize: 10.5), textAlign: TextAlign.right)),
                              Expanded(flex: 2, child: Text('PU HT', style: TextStyle(color: AppColors.text3, fontSize: 10.5), textAlign: TextAlign.right)),
                              Expanded(flex: 2, child: Text('Total HT', style: TextStyle(color: AppColors.text3, fontSize: 10.5), textAlign: TextAlign.right)),
                            ],
                          ),
                          const Divider(color: AppColors.border),
                          ...chiffrage.lignes.map((l) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(l.ref, style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600)),
                                          Text(l.famille, style: const TextStyle(color: AppColors.text3, fontSize: 9.5)),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text('${fmtN(l.qteNette)} ${l.unite}',
                                          style: const TextStyle(color: AppColors.text2, fontSize: 11), textAlign: TextAlign.right),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        l.nbBarres != null ? '${l.nbBarres} barre${l.nbBarres! > 1 ? 's' : ''}' : '${fmtN(l.qteCom)} ${l.unite}',
                                        style: const TextStyle(color: AppColors.text2, fontSize: 11),
                                        textAlign: TextAlign.right,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(fmtPrix(l.puHt), style: const TextStyle(color: AppColors.text2, fontSize: 11), textAlign: TextAlign.right),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(fmtPrix(l.totalHt),
                                          style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w600),
                                          textAlign: TextAlign.right),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.card2,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _totalRow('Total HT', fmtPrix(chiffrage.totalHt)),
                          _totalRow('TVA (20%)', fmtPrix(chiffrage.tva)),
                          const Divider(color: AppColors.border),
                          _totalRow('Total TTC', fmtPrix(chiffrage.totalTtc), big: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(FontAwesomeIcons.circleInfo, size: 14, color: AppColors.amber),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ordre de prix indicatif : cette estimation ne constitue pas un devis contractuel. '
                              'Contactez votre conseiller Staff Décor pour un devis détaillé.',
                              style: TextStyle(color: AppColors.text2, fontSize: 10.5, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SendQuoteButton(state: state, chiffrage: chiffrage),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _totalRow(String label, String value, {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: AppColors.text2, fontSize: big ? 13 : 12))),
          Text(value,
              style: TextStyle(
                  color: big ? AppColors.gold : AppColors.text,
                  fontSize: big ? 18 : 13,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Écran Devis verrouillé — affiché tant que [AppState.contactSubmitted]
/// est faux (Bug #14/#22).
class _DevisLocked extends StatelessWidget {
  final AppState state;
  const _DevisLocked({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            color: AppColors.bg,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text('Mon Devis',
                    style: TextStyle(color: AppColors.gold, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              IconBtn(icon: FontAwesomeIcons.arrowLeft, size: 32, onTap: () => state.goTo('comparateur')),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(FontAwesomeIcons.lock, size: 24, color: AppColors.gold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Devis masqué',
                    style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Renseignez vos coordonnées pour consulter le détail du '
                    'chiffrage et recevoir cette estimation par email.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.text3, fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 240,
                    child: BtnGold(
                      label: 'Voir mon devis',
                      icon: FontAwesomeIcons.unlock,
                      onTap: state.openContactModal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bouton "Envoyer ma demande de devis" (P24-QUOTE-GMAIL).
///
/// Gère localement les 3 états requis par le brief (idle / envoi en
/// cours / résultat), avec les libellés EXACTS demandés :
///   - repos  : "Envoyer ma demande de devis"
///   - envoi  : "Envoi de votre demande…"
///   - succès : "Votre demande de devis a bien été envoyée."
///   - erreur : "L'envoi n'a pas pu aboutir. Merci de réessayer."
/// Jamais de message technique (statut HTTP, erreur SMTP, etc.) —
/// voir `data/quote_send.dart`.
class _SendQuoteButton extends StatefulWidget {
  final AppState state;
  final Chiffrage chiffrage;

  const _SendQuoteButton({required this.state, required this.chiffrage});

  @override
  State<_SendQuoteButton> createState() => _SendQuoteButtonState();
}

enum _QuoteSendUiState { idle, sending, success, error }

class _SendQuoteButtonState extends State<_SendQuoteButton> {
  _QuoteSendUiState _uiState = _QuoteSendUiState.idle;

  Future<void> _onSend() async {
    final contact = widget.state.lastContactInfo;
    if (contact == null) {
      // Ne devrait pas arriver (bouton visible seulement une fois
      // contactSubmitted==true, donc lastContactInfo renseigné), mais
      // on reste défensif plutôt que de crasher.
      setState(() => _uiState = _QuoteSendUiState.error);
      return;
    }

    setState(() => _uiState = _QuoteSendUiState.sending);

    final items = widget.chiffrage.lignes
        .map((l) => QuoteItem(
              ref: l.ref,
              name: l.designation,
              quantity: l.qteCom,
              unit: l.unite,
            ))
        .toList();

    final result = await sendQuoteRequest(
      name: '${contact.prenom} ${contact.nom}'.trim(),
      email: contact.email,
      phone: contact.tel,
      message: contact.message,
      items: items,
      totalEstimate: widget.chiffrage.totalTtc,
    );

    if (!mounted) return;
    setState(() {
      _uiState = result.ok ? _QuoteSendUiState.success : _QuoteSendUiState.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_uiState) {
      case _QuoteSendUiState.sending:
        return _StatusBanner(
          icon: null,
          spinner: true,
          text: kQuoteSendLoadingMessage,
          color: AppColors.text2,
        );
      case _QuoteSendUiState.success:
        return _StatusBanner(
          icon: FontAwesomeIcons.circleCheck,
          text: kQuoteSendSuccessMessage,
          color: AppColors.gold,
        );
      case _QuoteSendUiState.error:
        return Column(
          children: [
            _StatusBanner(
              icon: FontAwesomeIcons.triangleExclamation,
              text: kQuoteSendErrorMessage,
              color: AppColors.amber,
            ),
            const SizedBox(height: 10),
            BtnGold(
              label: 'Envoyer ma demande de devis',
              icon: FontAwesomeIcons.paperPlane,
              onTap: _onSend,
            ),
          ],
        );
      case _QuoteSendUiState.idle:
        return BtnGold(
          label: 'Envoyer ma demande de devis',
          icon: FontAwesomeIcons.paperPlane,
          onTap: _onSend,
        );
    }
  }
}

/// Bandeau neutre de statut (envoi en cours / succès / erreur), aligné
/// visuellement sur le bandeau d'avertissement légal déjà présent dans
/// cet écran (`AppColors.card2` + coins arrondis).
class _StatusBanner extends StatelessWidget {
  final IconData? icon;
  final bool spinner;
  final String text;
  final Color color;

  const _StatusBanner({
    this.icon,
    this.spinner = false,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          if (spinner)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else if (icon != null)
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
