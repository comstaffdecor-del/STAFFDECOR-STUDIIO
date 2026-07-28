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

## Cas 1 — Profil LISSE (corniche/plinthe/cimaise sans motif répétitif)

**Format demandé, par ordre de préférence :**

### Option A (préférée) — DXF avec la coupe 2D dessinée directement

- Un fichier `.dxf` **classique** contenant la **coupe transversale du
  profil dessinée en polyligne fermée** (`LWPOLYLINE` ou `POLYLINE`) — le
  contour vu de bout, comme sur un plan de coupe papier. **Pas le solide
  3D : juste le contour 2D.**
- Sur un calque identifiable comme le contour du profil (pas mélangé aux
  cotes, cartouche, hachures).
- Unité `$INSUNITS` renseignée dans l'en-tête DXF (mm attendu).

### Option B (si le profil n'existe qu'en volume dans leur CAO)

- Un fichier **`.stl`** (binaire, préféré) ou **`.obj`**, exporté depuis
  AutoCAD/BricsCAD à partir du `3DSOLID`.
- Le maillage doit représenter un tronçon de barre **nettement allongé**
  (l'axe long doit être identifiable sans ambiguïté).
- **Fermé (watertight)**, sans trous ni faces dupliquées.
- Confirmer l'unité réelle du modèle (mm très probablement).

---

## Cas 2 — Profil ORNEMENTÉ (denticules, cannelures irrégulières, rosace, tout motif qui varie le long de la barre)

Une coupe 2D unique ne suffit pas : le relief varie le long de la barre.
**Le volume complet est obligatoire** (Option B ci-dessus), avec deux
exigences supplémentaires :

1. **Longueur exportée : au moins 3 à 4 répétitions complètes du motif.**
   Le pipeline détecte la période du motif par autocorrélation de l'aire
   de section balayée le long de la barre — un seul denticule ou une
   demi-période ne donne aucun pic net, la période est alors laissée
   `null` (jamais inventée), et le motif est traité comme incomplet.
   **Ne pas envoyer un tronçon trop court.**
2. **Maillage fermé (watertight), sans trous.** Le pipeline calcule des
   sections planaires tout le long de la barre ; un maillage ouvert
   produit des coupes incohérentes ou vides. Aucune réparation
   automatique n'est faite côté pipeline (règle stricte : jamais de
   correction silencieuse d'un profil).

**Format** : `.stl` (binaire, préféré) ou `.obj`, mêmes exigences
d'unité que le cas 1B.

---

## Récapitulatif — à copier-coller dans l'email au BE

> Pour chaque référence produit, merci de nous transmettre l'un des
> formats suivants (jamais le solide 3D `3DSOLID`/ACIS/SAB brut dans un
> DXF, que nous ne pouvons pas exploiter) :
>
> 1. **Profil lisse, si vous avez la coupe 2D** : un DXF classique avec la
>    coupe transversale dessinée en polyligne fermée (pas le solide),
>    unité mm renseignée dans l'en-tête.
> 2. **Profil lisse, si vous n'avez que le volume 3D** : un export STL
>    (ou OBJ) fermé/watertight du solide, tronçon de barre nettement
>    allongé, avec confirmation de l'unité (mm).
> 3. **Profil ornementé (denticules, motif répétitif, rosace...)** :
>    obligatoirement un STL/OBJ fermé/watertight, couvrant **au moins 3-4
>    répétitions complètes du motif** le long de la barre — un tronçon
>    trop court empêche la détection automatique de la période.
>
> Dans tous les cas : jamais de `.dwg` direct (convertir en DXF en amont),
> et merci de confirmer l'unité du fichier si elle n'est pas explicite.

---

## Ce que le pipeline produit ensuite (pour information au BE, si utile)

- `dxf2profile.py` (Cas 1A) ou `solid2profile.py` (Cas 1B et Cas 2)
  génèrent un JSON normalisé par référence (`assets/profiles/<sku>.json`,
  schéma `SPEC.md`) + un PNG de contrôle coté du profil.
- Pour un motif ornementé détecté comme variable : profil de pose calculé
  par **union** des coupes caractéristiques (jamais l'enveloppe convexe,
  qui effacerait les gorges/denticules), période du motif estimée par
  autocorrélation, et une carte de hauteur 16 bits (`heightmaps/`) est
  générée pour l'usage rendu/normal map ultérieur.
- Toute ambiguïté (unité inconnue, contour introuvable, orientation non
  déterminable, maillage insuffisant) produit un statut d'erreur explicite
  et **jamais** un profil de substitution inventé — le batch continue sur
  la référence suivante et journalise le problème.
