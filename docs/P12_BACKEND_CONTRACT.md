# P12 — Contrat backend de segmentation (source de vérité)

Référence de code : `lib/core/perspective/http_room_plane_segmenter.dart`
au commit `189856c212a4a70370675d0a9d24d67195ccf916` (origin/main).

En cas de divergence entre ce document et le code Dart, **le code gagne**
et ce document doit être corrigé. Ce fichier existe parce qu'un brief
antérieur annonçait `POST {"image_base64":..., "max_dim":512}` avec un
champ `classes` : ni l'un ni l'autre n'a jamais été implémenté.

## Requête

Émise par `HttpRoomPlaneSegmenter.segment()` via `http.MultipartRequest` :

    POST <endpoint>
    Content-Type: multipart/form-data; boundary=...

      width  = "512"                     (champ texte, décimal)
      height = "384"                     (champ texte, décimal)
      image  = <octets>, filename="room.jpg", name="image"

Le champ fichier s'appelle `image`. Pas de header d'authentification
(voir § Sécurité). Pas de base64, pas de `max_dim`.

## Réponse

Code 200 obligatoire (tout autre code lève). Corps JSON :

    {
      "width":  512,
      "height": 384,
      "labels": ["unknown", "ceiling", "wall", "floor"],
      "rle":    [[0, 120], [2, 340], [3, 900]]
    }

Le champ s'appelle `labels`, **pas** `classes`.

## Invariants (échec franc, jamais de repli silencieux)

1. `labels` == `["unknown","ceiling","wall","floor"]`, strictement et
   dans cet ordre. C'est `RoomPlaneClass.values` / `kRoomPlaneLabelOrder`.
   → `RoomPlaneContractViolationException`
2. `width`/`height` retournés == `width`/`height` demandés.
   → `RoomPlaneContractViolationException`  (patch P12-1)
3. `sum(runLength) == width * height`, exactement.
   → `ArgumentError` (constructeur de `RoomPlaneMaskResult`)
4. `0 <= classIndex <= 3` pour chaque paire.
   → `ArgumentError` (idem)
5. Parcours RLE **ligne-major** : haut→bas, gauche→droite. Chaque paire
   est `[classIndex, runLength]`.

## Mapping ADE20K → classes de plan

Indices **0-based**, tels que fournis par `model.config.id2label` :

    ADE20K 0  "wall"     -> 2  (wall)
    ADE20K 3  "floor"    -> 3  (floor)
    ADE20K 5  "ceiling"  -> 1  (ceiling)
    tout le reste        -> 0  (unknown)

⚠️ `objectInfo150.csv` du MIT est **1-based** (mur=1, sol=4, plafond=6).
Ne jamais coder ces indices de mémoire : les lire depuis `config.json`
au démarrage et faire échouer le service si `id2label` ne correspond pas.

Tout le reste va en `unknown` **délibérément**. Fenêtre, porte, tableau,
miroir, rideau sont sur un mur ; tapis, canapé, table sont sur le sol.
Les mapper vers `wall`/`floor` ferait ajuster la frontière sur le bas du
canapé au lieu de la plinthe. En `unknown`, les colonnes concernées sont
écartées de l'ajustement et `manualRequired` se déclenche si trop de
colonnes manquent — comportement voulu.

## Sécurité

Aucun secret dans le bundle Flutter Web (lisible par tous). Service soit
public + rate-limit par IP, soit derrière un proxy qui injecte la clé
côté serveur.

CORS : Flutter Web envoie un préflight `OPTIONS`. `CORSMiddleware`
compare les origines en **égalité stricte** — `"http://localhost:*"` ne
matche rien. Utiliser `allow_origin_regex=r"^http://localhost(:[0-9]+)?$"`
ou une liste explicite. Symptôme si oublié : erreur réseau opaque côté
Dart, aucune trace côté backend.

## Précision des frontières

`argmax` **après** upsampling bilinéaire des logits à `(height, width)`.
Jamais d'interpolation sur des indices de classe (fabrique des classes
fantômes aux frontières, soit exactement là où on mesure).
