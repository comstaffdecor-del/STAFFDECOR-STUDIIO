# Démo contrôlée — Staff Décor Studio (parcours + checklist)

> **Périmètre de cette démo — à annoncer explicitement en amont**
>
> Cette démo présente le **parcours Studio de Staff Décor** : import/choix
> d'une photo de pièce, sélection de produits du **catalogue Staff Décor**
> (458 réfs, 9 familles, source `ged.staffdecor.fr`), rendu d'aperçu IA
> contrôlé, puis accès au devis.
>
> **🔒 Règle absolue — transparence totale du pipeline IA (Mano/Nano
> invisible côté utilisateur)** : dans le code, les commentaires et les
> logs serveur, les termes *"Mano"* / *"Nano"* / *"ManoBanana"* /
> *"P19-MANOBANANA-QAD"* / *"Gemini"* désignent le **pipeline / modèle IA
> image** utilisé en interne pour générer l'aperçu. **Ce vocabulaire ne
> doit JAMAIS apparaître dans l'UI, dans le déroulé présenté à
> l'utilisateur, ni être mentionné à l'oral pendant la démo** — le
> pipeline IA reste une brique interne totalement transparente, intégrée
> derrière le bouton/parcours "aperçu". L'utilisateur ne doit voir qu'un
> parcours Staff Décor Studio fluide : scène démo → sélection produit →
> preview IA → résultat → devis.
>
> - ✅ Wording public autorisé, déjà en place dans le code UI (vérifié,
>   aucune autre mention n'existe) : **"Aperçu IA"**, **"Générer un
>   aperçu IA"**, **"Aperçu d'ambiance IA"**, **"Génération de l'aperçu
>   IA…"**, **"Nouvel aperçu"**, **"Rendu technique"** (bascule
>   comparateur).
> - ❌ Jamais dans l'UI ni à l'oral : "Mano", "Nano", "ManoBanana",
>   "Gemini", "proxy", "modèle IA [nom]", ou tout détail d'infrastructure.
> - ❌ Cette démo n'intègre par ailleurs **aucune** marketplace/API
>   ManoMano (catalogue live, checkout, panier, branding officiel) — sujet
>   sans rapport avec le pipeline interne ci-dessus, mentionné ici
>   uniquement pour éviter toute confusion résiduelle sur le mot "Mano".
> - Les détails proxy/quota/modèle restent **exclusivement dans la
>   checklist interne** (§5-6 ci-dessous), jamais dans le discours ou
>   l'écran présentés à un public externe.

---

## 1. Parcours de démo recommandé (~5 min)

| # | Étape | Où / comment | Ce qu'on montre |
|---|---|---|---|
| 1 | Ouvrir **Studio** | Nav principale | Écran vide, prêt à recevoir une photo |
| 2 | Charger une **scène démo** | Bouton scène démo (icône pièce) → choisir un style | Voir §2 pour le choix recommandé — **ne pas importer une vraie photo en live**, les scènes démo sont pré-calibrées (géométrie/perspective déjà réglée), une photo importée à la volée ne l'est pas |
| 3 | Sélectionner un produit via **CatBar** | Bandeau catégories en bas du Studio → onglet famille → tap sur une vignette produit | Le produit s'ajoute instantanément au projet (tap court = sélection directe) |
| 4 | Déclencher l'**aperçu IA** | Automatique ~1.5s après sélection (debounce), mode STANDARD/add uniquement — voir §3 | Rendu IA du produit posé sur la scène |
| 5 | Aller au **Devis** | Bouton "Devis" dans la topbar (scroll horizontal si écran étroit) | ⚠️ Voir §4 — un formulaire de contact bloque l'accès au détail du chiffrage |
| 6 | Montrer la **synthèse** | Écran Devis débloqué | Table de chiffrage, marge, total |

---

## 2. Scène démo recommandée

`assets/demo_scenes/` contient 4 scènes **déjà intégrées, calibrées et
chargeables en un clic** via `loadDemoScene()` — aucun asset à créer :

| Clé | Libellé UI | Fichier | Statut calibration |
|---|---|---|---|
| `haussmann` | 🏛️ Haussmannien | `haussmann.jpg` | ✅ calibrée |
| `moderne` | ◼ Contemporain | `moderne.jpg` | ✅ calibrée (moteur dynamique, pas d'image précomposée) |
| `provencal` | 🌿 Provençal | `provencal.jpg` | ✅ calibrée |
| `scandinave` | ❄ Scandinave | `scandinave.jpg` | ✅ calibrée |

**Recommandation** : partir sur **Haussmannien** — plafond haut, bonne
lisibilité de la corniche, c'est la scène la plus "démonstrative" pour un
produit de moulure/corniche.

Produits à préconiser pour cette scène (dans la famille **Corniches**,
déjà whitelistées présentation ET avec vignette de référence visuelle IA —
voir §3) : **D609**, **D607**, **D610**, **D620**, **D630**.

---

## 3. Rendu IA — ce qui est réellement actif

- **Seul le mode STANDARD/add est déclenché automatiquement**
  (`maybeAutoTriggerStandardAiPreview`). Le mode HYBRIDE/refine existe dans
  le code mais est **documenté comme retiré/dormant** après un test visuel
  jugé dégradé (`maybeAutoTriggerHybridAiPreview`, jamais appelé
  automatiquement) — il reste disponible en manuel uniquement si un jour
  réactivé, pas via l'auto-trigger.
- **L'IA est inactive par défaut.** Un build/run standard
  (`flutter build web --release` ou `flutter run` sans script dédié) ne
  contient AUCUNE URL de proxy — confirmé en inspectant le dernier bundle
  buildé (`build/web/main.dart.js` ne contient pas
  `AI_RENDER_PROXY_BASE_URL`).
- **Pour activer l'IA en démo**, il faut explicitement :
  1. Lancer le proxy (`server/ai_render_proxy/server.js`, port 8091,
     quotas actifs — voir §5).
  2. Builder/lancer l'app avec l'un des deux scripts dédiés (voir §6),
     qui injectent l'URL du proxy via `--dart-define`.
- Suggestion produit IA (panneau suggestion) : scorable seulement pour les
  refs qui ont une vignette `assets/profiles/control/<ref>.png` **et**
  sont dans la whitelist présentation `assets/profiles/index.json` (31
  refs scorables sur 43 présentées). D609/D607/D610/D620/D630 en font
  partie.
- **Vérification transparence UI (faite, ce document en fait foi)** :
  balayage exhaustif de tout `lib/` (hors commentaires de code) —
  **zéro** occurrence de "Mano", "Nano", "Gemini" ou "ManoBanana" dans
  une chaîne de texte affichée à l'utilisateur (`Text()`, `tooltip`,
  `label`, message d'erreur). Un message d'erreur contenait auparavant le
  mot technique "Proxy" (`kAiPreviewErrorProxyUnreachable` = *"Proxy de
  rendu injoignable."*) ; corrigé en *"Aperçu IA momentanément
  indisponible."* — voir `lib/data/ia_ambiance_preview.dart`.

---

## 4. Accès au Devis — point à anticiper

L'écran Devis complet (table de chiffrage détaillée) est **verrouillé**
tant que `state.contactSubmitted == false` (`_DevisLocked` dans
`devis_screen.dart`) — même logique que le panneau bas du Comparateur.

**Avant la démo**, décider :
- soit remplir le formulaire de contact en amont (bouton "Voir mon devis"
  → modal contact → soumission) pour arriver à l'écran Devis débloqué
  directement pendant la démo live,
- soit montrer volontairement l'écran verrouillé comme partie du parcours
  commercial normal (générateur de leads), puis débloquer en direct.

Les deux sont légitimes — à choisir selon le public (prospect vs interne).

---

## 5. Sécurité / quotas proxy IA (déjà configurés, ne rien changer)

Config actuelle de `server/ai_render_proxy/.env` (déjà conforme, vérifiée) :

```
AI_RENDER_PROXY_PORT=8091
AI_QUOTA_ENABLED=true
AI_DAILY_IP_LIMIT=10
AI_DAILY_GLOBAL_LIMIT=100
AI_QUOTA_STORE_PATH=/home/user/flutter_app/server/ai_render_proxy/.ai_quota_store.json
```

- Quota fail-closed (si le store est illisible, les requêtes sont
  rejetées plutôt que passées sans limite).
- Logs serveur (`server.js`) déjà vérifiés propres : `requestId` présent
  partout, jamais de `imageBase64`/clé API/`hasGeminiKey` loggés,
  uniquement des hash d'IP (jamais l'IP en clair).
- **Rappel dette connue (issue #3)** : ce store quota est un fichier JSON
  mono-instance — pas conçu pour scaler à plusieurs instances serveur.
  Adapté à une démo contrôlée, pas encore à un déploiement public large.

---

## 6. Checklist avant / après démo

### Avant

```bash
# 1. Lancer le proxy IA (dans un terminal dédié, laissé ouvert)
cd /home/user/flutter_app/server/ai_render_proxy
npm start
# → écoute sur 0.0.0.0:8091, quotas actifs

# 2. Noter l'URL publique du proxy (ex. via GetServiceUrl sur le port 8091)

# 3. Builder/lancer l'app AVEC l'IA activée
cd /home/user/flutter_app
AI_RENDER_PROXY_BASE_URL="https://<url-publique-proxy>:8091" \
  ./scripts/build_demo_ai.sh
# puis servir build/web (voir commandes standard du projet)

# --- OU, pour itérer en debug pendant la préparation ---
AI_RENDER_PROXY_BASE_URL="https://<url-publique-proxy>:8091" \
  ./scripts/run_demo_ai_debug.sh
```

### Pendant

- Suivre le parcours du §1.
- Rappeler à l'oral la clarification de vocabulaire "Mano/Nano" (§ en
  tête de ce document) si le mot apparaît dans une question de
  l'audience.
- Éviter les manipulations sur des tailles d'écran très étroites en
  orientation paysage (ex. ~812×375) — le fix d'overflow CatBar/topbar
  couvre ce cas (PR #5, mergée), mais la validation visuelle manuelle à
  cette taille précise n'a pas été menée à bien lors du fix ; préférer
  portrait mobile, tablette ou desktop pour une démo officielle.

### Après

```bash
# Couper le proxy IA (Ctrl+C dans son terminal, ou) :
lsof -ti:8091 | xargs -r kill -9

# Confirmer qu'il est bien arrêté
lsof -i:8091 2>/dev/null || echo "proxy 8091 arrêté"
```

Ne jamais laisser le proxy tourner (ni son URL partagée) après la fin de
la session de démo — c'est ce qui active la facturation Gemini réelle.

---

## 7. Ce qui n'est PAS dans le périmètre de cette démo

- ❌ Intégration marketplace/API ManoMano (catalogue live, checkout,
  panier officiel).
- ❌ Scaling multi-instance des quotas IA (issue #3 ouverte).
- ❌ Affordance visuelle du scroll horizontal topbar sur petit écran
  (issue #6 ouverte — le scroll est fonctionnel, juste pas encore
  visuellement évident).
- ❌ APK Android signé (hors périmètre sauf demande explicite ultérieure).
- ❌ Mode IA HYBRIDE/refine en automatique (retiré après test visuel,
  voir §3).
