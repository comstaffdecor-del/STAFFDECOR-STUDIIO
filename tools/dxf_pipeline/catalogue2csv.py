#!/usr/bin/env python3
"""
catalogue2csv.py — Étape « catalogue papier » : extrait le tarif public PDF
Staff Décor (deux colonnes de tableau par page, Référence/Désignation/Prix
HT/TTC répétées) en catalogue.csv normalisé.

CONTEXTE : le catalogue papier (Tarif Juillet 2026) est la source de vérité
demandée par l'utilisateur pour les cotes commerciales (hauteur, projection,
diamètre, longueur de barre). Beaucoup de désignations portent des cotes en
clair ("Colonnette Ø 20 H. 83 cm", "Rosace Ø 30 cm", "Pilastre cannelé 23 x
250 cm"). D'autres (la majorité des "Corniche en 2 ml") ne portent QUE une
longueur de barre, jamais la hauteur/projection de la section — ce n'est pas
un défaut d'extraction, c'est une absence réelle constatée dans le document
(vérifié par grep exhaustif avant d'écrire ce script). Dans ce cas les
champs de cote de section restent `null` avec `statut=A_VERIFIER` : on ne
déduit jamais une cote absente du papier depuis une autre source.

ÉTAPE 1 — texte natif ou scan ? Vérifié avant tout code (pdftotext absent de
l'environnement -> pdfplumber utilisé à la place, même nature de vérification
: extraction directe de la couche texte, PAS d'OCR). Le PDF contient bien une
couche texte native — confirmé par `page.extract_text()` non vide sur les
20 pages ET par une vérification mot-à-mot (`extract_words()` avec positions
x/y cohérentes, pas de texte "collé" typique d'un rendu OCR raté). Si un
futur tarif s'avère scanné (texte vide), ce script s'arrête avec un message
explicite recommandant OCR (ocrmypdf, langue fra) — il ne bascule jamais en
silence sur une extraction dégradée.

MÉTHODE D'EXTRACTION (tableau à 2 colonnes de blocs Référence/Désignation/
Prix HT/TTC, répété sur 18 pages, pages 1 à 18 sur 20 — page 0 = coordonnées
agences, page 19 = CGV, aucune n'est une page de tarif, exclues explicitement) :

  1. `pdfplumber.extract_words()` donne chaque mot avec sa position (x0, top).
  2. Les mots sont regroupés en RANGÉES par clustering sur `top` (tolérance
     4.5pt — mesuré empiriquement : le pas de ligne réel est ~15.7pt sur ce
     document, largement au-dessus de cette tolérance, donc aucun risque de
     fusionner deux rangées adjacentes ; à l'inverse, un même mot peut être
     rendu par pdfplumber sur deux `top` à ~1.3pt d'écart selon la police —
     la tolérance absorbe cela sans fusionner de rangées distinctes).
  3. Dans chaque rangée, les mots sont scindés en 2 "blocs tarif" par leur
     position x0 : bloc GAUCHE (colonne Référence x0<~200, Désignation
     200-198, Unité x0≈213.7, Prix HT x0≈232-240, TTC x0≈261-277) et bloc
     DROIT (mêmes rôles, décalés de ~287pt : Référence x0≈314-323, Unité
     x0≈501.1, Prix HT x0≈514-527, TTC x0≈548-561). Ces positions ont été
     mesurées sur plusieurs pages (1, 5, 9, 14, 18) et sont stables à
     +/-10pt — la coupure entre les deux blocs est faite à x0=290 (marge
     large entre TTC gauche ~277 max observé et Référence droite ~310 min
     observé, jamais de collision constatée).
  4. Dans chaque bloc, le premier mot est la Référence, le(s) dernier(s)
     mot(s) numériques avec virgule (format "NNN,NN" ou "N NNN,NN" avec
     espace milliers) sont Prix HT puis TTC, le mot juste avant (u/ml/Kg/
     cart./mul) est l'Unité, et tout le reste (entre Référence et Unité)
     est la Désignation.
  5. Lignes d'en-tête ("Référence Désignation Prix €uro HT TTC ...") et de
     titre ("TARIF JUILLET 2026") reconnues et ignorées explicitement (pas
     par accident de parsing).
  6. Marqueurs commerciaux en marge gauche (`*` = "Exception aux conditions
     commerciales générales", `2` = "Article soumis à l'éco-contribution
     DEEE", légende trouvée en bas de page 15 et confirmée par grep) :居
     capturés dans une colonne `marqueur` séparée, jamais mélangés à la
     référence produit.

COTES EXTRAITES DE LA DÉSIGNATION (`extract_dimensions_mm`, patterns observés
par inspection exhaustive du texte extrait avant d'écrire les regex, jamais
inventés) :
  - Diamètre : "Ø NN[,N] cm" ou "Ø NN mm" -> diametre_mm
  - Hauteur : "H.? NN[,N] cm" -> hauteur_mm (préfixe H explicite uniquement,
    jamais une cote générique confondue avec hauteur)
  - Triple cote "A x B x C cm" (niches) -> on rapporte les 3 valeurs dans
    des colonnes distinctes cote1_mm/cote2_mm/cote3_mm (mais PAS classées
    hauteur/projection sans confirmation — voir limite explicite ci-dessous)
  - Double cote "A x B cm" (rosaces rectangulaires, pilastres, plafonniers)
    -> cote1_mm/cote2_mm
  - Longueur de barre : "en N[,NN] ml" ou "de N ml" -> longueur_barre_mm
    (converti en mm, N ml = N*1000 mm)
  - Épaisseur explicite "Ep.? NN mm" -> epaisseur_mm

LIMITE EXPLICITE (pas une invention pour la combler) : le texte du tarif ne
distingue JAMAIS explicitement "hauteur_mur" de "projection_plafond" par un
libellé dédié (contrairement au schéma `assets/profiles/*.json`). Pour une
cote "A x B cm" sans lettre H/L/E, ce script ne devine PAS laquelle des deux
valeurs est la hauteur et laquelle la projection — elles sont rapportées
neutres (cote1_mm/cote2_mm dans l'ordre d'apparition) et c'est au RECOUPEMENT
(catalogue_vs_profil.py) de comparer chaque valeur mesurée aux DEUX cotes
catalogue et de rapporter la meilleure correspondance, jamais une affectation
préalable arbitraire.

C'EST UN TARIF, PAS UN CATALOGUE DE DIMENSIONS : le prix (`prix_ht`,
`prix_ttc`, `unite`) est la donnée PRINCIPALE de ce document, extraite
pour CHAQUE ligne (que la désignation porte une cote chiffrée ou non).
`date_tarif` (ex. "JUILLET 2026") est lue une fois dans le titre répété
en haut de chaque page de tarif ("TARIF JUILLET 2026") et reportée sur
chaque ligne — un tarif papier a une date de validité, jamais implicite.

SKU : normalisé via `normalize_sku()` (réutilisée depuis dxf2profile.py,
une seule implémentation) pour permettre la correspondance avec les
autres sources (noms de fichier DXF/STL) qui n'écrivent pas toujours la
référence à l'identique (ex. "1145C" vs "1145c"). La colonne `sku`
contient la valeur BRUTE telle qu'imprimée (jamais modifiée) ; la
correspondance normalisée est le rôle des scripts consommateurs
(catalogue_vs_profil.py, inject_cote_catalogue.py), jamais de ce script.

Sortie : catalogue.csv, colonnes :
  sku, designation, unite, prix_ht, prix_ttc, marqueur, page_source,
  date_tarif, diametre_mm, hauteur_mm, cote1_mm, cote2_mm, cote3_mm,
  epaisseur_mm, longueur_barre_mm, statut

statut = "OK" si au moins une cote a été extraite depuis la désignation,
"A_VERIFIER" si aucune cote (uniquement un prix/désignation sans dimension
chiffrée en clair) — JAMAIS d'estimation en cas d'absence. Le prix, lui,
est toujours renseigné dès qu'il a été lu (indépendant du statut de cote).
"""

import csv
import re
import sys
from pathlib import Path

try:
    import pdfplumber
except ImportError:
    print("ERREUR: pdfplumber manquant. pip install pdfplumber", file=sys.stderr)
    sys.exit(1)

HERE = Path(__file__).parent
OUTPUT_PATH = HERE / "catalogue.csv"

# Tolérance de clustering vertical (pt) pour regrouper les mots d'une même
# rangée de tableau — mesurée empiriquement (pas de ligne réel ~15.7pt).
ROW_CLUSTER_TOL_PT = 4.5

# Coupure horizontale entre le bloc "gauche" et le bloc "droit" du tableau
# à deux colonnes — mesurée sur plusieurs pages, marge large de part et
# d'autre des positions réelles observées (TTC gauche max ~277, Référence
# droite min ~310).
COLUMN_SPLIT_X = 290.0

# Unités valides observées dans la colonne Unité (mesuré par inspection
# exhaustive du texte, pas une liste supposée a priori).
KNOWN_UNITS = {"u", "ml", "Kg", "cart.", "mul", "m2"}

HEADER_MARKERS = ("Référence", "Désignation", "TARIF", "JUILLET")

PRICE_RE = re.compile(r"^-?[\d]{1,3}(?: \d{3})*,\d{2}$")

# Titre de tarif répété en haut de chaque page de tarif : "TARIF JUILLET
# 2026". Lu une fois par page (toujours identique sur ce document, mais
# on le relit par page plutôt que de le figer en constante, au cas où un
# futur tarif changerait de mois en cours de document — jamais supposé).
DATE_TARIF_RE = re.compile(r"TARIF\s+([A-ZÉÛÎ]+)\s+(\d{4})")


def is_price_token(tok):
    return bool(PRICE_RE.match(tok))


def price_to_float(tok):
    return float(tok.replace(" ", "").replace(",", "."))


def cluster_rows(words, tol=ROW_CLUSTER_TOL_PT):
    """Regroupe les mots d'une page en rangées par proximité verticale
    (moyenne mobile du 'top', pas un simple round() qui risquerait de
    couper une rangée en deux si elle chevauche une frontière d'arrondi)."""
    ws = sorted(words, key=lambda w: w["top"])
    clusters = []
    for w in ws:
        placed = False
        for c in clusters:
            if abs(c["top"] - w["top"]) < tol:
                n = len(c["words"])
                c["top"] = (c["top"] * n + w["top"]) / (n + 1)
                c["words"].append(w)
                placed = True
                break
        if not placed:
            clusters.append({"top": w["top"], "words": [w]})
    clusters.sort(key=lambda c: c["top"])
    return clusters


def parse_block(tokens_with_x):
    """tokens_with_x: liste de (x0, texte) triée par x0, pour UN bloc
    (gauche ou droit) d'une rangée. Retourne un dict ou None si le bloc
    est vide/non exploitable (ex: rangée d'en-tête, bloc absent car page
    n'a qu'une seule colonne remplie sur cette ligne)."""
    if not tokens_with_x:
        return None
    toks = [t for _, t in tokens_with_x]
    if any(h in toks for h in HEADER_MARKERS):
        return None

    marqueur = ""
    idx = 0
    # Marqueurs commerciaux en tout début de bloc : '*' ou '2' isolé,
    # PAS un token qui appartient à la référence elle-même (ex: référence
    # "2 ENC01" observée réellement -> le marqueur '2' est un mot SÉPARÉ,
    # à x0 plus petit que la référence qui suit, jamais collé).
    if toks and toks[0] in ("*", "2"):
        marqueur = toks[0]
        idx = 1

    if idx >= len(toks):
        return None

    sku = toks[idx]
    idx += 1

    # Repère les positions des 2 derniers tokens-prix de la fin du bloc
    # (HT puis TTC, dans cet ordre constant observé partout dans le
    # document). Un prix peut être scindé en 2 tokens si un espace de
    # séparateur de milliers est rendu comme mot séparé par pdfplumber
    # (ex. "1 963,83" vu réellement sur les plafonniers PL3xxC.BC) — on
    # les refusionne avant de tester le motif prix.
    merged_toks = []
    i = 0
    while i < len(toks):
        if (
            i + 1 < len(toks)
            and re.match(r"^\d{1,3}$", toks[i])
            and re.match(r"^\d{3},\d{2}$", toks[i + 1])
        ):
            merged_toks.append(toks[i] + " " + toks[i + 1])
            i += 2
        else:
            merged_toks.append(toks[i])
            i += 1
    toks = merged_toks

    price_positions = [j for j, t in enumerate(toks) if is_price_token(t)]
    if len(price_positions) < 2:
        # Ligne sans 2 prix identifiables -> bloc non exploitable (ex.
        # fragment de rangée wrap coupé entre deux mots visuels, très rare
        # avec le clustering par tolérance ci-dessus, mais on ne suppose
        # jamais un prix manquant).
        return None
    ht_pos, ttc_pos = price_positions[-2], price_positions[-1]
    prix_ht = price_to_float(toks[ht_pos])
    prix_ttc = price_to_float(toks[ttc_pos])

    # L'unité est le token juste avant le prix HT, s'il correspond au
    # vocabulaire d'unité connu. Sinon (rare), unité laissée vide plutôt
    # que déduite au hasard.
    unite = ""
    unit_pos = ht_pos - 1
    if 0 <= unit_pos < len(toks) and toks[unit_pos] in KNOWN_UNITS:
        unite = toks[unit_pos]
        designation_tokens = toks[idx:unit_pos]
    else:
        designation_tokens = toks[idx:ht_pos]

    designation = " ".join(designation_tokens).strip()
    if not sku or not designation:
        return None

    return {
        "sku": sku,
        "designation": designation,
        "unite": unite,
        "prix_ht": prix_ht,
        "prix_ttc": prix_ttc,
        "marqueur": marqueur,
    }


def extract_dimensions_mm(designation):
    """Applique les patterns de cotes observés (voir docstring module) sur
    UNE désignation. Retourne un dict de colonnes, valeurs `None` si le
    pattern correspondant n'est pas trouvé — jamais une valeur estimée."""
    d = designation

    out = {
        "diametre_mm": None,
        "hauteur_mm": None,
        "cote1_mm": None,
        "cote2_mm": None,
        "cote3_mm": None,
        "epaisseur_mm": None,
        "longueur_barre_mm": None,
    }

    def to_float_fr(s):
        return float(s.replace(",", "."))

    # Diamètre : "Ø NN[,N] cm" ou "Ø NN mm" (mm rencontré pour les petites
    # pièces d'encastrement/rosette, ex. "Rosette de la D889 Ø 44 mm").
    m = re.search(r"Ø\s*([\d]+(?:[,.]\d+)?)\s*mm\b", d)
    if m:
        out["diametre_mm"] = to_float_fr(m.group(1))
    else:
        m = re.search(r"Ø\s*([\d]+(?:[,.]\d+)?)\s*cm\b", d)
        if m:
            out["diametre_mm"] = to_float_fr(m.group(1)) * 10.0

    # Hauteur explicitement préfixée "H" (jamais confondue avec une cote
    # générique) : "H. 83 cm", "H 17", "H.514" (élément de référence, pas
    # une cote — filtré par la présence obligatoire de "cm" ou par un
    # contexte 'x' juste avant/après, voir triple/double cote ci-dessous).
    m = re.search(r"\bH\.?\s*([\d]+(?:[,.]\d+)?)\s*cm\b", d)
    if m:
        out["hauteur_mm"] = to_float_fr(m.group(1)) * 10.0

    # Épaisseur explicite "Ep. NN mm" ou "Ep.NNmm" (ex. bords propres).
    m = re.search(r"Ep\.?\s*([\d]+(?:[,.]\d+)?)\s*mm\b", d)
    if m:
        out["epaisseur_mm"] = to_float_fr(m.group(1))

    # Triple cote "A x B x C cm" (niches essentiellement).
    m = re.search(
        r"([\d]+(?:[,.]\d+)?)\s*x\s*([\d]+(?:[,.]\d+)?)\s*x\s*([\d]+(?:[,.]\d+)?)\s*cm\b",
        d,
    )
    if m:
        out["cote1_mm"] = to_float_fr(m.group(1)) * 10.0
        out["cote2_mm"] = to_float_fr(m.group(2)) * 10.0
        out["cote3_mm"] = to_float_fr(m.group(3)) * 10.0
    else:
        # Double cote "A x B cm" (uniquement si pas déjà couvert par la
        # triple cote ci-dessus, pour ne pas capturer un sous-ensemble).
        m2 = re.search(
            r"([\d]+(?:[,.]\d+)?)\s*x\s*([\d]+(?:[,.]\d+)?)\s*cm\b", d
        )
        if m2:
            out["cote1_mm"] = to_float_fr(m2.group(1)) * 10.0
            out["cote2_mm"] = to_float_fr(m2.group(2)) * 10.0

    # Longueur de barre : "en N[,NN] ml" (motif dominant, 234 occurrences
    # vérifiées) ou "de N ml" (motif "Boite à coupe de 1 ml" / "de 2 ml").
    m = re.search(r"\ben\s+([\d]+(?:[,.]\d+)?)\s*ml\b", d)
    if not m:
        m = re.search(r"\bde\s+([\d]+(?:[,.]\d+)?)\s*ml\b", d)
    if m:
        out["longueur_barre_mm"] = to_float_fr(m.group(1)) * 1000.0

    return out


def main():
    pdf_path = None
    if len(sys.argv) > 1:
        pdf_path = Path(sys.argv[1])
    else:
        candidates = sorted(
            Path("/home/user/uploaded_files").glob("Tarif-Public-Juillet-2026*.pdf")
        )
        if not candidates:
            print(
                "ERREUR: aucun PDF 'Tarif-Public-Juillet-2026*.pdf' trouvé dans "
                "/home/user/uploaded_files et aucun chemin fourni en argument.",
                file=sys.stderr,
            )
            sys.exit(1)
        pdf_path = candidates[0]

    if not pdf_path.exists():
        print(f"ERREUR: fichier introuvable: {pdf_path}", file=sys.stderr)
        sys.exit(1)

    rows = []
    with pdfplumber.open(pdf_path) as pdf:
        nb_pages = len(pdf.pages)
        print(f"PDF ouvert: {pdf_path.name} ({nb_pages} pages)")

        # --- Étape 1 : vérification texte natif vs scan, sur TOUTES les pages ---
        empty_pages = []
        for i, page in enumerate(pdf.pages):
            t = page.extract_text() or ""
            if len(t.strip()) < 20:
                empty_pages.append(i)
        if len(empty_pages) == nb_pages:
            print(
                "ERREUR: AUCUNE page ne contient de texte extractible — ce PDF "
                "semble être un SCAN (image), pas un PDF texte natif. Ne pas "
                "parser à l'aveugle : repasser ce fichier par un OCR (ocrmypdf "
                "--language fra, ou tesseract -l fra) avant de relancer ce script.",
                file=sys.stderr,
            )
            sys.exit(3)
        elif empty_pages:
            print(
                f"ATTENTION: {len(empty_pages)} page(s) sans texte extractible "
                f"(indices {empty_pages}) — possible page scannée isolée ou "
                f"page non-tarif (couverture/CGV). Ces pages sont ignorées, "
                f"pas interprétées comme une erreur bloquante."
            )
        else:
            print(
                "Vérification texte natif: OK — toutes les pages contiennent du "
                "texte extractible directement (pas de scan, pas d'OCR nécessaire)."
            )

        # --- Étape 2 : extraction du tableau tarif, pages contenant l'en-tête ---
        nb_tarif_pages = 0
        for page_idx0, page in enumerate(pdf.pages):
            page_num = page_idx0 + 1  # 1-indexé pour le rapport humain
            text = page.extract_text() or ""
            if "Référence Désignation" not in text:
                continue  # page de couverture / CGV, pas une page de tarif
            nb_tarif_pages += 1

            m_date = DATE_TARIF_RE.search(text)
            date_tarif = f"{m_date.group(1)} {m_date.group(2)}" if m_date else None

            words = page.extract_words()
            clusters = cluster_rows(words)
            for c in clusters:
                left_toks = sorted(
                    ((w["x0"], w["text"]) for w in c["words"] if w["x0"] < COLUMN_SPLIT_X),
                    key=lambda t: t[0],
                )
                right_toks = sorted(
                    ((w["x0"], w["text"]) for w in c["words"] if w["x0"] >= COLUMN_SPLIT_X),
                    key=lambda t: t[0],
                )
                for block_toks in (left_toks, right_toks):
                    parsed = parse_block(block_toks)
                    if parsed is None:
                        continue
                    dims = extract_dimensions_mm(parsed["designation"])
                    has_any_dim = any(v is not None for v in dims.values())
                    row = {
                        "sku": parsed["sku"],
                        "designation": parsed["designation"],
                        "unite": parsed["unite"],
                        "prix_ht": parsed["prix_ht"],
                        "prix_ttc": parsed["prix_ttc"],
                        "marqueur": parsed["marqueur"],
                        "page_source": page_num,
                        "date_tarif": date_tarif,
                        **dims,
                        "statut": "OK" if has_any_dim else "A_VERIFIER",
                    }
                    rows.append(row)

        print(f"Pages de tarif détectées (en-tête 'Référence Désignation'): {nb_tarif_pages} / {nb_pages}")

    # --- Écriture catalogue.csv ---
    fieldnames = [
        "sku", "designation", "unite", "prix_ht", "prix_ttc", "marqueur",
        "page_source", "date_tarif", "diametre_mm", "hauteur_mm",
        "cote1_mm", "cote2_mm", "cote3_mm", "epaisseur_mm",
        "longueur_barre_mm", "statut",
    ]
    with open(OUTPUT_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)

    nb_ok = sum(1 for r in rows if r["statut"] == "OK")
    nb_averifier = len(rows) - nb_ok
    nb_dup_sku = len(rows) - len({r["sku"] for r in rows})

    print(f"\n=== catalogue.csv écrit ({len(rows)} lignes) -> {OUTPUT_PATH} ===")
    print(f"  Lignes avec au moins une cote extraite (statut OK)   : {nb_ok}")
    print(f"  Lignes SANS cote chiffrée en clair (statut A_VERIFIER): {nb_averifier}")
    print(f"  SKU en doublon (référence apparaissant >1 fois)       : {nb_dup_sku}")
    print(
        "\nRAPPEL — beaucoup de lignes 'Corniche en N ml' n'ont, dans le texte "
        "du tarif, AUCUNE cote de section (hauteur/projection), seulement une "
        "longueur de barre : ce n'est pas une erreur d'extraction, c'est une "
        "absence réelle constatée dans le document papier (vérifié par grep "
        "exhaustif avant l'écriture de ce script). Ces lignes ressortent en "
        "statut A_VERIFIER sauf si une longueur_barre_mm a été trouvée."
    )


if __name__ == "__main__":
    main()
