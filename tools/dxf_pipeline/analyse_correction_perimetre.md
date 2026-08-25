# Correction de périmètre et de métriques — post-batch (suite au commit 3ac2bd2)

Analyse demandée et vérifiée point par point sur `gate_sanite_rapport.csv` /
`recoupement_catalogue_vs_profil.csv` (commit 3ac2bd2). Aucun code modifié
dans cette passe — analyse seule, en attente du feu vert pour le câblage.

## 1. Périmètre corrigé : 5 profils LED exclus des "corniches"

Le regex `^D\d+[A-Z]?$` utilisé pour compter les "corniches" dans le
reporting a attrapé 5 SKU qui sont en réalité des profils d'éclairage
indirect (catalogue.csv, colonne `designation`) :
- D106 : "Profil équerre lumineuse avec joint cre..."
- D110 : "Profil eclairage indirect en 2 ml - 13,5 x..."
- D114 : "Profil éclairage indirect en 2 ml - 20 x 1..."
- D114M : "Profil éclairage indirect en 2 ml - 15 x 1..."
- D117 : "Profil éclairage indirect en 2 ml - 25 x 1..."

Confirmé via `catalogue.csv`. Ces 5 SKU sont retirés du dénominateur
"corniches" pour tout calcul de taux ci-dessous.

## 2. Métrique corrigée : taux d'atteinte par le picker

Ancienne métrique (biaisée) : 18/50 = 36.0% -- ne comptait QUE le débord
de plan, et incluait les 5 profils LED.

Métrique corrigée : périmètre = SKU corniches (D+chiffres[+lettre], hors
les 5 LED ci-dessus), n_sommets_brut > 0 (extraction step2profile.py
réussie) => **45 corniches arrivées au contrôle géométrique**.

Deux modes d'échec du picker, DISTINCTS et UNIS ici en un seul total (une
corniche peut cumuler les deux, mais n'est comptée qu'une fois) :

  a) DEBORD_PLAN_MUR ou DEBORD_PLAN_PLAFOND (face détectée mais mal
     positionnée) : 16 corniches --
     D555, D560, D564, D576, D604, D608, D614, D622, D650, D652, D703,
     D712, D717, D835, D888, D896

  b) CONTRAT_LOADER_MUR_VIDE ou CONTRAT_LOADER_PLAFOND_VIDE (AUCUNE face
     détectée du tout -- mode d'échec invisible dans le taux de débord
     seul) : 5 corniches --
     D564 (plafond vide), D608 (plafond vide), D565 (plafond vide),
     D621 (mur vide), D651 (mur vide)
     (D564 et D608 apparaissent aussi en (a) -- débord sur l'autre face)

  UNION (a) ∪ (b) = **19 corniches abîmées par le picker** (D555, D560,
  D564, D565, D576, D604, D608, D614, D621, D622, D650, D651, D652,
  D703, D712, D717, D835, D888, D896)

  => **45 - 19 = 26 corniches qui passent intégralement.**

  **Taux de corniches abîmées par le picker = 19/45 = 42.2%** (à retenir
  comme métrique de référence, remplace le 36.0% du commit 3ac2bd2 qui
  sous-comptait le mode "aucune face détectée").

  Conséquence directe : une correction du picker de face (sans aucun
  retéléchargement, ces 19 STEP sont déjà sur disque) porterait les
  corniches exploitables de 26 à potentiellement 45 -- meilleur ratio
  rendement/effort observé sur toute la Piste A à ce stade.

## 3. Verdict sur les critères non bloquants (drapeaux), n=62

### JITTER_CONTOUR : mort, à supprimer
1 seul déclenchement sur 62 profils (D650, count=1, sous le seuil
indicatif de 3 -- ne génère même pas de drapeau). Aucune valeur
discriminante observée. Confirmé : formulation à supprimer du gate lors
de la prochaine passe de code (pas fait dans cette passe, analyse
seule).

### BRUIT_TESSELLATION : discriminant, mais PAS en compte absolu --
passer à un RATIO (segments courts / n_sommets_brut)

Comptes absolus observés (le seuil indicatif de 3 était bien absurde,
comme suspecté avant le batch) :
  D886=38, D896=18, D888=13, D652=14, D748=3, D114M=8, PLIN20=6, D650=4

Ratios (bruit_tessellation_count / n_sommets_brut) :
  D886  : 38/79 = 48.1%
  D114M : 8/21  = 38.1%
  D896  : 18/63 = 28.6%
  PLIN20: 6/24  = 25.0%
  D888  : 13/65 = 20.0%
  D652  : 14/70 = 20.0%
  D748  : 3/31  = 9.7%   (témoin -- faux positif connu, corniche sonde
                          visuellement, 3 segments consécutifs = détail
                          réel type feuillure, pas du bruit)
  D650  : 4/52  = 7.7%

Séparation nette autour de 20% : {D886, D114M, D896, PLIN20} >= 25% vs
{D888, D652} = 20.0% exactement (frontière) vs {D748, D650} <= 10%.

**ACTION REQUISE AVANT DE FIGER LE SEUIL** : inspection visuelle des PNG
D886, D114M, D896 vs témoin D748, pour trancher si le ratio élevé
traduit un contour richement mouluré (légitime, seuil à remonter) ou du
bruit de tessellation réel (seuil à ~20-25% confirmé). Non fait dans
cette passe -- prochaine action.

## 4. Deux défauts confirmés, non corrigés (documentés dans gate_sanite.py,
inchangés ici)

- **n_eff sous-estime encore plus que prévu sur le batch réel** : D710
  tombe de n_brut=42 à n_eff=18 (cascade sur arc discrétisé, même défaut
  que D718/D720 identifié sur l'échantillon pilote). Confirme que ce
  critère ne doit RIEN bloquer, comme déjà décidé.

- **platitude_critere_applique = False sur TOUTES les nouvelles
  corniches du batch** (D650, D651, D652, D703, D704, D708, D710, D712,
  D717, D830, D835, D886, D888, D896, D901, etc.) -- confirmé par
  inspection directe du CSV. Cause : `FAMILLE_CORNICHE_MOULURE_SKUS`
  dans gate_sanite.py est une liste EN DUR figée sur les 13 corniches +
  TAL26 du pilote, jamais mise à jour avec les 79 SKU du batch. Résultat :
  **aucune donnée de platitude n'a été produite sur le batch, le critère
  6 est actuellement muet sur 79/92 corniches.** À corriger au prochain
  passage sur gate_sanite.py (remplacer la liste en dur par une détection
  fondée sur le préfixe SKU "D" + famille corniche, ou toute autre règle
  moins fragile) -- pas fait dans cette passe.

## 5. Les 5 ALERTE de longueur : motif partiel, pas un bug d'extraction

Toutes les 5 ALERTE (D520, D550, D614, D616, D626) opposent une longueur
catalogue de 1500 ou 1750mm à une longueur mesurée de 2000mm. MAIS ce
n'est pas systématique pour la désignation "Corniche en 1,75 ml" :
D610, D622, D630 et D703 sont catalogués en 1,75 ml et mesurent
EXACTEMENT 1750mm (vérifié : `longueur_barre_mm=1750.0` dans leurs JSON,
statut=OK).

=> La divergence ne vient pas de l'extraction (qui mesure juste ce que
   contient le STEP) mais probablement d'une variante 2m servie par la
   GED pour ces 5 références précises. **Question pour le BE / la GED,
   pas un bug côté pipeline d'extraction.** Aucune action côté ce dépôt.

## 6. Bilan chiffré global (périmètre corrigé)

Références au statut_gate=OK (contrat loader respecté + pas de débord de
plan) : 31 au total, décomposées en :
  - 26 corniches (périmètre corrigé, hors LED, hors picker cassé) :
    D505, D520, D550, D562, D577, D607, D609, D610, D616, D620, D626,
    D630, D631, D704, D705, D706, D708, D709, D710, D718, D720, D748,
    D830, D886, D891, D901
  - 1000.json (moulure/pilastre)
  - TAL26 (moulure)
  - 3 profils LED (D114, D114M, D117 -- statut_gate=OK ; D106 et D110
    sont en revanche en DEBORD_PLAN_PLAFOND, donc EXCLUS du compte OK
    malgré leur statut d'extraction OK -- ils font partie des "abîmés
    par le picker" au même titre qu'une corniche, simplement hors du
    périmètre "corniche" au sens catalogue)

Sur les 165 corniches dites exploitables (classification_t1_t4.csv) :
**31/165 = 18.8%** au sens large (loader), ou en restreignant à la seule
famille corniche : 26/165 = 15.8%.

Réservoirs de récupération, PAR ORDRE DE RENTABILITÉ (effort croissant) :
  1. **19 corniches abîmées par le picker** -- déjà sur disque (STEP),
     aucun retéléchargement, correction logicielle seule (picker de
     face). Meilleur ratio rendement/effort.
  2. **23 corniches en ERREUR_TIMEOUT** -- déjà téléchargées, juste à
     retenter (probablement avec un timeout plus long ou en isolant les
     fichiers lourds individuellement).
  3. **19 corniches en ERREUR_SELECTION** (issues du batch, déplacées
     vers rejets_stl/) -- même famille de problème que le picker
     probablement, à investiguer une fois le picker corrigé.
  4. **51 corniches disponibles en STL seul** -- bloquées côté BE
     (ré-export attendu en mm, cf. arbitrage déjà tranché : abandon du
     chemin STL, ré-export BE).

## 7. Rappel du point non résolu (câblage applicatif)

`profile_dims_cache.dart` n'est importé par aucun painter à ce stade :
l'app rend toujours avec les ratios pixels, pas avec les cotes mm
réelles. Les 31 (ou 26) références justes ne s'affichent pas encore.
Le prochain brief porte sur le câblage (cache dans le repaint du
painter, section réelle en mm, épaisseur variable avec la distance au
point de fuite) -- PAS sur le picker, qui vient après, une fois le
moteur de rendu branché.
