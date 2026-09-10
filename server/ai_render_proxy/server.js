/**
 * P19-MANOBANANA-QAD - Proxy serveur pour rendu IA de corniches
 * ===============================================================
 *
 * REGLE DE SECURITE ABSOLUE : GEMINI_API_KEY vit UNIQUEMENT dans
 * process.env, cote serveur. Elle n'est JAMAIS :
 *   - loggee (console.log, console.error...)
 *   - renvoyee dans une reponse HTTP
 *   - ecrite dans un fichier
 *   - passee dans une URL (toujours via le header x-goog-api-key)
 *
 * Le client Flutter ne connait QUE l'URL de ce proxy, jamais la cle.
 *
 * Endpoint reel utilise (documente publiquement) :
 *   POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
 *
 * Construction du prompt :
 *   Le texte envoye a Gemini est un gabarit FIXE avec deux variables
 *   uniquement : la reference produit (sku) et ses cotes visuelles
 *   (retombee murale / avancee plafond en cm), lues dynamiquement
 *   depuis assets/profiles/<sku>.json (bbox_mm.h et bbox_mm.w,
 *   arrondies au centimetre). Rien n'est code en dur pour un SKU
 *   particulier - le meme gabarit sert pour n'importe quelle
 *   reference presente dans assets/profiles/.
 *
 * Pas de bloc negatif :
 *   generateContent n'a pas de champ negativePrompt. Le payload
 *   entrant peut contenir un champ negativePrompt (compatibilite
 *   avec l'ancien contrat), mais il est explicitement IGNORE et
 *   JAMAIS concatene dans le texte envoye a Gemini - une liste
 *   d'interdits serait lue par le modele comme une consigne
 *   positive. Les contraintes "ne pas modifier le reste de la
 *   piece" sont formulees en affirmatif dans le gabarit fixe.
 */

require('dotenv').config();

const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.AI_RENDER_PROXY_PORT || 8091;

// Repertoire des profils produits (source de verite pour les cotes visuelles)
const PROFILES_DIR = path.join(__dirname, '..', '..', 'assets', 'profiles');

const MODEL = process.env.MANOBANANA_MODEL || 'gemini-3.1-flash-lite-image';
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

// ---------------------------------------------------------------
// Middlewares
// ---------------------------------------------------------------

app.use(cors());
app.options('*', cors());

// Limite de taille de corps explicite (images en base64 -> volumineux,
// mais on borne pour eviter les abus / OOM du process proxy)
app.use(express.json({ limit: '20mb' }));

// ---------------------------------------------------------------
// Utilitaires
// ---------------------------------------------------------------

/**
 * Lit assets/profiles/<sku>.json et retourne les cotes visuelles
 * arrondies au centimetre : { retombeeCm, avanceeCm }.
 * bbox_mm.h -> retombee murale (hauteur visuelle)
 * bbox_mm.w -> avancee plafond (largeur visuelle)
 * Leve une erreur explicite si le fichier ou les champs sont absents.
 */
function loadProductDimensions(sku) {
  if (!sku || typeof sku !== 'string' || !/^[A-Za-z0-9_-]+$/.test(sku)) {
    throw new Error(`SKU invalide: ${JSON.stringify(sku)}`);
  }
  const filePath = path.join(PROFILES_DIR, `${sku}.json`);
  if (!fs.existsSync(filePath)) {
    throw new Error(`Profil introuvable pour sku="${sku}" (attendu: ${filePath})`);
  }
  const raw = fs.readFileSync(filePath, 'utf-8');
  const data = JSON.parse(raw);
  const bbox = data.bbox_mm;
  if (!bbox || typeof bbox.w !== 'number' || typeof bbox.h !== 'number') {
    throw new Error(`Champ bbox_mm.w/bbox_mm.h absent ou invalide pour sku="${sku}"`);
  }
  return {
    retombeeCm: Math.round(bbox.h / 10),
    avanceeCm: Math.round(bbox.w / 10),
  };
}

/**
 * Construit le texte de prompt (gabarit fixe, variables = sku + cotes).
 * AUCUN bloc negatif n'est jamais ajoute ici, meme si negativePrompt
 * est present dans le payload entrant - il est ignore par design.
 */
function buildPrompt(sku, retombeeCm, avanceeCm) {
  return (
    `Édite cette photo d'intérieur en conservant exactement la pièce d'origine. ` +
    `Ajoute uniquement une corniche décorative Staff Décor ${sku} le long de la jonction mur/plafond visible.\n\n` +
    `La corniche est un vrai profil de staff en plâtre mouluré, avec un volume architectural marqué : ` +
    `environ ${retombeeCm} cm de retombée sur le mur et ${avanceeCm} cm d'avancée sous le plafond, ` +
    `soit une corniche imposante qui occupe une part nettement visible de la hauteur du mur, ` +
    `comme une corniche de rénovation intérieure haut de gamme. Le profil présente des formes moulurées, ` +
    `des courbes douces, des creux et des arêtes, avec des ombres portées naturelles cohérentes avec ` +
    `l'éclairage réel de la pièce.\n\n` +
    `La corniche est peinte exactement du même blanc mat que le plafond existant de cette pièce, ` +
    `ton sur ton avec lui, en peinture plâtre mate.\n\n` +
    `La corniche est intégrée dans la perspective réelle de la prise de vue, suit les lignes de fuite ` +
    `et se pose précisément à la jonction entre les murs et le plafond, en continu sur tous les angles visibles.\n\n` +
    `Tout le reste de l'image demeure strictement identique à l'original : mobilier, fenêtres, rideaux, ` +
    `luminaires, sol, murs, plafond, couleurs, décoration, ambiance lumineuse et cadrage. ` +
    `Conserve les dimensions et le format exacts de l'image source.`
  );
}

/**
 * Detecte le type MIME reel a partir des octets magiques (PNG/JPEG),
 * en fallback sur la valeur declaree par le client.
 */
function detectMimeType(buffer, declaredMime) {
  if (buffer.length >= 8 &&
      buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4E && buffer[3] === 0x47) {
    return 'image/png';
  }
  if (buffer.length >= 3 && buffer[0] === 0xFF && buffer[1] === 0xD8 && buffer[2] === 0xFF) {
    return 'image/jpeg';
  }
  return declaredMime || 'image/jpeg';
}

// ---------------------------------------------------------------
// Routes
// ---------------------------------------------------------------

app.get('/health', (req, res) => {
  res.json({
    ok: true,
    service: 'ai_render_proxy',
    provider: 'gemini',
    model: MODEL,
    hasGeminiKey: Boolean(process.env.GEMINI_API_KEY),
  });
});

app.post('/api/ai-render', async (req, res) => {
  const startedAt = Date.now();
  try {
    const { imageBase64, mimeType, sku, prompt: clientPrompt } = req.body || {};

    if (!imageBase64 || typeof imageBase64 !== 'string') {
      return res.status(400).json({ ok: false, provider: 'gemini', error: 'imageBase64 manquant ou invalide' });
    }
    if (!sku || typeof sku !== 'string') {
      return res.status(400).json({ ok: false, provider: 'gemini', error: 'sku manquant ou invalide' });
    }

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      // Jamais de log de la cle - ici il n'y en a simplement pas.
      return res.status(503).json({
        ok: false,
        provider: 'gemini',
        mode: 'disabled',
        error: 'GEMINI_API_KEY missing',
      });
    }

    // --- Construction du prompt : variables = sku + cotes lues sur disque ---
    let retombeeCm, avanceeCm;
    try {
      const dims = loadProductDimensions(sku);
      retombeeCm = dims.retombeeCm;
      avanceeCm = dims.avanceeCm;
    } catch (dimErr) {
      return res.status(400).json({
        ok: false,
        provider: 'gemini',
        error: `Dimensions produit indisponibles: ${dimErr.message}`,
      });
    }

    // Le prompt cote serveur est TOUJOURS reconstruit a partir du gabarit fixe.
    // clientPrompt (si fourni) n'est pas utilise pour l'appel reel - evite qu'un
    // client injecte un texte arbitraire vers l'API payante. negativePrompt
    // (si present dans req.body) est ignore par design (voir en-tete du fichier).
    const finalPrompt = buildPrompt(sku, retombeeCm, avanceeCm);
    void clientPrompt; // explicitement non utilise

    const inputBuffer = Buffer.from(imageBase64, 'base64');
    const realMimeType = detectMimeType(inputBuffer, mimeType);

    const geminiBody = {
      contents: [{
        parts: [
          { text: finalPrompt },
          { inline_data: { mime_type: realMimeType, data: imageBase64 } },
        ],
      }],
      generationConfig: {
        responseModalities: ['IMAGE'],
      },
    };

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 30000);

    let geminiResp;
    try {
      geminiResp = await fetch(GEMINI_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: JSON.stringify(geminiBody),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeoutId);
    }

    const geminiJson = await geminiResp.json();

    if (!geminiResp.ok) {
      // On relaie le message d'erreur Google (texte), jamais les headers
      // (qui pourraient theoriquement contenir des infos internes), et
      // jamais la cle - qui n'apparait de toute facon pas dans une reponse
      // d'erreur Google standard.
      const errMessage = geminiJson?.error?.message || `Gemini API error (HTTP ${geminiResp.status})`;
      const errStatus = geminiJson?.error?.status || 'UNKNOWN';
      console.error(`[ai-render] Gemini error sku=${sku} httpStatus=${geminiResp.status} status=${errStatus} durationMs=${Date.now() - startedAt}`);
      return res.status(geminiResp.status).json({
        ok: false,
        provider: 'gemini',
        mode: 'real',
        error: errMessage,
        googleStatus: errStatus,
      });
    }

    // Extraction de l'image generee
    const candidates = geminiJson.candidates || [];
    let outData = null;
    let outMime = null;
    for (const c of candidates) {
      const parts = c?.content?.parts || [];
      for (const part of parts) {
        const inline = part.inlineData || part.inline_data;
        if (inline) {
          outData = inline.data;
          outMime = inline.mimeType || inline.mime_type;
        }
      }
    }

    if (!outData) {
      console.error(`[ai-render] Pas d'image dans la reponse Gemini sku=${sku} durationMs=${Date.now() - startedAt}`);
      return res.status(502).json({
        ok: false,
        provider: 'gemini',
        mode: 'real',
        error: 'Gemini n\'a retourné aucune image (réponse sans inlineData)',
      });
    }

    console.log(`[ai-render] OK sku=${sku} model=${MODEL} durationMs=${Date.now() - startedAt}`);
    return res.json({
      ok: true,
      provider: 'gemini',
      mode: 'real',
      model: MODEL,
      imageBase64: outData,
      mimeType: outMime || 'image/jpeg',
    });

  } catch (err) {
    // Jamais err complet si il pouvait par malheur contenir la cle (il ne devrait
    // jamais - la cle n'est utilisee que dans un header sortant), mais on reste
    // prudent et on ne logge que err.message.
    console.error(`[ai-render] Exception: ${err && err.message ? err.message : 'erreur inconnue'}`);
    return res.status(500).json({
      ok: false,
      provider: 'gemini',
      error: 'Erreur interne du proxy',
    });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[ai_render_proxy] Ecoute sur le port ${PORT} (model=${MODEL}, hasGeminiKey=${Boolean(process.env.GEMINI_API_KEY)})`);
});
