# SPEC.md — Schéma des profils produit (pipeline DXF → JSON)

**Statut : source de vérité.** Tout script du pipeline (`scan_assets.py`,
`dxf2profile.py`, et tout code Flutter qui consomme ces JSON) doit relire ce
fichier avant modification. Toute évolution du schéma passe par une bascule
de `version_schema` et une mise à jour de ce document.

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
| `source.insunits` | int \| null | oui | Valeur brute de `$INSUNITS` lue dans le header DXF. `null` si absente du fichier. Codes DXF standards : `0`=non spécifié, `1`=pouces, `4`=mm, `5`=cm, `6`=m. |
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
   "header"`. Si absent ou = 0 → le batch **ne s'arrête pas** : le fichier
   est marqué `statut: "ERREUR_UNITES"`, `origine_unite: "override"`, une
   unité par défaut (`mm`) est proposée dans `source.unite_retenue` **mais
   `profil_mm` reste vide** et le fichier est signalé dans le log/rapport
   pour confirmation manuelle ultérieure. Le run continue sur le fichier
   suivant.
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
   et un log détaillé par fichier.

## Arborescence

```
/home/user/flutter_app/
  SPEC.md                          <- ce fichier
  assets/dxf/*.dxf                 <- fichiers DXF source (issus d'ODA File Converter)
  assets/profiles/<sku>.json       <- sortie JSON par SKU
  assets/profiles/control/<sku>.png<- PNG de contrôle coté
  tools/dxf_pipeline/
    scan_assets.py                 <- inventaire des DXF disponibles
    dxf2profile.py                 <- extraction DXF -> JSON + PNG
    inventaire.csv                 <- sortie de scan_assets.py
    logs/                          <- logs détaillés par run
```

## Champs commerciaux — rappel

`marque`, `prix_ml`, `longueur_barre_mm` (si non standard) : toujours
`null` (ou valeur par défaut documentée ci-dessus) si non connus avec
certitude. **Jamais inventés.**
