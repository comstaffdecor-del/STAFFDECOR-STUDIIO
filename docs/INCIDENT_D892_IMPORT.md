# Incident D892 — blocage à l'import STEP (2026-08-31)

**Objet** : documenter, avec sources vérifiables, l'échec de traitement de
`assets/step/D892.stp` par le pipeline standard (`step2profile.py`), et
corriger deux chiffres cités par erreur dans une version antérieure de la
correspondance destinée au bureau d'études fournisseur.

## 1. Chiffres retirés

Une version précédente de la correspondance citait **« 4591 secondes »**
et **« aire indéfinie »** pour D892. Ces deux valeurs ont été introduites
sans source, ne correspondent à aucun run journalisé dans ce dépôt, et
sont retirées. Elles ne doivent **pas** être réutilisées.

Recherche exhaustive effectuée avant retrait (résultat négatif) :
- `grep -rn "D892" tools/dxf_pipeline/logs/*.csv` → une seule occurrence,
  antérieure au correctif two-pass (`e7965e9`, 2026-08-26) :
  `tools/dxf_pipeline/logs/batch_corniches_20260825_160054.csv:77`
  → `D892,ERREUR_TIMEOUT,,90.0,Timeout > 90s -- processus tué (groupe complet).`
  (90,0 s, pas 4591 s ; aucun champ "aire" dans ce format de log).
- `grep -rn "4591"` sur tout le dépôt (`.py/.csv/.log/.txt/.md`) → aucune
  occurrence liée à D892 (une seule correspondance fortuite, sans rapport :
  un lien de téléchargement GED se terminant par `/4591` dans
  `ged_diff_par_extension.csv`).
- `git log --all --grep="D892"` / `--grep="4591"` → aucun commit ne
  documente ces valeurs.

## 2. Ce qui remplace ces chiffres : un run borné, mesuré, daté

Le 2026-08-31, un run manuel a été lancé sous le pipeline **actuel**
(post-correctif two-pass, `e7965e9`) :

```
python3 step2profile.py --step-dir assets/step --sku D892 \
    --out-dir /tmp/step_test_d892
```

- **Démarré** : 2026-08-31 08:39 UTC.
- **Arrêté manuellement** : 2026-08-31 08:59:57 UTC, après **1210 s
  (20 min 10 s)** de temps CPU, borne fixée à l'avance.
- **Position au moment de l'arrêt** : bloqué dans
  `STEPControl_Reader.ReadFile()` / `TransferRoots()` (lecture/import du
  fichier), c'est-à-dire **avant** le début du balayage de coupe
  (`sample_areas_along_axis`, budget interne `STEP_SWEEP_BUDGET_S=60.0`
  qui ne s'applique qu'une fois le solide chargé — jamais atteint ici).
- **Aucun `run_step_*.csv` n'a été écrit** : `step2profile.py` n'écrit son
  CSV récapitulatif qu'à la sortie normale de la boucle `main()`
  (`tools/dxf_pipeline/step2profile.py`, écriture du log après la boucle
  de traitement) ; un arrêt par `SIGKILL` avant ce point ne laisse aucune
  trace CSV. C'est pourquoi ce document et le script associé
  (`step_text_inspect.py`) constituent la pièce justificative de
  remplacement.

**Fait citable, sans inférence de cause** : *aucune complétion en 20 min
10 s, blocage confirmé à l'étape de lecture/import, avant tout calcul de
section.*

## 3. Diagnostic textuel (sans OCP) — infirme l'hypothèse initiale

Un test décisif, indépendant du chargement OCP, consiste à lire
directement dans le texte STEP (format ISO-10303-21, lisible tel quel) les
mots-clés qui déclarent la topologie du solide. Script :
[`tools/dxf_pipeline/step_text_inspect.py`](../tools/dxf_pipeline/step_text_inspect.py).

Sortie complète et horodatée :
[`docs/incident_d892_step_inspect.txt`](incident_d892_step_inspect.txt)
(générée le 2026-08-31T09:06:21, reproductible via
`python3 tools/dxf_pipeline/step_text_inspect.py --out docs/incident_d892_step_inspect.txt assets/step/D615.stp assets/step/D629.stp assets/step/D802.stp assets/step/D880.stp assets/step/D887.step assets/step/D892.stp`).

Résultat pour D892.stp (SHA-256 `d4fa64dc...cf3f94a`, 10 315 135 octets) :

| Mot-clé topologique | Occurrences |
|---|---|
| `MANIFOLD_SOLID_BREP` | 1 |
| `CLOSED_SHELL` | 1 |
| `OPEN_SHELL` | 0 |
| `BREP_WITH_VOIDS` | 0 |
| `ADVANCED_FACE` | 273 |

→ **Aucun indice déclaratif de solide non fermé** (pas d'`OPEN_SHELL`, un
`MANIFOLD_SOLID_BREP`/`CLOSED_SHELL` uniques, cohérent avec un B-rep
correctement fermé). L'hypothèse initiale (« non-manifold ou
auto-intersectant ») n'est **pas soutenue** par cette lecture — elle est
donc abandonnée. **Limite explicite** : ceci est une lecture déclarative
du texte, pas une preuve géométrique formelle (pas de test
d'auto-intersection réel) ; elle sert à orienter le diagnostic, pas à le
clore définitivement.

## 4. Anomalie localisée, hypothèse retenue

Sur les 545 courbes `B_SPLINE_CURVE_WITH_KNOTS` du fichier (médiane : 34
points de contrôle, proxy via le nombre de références `#N` par courbe),
**4 courbes** portent entre 5032 et 6894 points de contrôle chacune :

- Rapportées à l'ensemble des références de points au sein des courbes
  B-spline uniquement : 25 580 / 42 465 = **60,2 %**.
- Rapportées à l'ensemble des entités `CARTESIAN_POINT` du fichier
  (97 426 occurrences totales, comptage indépendant) : 25 580 / 97 426 =
  **26,3 %** (chiffre retenu dans le courrier B, dénominateur plus large
  et plus directement comparable entre fichiers).

Ces deux chiffres ne sont pas contradictoires : ce sont deux
dénominateurs différents (parmi les seules courbes B-spline, vs. parmi
tous les points du fichier). Les deux sont cités ici pour traçabilité.

**Hypothèse retenue, formulée avec prudence** : une densité de points de
contrôle anormalement concentrée sur une minorité de courbes pourrait
expliquer le temps de chargement excessif, sans qu'il s'agisse d'un défaut
de solide. Le volume total du fichier n'est pas en cause en tant que tel :
D615.stp compte 29 397 entités et se charge normalement (`run_step_20260826_150219.csv`) ;
c'est la concentration localisée sur ces 4 courbes précises qui constitue
l'anomalie relevée.

## 5. Conséquence sur la correspondance fournisseur

Le diagnostic communiqué (courrier B) demande une vérification de la
discrétisation de ces courbes spécifiques, et non une reconstruction de
solide — cette dernière demande, envisagée dans une version antérieure du
courrier, est retirée car elle n'est plus soutenue par le point 3 ci-dessus.
