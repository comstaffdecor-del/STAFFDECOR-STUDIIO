# P12 — Service de segmentation reelle (backend derriere HttpRoomPlaneSegmenter)

Contrat de reference : `docs/P12_BACKEND_CONTRACT.md` (racine du repo).
Ce service est un wrapper mince autour de
`nvidia/segformer-b0-finetuned-ade-512-512` (ADE20K, 150 classes),
reduit aux 4 classes de plan attendues par le client Flutter.

## Installation

```bash
pip install -r requirements.txt
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
```

## Lancement (dev / mesure)

```bash
MEASURE_MODE=1 uvicorn main:app --host 0.0.0.0 --port 8000
```

`MEASURE_MODE=1` active un cache LRU (64 entrees, cle =
sha256(image)+dimensions) : utile uniquement pendant la phase de mesure
ou les 4 memes photos sont rejouees plusieurs fois. A laisser desactive
en production tant que la politique de cache multi-utilisateurs n'a pas
ete pensee (le cache actuel n'a pas de TTL ni d'eviction par age).

## Validation manuelle effectuee (curl, P12 execution order etape 4)

Sur les 4 vraies photos de `assets/demo_scenes/` a la resolution cible
512x384 :

| scene      | HTTP | temps  | sum(rle)==w*h | labels corrects |
|------------|------|--------|---------------|------------------|
| haussmann  | 200  | 0.92s  | oui           | oui              |
| moderne    | 200  | 0.65s  | oui           | oui              |
| provencal  | 200  | 0.77s  | oui           | oui              |
| scandinave | 200  | 0.71s  | oui           | oui              |

Repartition des classes (unknown/ceiling/wall/floor), a titre indicatif,
PAS une garantie de qualite de frontiere (voir sonde reelle P12 pour ca) :

- haussmann : 0.575 / 0.036 / 0.304 / 0.085
- moderne   : 0.555 / 0.060 / 0.233 / 0.152
- provencal : 0.608 / 0.125 / 0.134 / 0.134
- scandinave: 0.555 / 0.097 / 0.196 / 0.152

Cas d'erreur verifies :
- image illisible -> HTTP 400, `{"detail": "image illisible: ..."}`
- width/height hors bornes [16,2048] -> HTTP 400
- preflight CORS OPTIONS depuis `http://localhost:<port arbitraire>` ->
  200, `access-control-allow-origin` reflete correctement l'origine
  (confirme que `allow_origin_regex` fonctionne, contrairement a un
  simple `"http://localhost:*"` qui ne matcherait rien).

## Piege confirme en pratique : `do_resize`

`SegformerImageProcessor.from_pretrained(MODEL_ID).do_resize` vaut bien
`True` par defaut, avec une taille cible carree 512x512 — confirmation
du piege signale dans le brief : le modele infere sur une image dont le
rapport d'aspect a ete ecrase (photo 4:3 -> carre) avant meme l'entree
du reseau. L'upsampling des logits vers `(height, width)` en sortie
retablit une geometrie de sortie coherente en dimensions, mais ne
corrige pas la distorsion subie par le contenu pendant l'inference.

**Pas encore tranche a ce stade** : si les erreurs de frontiere mesurees
par la sonde P12 reelle sont systematiquement biaisees dans un sens
(ex: toujours vers le haut/bas ou toujours vers un cote), ce
redimensionnement carre est le premier suspect a eliminer avant de
blamer la qualite du modele B0 — comparer avec `do_resize=False` sur au
moins une photo avant de conclure quoi que ce soit.

## Non fait a ce stade (hors perimetre de cette etape)

- Deploiement Cloud Run / Fly.io (suggere par le brief, pas requis pour
  la phase de mesure locale).
- Authentification / rate-limiting (le brief precise qu'aucun secret ne
  doit se trouver dans le bundle Flutter Web ; a traiter avant toute
  exposition publique du service, pas avant).
- Verification `do_resize=False` comparative (voir section precedente).
