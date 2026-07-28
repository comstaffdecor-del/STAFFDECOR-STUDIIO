# Guide fichiers source — à transmettre au bureau d'études (BE)

**Statut : document de communication externe**, dérivé des règles strictes
de `SPEC.md` (pipeline `dxf2profile.py` / `solid2profile.py`). Objectif :
que le BE fournisse, dès le premier envoi, un fichier exploitable par le
pipeline — sans aller-retour de conversion.

---

## ⚠️ Ce qu'on ne peut PAS lire

Un fichier `.dxf` contenant un `3DSOLID` encodé en **SAB/ACIS** (le format
binaire propriétaire Autodesk hérité de la technologie ACIS — c'est le cas
du fichier D105A transmis initialement) **n'est exploitable par aucun
outil du pipeline**. Ni `ezdxf` (bibliothèque Python utilisée), ni FreeCAD,
ni ODA File Converter ne savent décoder ce format. **Seul AutoCAD ou
BricsCAD** (chez le BE) peut ouvrir ce solide et en extraire quelque chose
d'utilisable.

**Ne jamais envoyer** :
- un `.dxf` avec le solide 3D brut (`3DSOLID`, corps ACIS/SAB) tel quel ;
- un `.dwg` (toujours convertir en `.dxf` en amont, côté BE).

---

## Format demandé — UNIQUE pour toutes les références : STL/OBJ

**Décision retenue : on demande systématiquement un maillage 3D (STL de
préférence, OBJ accepté), quel que soit le type de profil.** Une seule
règle, aucune ambiguïté sur "quel cas s'applique à ma référence" — le
maillage couvre aussi bien un profil lisse qu'un profil ornementé, seule
la longueur exportée diffère (voir ci-dessous).

**Exigences communes, pour toute référence :**
- Export **`.stl` binaire** (préféré) ou `.obj`, réalisé depuis AutoCAD ou
  BricsCAD à partir du `3DSOLID` (seuls outils côté BE capables de lire ce
  format ACIS/SAB).
- Maillage **fermé (watertight)** : sans trous, sans faces dupliquées.
  Un maillage ouvert produit des coupes incohérentes ou vides — le
  pipeline ne répare jamais un maillage silencieusement (règle stricte,
  jamais de correction/complétion inventée d'un profil).
- Tronçon de barre **nettement allongé**, axe long identifiable sans
  ambiguïté.
- **Confirmer l'unité réelle du modèle** (mm très probablement) — un STL
  n'a pas d'unité native, elle doit être déclarée explicitement en retour.

**Seule variable selon le type de profil : la longueur du tronçon exporté.**

| Type de profil | Longueur exportée |
|---|---|
| Lisse (corniche/plinthe/cimaise sans motif répétitif) | Un tronçon représentatif suffit (pas d'exigence de répétition). |
| Ornementé (denticules, cannelures irrégulières, rosace, tout motif qui varie le long de la barre) | **Au moins 3 à 4 répétitions complètes du motif.** Le pipeline détecte la période par autocorrélation de l'aire de section balayée le long de la barre — un seul denticule ou une demi-période ne donne aucun pic net, la période reste alors `null` (jamais inventée), et le motif est traité comme incomplet. |

**Exception : si un DXF 2D de la coupe existe déjà chez le BE** (plan de
fabrication classique, polyligne fermée dessinant directement le contour
transversal), il reste utilisable directement pour un profil lisse — pas
besoin de le remodeler en 3D dans ce cas précis. Mais **par défaut, on
demande du STL/OBJ pour tout**, pour éviter l'aller-retour de
clarification.

---

## Récapitulatif — à copier-coller dans l'email au BE

> Pour chaque référence produit, merci de nous transmettre un export STL
> (de préférence binaire) ou OBJ du solide, réalisé depuis AutoCAD ou
> BricsCAD — jamais le fichier DXF contenant le solide 3D `3DSOLID`/
> ACIS/SAB brut, que nous ne pouvons pas exploiter directement.
>
> Exigences :
> - Maillage fermé ("watertight"), sans trous.
> - Tronçon de barre nettement allongé.
> - Pour un profil **ornementé** (denticules, motif répétitif, rosace...) :
>   au moins 3 à 4 répétitions complètes du motif sur la longueur
>   exportée — un tronçon trop court empêche la détection automatique du
>   pas du motif.
> - Pour un profil **lisse** : un tronçon représentatif suffit.
> - Merci de confirmer l'unité du fichier (mm très probablement).
>
> Si vous disposez déjà d'un DXF 2D de la coupe transversale pour un
> profil lisse (polyligne fermée du contour), il reste utilisable tel
> quel, sans passer par le 3D.
>
> Dans tous les cas : jamais de fichier .dwg directement, merci de le
> convertir en .dxf en amont si besoin.

---

## Ce que le pipeline produit ensuite (pour information au BE, si utile)

- Le script qui traite les STL/OBJ (ou le DXF 2D dans le cas d'exception
  ci-dessus) génère un JSON normalisé par référence
  (`assets/profiles/<sku>.json`, schéma `SPEC.md`) + un PNG de contrôle
  coté du profil.
- Pour un motif ornementé détecté comme variable : profil de pose calculé
  par **union** des coupes caractéristiques (jamais l'enveloppe convexe,
  qui effacerait les gorges/denticules), période du motif estimée par
  autocorrélation, et une carte de hauteur 16 bits (`heightmaps/`) est
  générée pour l'usage rendu/normal map ultérieur.
- Toute ambiguïté (unité inconnue, contour introuvable, orientation non
  déterminable, maillage insuffisant) produit un statut d'erreur explicite
  et **jamais** un profil de substitution inventé — le batch continue sur
  la référence suivante et journalise le problème.
