/// P17-VISUEL — "Aperçu d'ambiance IA" via Gemini image (Nano Banana).
///
/// ⚠️ ARBITRAGE EXPLICITE (à trancher AVANT tout code, brief point 2) :
/// un appel Gemini depuis le client Flutter WEB place nécessairement la
/// clé API en clair dans le bundle compilé (`main.dart.js`), donc
/// publiquement lisible par quiconque ouvre le lien de démo (port 8080).
/// Trois options existaient : (a) proxy serveur minimal gardant la clé
/// côté serveur, (b) clé jetable restreinte assumée pour la durée de la
/// démo puis révoquée, (c) pas de génération côté client.
///
/// **Option retenue : (b) — clé jetable restreinte, assumée.**
/// Motif : ce sandbox ne sert la démo qu'avec un `python3 -m
/// http.server` statique (voir port 8080) — aucun processus serveur
/// applicatif n'existe pour héberger un proxy, et en créer un est un
/// "backend lourd" explicitement interdit par le brief (point 9). La clé,
/// SI elle est un jour fournie, serait injectée au build via
/// `--dart-define=GEMINI_API_KEY=...` (jamais codée en dur dans ce
/// fichier, jamais commitée) et resterait donc visible en clair dans le
/// bundle web compilé. Risque résiduel accepté et documenté : clé à
/// quota/portée minimale, restriction par domaine/referrer si l'API le
/// permet, révocation dès la fin de la démonstration. Aucune clé Gemini
/// n'est présente dans ce sandbox au moment de cette passe (vérifié) :
/// [kAiPreviewEnabled] reste donc `false` et aucun appel réseau n'a lieu.
///
/// ⚠️ PÉRIMÈTRE STRICT (brief points 4, 6, 7) :
///  - ne s'active QUE pour les 43 refs de `assets/profiles/index.json`
///    (même gate que [CatalogueVisibilityGate], jamais un accès direct
///    à un SKU hors index, jamais un brouillon) ;
///  - l'image générée est affichée UNIQUEMENT en mémoire
///    ([Uint8List]/[ui.Image]) — AUCUNE écriture dans `assets/`, aucune
///    modification de `pubspec.yaml`. Seuls les échantillons du rapport
///    sont écrits par l'outillage de build, dans `artifacts/p17-visuel/`
///    (jamais depuis ce fichier lui-même, qui ne fait aucune I/O
///    disque) ;
///  - ce module ne valide AUCUNE géométrie/STL/gate, ne déclare rien
///    "renderable" : c'est une illustration d'ambiance, non contractuelle ;
///  - le module de similarité visuelle ([IaSuggestionGate], fichier
///    voisin `ia_suggestion.dart`) continue de ne lire QUE
///    `assets/profiles/control/*.png` — jamais une image générée par ce
///    module-ci (aucun lien de code entre les deux, vérifié par lecture).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// POINT UNIQUE DE RÉVERSIBILITÉ — brief point 6.
///
/// `false` par défaut. Ne DOIT passer à `true` que juste après qu'une
/// génération réelle a été testée avec succès dans cet environnement
/// (clé + réseau + réponse Gemini valide) — jamais activé "en aveugle".
/// Au moment de cette passe (P17-VISUEL) : AUCUNE clé Gemini n'a été
/// trouvée dans le sandbox (voir /tmp/presentation_ai_demo.txt) ; ce
/// booléen reste donc `false` et l'UI affiche le bouton grisé +
/// "fonction bientôt disponible" (jamais une simulation locale faisant
/// croire à une génération IA réelle).
const bool kAiPreviewEnabled = false;

/// Nom du modèle Gemini image utilisé (aucun secret ici — uniquement un
/// identifiant de modèle public). Documenté tel quel dans le rapport,
/// jamais accompagné d'une valeur de clé.
const String kGeminiImageModel = 'gemini-3-pro-image-preview';

/// Endpoint Gemini generateContent (aucun secret dans l'URL elle-même —
/// la clé est passée en en-tête `x-goog-api-key`, jamais concatenée ici
/// en dur).
String _geminiEndpoint(String model) =>
    'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

/// Limites strictes du client (brief 2bis, appliquées même en absence de
/// proxy : le client lui-même respecte un plafond d'appels et un timeout
/// court, pour ne jamais consommer un quota de façon incontrôlée).
const Duration kAiPreviewTimeout = Duration(seconds: 20);
const int kAiPreviewMaxCallsPerSession = 5;
const int kAiPreviewMaxImageBytes = 8 * 1024 * 1024; // 8 Mo

/// Lit la clé API injectée au build via `--dart-define=GEMINI_API_KEY=...`
/// — JAMAIS codée en dur dans le dépôt. Renvoie `''` si absente (cas
/// attendu et normal dans ce sandbox à ce jour).
const String _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

/// `true` si une clé a été injectée au build (sans jamais exposer sa
/// valeur — utilisé uniquement pour piloter l'état grisé du bouton et
/// pour le rapport, qui ne loggue QUE ce booléen, jamais la valeur).
bool get isGeminiApiKeyConfigured => _geminiApiKey.isNotEmpty;

/// Compteur d'appels de la session courante (mémoire uniquement, remis à
/// zéro à chaque rechargement de page) — applique
/// [kAiPreviewMaxCallsPerSession] côté client, en complément du timeout.
int _callsThisSession = 0;

/// Résultat d'une tentative de génération d'aperçu IA.
class AiPreviewResult {
  final bool success;
  final Uint8List? imageBytes;
  final String? errorMessage;
  const AiPreviewResult._({required this.success, this.imageBytes, this.errorMessage});

  factory AiPreviewResult.ok(Uint8List bytes) =>
      AiPreviewResult._(success: true, imageBytes: bytes);

  factory AiPreviewResult.fail(String message) =>
      AiPreviewResult._(success: false, errorMessage: message);
}

/// Message de repli UNIQUE et obligatoire (brief point 6) — utilisé pour
/// TOUTE cause d'échec (API absente, erreur réseau, quota, timeout,
/// image invalide), jamais un message technique brut affiché à
/// l'utilisateur final.
const String kAiPreviewFallbackMessage =
    'Aperçu IA momentanément indisponible — continuez avec le catalogue validé.';

/// Mention non-contractuelle permanente, non masquable (brief point 5),
/// affichée sous TOUTE image générée.
const String kAiPreviewDisclaimer =
    'Aperçu IA non contractuel — illustration d\'ambiance, ne représente '
    'pas le rendu technique du produit.';

/// Construit le prompt Gemini à partir du produit et de la scène (brief
/// point 8) — jamais de fausse génération locale, jamais de score
/// inventé : ce texte ne fait que décrire la demande envoyée au modèle
/// distant réel.
String buildAiPreviewPrompt({
  required String ref,
  required String nom,
  required String famille,
}) {
  return 'Create a visual concept preview only. Do not invent product '
      'geometry specifications. Integrate the decorative plaster/staff '
      'moulding product "$nom" (reference $ref, family: $famille) '
      'realistically onto the wall or ceiling of the provided room photo. '
      'Use an off-white plaster/staff tone (blanc cassé), respect the '
      'existing perspective, lighting and shadows of the photo. Do not '
      'add any other decorative product. Photorealistic architectural '
      'visualization style, subtle and coherent with the room.';
}

/// Tente une génération d'aperçu d'ambiance IA. Ne lève JAMAIS
/// d'exception : toute erreur (clé absente, réseau, quota, timeout,
/// réponse invalide) aboutit à un [AiPreviewResult.fail] avec
/// [kAiPreviewFallbackMessage], jamais un crash.
///
/// [sceneImageBytes] : la photo de scène (démo ou importée) à utiliser
/// comme image de référence pour l'intégration produit.
Future<AiPreviewResult> generateAiAmbiancePreview({
  required Uint8List sceneImageBytes,
  required String ref,
  required String nom,
  required String famille,
}) async {
  if (!kAiPreviewEnabled) {
    return AiPreviewResult.fail(kAiPreviewFallbackMessage);
  }
  if (!isGeminiApiKeyConfigured) {
    return AiPreviewResult.fail(kAiPreviewFallbackMessage);
  }
  if (_callsThisSession >= kAiPreviewMaxCallsPerSession) {
    return AiPreviewResult.fail(kAiPreviewFallbackMessage);
  }
  if (sceneImageBytes.length > kAiPreviewMaxImageBytes) {
    return AiPreviewResult.fail(kAiPreviewFallbackMessage);
  }

  _callsThisSession++;

  try {
    final prompt = buildAiPreviewPrompt(ref: ref, nom: nom, famille: famille);
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Encode(sceneImageBytes),
              }
            },
          ],
        }
      ],
    });

    final uri = Uri.parse(_geminiEndpoint(kGeminiImageModel));
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': _geminiApiKey,
          },
          body: body,
        )
        .timeout(kAiPreviewTimeout);

    if (response.statusCode != 200) {
      if (kDebugMode) {
        // Jamais la clé, jamais le corps complet (pourrait contenir des
        // données image) — uniquement le code HTTP, à but diagnostic
        // local. Jamais persisté dans un fichier/rapport.
        debugPrint('generateAiAmbiancePreview: HTTP ${response.statusCode}');
      }
      return AiPreviewResult.fail(kAiPreviewFallbackMessage);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      return AiPreviewResult.fail(kAiPreviewFallbackMessage);
    }
    final parts = (candidates.first as Map<String, dynamic>)['content']
        ?['parts'] as List?;
    if (parts == null) {
      return AiPreviewResult.fail(kAiPreviewFallbackMessage);
    }
    for (final part in parts) {
      final inline = (part as Map<String, dynamic>)['inline_data'] ??
          part['inlineData'];
      if (inline is Map<String, dynamic>) {
        final data = inline['data'] as String?;
        if (data != null && data.isNotEmpty) {
          final bytes = base64Decode(data);
          if (bytes.isEmpty) {
            return AiPreviewResult.fail(kAiPreviewFallbackMessage);
          }
          return AiPreviewResult.ok(bytes);
        }
      }
    }
    return AiPreviewResult.fail(kAiPreviewFallbackMessage);
  } on TimeoutException {
    return AiPreviewResult.fail(kAiPreviewFallbackMessage);
  } catch (_) {
    // Toute autre erreur (réseau, parsing, image invalide...) : jamais
    // de crash, toujours le message de repli standard.
    return AiPreviewResult.fail(kAiPreviewFallbackMessage);
  }
}
