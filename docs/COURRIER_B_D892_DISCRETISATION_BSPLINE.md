# Courrier B — D892 : blocage au chargement STEP, anomalie localisée sur 4 courbes

**Statut : prêt à transcrire dans un email au bureau d'études fournisseur.**
**Sources internes (traçabilité, à ne pas inclure dans l'email)** :
`docs/INCIDENT_D892_IMPORT.md` et `docs/incident_d892_step_inspect.txt`,
commit `db99f2e`, générés par `tools/dxf_pipeline/step_text_inspect.py`.

**Note de correction** : une version antérieure de cette correspondance
citait « 4591 secondes » et « aire indéfinie » pour cette référence. Ces
deux valeurs ont été introduites sans source vérifiable et sont retirées —
voir ci-dessous les chiffres qui les remplacent, mesurés et datés.

---

## Objet

Le fichier D892.stp bloque au chargement (import), avant même le début du
calcul de section. Une lecture indépendante du texte du fichier localise
l'anomalie probable sur 4 courbes précises, sur les 545 que compte le
fichier.

## Fichier concerné

| Élément | Valeur |
|---|---|
| Fichier | D892.stp |
| Taille | 10 315 135 octets |
| SHA-256 | `d4fa64dc2fc056404328271c63ddb6a19d085a8ccfe032e416dfe76e0cf3f94a` |
| Nombre d'entités STEP | 103 995 |

## 1. Constat mesuré : blocage au chargement, pas au calcul

Un run manuel borné dans le temps a été effectué le 2026-08-31 :
- Démarré 08:39 UTC.
- Arrêté manuellement à 08:59:57 UTC, après **1210 secondes (20 min 10 s)**,
  borne fixée à l'avance.
- Position au moment de l'arrêt : dans la lecture/import du fichier
  (`STEPControl_Reader.ReadFile()` / `TransferRoots()`) — **avant** le début
  du balayage de coupe. Le calcul de section n'a donc jamais commencé ;
  aucun résultat d'aire (« indéfini » ou autre) n'a été produit à ce stade,
  puisque cette étape n'a pas été atteinte.
- Un arrêt manuel avant la fin normale du traitement ne produit aucun
  fichier de log récapitulatif de notre côté — d'où l'absence de résultat
  chiffré pour cette référence dans nos journaux automatiques.

## 2. Vérification déclarative : le solide n'est pas signalé comme ouvert

Une lecture directe du texte STEP (mots-clés topologiques, indépendante du
solveur géométrique) donne :

| Mot-clé topologique | Occurrences |
|---|---:|
| MANIFOLD_SOLID_BREP | 1 |
| CLOSED_SHELL | 1 |
| OPEN_SHELL | 0 |
| BREP_WITH_VOIDS | 0 |
| ADVANCED_FACE | 273 |

Aucun indice déclaratif de solide non fermé. L'hypothèse initiale d'un
solide non-manifold ou auto-intersectant n'est pas soutenue par cette
lecture et est abandonnée (lecture déclarative uniquement, pas une preuve
géométrique formelle).

## 3. Anomalie localisée

Le fichier contient 545 courbes `B_SPLINE_CURVE_WITH_KNOTS`, avec une
médiane de 34 points de contrôle. Parmi elles, **4 courbes** portent chacune
entre 5 032 et 6 894 points de contrôle :

- Rapportées aux seules références de points au sein des courbes B-spline :
  25 580 / 42 465 = **60,2 %**.
- Rapportées à l'ensemble des points `CARTESIAN_POINT` du fichier (97 426
  occurrences) : 25 580 / 97 426 = **26,3 %**.

À titre de comparaison : D615.stp, dont le volume total (29 397 entités)
est du même ordre de grandeur que la partie non problématique de D892, se
charge normalement. Ce n'est donc pas le volume global du fichier qui est
en cause, mais la concentration très localisée de points de contrôle sur
ces 4 courbes précises.

## 4. Demande

Merci de vérifier, sur le modèle source, la discrétisation des 4 courbes à
plus forte densité de points de contrôle (probablement des congés/gorges
du profil ornemental) et, si la forme le permet géométriquement, de les
ré-exporter avec une tolérance de discrétisation plus grossière (moins de
points de contrôle pour une géométrie équivalente).

Il ne s'agit pas d'une demande de reconstruction complète du solide — le
diagnostic déclaratif (section 2 ci-dessus) ne la justifie pas — mais
d'une vérification ciblée sur ces courbes spécifiques.
