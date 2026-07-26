#!/usr/bin/env python3
"""
build_manifest.py — Étape 2a (révisée) : construit manifest.csv à partir
d'un parcours RÉEL et LECTURE SEULE de la GED (login -> catégories ->
fiches référence -> tableau de fichiers). AUCUN téléchargement de contenu
de fichier n'est effectué : seules les pages HTML (login, accueil,
catégories, fiches référence) sont lues.

Politesse imposée : pas de parallélisme (1 requête à la fois, largement
sous la limite de 2 simultanées autorisée), delay=300ms entre deux
requêtes GET, pour ne pas charger la GED de production.

Sortie :
  - manifest.csv : sku, categorie, nom_fichier, extension, taille_octets_estimee,
    taille_affichee_ged, download_url, type_presume
    (restreint aux fichiers .dwg et .dxf — voir note dans la sortie console)
  - Récapitulatif imprimé : nb fichiers + volume par catégorie et par
    type_presume, SKU sans candidat 2D.
  - Vérifie sur TOUTES les fiches référence parcourues si un contenu
    textuel descriptif existe hors du tableau de fichiers (désignation,
    dimensions, longueur de barre, matière) et rapporte le résultat réel
    (aucune invention).

IMPORTANT sur taille_octets_estimee : la GED affiche un poids humain
("241.3 Ko", "35.31 Mo"), pas un Content-Length exact. Ce script convertit
CE texte affiché en octets avec la convention 1 Ko = 1024 o, 1 Mo = 1024^2 o
(hypothèse déclarée, pas une mesure octet-exacte). Pour un octet-exact, il
faudrait des requêtes HEAD supplémentaires (non faites ici pour limiter la
charge sur la GED) — à faire uniquement si demandé.
"""

import csv
import io
import os
import re
import sys
import time
from pathlib import Path
from urllib.parse import urljoin

import requests

try:
    from dotenv import load_dotenv
except ImportError:
    print("ERREUR: python-dotenv manquant. pip install python-dotenv", file=sys.stderr)
    sys.exit(1)

try:
    from PIL import Image
except ImportError:
    print("ERREUR: Pillow manquant (nécessaire pour lire les dimensions px des "
          "miniatures sans les enregistrer sur disque). pip install Pillow", file=sys.stderr)
    sys.exit(1)

HERE = Path(__file__).parent
ENV_PATH = HERE / ".env"
MANIFEST_PATH = HERE / "manifest.csv"
THUMBNAILS_PATH = HERE / "thumbnails.csv"
DELAY_S = 0.3  # 300 ms entre deux requêtes, imposé par consigne utilisateur

# Nom de fichier du placeholder "dossier" générique observé sur la GED
# quand un SKU n'a pas de vraie miniature produit (ex: Folder-voir.png).
# Détecté par motif de nom de fichier, pas par contenu de l'image.
PLACEHOLDER_THUMBNAIL_HINTS = ("folder-voir", "folder_voir")

USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)
CAPTCHA_HINTS = ("captcha", "recaptcha", "hcaptcha", "cf-turnstile")
JS_CHALLENGE_HINTS = ("just a moment", "checking your browser", "cf-browser-verification", "__cf_chl")

# Extensions retenues dans le manifeste : uniquement les fichiers CAO
# pertinents pour le pipeline profils. Restriction déclarée explicitement
# (pas une omission silencieuse) — voir message affiché en fin de run.
RETAINED_EXTENSIONS = {"dwg", "dxf"}


class GedAccessError(RuntimeError):
    pass


def load_credentials():
    if not ENV_PATH.exists():
        raise GedAccessError(f".env introuvable à {ENV_PATH}")
    load_dotenv(ENV_PATH)
    base_url = os.environ.get("GED_BASE_URL", "").strip()
    email = os.environ.get("GED_EMAIL", "").strip()
    password = os.environ.get("GED_PASSWORD", "").strip()
    missing = [k for k, v in [("GED_BASE_URL", base_url), ("GED_EMAIL", email), ("GED_PASSWORD", password)] if not v]
    if missing:
        raise GedAccessError(f"Variables manquantes dans .env: {', '.join(missing)}")
    return base_url, email, password


def detect_blocker(text, status_code, content_type):
    if status_code == 403:
        return "HTTP 403 reçu — accès refusé par le serveur."
    low = text.lower()
    for hint in CAPTCHA_HINTS:
        if hint in low:
            return f"Captcha détecté (motif '{hint}')."
    for hint in JS_CHALLENGE_HINTS:
        if hint in low:
            return f"Challenge JS détecté (motif '{hint}')."
    if "text/html" not in content_type and "text/plain" not in content_type:
        return f"Content-Type inattendu: '{content_type}'."
    return None


def login(session, base_url, email, password):
    login_url = urljoin(base_url, "/login")
    login_check_url = urljoin(base_url, "/login_check")

    r_get = session.get(login_url, timeout=15)
    print(f"GET {login_url} -> HTTP {r_get.status_code}")
    blocker = detect_blocker(r_get.text, r_get.status_code, r_get.headers.get("Content-Type", ""))
    if blocker:
        raise GedAccessError(f"Blocage sur la page de login: {blocker}")

    if not re.search(r'<form[^>]*action="([^"]*login_check[^"]*)"', r_get.text):
        raise GedAccessError("Formulaire de login introuvable — structure de page modifiée.")

    payload = {"_email": email, "_password": password}
    time.sleep(DELAY_S)
    r_post = session.post(login_check_url, data=payload, timeout=15, allow_redirects=True,
                           headers={"Referer": login_url})
    status_post = r_post.history[0].status_code if r_post.history else r_post.status_code
    print(f"POST {login_check_url} -> HTTP {status_post}")
    print(f"URL finale après redirection: {r_post.url}")

    blocker = detect_blocker(r_post.text, r_post.status_code, r_post.headers.get("Content-Type", ""))
    if blocker:
        raise GedAccessError(f"Blocage après login: {blocker}")
    if r_post.url.rstrip("/") == login_url.rstrip("/"):
        raise GedAccessError("Login refusé (URL finale toujours /login).")

    return r_post.text


def list_category_links(html, base_url):
    hrefs = re.findall(r'href="(/category/([^"/]+))"', html)
    seen, out = set(), []
    for href, slug in hrefs:
        if href not in seen:
            seen.add(href)
            out.append((urljoin(base_url, href), slug))
    return out


def list_reference_links(html, base_url):
    hrefs = re.findall(r'href="(/reference/[^"]+)"', html)
    unique = sorted(set(hrefs))
    return [urljoin(base_url, h) for h in unique]


def list_reference_thumbnails(html, base_url):
    """Extrait, pour chaque bloc <div class="reference">...</div> d'une
    page catégorie, le couple (url_reference, url_miniature). C'est la
    SEULE page où la miniature apparaît (pas sur la fiche /reference/{sku}
    elle-même, qui ne montre que le tableau de fichiers)."""
    blocks = re.findall(
        r'<div class="reference[^"]*">\s*<a href="(/reference/[^"]+)">\s*<img[^>]*src="([^"]+)"',
        html, re.S,
    )
    out = []
    for ref_href, img_src in blocks:
        out.append((urljoin(base_url, ref_href), urljoin(base_url, img_src)))
    return out


def is_placeholder_thumbnail(thumb_url):
    low = thumb_url.lower()
    return any(hint in low for hint in PLACEHOLDER_THUMBNAIL_HINTS)


def fetch_image_dimensions(session, img_url):
    """Récupère les dimensions px réelles d'une image en la lisant en
    mémoire (via GET, car un HEAD ne donne pas les dimensions), SANS
    jamais l'écrire sur disque — l'objet image est jeté après lecture des
    dimensions. Retourne (width, height, content_length_octets) ou lève
    une exception si l'image n'est pas lisible (rapporté, jamais deviné)."""
    r = session.get(img_url, timeout=15)
    r.raise_for_status()
    content_length = len(r.content)
    with Image.open(io.BytesIO(r.content)) as im:
        width, height = im.size
    return width, height, content_length


def category_name_from_html(html, fallback_slug):
    """Nom de catégorie tel qu'affiché dans le <title> de la page
    catégorie ("Staff decor GED - <Nom>"), sinon le slug d'URL."""
    m = re.search(r"<title>Staff decor GED - ([^<]+)</title>", html)
    if m:
        return m.group(1).strip()
    return fallback_slug


def parse_file_table(html, base_url):
    rows = re.findall(
        r'<tr>\s*<td[^>]*>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>\s*<td>\s*<a[^>]*href="(/download/\d+)"',
        html,
    )
    out = []
    for filename, _mobile, ext, size, dl_href in rows:
        out.append({
            "filename": filename.strip(),
            "ext": ext.strip().lower(),
            "size_display": size.strip(),
            "download_url": urljoin(base_url, dl_href),
        })
    return out


def sku_from_reference_url(ref_url):
    m = re.search(r"/reference/([^/?#]+)", ref_url)
    return m.group(1) if m else ref_url


def size_display_to_bytes(size_display):
    """Convertit '241.3 Ko' / '35.31 Mo' / '480.26 Ko' en octets, avec la
    convention déclarée 1 Ko=1024o, 1 Mo=1024^2 o. Retourne None si le
    format n'est pas reconnu (jamais une valeur inventée)."""
    m = re.match(r"^([\d.,]+)\s*(o|Ko|Mo|Go)$", size_display.strip(), re.I)
    if not m:
        return None
    value = float(m.group(1).replace(",", "."))
    unit = m.group(2).lower()
    factor = {"o": 1, "ko": 1024, "mo": 1024 ** 2, "go": 1024 ** 3}[unit]
    return int(round(value * factor))


def guess_type_presume(filename, size_bytes):
    """Applique la règle exacte demandée, dans l'ordre indiqué :
    1) '3D' si le nom contient -3D (insensible à la casse), OU si
       taille > 5 Mo (5*1024*1024 octets, convention déclarée) ;
    2) sinon '2D' si le nom contient -2D ;
    3) sinon 'INDETERMINE'."""
    name_low = filename.lower()
    five_mo = 5 * 1024 * 1024
    if "-3d" in name_low or (size_bytes is not None and size_bytes > five_mo):
        return "3D"
    if "-2d" in name_low:
        return "2D"
    return "INDETERMINE"


def extract_extra_descriptive_text(html):
    """Cherche un contenu textuel dans .box-body qui ne provienne PAS du
    tableau de fichiers (id="table-products") ni de la navigation/en-tête.
    Retourne le texte résiduel (peut être vide). Ne suppose rien : rapporte
    tel quel ce qui est trouvé."""
    body_match = re.search(r'<div class="box-body">(.*?)<!--\s*/\.box-body\s*-->', html, re.S)
    if not body_match:
        return ""
    body = body_match.group(1)
    # retire le tableau entier
    body_no_table = re.sub(r'<table id="table-products".*?</table>', "", body, flags=re.S)
    text = re.sub(r"<[^>]+>", " ", body_no_table)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def main():
    try:
        base_url, email, password = load_credentials()
    except GedAccessError as e:
        print(f"ERREUR: {e}", file=sys.stderr)
        sys.exit(1)

    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})

    try:
        home_html = login(session, base_url, email, password)
        time.sleep(DELAY_S)

        category_links = list_category_links(home_html, base_url)
        print(f"\nCatégories détectées: {len(category_links)}")

        # cat_url -> nom_categorie ; ref_url -> set(cat_url) (une réf peut apparaître
        # dans plusieurs catégories, on le signale si observé, sans le supposer)
        category_names = {}
        ref_to_categories = {}
        # ref_url -> url_miniature (telle que vue sur LA PREMIÈRE catégorie
        # rencontrée contenant cette référence — cohérent avec le choix déjà
        # fait pour categorie_nom dans le manifeste principal)
        ref_to_thumbnail = {}
        for i, (cat_url, slug) in enumerate(category_links, start=1):
            r_cat = session.get(cat_url, timeout=15)
            print(f"  [{i}/{len(category_links)}] GET {cat_url} -> HTTP {r_cat.status_code}")
            blocker = detect_blocker(r_cat.text, r_cat.status_code, r_cat.headers.get("Content-Type", ""))
            if blocker:
                raise GedAccessError(f"Blocage sur catégorie ({cat_url}): {blocker}")
            cat_name = category_name_from_html(r_cat.text, slug)
            category_names[cat_url] = cat_name
            for ref_url in list_reference_links(r_cat.text, base_url):
                ref_to_categories.setdefault(ref_url, set()).add(cat_url)
            for ref_url, thumb_url in list_reference_thumbnails(r_cat.text, base_url):
                ref_to_thumbnail.setdefault(ref_url, thumb_url)
            time.sleep(DELAY_S)

        multi_cat_refs = {r: c for r, c in ref_to_categories.items() if len(c) > 1}
        print(f"Fiches référence uniques: {len(ref_to_categories)}")
        if multi_cat_refs:
            print(f"ATTENTION — {len(multi_cat_refs)} fiche(s) référence apparaissent dans plusieurs catégories "
                  f"(la 1ère catégorie rencontrée est retenue dans le manifeste).")

        manifest_rows = []
        pages_with_extra_text = []
        ordered_refs = sorted(ref_to_categories.keys())
        for i, ref_url in enumerate(ordered_refs, start=1):
            r_ref = session.get(ref_url, timeout=15)
            if i % 50 == 0 or i == len(ordered_refs):
                print(f"  [{i}/{len(ordered_refs)}] GET fiche référence -> dernier statut HTTP {r_ref.status_code}")
            blocker = detect_blocker(r_ref.text, r_ref.status_code, r_ref.headers.get("Content-Type", ""))
            if blocker:
                raise GedAccessError(f"Blocage sur fiche référence ({ref_url}): {blocker}")

            sku = sku_from_reference_url(ref_url)
            cats_for_ref = sorted(ref_to_categories[ref_url])
            categorie_nom = category_names.get(cats_for_ref[0], cats_for_ref[0])

            extra_text = extract_extra_descriptive_text(r_ref.text)
            if extra_text:
                pages_with_extra_text.append((sku, extra_text))

            rows = parse_file_table(r_ref.text, base_url)
            for row in rows:
                if row["ext"] not in RETAINED_EXTENSIONS:
                    continue
                size_bytes = size_display_to_bytes(row["size_display"])
                manifest_rows.append({
                    "sku": sku,
                    "categorie": categorie_nom,
                    "nom_fichier": row["filename"],
                    "extension": row["ext"],
                    "taille_octets_estimee": size_bytes if size_bytes is not None else "",
                    "taille_affichee_ged": row["size_display"],
                    "download_url": row["download_url"],
                    "type_presume": guess_type_presume(row["filename"], size_bytes),
                })
            time.sleep(DELAY_S)

        # --- Écriture manifest.csv ---
        with open(MANIFEST_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=[
                "sku", "categorie", "nom_fichier", "extension",
                "taille_octets_estimee", "taille_affichee_ged",
                "download_url", "type_presume",
            ])
            writer.writeheader()
            for row in manifest_rows:
                writer.writerow(row)

        print(f"\n=== manifest.csv écrit ({len(manifest_rows)} lignes, extensions {sorted(RETAINED_EXTENSIONS)}) ===")

        # --- Miniatures : dimensions px réelles, sans écrire sur disque ---
        print(f"\n=== Récupération des dimensions réelles des miniatures ({len(ref_to_thumbnail)} URL de référence) ===")
        # Dédup par URL de miniature (plusieurs SKU peuvent partager la même
        # image, ex. "colonnes lisses.jpg" pour plusieurs variantes) — on ne
        # télécharge chaque image UNE seule fois.
        unique_thumb_urls = sorted(set(ref_to_thumbnail.values()))
        thumb_dimensions = {}  # url -> (w, h, octets) ou None si échec
        for i, thumb_url in enumerate(unique_thumb_urls, start=1):
            if i % 100 == 0 or i == len(unique_thumb_urls):
                print(f"  [{i}/{len(unique_thumb_urls)}] miniatures uniques traitées")
            try:
                w, h, nbytes = fetch_image_dimensions(session, thumb_url)
                thumb_dimensions[thumb_url] = (w, h, nbytes)
            except Exception as e:
                thumb_dimensions[thumb_url] = None
                print(f"  ATTENTION — miniature illisible ({thumb_url}): {e}")
            time.sleep(DELAY_S)

        thumbnail_rows = []
        for ref_url in ordered_refs:
            sku = sku_from_reference_url(ref_url)
            thumb_url = ref_to_thumbnail.get(ref_url)
            if thumb_url is None:
                thumbnail_rows.append({
                    "sku": sku, "url": "", "largeur_px": "", "hauteur_px": "",
                    "taille_octets": "", "est_placeholder": "",
                    "note": "aucune miniature trouvée sur la page catégorie",
                })
                continue
            dims = thumb_dimensions.get(thumb_url)
            placeholder = is_placeholder_thumbnail(thumb_url)
            if dims is None:
                thumbnail_rows.append({
                    "sku": sku, "url": thumb_url, "largeur_px": "", "hauteur_px": "",
                    "taille_octets": "", "est_placeholder": placeholder,
                    "note": "erreur de lecture — dimensions non obtenues",
                })
            else:
                w, h, nbytes = dims
                thumbnail_rows.append({
                    "sku": sku, "url": thumb_url, "largeur_px": w, "hauteur_px": h,
                    "taille_octets": nbytes, "est_placeholder": placeholder,
                    "note": "",
                })

        with open(THUMBNAILS_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=[
                "sku", "url", "largeur_px", "hauteur_px", "taille_octets",
                "est_placeholder", "note",
            ])
            writer.writeheader()
            for row in thumbnail_rows:
                writer.writerow(row)

        nb_placeholder = sum(1 for r in thumbnail_rows if r["est_placeholder"] is True)
        nb_reelles = sum(1 for r in thumbnail_rows if r["url"] and not r["est_placeholder"] and r["largeur_px"] != "")
        nb_sans = sum(1 for r in thumbnail_rows if not r["url"])
        print(f"\n=== thumbnails.csv écrit ({len(thumbnail_rows)} lignes) ===")
        print(f"  Miniatures réelles (dimensions obtenues, non placeholder): {nb_reelles}")
        print(f"  Placeholders génériques (dossier vide, motif 'Folder-voir'): {nb_placeholder}")
        print(f"  SKU sans aucune miniature détectée sur leur page catégorie: {nb_sans}")

        # --- Récapitulatif par catégorie ---
        by_cat = {}
        for row in manifest_rows:
            c = by_cat.setdefault(row["categorie"], {"count": 0, "bytes": 0})
            c["count"] += 1
            if isinstance(row["taille_octets_estimee"], int):
                c["bytes"] += row["taille_octets_estimee"]

        print("\n--- Récapitulatif par catégorie (nb fichiers, volume estimé Mo) ---")
        for cat, stats in sorted(by_cat.items(), key=lambda kv: -kv[1]["count"]):
            print(f"  {cat}: {stats['count']} fichier(s), {stats['bytes'] / (1024**2):.2f} Mo")

        # --- Récapitulatif par type_presume ---
        by_type = {}
        for row in manifest_rows:
            t = by_type.setdefault(row["type_presume"], {"count": 0, "bytes": 0})
            t["count"] += 1
            if isinstance(row["taille_octets_estimee"], int):
                t["bytes"] += row["taille_octets_estimee"]

        print("\n--- Récapitulatif par type_presume (nb fichiers, volume estimé Mo) ---")
        for t, stats in sorted(by_type.items(), key=lambda kv: -kv[1]["count"]):
            print(f"  {t}: {stats['count']} fichier(s), {stats['bytes'] / (1024**2):.2f} Mo")

        # --- SKU sans candidat 2D ---
        skus_with_2d = set()
        all_skus = set()
        for row in manifest_rows:
            all_skus.add(row["sku"])
            if row["type_presume"] == "2D":
                skus_with_2d.add(row["sku"])
        skus_without_2d = sorted(all_skus - skus_with_2d)
        print(f"\n--- SKU sans AUCUN candidat 2D : {len(skus_without_2d)} sur {len(all_skus)} SKU total (avec >=1 fichier dwg/dxf) ---")
        for sku in skus_without_2d[:50]:
            print(f"  - {sku}")
        if len(skus_without_2d) > 50:
            print(f"  ... ({len(skus_without_2d) - 50} de plus, voir manifest.csv)")

        # --- Champs descriptifs sur les fiches référence ---
        print(f"\n--- Vérification champs descriptifs sur les {len(ordered_refs)} fiches référence parcourues ---")
        if pages_with_extra_text:
            print(f"{len(pages_with_extra_text)} fiche(s) contiennent un texte résiduel hors tableau de fichiers "
                  f"(désignation/dimensions potentielles) :")
            for sku, text in pages_with_extra_text[:20]:
                print(f"  - [{sku}] {text[:200]}")
        else:
            print("AUCUNE des fiches référence parcourues ne contient de champ descriptif "
                  "(désignation, dimensions, longueur de barre, matière) hors du tableau de "
                  "fichiers et du titre H1 (qui ne répète que le SKU). Confirmé réellement, "
                  "pas supposé.")

    except GedAccessError as e:
        print(f"\nARRÊT — accès bloqué: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
