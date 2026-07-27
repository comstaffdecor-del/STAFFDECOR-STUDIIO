# SPEC.md — Schéma des profils produit (pipeline DXF → JSON)

**Statut : source de vérité.** Tout script du pipeline (`scan_assets.py`,
`dxf2profile.py`, et tout code Flutter qui consomme ces JSON) doit relire ce
fichier avant modification. Toute évolution du schéma passe par une bascule
de `version_schema` et une mise à jour de ce document.

## 🔒 RÈGLE PERMANENTE — INTÉGRITÉ DES DONNÉES SOUS `assets/`

**On ne supprime, ne déplace, ni n'écrase JAMAIS un fichier sous `assets/`.**

- `assets/dwg/`, `assets/dxf/`, `assets/profiles/` (et tout sous-dossier)
  ne contiennent que des données produit réelles fournies par l'utilisateur
  ou générées par le pipeline validé. Ce sont des dossiers en **écriture
  additive uniquement** : on y ajoute, on n'y retire jamais rien sans
  demande explicite et confirmée de l'utilisateur.
- Aucun script, aucune commande de "nettoyage", aucun test ne doit
  jamais faire de `rm`, `mv`, ou d'écrasement (`>`, overwrite) visant un
  chemin sous `assets/`.
- Les artefacts de test (fixtures synthétiques, sorties de test,
  fichiers générés pendant le développement du pipeline) vont **exclusivement**
  dans `/tmp/` ou `tests/fixtures/` — jamais dans `assets/`.
- Toute exception à cette règle nécessite une confirmation explicite,
  écrite, de l'utilisateur, dans le tour de conversation où l'action est
  demandée — jamais une décision autonome, même pour un fichier qui
  "semble" être un doublon ou un artefact de test.

## Contexte

Staff Décor fabrique des moulures en plâtre (corniches, plinthes, cimaises,
rosaces, profils LED, etc.). Chaque référence produit (`sku`) possède un
plan de coupe transversal (le "profil") dessiné en DXF/DWG. Ce profil est
utilisé par l'app Flutter (Studio) pour le rendu en perspective calibrée
dans les photos de pièces (calepinage).

Le pipeline extrait le contour fermé de la coupe depuis un fichier DXF et
produit un fichier JSON normalisé par SKU, au format ci-dessous.

## Schéma JSON (`version_schema: 1`)

```json
{
  "sku": "D570",
  "marque": "",
  "famille": "corniche|plinthe|cimaise|rosace",
  "source": {
    "fichier": "D570.dxf",
    "insunits": 4,
    "unite_retenue": "mm",
    "origine_unite": "header|override|manuel"
  },
  "profil_mm": [[0.0, 0.0], [10.5, 3.2]],
  "face_pose_mur":     { "indices": [], "auto": true },
  "face_pose_plafond": { "indices": [], "auto": true },
  "bbox_mm": { "w": 0, "h": 0 },
  "hauteur_mur_mm": 0,
  "projection_plafond_mm": 0,
  "motif": null,
  "assets": { "albedo": null, "normal": null },
  "longueur_barre_mm": 2000,
  "prix_ml": null,
  "statut": "OK",
  "version_schema": 1
}
```

## Détail des champs

| Champ | Type | Obligatoire | Description |
|---|---|---|---|
| `sku` | string | oui | Référence produit, reprise du nom de fichier DXF (sans extension). |
| `marque` | string | oui | Marque commerciale. `""` si inconnue — **jamais inventée**. |
| `famille` | enum string | oui | `"corniche"`, `"plinthe"`, `"cimaise"`, `"rosace"` (extensible : profil, ornement...). Déduite du calque/nom de fichier si possible, sinon `null`. |
| `source.fichier` | string | oui | Nom du fichier DXF source utilisé pour l'extraction. |
| `source.insunits` | int \| null | oui | Valeur brute de `$INSUNITS` lue dans le header DXF. `null` si absente du fichier. Codes DXF standards : `0`=non spécifié, `1`=pouces, `4`=mm, `5`=cm, `6`=m. **Pour `solid2profile.py` (source maillage STL/OBJ) : toujours `null`, voir section "Extension — pipeline 3D" ci-dessous — un maillage n'a pas d'en-tête d'unités, il ne faut jamais fabriquer une valeur de champ DXF à partir d'un simple facteur d'échelle de substitution.** |
| `source.unite_retenue` | string | oui | Unité effectivement utilisée pour produire `profil_mm` (toujours convertie en `mm` en sortie). |
| `source.origine_unite` | enum string | oui | `"header"` = lue directement dans `$INSUNITS` ; `"override"` = `$INSUNITS` absent/nul et une unité par défaut a été appliquée automatiquement (voir règle batch ci-dessous) ; `"manuel"` = confirmée manuellement par un opérateur. |
| `profil_mm` | array[[x,y]] | oui (sauf `statut != "OK"`) | Liste ordonnée de sommets du contour fermé, en mm, sens horaire, après aplatissement des courbes et recalage d'origine. Vide (`[]`) si `statut != "OK"`. |
| `face_pose_mur.indices` | array[int] | oui | Indices (dans `profil_mm`) des sommets identifiés comme face d'appui contre le mur. `[]` si non déterminé automatiquement. |
| `face_pose_mur.auto` | bool | oui | `true` si détectée automatiquement (segment vertical le plus à x≈0), `false` si nécessite une revue manuelle. |
| `face_pose_plafond.indices` / `.auto` | idem | oui | Idem pour la face d'appui plafond (segment horizontal le plus proche de y≈0 après recalage). |
| `bbox_mm.w` / `.h` | number | oui | Largeur/hauteur de la bounding box du profil, en mm. |
| `hauteur_mur_mm` | number | oui | Hauteur du profil projetée sur le mur (0 si non applicable / non calculable). |
| `projection_plafond_mm` | number | oui | Profondeur du profil projetée sur le plafond (0 si non applicable). |
| `motif` | null \| object | oui | Toujours `null` en sortie du pipeline DXF. Renseigné plus tard, hors chaîne DXF (texture/relief du motif). |
| `assets.albedo` / `assets.normal` | null \| string | oui | Chemins de textures, renseignés hors pipeline DXF. `null` par défaut. |
| `longueur_barre_mm` | number | oui | Longueur commerciale standard de la barre. `2000` par défaut (barre standard Staff Décor) sauf indication contraire connue. |
| `prix_ml` | null \| number | oui | Prix au mètre linéaire. `null` si inconnu — **jamais inventé**. |
| `statut` | enum string | oui | `"OK"`, `"ERREUR_UNITES"`, `"ERREUR_SELECTION"`, `"ERREUR_LECTURE"` (voir règles d'erreur ci-dessous). |
| `version_schema` | int | oui | `1` pour ce document. |

## Règles strictes de production (rappel, cf. mission d'origine)

1. **Unités** : lire `$INSUNITS`. Si présent et non nul → `origine_unite:
   "header"`. Si absent ou = 0 → priorité 2 : lecture de `units_override.csv`
   (voir plus bas) — si le SKU y figure, `origine_unite: "override"` et
   l'unité de ce fichier est utilisée sans ambiguïté. Sinon → le batch **ne
   s'arrête pas** : le fichier est marqué `statut: "ERREUR_UNITES"`, une
   **proposition d'unité par plausibilité de bbox** est calculée (voir
   `_propose_unit_by_bbox` dans `dxf2profile.py`) et consignée dans le log
   (colonne `proposition_unite` + `proposition_motif`), **mais `profil_mm`
   reste vide** — la proposition est indicative pour aider à remplir
   `units_override.csv`, jamais appliquée automatiquement. Le run continue
   sur le fichier suivant.
2. **Sélection du contour** : ne garder que la polyligne **fermée** de
   plus grande aire, sur le calque de contour. Ignorer `HATCH`,
   `DIMENSION`, `TEXT`, cartouche, axes. Si zéro ou plusieurs candidates
   → `statut: "ERREUR_SELECTION"`, `profil_mm: []`, message listant les
   calques trouvés dans le log. Aucun choix implicite. Le run continue.
3. **Aplatissement** : `SPLINE`, `ARC`, `ELLIPSE` et bulges de
   `LWPOLYLINE` sont aplatis en segments avec une tolérance de flèche de
   0,15 mm (`ezdxf.path.from_entity` + flattening).
4. **Origine** : recalée à `x=0` sur la face mur, `y=0` sur la face
   plafond.
5. **INTERDICTION** : ne jamais compléter, lisser ou "corriger" un
   profil. Un DXF illisible ou ambigu produit une entrée `statut !=
   "OK"` avec `profil_mm: []`, jamais un profil de substitution.
6. **PNG de contrôle** : un PNG coté et tracé du profil est produit pour
   chaque SKU en `statut: "OK"` (nom : `<sku>.png`, même dossier que le
   JSON ou sous-dossier `control/`).
7. **Log par fichier** : nombre de sommets, bbox (mm), hauteur mur,
   projection plafond — un log global (`inventaire.csv` / rapport batch)
   et un log détaillé par fichier. Pour `ERREUR_UNITES`, le log contient
   obligatoirement la proposition d'unité calculée par plausibilité de
   bbox (jamais une case vide).
8. **Correspondance fichier → SKU** : jamais déduite par une regex sur le
   nom de fichier. `mapping.csv` (colonnes `fichier,sku,type`) est la
   seule source de vérité pour associer un fichier DWG/DXF à un SKU
   catalogue. Un fichier absent de `mapping.csv` est traité avec
   `sku = nom_de_fichier_sans_extension` par défaut, mais signalé
   `mapping_absent: true` dans l'inventaire/le log — jamais une déduction
   silencieuse par regex.
9. **Unités forcées** : `units_override.csv` (colonnes `sku_ou_fichier,
   insunits,motif`) est lu en priorité 2, juste après `$INSUNITS` du
   header DXF et avant toute proposition automatique. Permet de débloquer
   un fichier sans `$INSUNITS` sans jamais deviner silencieusement.

## ⚠️ ALERTE OUTIL — 3DSOLID (ACIS) illisible par FreeCAD et ODA File Converter

**Constat confirmé par l'utilisateur, à respecter dans toute recommandation future :**

- Plusieurs DXF fabricants ne contiennent aucune polyligne 2D de coupe mais
  un modèle volumique `3DSOLID` (format ACIS, propriétaire Autodesk).
- **Ni FreeCAD ni ODA File Converter ne savent lire un `3DSOLID` ACIS.**
  Ces deux outils, utilisés par ailleurs dans ce projet (conversion DWG→DXF
  via ODA), échouent silencieusement ou refusent ce type d'entité.
- **Seul AutoCAD ou BricsCAD peut exporter un maillage (STL/OBJ) depuis un
  `3DSOLID`.** Cette conversion est entièrement manuelle, effectuée par
  l'utilisateur (comme le lot ODA DWG→DXF), **jamais tentée par le pipeline
  ou l'agent**.
- **Ne jamais recommander FreeCAD pour cette étape de conversion** —
  consigne explicite de l'utilisateur, à respecter dans toute suggestion
  d'outillage future.
- Export recommandé : **STL binaire**, **déviation linéaire (tolérance de
  tessellation) ≤ 0,1 mm** — validé par l'utilisateur. Une fois le maillage
  obtenu, `solid2profile.py` (voir section suivante) prend le relais.

## Arborescence

```
/home/user/flutter_app/
  SPEC.md                          <- ce fichier
  assets/dwg/*.dwg                 <- fichiers DWG source (non convertis) -- JAMAIS supprimés
  assets/dxf/*.dxf                 <- fichiers DXF source (issus d'ODA File Converter) -- JAMAIS supprimés
  assets/solids/*.stl|*.obj        <- maillages 3D (issus d'AutoCAD/BricsCAD depuis un 3DSOLID) -- JAMAIS supprimés
  assets/profiles/<sku>.json       <- sortie JSON par SKU -- JAMAIS supprimé sans confirmation
  assets/profiles/control/<sku>.png<- PNG de contrôle coté
  assets/profiles/heightmaps/<sku>_height.png <- height map 16 bits (motif variable uniquement)
  tools/dxf_pipeline/
    scan_assets.py                 <- inventaire DWG+DXF (sku, dwg_present, dxf_present, statut)
    dxf2profile.py                 <- extraction DXF (2D) -> JSON + PNG
    solid2profile.py               <- extraction maillage 3D (STL/OBJ) -> JSON + PNG + height map
    mapping.csv                    <- correspondance fichier -> sku (source de vérité, non déduite)
    units_override.csv             <- unités forcées par sku/fichier, priorité 2 après $INSUNITS
    inventaire.csv                 <- sortie de scan_assets.py
    logs/                          <- logs détaillés par run (jamais supprimés sans confirmation)
    tests/fixtures/*.dxf           <- fixtures synthétiques de non-régression (pytest) -- permanentes
    tests/fixtures/*.stl           <- fixtures synthétiques (barres L/denticules) pour solid2profile.py
    test_dxf2profile.py            <- suite pytest de non-régression (dxf2profile.py)
    test_solid2profile.py          <- suite pytest de non-régression (solid2profile.py)
```

### `mapping.csv` — schéma

| Colonne | Description |
|---|---|
| `fichier` | Nom de fichier DWG ou DXF (ex: `D570-sansmotif.dxf`) |
| `sku` | Référence catalogue officielle (ex: `D570`) |
| `type` | `dwg` ou `dxf` |

### `units_override.csv` — schéma

| Colonne | Description |
|---|---|
| `sku_ou_fichier` | SKU ou nom de fichier concerné |
| `insunits` | Code `$INSUNITS` à appliquer (ex: `4` pour mm) |
| `motif` | Justification humaine (ex: "confirmé par plan papier original") |

## Extension — pipeline 3D (`solid2profile.py`)

**Même schéma JSON, `version_schema: 1` inchangé — aucun schéma parallèle.**
`solid2profile.py` importe directement `dxf2profile.py` (`import dxf2profile
as d2p`) et réutilise ses fonctions/constantes (`build_error_record`,
`write_json`, `load_mapping`, `load_units_override`, `propose_unit_by_bbox`,
`ensure_clockwise`, `detect_wall_and_ceiling_faces`, `INSUNITS_TO_MM`,
`SCHEMA_VERSION`). Seuls des champs **additifs** sont introduits :

| Champ | Type | Description |
|---|---|---|
| `source.methode` | string | `"section_3d"` pour tout enregistrement produit par `solid2profile.py` (y compris les erreurs). Absent/non renseigné pour `dxf2profile.py`. Ne pas confondre avec `source.origine_unite` (qui décrit l'origine de l'unité, pas la méthode d'extraction du profil). |
| `motif.type` | enum string | `"lisse"` (aire de section constante) ou `"variable"` (aire variable le long de la barre). `null` (le champ `motif` entier) si non applicable. |
| `motif.periode_mm` | number \| null | Période du motif ornemental, estimée par autocorrélation. `null` si aucun pic net détecté (jamais une valeur inventée). |
| `motif.methode` | string | `"autocorrelation"`, ou une chaîne explicative si `periode_mm` est `null` (ex : "aucun pic d'autocorrelation net"). |
| `motif.auto` | bool | `true` — détection systématiquement automatique, même convention que `face_pose_mur.auto`/`face_pose_plafond.auto`. |
| `motif.profil_source` | string | `"union_sections"` — présent uniquement quand `motif.type == "variable"`. Documente que le polygone de profil retenu (`profil_mm`) est l'**union** (pas l'enveloppe convexe) des 3 coupes min/max/médiane du balayage dense. Voir paragraphe dédié ci-dessous. |
| `assets.height` | string \| null | Chemin relatif vers la height map PNG 16 bits (`heightmaps/<sku>_height.png`), uniquement pour `motif.type == "variable"`. `null` sinon (jamais générée pour un motif lisse). Base de la future normal map de rendu — hors scope de ce script. |

**Méthode d'extraction (résumé, cf. docstring de `solid2profile.py` pour le
détail complet)** :
1. Axe long trouvé par ACP (PCA) sur les sommets du maillage.
2. Aire de section échantillonnée par un **balayage dense** le long de
   l'axe (résolution 1 mm) — remplace un échantillonnage à 3 abscisses
   fixes (25/50/75 %), rejeté après vérification empirique : un motif
   périodique peut ne tomber sur aucun des 3 points par pur hasard de
   phase et être manqué en totalité (ex. période 42 mm sur une barre de
   2000 mm — vérifié sur la fixture `TESTSOLIDE_DENTICULES.stl`).
3. Un **repère 2D fixe** (`build_fixed_rotation`, dérivé une seule fois de
   l'axe long) est imposé à toutes les coupes d'un même maillage. Sans
   cela, `Path3D.to_2D()` (trimesh) recalcule indépendamment un plan de
   référence par tranche, produisant des origines/rotations différentes
   d'une coupe à l'autre — rendant toute union/comparaison entre coupes
   géométriquement invalide (bug détecté et corrigé pendant le
   développement).
4. `motif.periode_mm` estimée par autocorrélation du signal d'aire
   (`np.correlate` + `scipy.signal.find_peaks`, prominence ≥ 0,15).
5. **Profil retenu pour un motif variable = UNION (`shapely.unary_union`),
   PAS enveloppe convexe**, des 3 polygones de coupe aux positions
   d'aire minimale, maximale et médiane, réellement localisées par le
   balayage dense (jamais des fractions arbitraires 25/50/75 %).
   **Correction de spécification** : une version antérieure de ce
   document préconisait l'enveloppe convexe de ces 3 coupes ; abandonnée
   car une corniche a des gorges concaves (creux du profil, denticules)
   que le convexe effacerait, détruisant le galbe réel de la moulure.
   Vérifié sur `TESTSOLIDE_DENTICULES.stl` : aire de l'union = 2564 mm²
   contre 4002 mm² pour l'enveloppe convexe des mêmes 3 coupes — la
   différence mesure exactement l'ampleur de la déformation qu'aurait
   introduite le convexe. `motif.profil_source="union_sections"`
   documente ce choix dans le JSON. Cas rare (coupes disjointes) : si
   l'union renvoie un `MultiPolygon`, on garde le plus grand polygone par
   aire (même logique que `section_polygon_at` pour une coupe unique).
6. Height map : pour un motif variable, distance à la face de pose
   échantillonnée sur une grille (axe long × pourtour du profil) par
   ray-casting sur le maillage réel, exportée en PNG 16 bits.

**Unités (`source.insunits`) — cas particulier maillage** : un fichier
STL/OBJ n'a pas d'en-tête `$INSUNITS` (contrairement au DXF). L'unité est
toujours fournie par substitution externe (`units_override.csv`,
`source.origine_unite="override"`). Le facteur d'échelle interne
(`insunits_raw`, réutilisé via `d2p.INSUNITS_TO_MM` pour la conversion mm)
n'est **jamais** exposé comme `source.insunits` dans le JSON — ce champ
vaut systématiquement `null` pour `solid2profile.py`, afin de ne pas faire
croire qu'un en-tête d'unités DXF a été lu sur un maillage qui n'en a pas.

**Fixtures de validation** (vérité de terrain connue, `tests/fixtures/`,
jamais dans `assets/`) : `TESTSOLIDE_L.stl` (barre 2 m, profil en L,
section constante → `motif=null`) et `TESTSOLIDE_DENTICULES.stl` (même
profil + 47 denticules réguliers tous les 42 mm → `motif.type="variable"`,
`motif.periode_mm≈42`, height map non triviale, `motif.profil_source=
"union_sections"`). Validées par `test_solid2profile.py` (26 tests, tous
verts).

## Observation — logique de nommage des SKU (suffixes)

**Statut : observation empirique, PAS une règle métier confirmée.**
Cette section documente un motif récurrent observé dans `manifest.csv`
(1023 fichiers, 710 SKU) en résolvant le lot pilote (SKU `1101`/`1101E`
sans correspondance exacte). Elle est là pour aider à interpréter les
~950 SKU restants, mais **ne doit jamais servir à déduire ou fabriquer
un SKU par regex** — la règle "mapping via `mapping.csv`, jamais déduit"
reste absolue. En cas de doute sur un SKU réel, se référer à
`manifest.csv` (source de vérité) et/ou demander confirmation.

De nombreux SKU numériques de la catégorie **Moulures** portent un
suffixe alphabétique désignant une variante du même profil de base.
Observé sur le radical `11xx` (ex: `1101`, `1103`, `1200`, `1202`,
`1207`, `1210`) :

| Suffixe | Catégorie GED observée | Sens probable (hypothèse, non confirmée) |
|---|---|---|
| `H` | Angles et doucines / Chapiteaux / Classiques | Angle **H**aut / **H**orizontal ? |
| `BH` | Angles et doucines (7 occurrences, exclusivement) | Combinaison **B**as+**H**aut ou variante d'angle |
| `C` | Cimaises / Moulures / Grandes dimensions | Corniche / **C**imaise |
| `E` | Angles et doucines / Profils LED / Équerres-U-Joints creux | Angle/**É**querre, ou **E**xtrémité |
| `B` | Classiques / Socles / Ornementées | **B**as / **B**ase |
| `P` | Moulures / Profils de finition / Rosaces / Puits de lumière | **P**etit, ou **P**rofil |
| `I` | Profils LED / Équerres-U-Joints creux | **I**ntérieur ? (à l'opposé possible de `E`) |
| `L` | Passages et meubles de passage / Classiques | **L**inteau ? |
| `M` | Corniches à éclairage indirect / Modulostaff / Plinthes | **M**odule / **M**oulure |
| `A` | Grandes dimensions / Plinthes et talons | **A**ngle ? |
| `S` | Angles et doucines / Plinthes et talons | **S**pécial ? |

**Cas concret ayant motivé cette note** : le SKU radical `1101` (sans
suffixe) n'existe pas tel quel dans le manifeste — seules ses variantes
suffixées existent : `1101-1108` (dwg combiné 1101+1108, catégorie
Moulures), `1101BH`, `1101C` (catégorie Cimaises — donc *pas* la même
catégorie GED que les autres suffixes 1101), `1101E-1` (noter le `-1`
additionnel), `1101H`. Le suffixe `E` demandé par l'utilisateur («
1101E ») correspond en réalité au SKU manifeste `1101E-1` (avec un
suffixe numérique supplémentaire `-1`, motif non expliqué par ce
tableau).

**Limite explicite de cette observation** : le mapping `catégorie GED
↔ suffixe` n'est pas strictement 1:1 (ex. `C` apparaît à la fois en
Cimaises, Moulures et Grandes dimensions ; `H` apparaît en Angles et
doucines, Chapiteaux et Classiques) — donc le suffixe seul ne permet
**pas** de déduire la catégorie ou la géométrie avec certitude. À
utiliser uniquement comme aide de lecture humaine, jamais comme règle
de code.

## Champs commerciaux — rappel

`marque`, `prix_ml`, `longueur_barre_mm` (si non standard) : toujours
`null` (ou valeur par défaut documentée ci-dessus) si non connus avec
certitude. **Jamais inventés.**

## Décision d'architecture — rendu 3D côté Flutter (post-pipeline DXF)

**Statut : décidé, non codé.** Cette section documente le choix retenu
et les options rejetées, pour éviter toute redécouverte future des
mêmes impasses.

### Constat de départ

Le rendu actuel (`lib/core/perspective/moulure_painter.dart`,
`cornice_plinth_painter.dart`) plaque une **texture photo** sur un quad
2D déformé en perspective (`Vertices` + `ImageShader` sur `CustomPainter`
Skia). Le profil réel de la moulure n'intervient pas dans le dessin :
c'est une approximation visuelle, pas une géométrie exacte. C'est le
défaut à corriger.

### Option retenue : "A bis" — maillage réel, même technique de dessin

On garde `CustomPainter` + `drawVertices` + Skia (aucun changement de
techno de rendu). Ce qui change, c'est **ce qui est dessiné** : un
maillage 3D réel, issu de `profil_mm` (le pipeline DXF), extrudé le
long de la polyligne de pose, projeté par une vraie caméra — puis
seulement à ce stade rasterisé en triangles 2D via `drawVertices`.

Architecture cible (Dart pur pour `geometry/`, testable sans UI) :

- **`geometry/`** (aucune dépendance UI) :
  - `Mat4` / `Vec3` maison ou `vector_math` (déjà transitivement
    présent via Flutter — à confirmer avant usage, ne pas l'ajouter en
    dépendance directe sans vérifier qu'il n'entraîne pas de montée de
    version).
  - `camera.dart` : matrice caméra construite depuis `PerspCalib`
    (focale + pose), projection perspective sommets 3D → écran 2D.
  - `planes.dart` : plans mur et plafond exprimés en mètres ; leur
    intersection analytique donne l'arête mur/plafond. **Jamais
    détectée visuellement** — toujours calculée depuis la géométrie
    connue des plans.
  - `sweep.dart` : extrusion de `profil_mm` (JSON du pipeline DXF) le
    long de la polyline de pose ; faces de pose contraintes aux plans
    mur/plafond ; onglets calculés sur plan bissecteur aux angles.
    Sortie : positions 3D + indices de triangulation + normales.
- **`rendering/`** : projection des sommets via `camera.dart`, tri des
  triangles par l'algorithme du peintre (painter's algorithm, tri par
  profondeur), `drawVertices` avec couleur par sommet (ombrage plat =
  produit scalaire normale/direction de lumière). `ImageShader`
  conservé, mais **uniquement** pour les moulures ornées (motif
  répétitif), avec UV calculées au pas réel en mm (pas d'étirement
  approximatif d'une texture sur un quad).

Ordre de grandeur attendu : ~5000 triangles par corniche — sans
difficulté pour Skia sur les plateformes cibles (Web + Android).

**À supprimer une fois A bis opérationnel** : le chemin "texture photo
sur quad déformé" dans `moulure_painter.dart` et
`cornice_plinth_painter.dart` (code legacy, à retirer, pas à garder en
fallback silencieux).

**Occlusion (plantes, meubles devant la moulure) : explicitement hors
périmètre pour l'instant.** Traitement futur envisagé : masque alpha
dessiné par l'utilisateur, ou depth map. **Ne pas anticiper cela dans
le code de A bis** — complexité à ne pas préémptivement absorber.

### Options rejetées et pourquoi

- **Option B (packages 3D Flutter natifs — `flutter_scene`,
  `flutter_cube`, etc.)** : **rejetée**. Écosystème encore trop jeune
  / peu mature pour une app de production (maintenance incertaine,
  couverture de plateforme incomplète, API instables). Réévaluable
  dans le futur si l'écosystème mûrit, mais pas maintenant.
- **Option C (WebView embarquée + three.js/opencv.js, fidèle au brief
  moteur d'origine qui était pensé web)** : **rejetée**. Reviendrait à
  faire tourner **deux moteurs de rendu** dans la même app (Skia natif
  Flutter + moteur JS dans une WebView), avec un pont JS↔Dart fragile
  (`JavascriptChannel`), un poids de build significativement alourdi
  (bundler un moteur JS complet), pour un gain nul par rapport à A bis
  qui atteint le même résultat (maillage réel, vraie caméra) en restant
  100% Dart/Skia natif. Non retenue.

### Interface avec le pipeline DXF

Aucun changement du pipeline DXF (`dxf2profile.py`, `scan_assets.py`,
schéma JSON ci-dessus) : `profil_mm` reste la seule donnée géométrique
consommée par `sweep.dart`. Le pipeline continue de produire du JSON
neutre, indépendant de la technique de rendu choisie côté Flutter.
