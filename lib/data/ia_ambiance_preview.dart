/// P19-MANOBANANA-QAD (clôturé) — "Aperçu d'ambiance IA".
///
/// ⚠️ HISTORIQUE, POUR LE PROCHAIN LECTEUR : cette passe a exploré
/// l'intégration d'un rendu IA réel via un proxy serveur portant la clé
/// côté serveur (jamais côté client Flutter — ce principe reste
/// intégralement valide et devra être repris tel quel le jour où un
/// provider exploitable sera confirmé). Trois voies ont été testées et
/// **aucune n'est actuellement exploitable** :
///
///  1. Gemini (`gemini-3.1-flash-image` via generateContent) : la clé
///     fournie a été RECONNUE par Google (projet réel identifié), mais
///     le quota `generate_content_free_tier_requests` est à **0** sur ce
///     projet pour ce modèle → HTTP 429 systématique. Le proxy testé a
///     bien confirmé le principe (health check OK, aucune fuite de clé
///     dans les logs/réponses), mais aucune image n'a pu être générée.
///  2. OpenAI (`images/edits`) : aucune clé OpenAI personnelle
///     disponible dans cet environnement. `OPENAI_API_KEY` existe bien
///     dans l'environnement sandbox, mais elle pointe vers le proxy LLM
///     INTERNE de la plateforme Genspark (`OPENAI_BASE_URL=.../llm_proxy/v1`,
///     préfixe `gsk-...`), qui n'expose QUE des modèles texte/code
///     (55 modèles listés via `/models` — GPT-5.x, Claude, DeepSeek,
///     Grok, etc., zéro modèle image) — vérifié, donc explicitement
///     écarté, jamais utilisé pour ce module.
///  3. Genspark (infra plateforme) : hors périmètre par consigne
///     explicite — jamais utilisé comme provider applicatif pour ce
///     module, quelle que soit sa disponibilité technique.
///
/// **Décision** : clôture de l'intégration réelle. [kAiPreviewEnabled]
/// reste figé à `false`. Aucun bouton actif côté client ne promet un
/// rendu IA réel tant qu'un provider n'a pas été validé de bout en bout
/// (clé + quota + génération réussie). Le proxy serveur créé pendant
/// cette passe (`server/manobanana_proxy/`) a été supprimé du dépôt
/// (jamais poussé — commits locaux uniquement, vérifiés sans secret) ;
/// aucune clé n'a jamais été committée. Court terme retenu : un pack de
/// prompts manuels (texte, ci-dessous) à utiliser côté Genspark
/// directement par un opérateur humain, hors app.
///
/// PÉRIMÈTRE INCHANGÉ (hérité de P17-VISUEL, toujours respecté) :
///  - ne s'active QUE pour les refs de `assets/profiles/index.json` ;
///  - l'image générée reste UNIQUEMENT en mémoire ([Uint8List]) ;
///  - ce module ne touche ni au moteur perspective ni aux presets.
library;

import 'dart:typed_data';

/// POINT UNIQUE DE RÉVERSIBILITÉ. Reste `false` : aucun provider image
/// exploitable n'a été validé à ce jour (voir historique ci-dessus).
/// Ne DOIT passer à `true` que juste après qu'une génération réelle a été
/// testée avec succès (clé + quota + réseau + réponse image valide).
const bool kAiPreviewEnabled = false;

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

/// Résultat d'une tentative de génération d'aperçu IA. Conservé pour
/// compatibilité avec l'appelant UI, même si [generateAiAmbiancePreview]
/// renvoie désormais toujours un échec (fonction non exploitable).
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

/// Construit le prompt positif — conservé pour usage MANUEL (pack de
/// prompts côté Genspark, court terme retenu), et pour readiness future
/// si un provider devient exploitable. N'est appelé par AUCUN chemin
/// réseau actuellement (fonction pure, aucune I/O).
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

/// Négatif-prompt générique — conservé pour le même usage manuel que
/// [buildAiPreviewPrompt] ci-dessus.
const String kAiPreviewNegativePrompt =
    'corniche trop massive, blanc pur surexposé, dorure, moulure inventée, '
    'bande plate, changement du mobilier, changement du plafond, '
    'changement des ouvertures, texture plastique, rendu cartoon, aspect '
    'illustration, rendu 3D';

/// Cotes visuelles connues (cm) — issues de `assets/profiles/D609.json`
/// (`bbox_mm` : 186,963 × 196,482 mm). Conservé pour le pack de prompts
/// manuel.
const Map<String, (double, double)> kKnownVisualDimsCm = {
  'D609': (19, 20),
};

/// Toujours un échec — AUCUN provider image exploitable actuellement
/// (voir historique en tête de fichier). Ne lève jamais d'exception,
/// ne fait plus AUCUN appel réseau depuis la clôture de cette passe.
Future<AiPreviewResult> generateAiAmbiancePreview({
  required Uint8List sceneImageBytes,
  required String ref,
  required String nom,
  required String famille,
}) async {
  return AiPreviewResult.fail(kAiPreviewErrorDisabled);
}
