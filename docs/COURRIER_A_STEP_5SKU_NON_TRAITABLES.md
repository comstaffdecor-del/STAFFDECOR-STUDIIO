# Courrier A — Cinq références STEP en échec de traitement (D615, D629, D802, D880, D887)

**Statut : prêt à transcrire dans un email au bureau d'études fournisseur.**
**Sources internes (traçabilité, à ne pas inclure dans l'email)** : SHA-256 et
comptages d'entités générés par `tools/dxf_pipeline/step_text_inspect.py`
(sortie complète : `docs/incident_d892_step_inspect.txt`) ; messages d'échec
issus des logs `tools/dxf_pipeline/logs/run_step_20260826_15{0219,0323,0426,0531}.csv`
et `run_step_20260826_145936.csv` (D887, premier essai) — ces cinq fichiers
sont générés localement par `step2profile.py` et **ne sont pas versionnés**
(`tools/dxf_pipeline/logs/` est explicitement dans `.gitignore` à la racine
du dépôt) ; ils restent cependant lisibles tels quels tant que le poste de
travail qui les a produits n'a pas été réinitialisé.

---

## Objet

Cinq références produit, transmises au format STEP, échouent systématiquement
à l'étape d'extraction du profil de section — indépendamment du nombre de
positions testées le long de l'axe de la barre.

## Contexte technique (pour information, si utile côté BE)

Notre pipeline extrait automatiquement le profil de coupe transversale d'un
solide STEP en balayant des plans perpendiculaires à l'axe long de la barre
(l'axe est déterminé automatiquement par analyse en composantes principales
du solide) et en calculant l'intersection géométrique exacte (B-rep) à
chaque position. Pour les cinq références ci-dessous, **aucune position
testée n'a produit de coupe valide**.

## Détail par référence

| SKU | Fichier | Taille | SHA-256 | Entités STEP | Positions testées | Résultat |
|---|---|---:|---|---:|---:|---|
| D615 | D615.stp | 2 298 785 o | `ed38a2661bb33f373e74b04e53279c3f8ea32ec7f396425141120e290110145b` | 29 397 | 85 | Aucune coupe valide |
| D629 | D629.stp | 1 045 858 o | `a4f3e521fea635a38958883481fdba550986efb3efba55939401d612b4ecef86` | 20 781 | 97 | Aucune coupe valide |
| D802 | D802.stp | 37 189 o | `d350b286c023f32dbfd4b9d897c9c89f0026dc699b1e686ad1b1dd125622b7dd` | 704 | 96 | Aucune coupe valide |
| D880 | D880.stp | 265 811 o | `fa985adb5c0c5d52696c4736fd38640edf70fe465870c603f56b007371f46048` | 4 507 | 97 | Aucune coupe valide |
| D887 | D887.step | 750 302 o | `6590dc202157fa76b1cf087e3c35a38674eb7c9cc978a5bc45e29a8df3564f01` | 11 676 | 97 | Aucune coupe valide (reproductible sur deux essais distincts) |

Message d'échec identique (verbatim) pour les cinq références :
> Aucune coupe valide sur le balayage dense de `<fichier>` (`<N>` positions
> testees). Solide non ferme (non watertight) ou axe long mal identifie.

## Vérification déclarative complémentaire (indépendante du chargeur de coupe)

Une lecture directe du texte STEP (mots-clés topologiques ISO-10303-21,
sans passer par le solveur géométrique) montre que les cinq fichiers
**déclarent** une topologie fermée et manifold :

| SKU | MANIFOLD_SOLID_BREP | CLOSED_SHELL | OPEN_SHELL | BREP_WITH_VOIDS |
|---|---:|---:|---:|---:|
| D615 | 1 | 1 | 0 | 0 |
| D629 | 1 | 1 | 0 | 0 |
| D802 | 1 | 1 | 0 | 0 |
| D880 | 1 | 1 | 0 | 0 |
| D887 | 1 | 1 | 0 | 0 |

Aucun des cinq fichiers n'annonce lui-même un solide ouvert au niveau du
texte. Cette lecture est purement déclarative (elle ne teste pas
l'auto-intersection ni la couture réelle des faces) : elle élimine
l'hypothèse la plus simple, elle ne prouve pas l'étanchéité effective.

## Conclusion et demande

L'échec se situe donc probablement à l'un de ces deux niveaux, non
distingués par notre diagnostic actuel :
- le solide, bien que déclaré fermé, comporte des micro-écarts de couture
  entre faces qui empêchent une intersection B-rep exacte à toute position ;
- ou l'axe long de la barre n'est pas identifiable sans ambiguïté par
  analyse en composantes principales (forme trop proche d'un solide de
  révolution, ou proportions insuffisamment allongées).

**Demande** : pour ces cinq références uniquement, merci de fournir un
export maillage (STL binaire de préférence, OBJ accepté), réalisé depuis
AutoCAD ou BricsCAD à partir du même solide, avec :
- un contrôle de cousu (sewing/healing) natif du logiciel avant export ;
- confirmation que le tronçon exporté est nettement allongé selon un axe
  identifiable sans ambiguïté ;
- confirmation de l'unité du fichier (mm très probablement).

Ce format est celui déjà documenté dans notre guide fichiers source
(`GUIDE_BE_FICHIERS_SOURCE.md`, section "Format demandé — UNIQUE pour
toutes les références : STL/OBJ").

Si un nouvel export STEP est préféré à un maillage, merci de vérifier au
préalable, côté logiciel source, que le solide passe un contrôle de
cousu/étanchéité avant réexport — un nouveau STEP reproduisant le même
défaut de couture donnerait le même résultat de notre côté.
