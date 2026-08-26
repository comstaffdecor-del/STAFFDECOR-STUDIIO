# Message de démonstration — instantané daté

**Date** : 2026-08-26
**Épinglé au commit** : `354201e9daf47274813fae75be2dd9edae3f2ed6`

Ce document est un instantané, pas une vérité permanente. Le chiffre
« 31 » ci-dessous est celui de `tools/dxf_pipeline/gate_sanite_rapport.csv`
(colonne `statut_gate=OK`) **à la date et au commit indiqués ci-dessus** —
31 lignes `OK` sur 62 au total, vérifié par lecture directe du fichier à
cette date. Ce nombre change à chaque relance du gate (`gate_sanite.py`)
si le catalogue, l'extraction ou les critères évoluent. **Ne pas recopier
ce chiffre ailleurs sans revérifier `gate_sanite_rapport.csv` à la date de
réutilisation.** C'est précisément pour cette raison que ce message ne
vit pas dans l'application (pas d'encart in-app) ni dans un texte
non daté : un instantané doit être daté, ou il devient trompeur au
premier rerun.

---

## Texte

> Jusqu'ici, les profils étaient dessinés à l'échelle de l'image : un
> ratio de pixels calé à la main. Aujourd'hui, pour 31 références du
> catalogue, les cotes affichées sont lues directement dans les fichiers
> d'origine du bureau d'études — des millimètres réels, sans ressaisie.
> Chaque profil passe une vérification géométrique automatique avant
> d'entrer dans le moteur ; ceux dont la géométrie est douteuse sont
> écartés et rendus comme avant. Aucun profil du catalogue n'a changé
> d'aspect en dehors de ces 31.

## Appui visuel

Capture D835, commit `354201e` (`test/core/perspective/
d835_wrong_vs_fallback_capture_test.dart`) : ancienne cote calculée
`65,097 mm` (ratio d'image, fail-open) contre géométrie réelle
`bbox_mm.w = 104,962 mm` lue dans le fichier d'origine du bureau
d'études — écart de 38 %.

## Si on demande la preuve du garde-fou

Ce n'est pas une image, c'est un comportement de repli : un profil dont
la géométrie est jugée douteuse par le gate n'entre pas dans le moteur
métrique — il est rendu avec les coefficients par défaut
(`StripThickness.corniceDefault`), exactement comme avant cette
évolution. Rien à montrer en plus de la capture D835 ci-dessus, qui
illustre déjà les deux issues côte à côte (fausse cote vs repli
honnête).

## Provenance exacte des 31 (pour mémoire, pas pour l'oral)

Les 31 références proviennent de deux chaînes d'extraction distinctes —
STEP (`tools/dxf_pipeline/step2profile.py`) et DXF
(`tools/dxf_pipeline/dxf2profile.py`) — toutes deux lisant les fichiers
d'origine du bureau d'études, jamais une ressaisie. Le texte ci-dessus
dit « fichiers d'origine du bureau d'études » plutôt que « fichiers
STEP » précisément pour rester vrai dans les deux cas sans détailler la
chaîne à l'oral. Détail des deux chaînes et de leurs limites respectives
dans `docs/ETAT_MOTEUR_RENDU.md`, section 5.
