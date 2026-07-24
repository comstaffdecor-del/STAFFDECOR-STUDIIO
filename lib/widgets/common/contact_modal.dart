/// Modal de saisie des coordonnées client — port étendu de
/// `#modal-contact` (contact.js), avec les corrections demandées :
///
/// ⚠️ CORRECTION Bug #15 : ajout des champs Nom et Entreprise (l'ancien
/// formulaire n'avait que Prénom/Email/Téléphone/Code postal/Message).
///
/// ⚠️ CORRECTION Bug #16 : ajout d'une case de consentement RGPD
/// explicite, obligatoire pour valider le formulaire.
///
/// ⚠️ CORRECTION Bug #14/#22 : ce modal est désormais la porte d'entrée
/// OBLIGATOIRE avant de pouvoir consulter le chiffrage détaillé
/// (Comparateur/Devis, voir [AppState.contactSubmitted]). La validation
/// déclenche [AppState.submitContact] (déverrouille l'affichage des prix)
/// PUIS ouvre le client mail de l'utilisateur, pré-rempli à destination
/// de contact@staffdecor.fr avec le récapitulatif du projet — objectif
/// "génération de leads" explicitement demandé par l'utilisateur, sans
/// backend d'envoi automatique disponible dans cet environnement.
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/chiffrage.dart';
import '../../core/theme.dart';
import '../../models/contact_info.dart';
import '../../state/app_state.dart';

/// Construit le corps texte du mailto — récapitulatif coordonnées +
/// métrés + chiffrage, lisible tel quel dans un client mail.
String buildProjectMailBody(ContactInfo info, AppState state) {
  final chiffrage = calcChiffrage(
    selectedProducts: state.selectedProducts,
    margeCoupePct: state.margeCoupePct,
    isCalibrated: state.isCalibrated,
  );

  final b = StringBuffer();
  b.writeln('Nouveau projet Staff Décor Studio');
  b.writeln('==================================');
  b.writeln();
  b.writeln('— Contact —');
  b.writeln('Prénom : ${info.prenom}');
  b.writeln('Nom : ${info.nom}');
  if (info.entreprise.trim().isNotEmpty) {
    b.writeln('Entreprise : ${info.entreprise}');
  }
  b.writeln('Email : ${info.email}');
  if (info.tel.trim().isNotEmpty) b.writeln('Téléphone : ${info.tel}');
  if (info.cp.trim().isNotEmpty) b.writeln('Code postal : ${info.cp}');
  if (info.message.trim().isNotEmpty) {
    b.writeln();
    b.writeln('Message : ${info.message}');
  }
  b.writeln();
  if (state.metresPerimetreNet > 0) {
    b.writeln('— Métrés —');
    b.writeln(
      'Pièce : ${fmtN(state.metresMurA)}m × ${fmtN(state.metresMurB)}m · H ${fmtN(state.metresHauteur)}m',
    );
    b.writeln('Périmètre net : ${fmtN(state.metresPerimetreNet)} m');
    if (state.metresSurface > 0) {
      b.writeln('Surface : ${fmtN(state.metresSurface)} m²');
    }
    b.writeln();
  }
  b.writeln('— Chiffrage estimatif —');
  for (final l in chiffrage.lignes) {
    final qteStr = l.nbBarres != null
        ? '${l.nbBarres} barre${l.nbBarres! > 1 ? 's' : ''}'
        : '${fmtN(l.qteCom)} ${l.unite}';
    b.writeln('${l.ref} (${l.famille}) — $qteStr — ${fmtPrix(l.totalHt)}');
  }
  b.writeln();
  b.writeln('Total HT : ${fmtPrix(chiffrage.totalHt)}');
  b.writeln('TVA (20%) : ${fmtPrix(chiffrage.tva)}');
  b.writeln('Total TTC : ${fmtPrix(chiffrage.totalTtc)}');
  b.writeln();
  b.writeln(
    'Document non contractuel · Estimation automatique Staff Décor Studio.',
  );
  return b.toString();
}

/// Ouvre le client mail de l'utilisateur, pré-rempli vers
/// contact@staffdecor.fr avec le récapitulatif du projet.
Future<void> launchProjectMailto(ContactInfo info, AppState state) async {
  final subject = Uri.encodeComponent(
    '[Studio] Projet de ${info.prenom} ${info.nom}',
  );
  final body = Uri.encodeComponent(buildProjectMailBody(info, state));
  final uri = Uri.parse(
    'mailto:contact@staffdecor.fr?subject=$subject&body=$body',
  );
  try {
    await launchUrl(uri);
  } catch (_) {
    // Client mail indisponible (ex: environnement web sandbox) — le
    // formulaire reste néanmoins validé, l'utilisateur peut relancer
    // l'envoi plus tard (bouton "Envoyer" toujours accessible depuis le
    // Comparateur une fois les coordonnées connues).
  }
}

class ContactModal extends StatefulWidget {
  const ContactModal({super.key});

  @override
  State<ContactModal> createState() => _ContactModalState();
}

class _ContactModalState extends State<ContactModal> {
  late final TextEditingController _prenomCtrl;
  late final TextEditingController _nomCtrl;
  late final TextEditingController _entrepriseCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _telCtrl;
  late final TextEditingController _cpCtrl;
  late final TextEditingController _msgCtrl;
  bool _rgpd = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final prev = context.read<AppState>().lastContactInfo;
    _prenomCtrl = TextEditingController(text: prev?.prenom ?? '');
    _nomCtrl = TextEditingController(text: prev?.nom ?? '');
    _entrepriseCtrl = TextEditingController(text: prev?.entreprise ?? '');
    _emailCtrl = TextEditingController(text: prev?.email ?? '');
    _telCtrl = TextEditingController(text: prev?.tel ?? '');
    _cpCtrl = TextEditingController(text: prev?.cp ?? '');
    _msgCtrl = TextEditingController(text: prev?.message ?? '');
    _rgpd = prev?.rgpdConsent ?? false;
  }

  @override
  void dispose() {
    _prenomCtrl.dispose();
    _nomCtrl.dispose();
    _entrepriseCtrl.dispose();
    _emailCtrl.dispose();
    _telCtrl.dispose();
    _cpCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String v) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v);

  Future<void> _submit() async {
    final prenom = _prenomCtrl.text.trim();
    final nom = _nomCtrl.text.trim();
    final email = _emailCtrl.text.trim();

    if (prenom.isEmpty || nom.isEmpty || !_validEmail(email)) {
      setState(
        () => _error = 'Merci de renseigner prénom, nom et un email valide.',
      );
      return;
    }
    if (!_rgpd) {
      setState(
        () => _error =
            'Merci d\'accepter le traitement de vos données pour continuer.',
      );
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    final info = ContactInfo(
      prenom: prenom,
      nom: nom,
      entreprise: _entrepriseCtrl.text.trim(),
      email: email,
      tel: _telCtrl.text.trim(),
      cp: _cpCtrl.text.trim(),
      message: _msgCtrl.text.trim(),
      rgpdConsent: _rgpd,
    );

    final state = context.read<AppState>();
    state.submitContact(info);
    await launchProjectMailto(info, state);

    if (!mounted) return;
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: state.closeContactModal,
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 620),
            decoration: const BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                top: BorderSide(color: AppColors.border),
                left: BorderSide(color: AppColors.border),
                right: BorderSide(color: AppColors.border),
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Envoyer votre projet',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Vos coordonnées sont nécessaires pour afficher '
                    'l\'estimation détaillée et être recontacté par un '
                    'conseiller Staff Décor.',
                    style: TextStyle(color: AppColors.text3, fontSize: 11.5),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          'Prénom *',
                          _prenomCtrl,
                          hint: 'Florence',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field('Nom *', _nomCtrl, hint: 'Dupont'),
                      ),
                    ],
                  ),
                  _field(
                    'Entreprise (optionnel)',
                    _entrepriseCtrl,
                    hint: 'Cabinet Dupont Architecture',
                  ),
                  _field(
                    'Email *',
                    _emailCtrl,
                    hint: 'vous@email.com',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  _field(
                    'Téléphone (optionnel)',
                    _telCtrl,
                    hint: '+33 6 …',
                    keyboardType: TextInputType.phone,
                  ),
                  _field(
                    'Code postal (routing régional)',
                    _cpCtrl,
                    hint: '75001',
                    keyboardType: TextInputType.number,
                    maxLength: 5,
                  ),
                  _field(
                    'Message (optionnel)',
                    _msgCtrl,
                    hint: 'Précisions sur votre projet…',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 6),
                  // ⚠️ Bug #16 : consentement RGPD explicite obligatoire.
                  InkWell(
                    onTap: () => setState(() => _rgpd = !_rgpd),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _rgpd,
                            onChanged: (v) => setState(() => _rgpd = v ?? false),
                            activeColor: AppColors.gold,
                            checkColor: AppColors.bg,
                          ),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'J\'accepte que mes données soient utilisées par '
                                'Staff Décor pour traiter ma demande de devis, '
                                'conformément au RGPD. Elles ne seront ni '
                                'revendues ni transmises à des tiers. *',
                                style: TextStyle(
                                  color: AppColors.text2,
                                  fontSize: 10.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.bg,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.bg,
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(FontAwesomeIcons.paperPlane, size: 13),
                                SizedBox(width: 8),
                                Text(
                                  'Envoyer le projet',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: state.closeContactModal,
                      child: const Text(
                        'Annuler',
                        style: TextStyle(
                          color: AppColors.text3,
                          fontSize: 11.5,
                        ),
                      ),
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

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    TextInputType? keyboardType,
    int? maxLength,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.text2, fontSize: 11),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: keyboardType,
            maxLength: maxLength,
            maxLines: maxLines,
            style: const TextStyle(color: AppColors.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: AppColors.text3,
                fontSize: 12,
              ),
              counterText: '',
              filled: true,
              fillColor: AppColors.card2,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
