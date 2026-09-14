/// P19-MANOBANANA-QAD — "Aperçu d'ambiance IA".
///
/// ⚠️ HISTORIQUE (mis à jour) : cette passe avait exploré l'intégration
/// d'un rendu IA réel via un proxy serveur portant la clé côté serveur
/// (jamais côté client Flutter — ce principe reste intégralement
/// valide). Trois voies avaient été testées, avec un blocage quota=0
/// systématique côté Gemini à l'époque :
///
///  1. Gemini (`gemini-3.1-flash-image` / `gemini-3.1-flash-lite-image`
///     via generateContent) : une PREMIÈRE clé testée avait bien été
///     RECONNUE par Google (projet réel identifié), mais le quota
///     `generate_content_free_tier_requests` était à **0** → HTTP 429
///     systématique sur 3 variantes de modèle testées.
///  2. OpenAI (`images/edits`) : aucune clé OpenAI personnelle
///     disponible dans cet environnement (`OPENAI_API_KEY` pointe vers
///     le proxy LLM interne Genspark, texte/code uniquement).
///  3. Genspark (infra plateforme) : hors périmètre par consigne
///     explicite.
///
/// **Mise à jour (test live serveur, nouvelle clé fournie) :** une
/// NOUVELLE clé a été testée en direct côté serveur (appel minimal
/// `generateContent`, prompt "generate a small neutral plaster cornice
/// preview on a white wall") → **HTTP 200, image réellement générée**
/// (JPEG 1408×768, ~528 Ko), confirmé aussi en conditions réelles via
/// le proxy `server/ai_render_proxy/` avec une vraie photo de scène et
/// le SKU D609 (HTTP 200, image ~794 Ko en 4,4 s). Le quota n'est donc
/// PAS bloqué pour cette clé. [kAiPreviewEnabled] passe à `true` sur
/// cette base.
///
/// La clé vit UNIQUEMENT dans `server/ai_render_proxy/.env` (fichier
/// gitignored, jamais committé) et n'est JAMAIS embarquée dans le
/// client Flutter : ce fichier appelle uniquement l'URL PUBLIQUE du
/// proxy (voir [kAiRenderProxyBaseUrl]), qui lui-même détient la clé
/// côté serveur et ne la renvoie/logge jamais (voir server.js).
///
/// PÉRIMÈTRE INCHANGÉ (hérité de P17-VISUEL, toujours respecté) :
///  - ne s'active QUE pour les refs de `assets/profiles/index.json` ;
///  - l'image générée reste UNIQUEMENT en mémoire ([Uint8List]) ;
///  - ce module ne touche ni au moteur perspective ni aux presets.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// URL PUBLIQUE du proxy serveur (jamais la clé elle-même — le proxy la
/// détient côté serveur dans son propre `.env`, jamais exposée ici).
/// ⚠️ Cette URL dépend du sandbox de développement courant : si le
/// sandbox est recréé, régénérer l'URL publique du port 8091 et la
/// remplacer ici (seul point à mettre à jour, aucune clé concernée).
const String kAiRenderProxyBaseUrl =
    'https://8091-iv0to5t5muaul2o2div2d-c81df28e.sandbox.novita.ai';

/// POINT UNIQUE DE RÉVERSIBILITÉ. Passé à `true` après confirmation
/// d'une génération réelle réussie (clé + quota + réseau + réponse
/// image valide), voir historique ci-dessus. Remettre à `false` en cas
/// de nouveau blocage quota/clé pour désactiver proprement le flux IA
/// sans retirer de code.
const bool kAiPreviewEnabled = true;

/// Messages d'erreur COURTS, un par cause distincte — jamais un message
/// technique brut affiché à l'utilisateur final.
const String kAiPreviewErrorNoPhoto = 'Aucune photo sélectionnée.';
const String kAiPreviewErrorNoProduct = 'Aucun produit sélectionné.';
const String kAiPreviewErrorProxyUnreachable = 'Proxy de rendu injoignable.';
const String kAiPreviewErrorGenerationFailed = 'Échec de la génération.';
const String kAiPreviewErrorDisabled = 'Fonction non configurée sur cet environnement.';

/// Message de repli générique (compat rétro).
const String kAiPreviewFallbackMessage = kAiPreviewErrorGenerationFailed;

/// Mention non-contractuelle permanente, non masquable, affichée sous
/// TOUTE image générée (résultat réel ou mock local).
const String kAiPreviewDisclaimer =
    'Aperçu IA non contractuel — illustration d\'ambiance, ne représente '
    'pas le rendu technique du produit.';

/// Résultat d'une tentative de génération d'aperçu IA.
///
/// [model], [sku], [usedProductReference] et [productReferencePath] sont de
/// simples champs de PREUVE/TRAÇABILITÉ — lus tels quels dans la réponse
/// JSON déjà renvoyée par le proxy (`server/ai_render_proxy/server.js`,
/// NON modifié ici), jamais recalculés côté client. Permettent de
/// confirmer, y compris à l'écran (voir écran Avant/Après), que le bon
/// profil produit a bien servi de référence visuelle à la génération
/// (ex: sku=D609, usedProductReference=true,
/// productReferencePath=assets/profiles/control/D609.png).
class AiPreviewResult {
  final bool success;
  final Uint8List? imageBytes;
  final String? errorMessage;
  final String? model;
  final String? sku;
  final bool? usedProductReference;
  final String? productReferencePath;
  // P21-HYBRIDE — mode de rendu effectivement appliqué côté serveur
  // ('add' = corniche ajoutée depuis une photo brute, comportement
  // historique ; 'refine' = réalisme amélioré sur une corniche déjà
  // posée par le moteur dynamique). Simple champ de traçabilité, lu
  // tel quel dans la réponse JSON du proxy, jamais recalculé ici.
  final String? renderMode;
  const AiPreviewResult._({
    required this.success,
    this.imageBytes,
    this.errorMessage,
    this.model,
    this.sku,
    this.usedProductReference,
    this.productReferencePath,
    this.renderMode,
  });

  factory AiPreviewResult.ok(
    Uint8List bytes, {
    String? model,
    String? sku,
    bool? usedProductReference,
    String? productReferencePath,
    String? renderMode,
  }) =>
      AiPreviewResult._(
        success: true,
        imageBytes: bytes,
        model: model,
        sku: sku,
        usedProductReference: usedProductReference,
        productReferencePath: productReferencePath,
        renderMode: renderMode,
      );

  factory AiPreviewResult.fail(String message) =>
      AiPreviewResult._(success: false, errorMessage: message);
}

/// Construit le prompt positif — conservé pour usage MANUEL (pack de
/// prompts côté Genspark) et pour référence. Le prompt RÉELLEMENT
/// envoyé au modèle est reconstruit côté SERVEUR (voir
/// `server/ai_render_proxy/server.js` → `buildPrompt`), à partir d'un
/// gabarit fixe + du sku + des cotes lues sur disque : jamais ce texte
/// client qui n'est envoyé à aucun réseau.
String buildAiPreviewPrompt({
  required String ref,
  required String nom,
  required String famille,
  double? retombeeCm,
  double? avanceeCm,
}) {
  final cotes = (retombeeCm != null && avanceeCm != null)
      ? ' La corniche doit avoir une retombée murale d\'environ '
          '${retombeeCm.toStringAsFixed(0)} cm et une avancée au plafond '
          'd\'environ ${avanceeCm.toStringAsFixed(0)} cm.'
      : '';
  return 'Ajoute une moulure décorative Staff Décor $nom (référence $ref, '
      'famille $famille) dans cette pièce, le long de la jonction '
      'mur/plafond visible.$cotes Respecte strictement la perspective '
      'réelle de la pièce, les lignes de fuite, les proportions et '
      'l\'éclairage existant. Couleur staff blanc cassé / ivoire chaud, '
      'finition mate, relief subtil mais lisible. Ne modifie pas les '
      'meubles, luminaires, fenêtres, murs, sol, plafond, couleurs '
      'principales ni l\'ambiance générale. La moulure doit être intégrée '
      'naturellement, comme réellement posée en staff, pas comme une '
      'bande plate.';
}

/// Négatif-prompt générique — conservé pour référence (non envoyé au
/// modèle, voir note ci-dessus sur `buildPrompt` côté serveur).
const String kAiPreviewNegativePrompt =
    'corniche trop massive, blanc pur surexposé, dorure, moulure inventée, '
    'bande plate, changement du mobilier, changement du plafond, '
    'changement des ouvertures, texture plastique, rendu cartoon, aspect '
    'illustration, rendu 3D';

/// Cotes visuelles connues (cm) — issues de `assets/profiles/D609.json`
/// (`bbox_mm` : 186,963 × 196,482 mm). Conservé pour le pack de prompts
/// manuel / référence.
const Map<String, (double, double)> kKnownVisualDimsCm = {
  'D609': (19, 20),
};

/// Détecte le MIME réel à partir des octets magiques (PNG/JPEG), avec
/// repli sur JPEG par défaut — miroir de `detectMimeType` côté serveur,
/// utilisé ici uniquement pour renseigner le champ `mimeType` envoyé
/// (le serveur re-détecte de toute façon lui-même par sécurité).
String _guessMimeType(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  return 'image/jpeg';
}

/// Génère un aperçu d'ambiance IA réel via le proxy serveur (jamais la
/// clé côté client). Retourne un échec avec un message court si :
/// - la fonction est désactivée ([kAiPreviewEnabled] == false) ;
/// - le proxy est injoignable (réseau, timeout, DNS) ;
/// - Google/le proxy renvoie une erreur (429, 403, 500...) ;
/// - la réponse ne contient aucune image.
/// Ne lève jamais d'exception — toute erreur est convertie en
/// [AiPreviewResult.fail] avec un message utilisateur générique (le
/// détail technique reste uniquement dans les logs serveur, jamais
/// exposé au client).
/// [renderMode] — P21-HYBRIDE, whitelist stricte côté serveur (voir
/// `server.js` → `effectiveRenderMode`) :
///  - 'add' (défaut, inchangé) : [sceneImageBytes] est une photo BRUTE de
///    la pièce, Gemini doit AJOUTER la corniche $ref (comportement
///    historique P19-MANOBANANA-QAD) ;
///  - 'refine' (nouveau, P21-HYBRIDE) : [sceneImageBytes] est déjà un
///    rendu COMPOSÉ par le moteur dynamique déterministe (RoomPainter),
///    corniche déjà placée géométriquement — Gemini doit UNIQUEMENT
///    améliorer le réalisme photographique (matière, ombres, lumière),
///    sans déplacer/redimensionner/réinventer la corniche.
/// Ce champ n'est PAS un texte libre — seules ces deux valeurs fixes
/// sont acceptées, le serveur retombe sur 'add' pour toute autre valeur.
/// [httpClient] — point d'injection UNIQUEMENT pour les tests (voir
/// `test/data/ia_ambiance_preview_render_mode_test.dart`, qui utilise
/// `package:http/testing.dart` → `MockClient` pour vérifier le
/// `renderMode` réellement envoyé dans le corps JSON, SANS jamais
/// appeler le vrai réseau/proxy/Gemini). Null par défaut : le
/// comportement de production (client HTTP réel via `http.post`)
/// reste strictement inchangé pour tout appelant existant.
Future<AiPreviewResult> generateAiAmbiancePreview({
  required Uint8List sceneImageBytes,
  required String ref,
  required String nom,
  required String famille,
  String renderMode = 'add',
  http.Client? httpClient,
}) async {
  if (!kAiPreviewEnabled) {
    return AiPreviewResult.fail(kAiPreviewErrorDisabled);
  }

  final uri = Uri.parse('$kAiRenderProxyBaseUrl/api/ai-render');
  final body = jsonEncode({
    'imageBase64': base64Encode(sceneImageBytes),
    'mimeType': _guessMimeType(sceneImageBytes),
    'sku': ref,
    'renderMode': renderMode,
  });

  http.Response resp;
  try {
    final future = httpClient != null
        ? httpClient.post(uri, headers: const {'Content-Type': 'application/json'}, body: body)
        : http.post(uri, headers: const {'Content-Type': 'application/json'}, body: body);
    resp = await future.timeout(const Duration(seconds: 45));
  } catch (_) {
    // Timeout, DNS, connexion refusée, etc. — jamais de détail réseau
    // brut affiché à l'utilisateur final.
    return AiPreviewResult.fail(kAiPreviewErrorProxyUnreachable);
  }

  Map<String, dynamic>? json;
  try {
    json = jsonDecode(resp.body) as Map<String, dynamic>;
  } catch (_) {
    return AiPreviewResult.fail(kAiPreviewErrorGenerationFailed);
  }

  if (resp.statusCode != 200 || json['ok'] != true) {
    // Le message technique (Google 429/403/etc.) reste dans les logs
    // implicites de la requête HTTP ; l'utilisateur final ne voit que
    // le message court générique.
    return AiPreviewResult.fail(kAiPreviewErrorGenerationFailed);
  }

  final imageBase64 = json['imageBase64'] as String?;
  if (imageBase64 == null || imageBase64.isEmpty) {
    return AiPreviewResult.fail(kAiPreviewErrorGenerationFailed);
  }

  try {
    final bytes = base64Decode(imageBase64);
    // Champs de preuve/traçabilité — déjà présents dans la réponse JSON
    // du proxy (server.js, non modifié), simplement lus ici pour
    // vérification (ex: sku=D609, usedProductReference=true,
    // productReferencePath=assets/profiles/control/D609.png) et pour
    // affichage sur l'écran Avant/Après.
    return AiPreviewResult.ok(
      bytes,
      model: json['model'] as String?,
      sku: json['sku'] as String?,
      usedProductReference: json['usedProductReference'] as bool?,
      productReferencePath: json['productReferencePath'] as String?,
      renderMode: json['renderMode'] as String?,
    );
  } catch (_) {
    return AiPreviewResult.fail(kAiPreviewErrorGenerationFailed);
  }
}
