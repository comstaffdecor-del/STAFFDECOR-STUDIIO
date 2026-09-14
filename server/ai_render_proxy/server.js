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
// Repertoire des images de reference visuelle produit (control/<sku>.png)
const PRODUCT_CONTROL_DIR = path.join(PROFILES_DIR, 'control');

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
 *
 * Version 2 (durcie, anglaise) - validee empiriquement le 14/09 sur
 * moderne.jpg + assets/profiles/control/D609.png (2 images en entree) :
 * seule cette combinaison (prompt directif + image de reference produit
 * en 2eme position) produit une corniche visiblement ajoutee. Le gabarit
 * francais precedent (1 seule image, pas de reference visuelle) degenerait
 * systematiquement en quasi-copie/resize de l'image source, y compris avec
 * le modele non-lite.
 *
 * hasProductRef=true : mentionne la SECOND image (reference visuelle du
 * produit) - utilise seulement quand assets/profiles/control/<sku>.png
 * existe reellement et est effectivement envoye a Gemini.
 * hasProductRef=false : fallback sans reference visuelle (comportement
 * degrade, documente comme moins fiable - voir usedProductReference dans
 * la reponse JSON).
 */
function buildPrompt(sku, retombeeCm, avanceeCm, hasProductRef) {
  if (hasProductRef) {
    return (
      `Edit the FIRST image, which is the room photo.\n` +
      `Add a clearly visible white plaster crown moulding / cornice ${sku} along the entire wall-ceiling junction.\n` +
      `Use the SECOND image as the product reference for the shape and relief of ${sku}.\n` +
      `The cornice must be visibly added to the room, not merely preserve the original image.\n` +
      `It must have approximately ${retombeeCm} cm wall drop and ${avanceeCm} cm ceiling projection, with realistic shadows and molded relief.\n` +
      `Preserve the room, furniture, lighting, people, perspective, camera angle, and all existing objects.\n` +
      `Do not redesign the room.\n` +
      `Do not change the furniture.\n` +
      `Do not crop the image unnecessarily.\n` +
      `The only meaningful change should be the added ${sku} plaster cornice at the wall-ceiling junction.\n` +
      `If the original image has no cornice, add one clearly.\n` +
      `Return the edited room image.`
    );
  }
  // Fallback sans reference visuelle produit (moins fiable - voir docstring).
  return (
    `Edit this room photo.\n` +
    `Add a clearly visible white plaster crown moulding / cornice ${sku} along the entire wall-ceiling junction.\n` +
    `The cornice must be visibly added to the room, not merely preserve the original image.\n` +
    `It must have approximately ${retombeeCm} cm wall drop and ${avanceeCm} cm ceiling projection, with realistic shadows and molded relief.\n` +
    `Preserve the room, furniture, lighting, people, perspective, camera angle, and all existing objects.\n` +
    `Do not redesign the room.\n` +
    `Do not change the furniture.\n` +
    `Do not crop the image unnecessarily.\n` +
    `The only meaningful change should be the added ${sku} plaster cornice at the wall-ceiling junction.\n` +
    `If the original image has no cornice, add one clearly.\n` +
    `Return the edited room image.`
  );
}

/**
 * Tente de charger l'image de reference visuelle du produit
 * (assets/profiles/control/<sku>.png). Retourne null si absente,
 * ne leve jamais d'exception (fallback documente, pas de crash).
 */
function loadProductReferenceImage(sku) {
  if (!sku || typeof sku !== 'string' || !/^[A-Za-z0-9_-]+$/.test(sku)) {
    return null;
  }
  const filePath = path.join(PRODUCT_CONTROL_DIR, `${sku}.png`);
  if (!fs.existsSync(filePath)) {
    return null;
  }
  try {
    const buffer = fs.readFileSync(filePath);
    return {
      base64: buffer.toString('base64'),
      mimeType: detectMimeType(buffer, 'image/png'),
      path: filePath,
    };
  } catch (readErr) {
    console.error(`[ai-render] Erreur lecture reference produit sku=${sku}: ${readErr.message}`);
    return null;
  }
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

    // --- Reference visuelle produit (2eme image envoyee a Gemini) ---
    // Chargee automatiquement depuis assets/profiles/control/<sku>.png si
    // le fichier existe. Absence = fallback documente (voir buildPrompt),
    // jamais un crash. Pour D609, le fichier existe -> usedProductReference=true.
    const productRef = loadProductReferenceImage(sku);
    const usedProductReference = Boolean(productRef);

    // Le prompt cote serveur est TOUJOURS reconstruit a partir du gabarit fixe.
    // clientPrompt (si fourni) n'est pas utilise pour l'appel reel - evite qu'un
    // client injecte un texte arbitraire vers l'API payante. negativePrompt
    // (si present dans req.body) est ignore par design (voir en-tete du fichier).
    const finalPrompt = buildPrompt(sku, retombeeCm, avanceeCm, usedProductReference);
    void clientPrompt; // explicitement non utilise

    const inputBuffer = Buffer.from(imageBase64, 'base64');
    const realMimeType = detectMimeType(inputBuffer, mimeType);

    // Ordre des parts : texte, PUIS FIRST image (room photo), PUIS SECOND
    // image (reference produit) si disponible - cet ordre correspond
    // exactement a celui du test manuel valide le 14/09 (moderne.jpg +
    // control/D609.png, gemini-3.1-flash-image) qui a produit une corniche
    // visiblement ajoutee, contrairement au mode 1-image qui degenerait en
    // quasi-copie/resize.
    const geminiParts = [
      { text: finalPrompt },
      { inline_data: { mime_type: realMimeType, data: imageBase64 } },
    ];
    if (productRef) {
      geminiParts.push({
        inline_data: { mime_type: productRef.mimeType, data: productRef.base64 },
      });
    }

    const geminiBody = {
      contents: [{
        parts: geminiParts,
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

    console.log(`[ai-render] OK sku=${sku} model=${MODEL} usedProductReference=${usedProductReference} durationMs=${Date.now() - startedAt}`);
    return res.json({
      ok: true,
      provider: 'gemini',
      mode: 'real',
      model: MODEL,
      sku,
      imageBase64: outData,
      mimeType: outMime || 'image/jpeg',
      usedProductReference,
      productReferencePath: productRef ? path.relative(path.join(__dirname, '..', '..'), productRef.path) : null,
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
