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

require('dotenv').config({ quiet: true });

const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const app = express();
const PORT = process.env.AI_RENDER_PROXY_PORT || 8091;

// Repertoire des profils produits (source de verite pour les cotes visuelles)
const PROFILES_DIR = path.join(__dirname, '..', '..', 'assets', 'profiles');
// Repertoire des images de reference visuelle produit (control/<sku>.png)
const PRODUCT_CONTROL_DIR = path.join(PROFILES_DIR, 'control');

const MODEL = process.env.MANOBANANA_MODEL || 'gemini-3.1-flash-lite-image';
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

// ---------------------------------------------------------------
// Quotas serveur (issue #2) : IP/jour + global/jour, fail-closed en
// cas d'erreur de lecture du store. Jamais de cle/secret dans ce
// store - uniquement des compteurs et des hash d'IP (jamais l'IP en
// clair).
// ---------------------------------------------------------------

const AI_QUOTA_ENABLED = process.env.AI_QUOTA_ENABLED !== 'false';

/**
 * Log JSON minimal utilisable AVANT la declaration du logger principal
 * (utilise ici uniquement pour signaler une config d'env invalide au
 * demarrage, avant que le reste du fichier soit charge).
 */
function bootLogJson(payload) {
  console.log(JSON.stringify(payload));
}

/**
 * Parse une variable d'env en entier positif, avec fallback EXPLICITE
 * (et logge) vers defaultValue si la valeur est absente, vide, non
 * numerique, non entiere ou negative. Empeche un cas silencieux du
 * type AI_DAILY_GLOBAL_LIMIT=abc -> Number(...) -> NaN -> toute
 * comparaison avec NaN est toujours false -> quota jamais applique
 * sans qu'aucune erreur ne soit visible.
 */
function parsePositiveIntegerEnv(name, defaultValue) {
  const raw = process.env[name];

  if (raw === undefined || raw === '') {
    return defaultValue;
  }

  const value = Number(raw);

  if (!Number.isFinite(value) || !Number.isInteger(value) || value < 0) {
    bootLogJson({
      event: 'ai_quota_config_invalid',
      name,
      rawValue: raw,
      fallbackValue: defaultValue,
    });
    return defaultValue;
  }

  return value;
}

const AI_DAILY_IP_LIMIT = parsePositiveIntegerEnv('AI_DAILY_IP_LIMIT', 10);

const AI_DAILY_GLOBAL_LIMIT = parsePositiveIntegerEnv('AI_DAILY_GLOBAL_LIMIT', 100);

const AI_QUOTA_STORE_PATH =
  process.env.AI_QUOTA_STORE_PATH ||
  path.join(__dirname, '.ai_quota_store.json');

const AI_QUOTA_IP_HASH_SALT =
  process.env.AI_QUOTA_IP_HASH_SALT ||
  'staffdecor-ai-demo-quota-salt';

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
/**
 * P21-HYBRIDE - Gabarit fixe pour le mode "refine" (rendu hybride).
 *
 * Contexte : contrairement au mode "add" (buildPrompt ci-dessous), qui
 * demande a Gemini d'AJOUTER une corniche a partir d'une photo brute
 * (l'IA doit alors deviner seule la position, la ligne, l'echelle -
 * source d'incoherences visuelles constatees en test reel), ce mode
 * recoit en FIRST image une image DEJA COMPOSEE par le moteur de rendu
 * deterministe (RoomPainter/cornice_plinth_painter, cote client) : la
 * corniche ${sku} y est deja placee geometriquement (bonne ligne
 * plafond/mur, bonne perspective, bon positionnement), mais avec un
 * rendu visuellement trop artificiel/plat pour etre montre tel quel.
 *
 * Le role de Gemini ici n'est PAS de replacer/reinventer la corniche -
 * seulement d'en ameliorer le realisme photographique (matiere platre,
 * ombres, integration lumineuse). Gabarit fixe, aucune variable libre
 * cote client (meme principe que buildPrompt : sku + cotes lues sur
 * disque uniquement).
 */
function buildRefinePrompt(sku, retombeeCm, avanceeCm) {
  return (
    `Edit the FIRST image. It already shows a white plaster crown moulding / cornice ${sku} ` +
    `correctly placed along the wall-ceiling junction by a geometric rendering engine.\n` +
    `Use the SECOND image only as a material/texture reference for ${sku} (plaster relief, profile detail).\n` +
    `Improve ONLY the photographic realism of the already-placed cornice: plaster material texture, ` +
    `contact shadows, ambient light integration, and how it blends with the room lighting.\n` +
    `Do NOT move the cornice. Do NOT resize it. Do NOT change its position, angle, length, wall drop ` +
    `(approx ${retombeeCm} cm) or ceiling projection (approx ${avanceeCm} cm).\n` +
    `Do NOT redesign, invent, or reinterpret the cornice shape - keep its exact silhouette and placement ` +
    `from the FIRST image unchanged.\n` +
    `Do not change the room, furniture, walls, floor, windows, perspective, camera angle or lighting color.\n` +
    `Do not crop the image.\n` +
    `The only meaningful change should be a more realistic, natural, photographic rendering of the ` +
    `${sku} cornice that is already in place.\n` +
    `${WINDOW_PRESERVATION_BLOCK}\n` +
    `${GEOMETRY_PRESERVATION_BLOCK}\n` +
    `Return the edited room image.`
  );
}

/**
 * P22-FENETRES-STL - Blocs de contraintes ajoutes au prompt (brief du
 * 15/09) suite au retour "Mano ne reconnait pas bien les fenetres et les
 * vues STL / produits ne sont pas bien interpretees". Textes EXACTS
 * fournis par le brief (EN + FR concatenes, aucune reformulation) :
 * on envoie les deux langues au modele pour maximiser la robustesse de
 * comprehension, le gabarit restant par ailleurs entierement fixe (pas
 * de variable libre cote client au-dela de sku/cotes, cf. docstring
 * en tete de fichier).
 */
const WINDOW_PRESERVATION_BLOCK =
  `Preserve all windows, glass doors, curtains, shutters and openings exactly as in the source image.\n` +
  `Do not cover, remove, duplicate, move or reinterpret windows.\n` +
  `Do not add decorative moulding across windows, glass panes, curtains or openings.\n` +
  `Treat windows and openings as architectural obstacles.\n` +
  `The decorative product must follow only the existing wall/ceiling boundary and stop cleanly before openings if necessary.\n` +
  `Conserver toutes les fenetres, portes vitrees, rideaux, volets et ouvertures exactement comme sur l'image source.\n` +
  `Ne pas couvrir, supprimer, dupliquer, deplacer ou transformer les fenetres.\n` +
  `Ne pas placer la moulure sur les vitres, rideaux ou ouvertures.\n` +
  `Considerer les fenetres comme des obstacles architecturaux.\n` +
  `Le produit decoratif doit suivre uniquement la jonction mur/plafond existante et s'interrompre proprement si une ouverture gene.`;

const GEOMETRY_PRESERVATION_BLOCK =
  `Preserve the original room geometry exactly.\n` +
  `Do not create new walls, recesses, alcoves, false ceilings, beams, ledges, columns, openings or protrusions.\n` +
  `Do not change the shape of corners, ceiling lines, wall edges or perspective.\n` +
  `Only add the selected decorative moulding/product.`;

const STL_REFERENCE_ONLY_BLOCK =
  `The STL/reference image is only a product shape reference.\n` +
  `Do not render it as a floating 3D object.\n` +
  `Do not copy the raw technical STL look.\n` +
  `Convert the product into a realistic installed white/off-white decorative moulding integrated into the room.\n` +
  `La vue STL/reference produit sert uniquement a comprendre la forme du produit.\n` +
  `Ne pas afficher un objet 3D flottant.\n` +
  `Ne pas reproduire l'aspect technique brut du STL.\n` +
  `Transformer le produit en moulure decorative blanche/blanc casse, posee naturellement dans la piece.`;

function buildPrompt(sku, retombeeCm, avanceeCm, hasProductRef) {
  // P22-FENETRES-STL - rendu attendu : naturel mais strict (blanc/blanc
  // casse, adapte a la lumiere reelle de la piece, ombres douces,
  // perspective respectee, grain photo conserve). Interdit : aspect
  // plastique, corniche trop blanche/brulee, detachement visuel.
  const renderQualityBlock =
    `The final render must look natural but precise: white/off-white plaster, ` +
    `matched to the real light of the room, soft realistic shadows, respected perspective, ` +
    `and the original photo grain/texture preserved.\n` +
    `Do not render a plastic-looking or overly-white/burnt-out cornice.\n` +
    `The added product must look physically attached to the wall/ceiling, never visually detached or floating.`;

  if (hasProductRef) {
    return (
      `Edit the FIRST image, which is the room photo.\n` +
      `Add a clearly visible white plaster crown moulding / cornice ${sku} along the entire wall-ceiling junction.\n` +
      `Use the SECOND image as the product reference for the shape and relief of ${sku}.\n` +
      `${STL_REFERENCE_ONLY_BLOCK}\n` +
      `The cornice must be visibly added to the room, not merely preserve the original image.\n` +
      `It must have approximately ${retombeeCm} cm wall drop and ${avanceeCm} cm ceiling projection, with realistic shadows and molded relief.\n` +
      `Preserve the room, furniture, lighting, people, perspective, camera angle, and all existing objects.\n` +
      `Do not redesign the room.\n` +
      `Do not change the furniture.\n` +
      `Do not crop the image unnecessarily.\n` +
      `${WINDOW_PRESERVATION_BLOCK}\n` +
      `${GEOMETRY_PRESERVATION_BLOCK}\n` +
      `${renderQualityBlock}\n` +
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
    `${WINDOW_PRESERVATION_BLOCK}\n` +
    `${GEOMETRY_PRESERVATION_BLOCK}\n` +
    `${renderQualityBlock}\n` +
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
// Helpers quota
// ---------------------------------------------------------------

function quotaDayKey(now = new Date()) {
  return now.toISOString().slice(0, 10); // UTC YYYY-MM-DD
}

function getClientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim().length > 0) {
    return forwarded.split(',')[0].trim();
  }

  const realIp = req.headers['x-real-ip'];
  if (typeof realIp === 'string' && realIp.trim().length > 0) {
    return realIp.trim();
  }

  return req.socket?.remoteAddress || 'unknown';
}

function hashIp(ip) {
  return crypto
    .createHash('sha256')
    .update(`${AI_QUOTA_IP_HASH_SALT}:${ip}`)
    .digest('hex')
    .slice(0, 24);
}

function emptyQuotaStore() {
  return {
    day: quotaDayKey(),
    globalCount: 0,
    byIpHash: {},
  };
}

function readQuotaStore() {
  try {
    if (!fs.existsSync(AI_QUOTA_STORE_PATH)) {
      return emptyQuotaStore();
    }

    const raw = fs.readFileSync(AI_QUOTA_STORE_PATH, 'utf8');
    const parsed = JSON.parse(raw);

    if (!parsed || parsed.day !== quotaDayKey()) {
      return emptyQuotaStore();
    }

    if (typeof parsed.globalCount !== 'number') {
      parsed.globalCount = 0;
    }

    if (!parsed.byIpHash || typeof parsed.byIpHash !== 'object') {
      parsed.byIpHash = {};
    }

    return parsed;
  } catch (err) {
    console.error(
      JSON.stringify({
        event: 'ai_quota_store_read_error',
        error: String(err?.message || err),
      }),
    );

    // fail closed quand quota active
    throw err;
  }
}

function writeQuotaStore(store) {
  const tmp = `${AI_QUOTA_STORE_PATH}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(store, null, 2));
  fs.renameSync(tmp, AI_QUOTA_STORE_PATH);
}

function reserveAiQuota(req, meta = {}) {
  if (!AI_QUOTA_ENABLED) {
    return {
      ok: true,
      quotaEnabled: false,
      ipHash: null,
      globalCount: null,
      ipCount: null,
    };
  }

  const ip = getClientIp(req);
  const ipHash = hashIp(ip);

  const store = readQuotaStore();

  const ipCount = store.byIpHash[ipHash] || 0;
  const globalCount = store.globalCount || 0;

  if (AI_DAILY_GLOBAL_LIMIT >= 0 && globalCount >= AI_DAILY_GLOBAL_LIMIT) {
    return {
      ok: false,
      status: 429,
      code: 'AI_GLOBAL_DAILY_QUOTA_EXCEEDED',
      message: 'Quota IA global journalier atteint.',
      ipHash,
      globalCount,
      ipCount,
      globalLimit: AI_DAILY_GLOBAL_LIMIT,
      ipLimit: AI_DAILY_IP_LIMIT,
    };
  }

  if (AI_DAILY_IP_LIMIT >= 0 && ipCount >= AI_DAILY_IP_LIMIT) {
    return {
      ok: false,
      status: 429,
      code: 'AI_IP_DAILY_QUOTA_EXCEEDED',
      message: 'Quota IA journalier atteint pour cette adresse.',
      ipHash,
      globalCount,
      ipCount,
      globalLimit: AI_DAILY_GLOBAL_LIMIT,
      ipLimit: AI_DAILY_IP_LIMIT,
    };
  }

  store.globalCount = globalCount + 1;
  store.byIpHash[ipHash] = ipCount + 1;

  writeQuotaStore(store);

  return {
    ok: true,
    quotaEnabled: true,
    ipHash,
    globalCount: store.globalCount,
    ipCount: store.byIpHash[ipHash],
    globalLimit: AI_DAILY_GLOBAL_LIMIT,
    ipLimit: AI_DAILY_IP_LIMIT,
    ...meta,
  };
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
    quotaEnabled: AI_QUOTA_ENABLED,
  });
});

app.post('/api/ai-render', async (req, res) => {
  const startedAt = Date.now();
  // Declare AVANT le try : doit rester accessible dans le catch meme si
  // une erreur survient avant la ligne qui l'initialisait auparavant
  // (evite un ReferenceError dans le bloc catch en cas d'echec tres tot
  // dans le handler).
  let requestId = crypto.randomUUID();
  try {
    const { imageBase64, mimeType, sku, prompt: clientPrompt, renderMode } = req.body || {};

    if (!imageBase64 || typeof imageBase64 !== 'string') {
      return res.status(400).json({ ok: false, provider: 'gemini', error: 'imageBase64 manquant ou invalide' });
    }
    if (!sku || typeof sku !== 'string') {
      return res.status(400).json({ ok: false, provider: 'gemini', error: 'sku manquant ou invalide' });
    }

    const source = req.body?.source || 'unknown';
    const usedProductReferenceHint = Boolean(req.body?.productReferenceBase64);

    let quota;
    try {
      quota = reserveAiQuota(req, {
        requestId,
        sku,
        renderMode,
        source,
      });
    } catch (quotaErr) {
      console.error(
        JSON.stringify({
          event: 'ai_quota_error',
          requestId,
          status: 429,
          error: String(quotaErr?.message || quotaErr),
        }),
      );

      return res.status(429).json({
        ok: false,
        error: 'AI_QUOTA_UNAVAILABLE',
        message: 'Quota IA temporairement indisponible.',
        requestId,
      });
    }

    if (!quota.ok) {
      console.warn(
        JSON.stringify({
          event: 'ai_quota_rejected',
          requestId,
          status: 429,
          code: quota.code,
          ipHash: quota.ipHash,
          sku,
          renderMode,
          source,
          globalCount: quota.globalCount,
          ipCount: quota.ipCount,
          globalLimit: quota.globalLimit,
          ipLimit: quota.ipLimit,
        }),
      );

      return res.status(429).json({
        ok: false,
        error: quota.code,
        message: quota.message,
        requestId,
      });
    }

    console.log(
      JSON.stringify({
        event: 'ai_quota_reserved',
        requestId,
        ipHash: quota.ipHash,
        sku,
        renderMode,
        source,
        usedProductReferenceHint,
        globalCount: quota.globalCount,
        ipCount: quota.ipCount,
        globalLimit: quota.globalLimit,
        ipLimit: quota.ipLimit,
      }),
    );

    // P21-HYBRIDE - `renderMode` est une WHITELIST STRICTE a 2 valeurs
    // fixes, jamais un texte libre : 'add' (comportement historique
    // inchange, defaut) ou 'refine' (nouveau mode hybride, voir
    // buildRefinePrompt ci-dessus). Toute valeur hors de cette liste
    // retombe silencieusement sur 'add' - jamais de 400 bloquant pour ne
    // pas casser le flux existant si un ancien client n'envoie pas ce
    // champ. Ce n'est PAS un prompt arbitraire (voir clientPrompt,
    // toujours ignore ci-dessous) : seul le CHOIX du gabarit fixe varie.
    const effectiveRenderMode = renderMode === 'refine' ? 'refine' : 'add';

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

    // Le prompt cote serveur est TOUJOURS reconstruit a partir d'un gabarit
    // FIXE parmi 2 possibles (voir effectiveRenderMode ci-dessus) - jamais
    // depuis un texte libre client. clientPrompt (si fourni) n'est pas
    // utilise pour l'appel reel - evite qu'un client injecte un texte
    // arbitraire vers l'API payante. negativePrompt (si present dans
    // req.body) est ignore par design (voir en-tete du fichier).
    const finalPrompt = effectiveRenderMode === 'refine'
      ? buildRefinePrompt(sku, retombeeCm, avanceeCm)
      : buildPrompt(sku, retombeeCm, avanceeCm, usedProductReference);
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
      console.error(
        JSON.stringify({
          event: 'ai_render_error',
          requestId,
          sku,
          renderMode: effectiveRenderMode,
          source,
          model: MODEL,
          status: geminiResp.status,
          googleStatus: errStatus,
          durationMs: Date.now() - startedAt,
          quota: {
            globalCount: quota.globalCount,
            ipCount: quota.ipCount,
            globalLimit: quota.globalLimit,
            ipLimit: quota.ipLimit,
          },
        }),
      );
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
      console.error(
        JSON.stringify({
          event: 'ai_render_error',
          requestId,
          sku,
          renderMode: effectiveRenderMode,
          source,
          model: MODEL,
          status: 502,
          error: 'no_image_in_response',
          durationMs: Date.now() - startedAt,
          quota: {
            globalCount: quota.globalCount,
            ipCount: quota.ipCount,
            globalLimit: quota.globalLimit,
            ipLimit: quota.ipLimit,
          },
        }),
      );
      return res.status(502).json({
        ok: false,
        provider: 'gemini',
        mode: 'real',
        error: 'Gemini n\'a retourné aucune image (réponse sans inlineData)',
      });
    }

    console.log(
      JSON.stringify({
        event: 'ai_render_success',
        requestId,
        sku,
        renderMode: effectiveRenderMode,
        source,
        usedProductReference,
        productReferencePath: productRef ? path.relative(path.join(__dirname, '..', '..'), productRef.path) : null,
        model: MODEL,
        status: 200,
        durationMs: Date.now() - startedAt,
        quota: {
          globalCount: quota.globalCount,
          ipCount: quota.ipCount,
          globalLimit: quota.globalLimit,
          ipLimit: quota.ipLimit,
        },
      }),
    );
    return res.json({
      ok: true,
      provider: 'gemini',
      mode: 'real',
      model: MODEL,
      sku,
      renderMode: effectiveRenderMode,
      imageBase64: outData,
      mimeType: outMime || 'image/jpeg',
      usedProductReference,
      productReferencePath: productRef ? path.relative(path.join(__dirname, '..', '..'), productRef.path) : null,
    });

  } catch (err) {
    // Jamais err complet si il pouvait par malheur contenir la cle (il ne devrait
    // jamais - la cle n'est utilisee que dans un header sortant), mais on reste
    // prudent et on ne logge que err.message.
    console.error(
      JSON.stringify({
        event: 'ai_render_error',
        requestId,
        error: String(err && err.message ? err.message : 'erreur inconnue'),
        status: 500,
      }),
    );
    return res.status(500).json({
      ok: false,
      provider: 'gemini',
      error: 'Erreur interne du proxy',
    });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(
    JSON.stringify({
      event: 'ai_render_proxy_listening',
      port: PORT,
      model: MODEL,
      quotaEnabled: AI_QUOTA_ENABLED,
      dailyIpLimit: AI_DAILY_IP_LIMIT,
      dailyGlobalLimit: AI_DAILY_GLOBAL_LIMIT,
    }),
  );
});
