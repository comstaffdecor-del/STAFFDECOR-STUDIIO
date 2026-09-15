/// P24-QUOTE-GMAIL — Envoi de la demande de devis par email.
///
/// RÈGLE DE SÉCURITÉ ABSOLUE (même principe que
/// `data/ia_ambiance_preview.dart` pour le rendu IA) : AUCUN identifiant
/// Gmail/SMTP ne vit jamais côté Flutter, ni en dur ni via
/// `--dart-define`. Ce module ne connaît QUE l'URL publique du proxy
/// serveur (le même proxy que l'aperçu IA, voir [kAiRenderProxyBaseUrl]
/// dans `ia_ambiance_preview.dart`) et appelle uniquement
/// `POST /api/quote/send`. Le proxy détient les identifiants Gmail SMTP
/// dans son propre `.env` (`GMAIL_SMTP_USER` / `GMAIL_SMTP_APP_PASSWORD`),
/// jamais renvoyés ni loggés vers le client.
///
/// Architecture imposée par le brief :
///   Flutter → POST /api/quote/send → serveur/proxy → Gmail SMTP
///
/// Contrat HTTP (fixe, voir `server/ai_render_proxy/server.js`) :
///   - Succès : `{"ok": true, "requestId": "quote_..."}`
///   - Erreur : `{"ok": false, "error": "QUOTE_SEND_FAILED"}`
///
/// Wording client (voir contrainte globale du projet) : les messages
/// affichés à l'utilisateur restent volontairement neutres et courts,
/// jamais de détail technique (pas de statut HTTP, pas de message SMTP
/// brut, pas de mention d'infrastructure).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ia_ambiance_preview.dart' show kAiRenderProxyBaseUrl;

/// Un produit du projet tel qu'il doit apparaître dans le mail de devis.
class QuoteItem {
  final String ref;
  final String name;
  final num quantity;
  final String unit;

  const QuoteItem({
    required this.ref,
    required this.name,
    required this.quantity,
    required this.unit,
  });

  Map<String, dynamic> toJson() => {
    'ref': ref,
    'name': name,
    'quantity': quantity,
    'unit': unit,
  };
}

/// Résultat de l'envoi — jamais de message technique brut exposé, voir
/// [kQuoteSendErrorMessage] pour le seul message d'erreur affiché à
/// l'utilisateur final quelle que soit la cause réelle (réseau, quota,
/// config Gmail absente côté serveur, refus SMTP...).
class QuoteSendResult {
  final bool ok;
  final String? requestId;

  const QuoteSendResult._({required this.ok, this.requestId});

  factory QuoteSendResult.success(String requestId) =>
      QuoteSendResult._(ok: true, requestId: requestId);

  factory QuoteSendResult.failure() => const QuoteSendResult._(ok: false);
}

/// Message affiché pendant l'envoi.
const String kQuoteSendLoadingMessage = 'Envoi de votre demande…';

/// Message affiché en cas de succès.
const String kQuoteSendSuccessMessage =
    'Votre demande de devis a bien été envoyée.';

/// Message affiché en cas d'échec — volontairement générique, jamais de
/// détail technique (voir docstring du fichier).
const String kQuoteSendErrorMessage =
    "L'envoi de votre demande a échoué. Merci de réessayer.";

/// Envoie la demande de devis au proxy serveur, qui se charge de
/// l'envoi réel par Gmail SMTP. [httpClient] — point d'injection
/// UNIQUEMENT pour les tests (même pattern que
/// `generateAiAmbiancePreview`), null par défaut : comportement de
/// production (`http.post` réel) inchangé pour tout appelant existant.
Future<QuoteSendResult> sendQuoteRequest({
  required String name,
  required String email,
  required String phone,
  required String message,
  required List<QuoteItem> items,
  required double totalEstimate,
  // Scène ou photo utilisée par le client au moment de la demande (ex:
  // "Scène démo — Haussmannien", "Photo importée par le client",
  // "Scène actuelle du Studio") — transmise telle quelle au corps du
  // mail (brief "correction de consigne" Gmail, champ "scène ou photo
  // utilisée si disponible"). `null`/vide si aucune scène n'a encore
  // été chargée dans le Studio au moment de l'envoi.
  String? sceneLabel,
  http.Client? httpClient,
}) async {
  // SÉCURITÉ (même garde que l'aperçu IA) : URL proxy non configurée
  // pour cet environnement (build sans
  // --dart-define=AI_RENDER_PROXY_BASE_URL) → échec propre, jamais
  // d'appel réseau vers une URL vide.
  if (httpClient == null && kAiRenderProxyBaseUrl.isEmpty) {
    return QuoteSendResult.failure();
  }

  final uri = Uri.parse('$kAiRenderProxyBaseUrl/api/quote/send');
  final body = jsonEncode({
    'name': name,
    'email': email,
    'phone': phone,
    'message': message,
    'items': items.map((i) => i.toJson()).toList(),
    'totalEstimate': totalEstimate,
    if (sceneLabel != null && sceneLabel.isNotEmpty) 'sceneLabel': sceneLabel,
  });

  http.Response resp;
  try {
    final future = httpClient != null
        ? httpClient.post(uri, headers: const {'Content-Type': 'application/json'}, body: body)
        : http.post(uri, headers: const {'Content-Type': 'application/json'}, body: body);
    resp = await future.timeout(const Duration(seconds: 30));
  } catch (_) {
    // Timeout, DNS, connexion refusée, etc. — jamais de détail réseau
    // brut affiché à l'utilisateur final.
    return QuoteSendResult.failure();
  }

  Map<String, dynamic>? json;
  try {
    json = jsonDecode(resp.body) as Map<String, dynamic>;
  } catch (_) {
    return QuoteSendResult.failure();
  }

  if (resp.statusCode != 200 || json['ok'] != true) {
    return QuoteSendResult.failure();
  }

  final requestId = json['requestId'] as String?;
  if (requestId == null || requestId.isEmpty) {
    return QuoteSendResult.failure();
  }

  return QuoteSendResult.success(requestId);
}
