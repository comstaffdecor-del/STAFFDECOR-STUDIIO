#!/usr/bin/env python3
"""
ged_fetch.py — Accès en LECTURE SEULE STRICTE à la GED Staff Décor
(https://ged.staffdecor.fr) : authentification, inventaire des fichiers
CAO, et téléchargement idempotent vers assets/dwg/ et assets/dxf/.

Aucune écriture, aucune suppression, aucune modification côté GED.
Ce script ne fait que : se connecter (POST /login_check), lister les
répertoires/catégories, et télécharger des fichiers déjà existants.

Identifiants : lus depuis un fichier .env (GED_BASE_URL, GED_EMAIL,
GED_PASSWORD), JAMAIS en dur dans ce script, JAMAIS affichés/loggés en
clair. .env est explicitement dans .gitignore (jamais commité).

Usage:
    # Étape 1 — preuve d'accès uniquement (aucun téléchargement) :
    python3 ged_fetch.py --check-only

    # Étape 2 — inventaire + téléchargement réel dans assets/dwg/, assets/dxf/ :
    python3 ged_fetch.py --download

En cas d'échec de login, de captcha détecté, de contenu JS-only, ou de
403 : le script s'arrête immédiatement avec un message explicite. Il
n'invente jamais un décompte ni un nom de fichier — toute donnée
rapportée provient d'une requête HTTP réellement exécutée dans ce run.
"""

import argparse
import os
import re
import sys
import time
from pathlib import Path
from urllib.parse import urljoin, urlparse

import requests

try:
    from dotenv import load_dotenv
except ImportError:
    print("ERREUR: le module 'python-dotenv' n'est pas installé. pip install python-dotenv", file=sys.stderr)
    sys.exit(1)


HERE = Path(__file__).parent
ENV_PATH = HERE / ".env"
DEFAULT_DWG_DIR = Path("/home/user/flutter_app/assets/dwg")
DEFAULT_DXF_DIR = Path("/home/user/flutter_app/assets/dxf")

USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)

CAPTCHA_HINTS = ("captcha", "recaptcha", "hcaptcha", "cf-turnstile")
JS_CHALLENGE_HINTS = ("just a moment", "checking your browser", "cf-browser-verification", "__cf_chl")


class GedAccessError(RuntimeError):
    """Levée pour tout échec d'accès explicite (login, captcha, JS, 403)."""


def load_credentials():
    if not ENV_PATH.exists():
        raise GedAccessError(
            f".env introuvable à {ENV_PATH}. Créer ce fichier (jamais commité, voir "
            f".gitignore) avec GED_BASE_URL, GED_EMAIL, GED_PASSWORD."
        )
    load_dotenv(ENV_PATH)
    base_url = os.environ.get("GED_BASE_URL", "").strip()
    email = os.environ.get("GED_EMAIL", "").strip()
    password = os.environ.get("GED_PASSWORD", "").strip()
    missing = [k for k, v in [("GED_BASE_URL", base_url), ("GED_EMAIL", email), ("GED_PASSWORD", password)] if not v]
    if missing:
        raise GedAccessError(f"Variables manquantes dans .env: {', '.join(missing)}")
    return base_url, email, password


def detect_blocker(text: str, status_code: int, content_type: str):
    """Détecte captcha / JS-challenge / 403 explicite. Retourne un message
    d'erreur si un blocage est détecté, sinon None."""
    if status_code == 403:
        return f"HTTP 403 reçu — accès refusé par le serveur."
    low = text.lower()
    for hint in CAPTCHA_HINTS:
        if hint in low:
            return f"Captcha détecté (motif '{hint}' trouvé dans la réponse)."
    for hint in JS_CHALLENGE_HINTS:
        if hint in low:
            return f"Challenge JS détecté (motif '{hint}' trouvé dans la réponse)."
    if "text/html" not in content_type and "text/plain" not in content_type:
        return f"Content-Type inattendu pour une page HTML: '{content_type}'."
    return None


def login(session: requests.Session, base_url: str, email: str, password: str, verbose=True):
    """Effectue le login. Retourne (final_url, status_code_post) ou lève
    GedAccessError. N'affiche/ne logue jamais le mot de passe."""
    login_url = urljoin(base_url, "/login")
    login_check_url = urljoin(base_url, "/login_check")

    r_get = session.get(login_url, timeout=15)
    if verbose:
        print(f"GET {login_url} -> HTTP {r_get.status_code}")
    blocker = detect_blocker(r_get.text, r_get.status_code, r_get.headers.get("Content-Type", ""))
    if blocker:
        raise GedAccessError(f"Blocage détecté sur la page de login ({login_url}): {blocker}")

    # Vérifie la présence du formulaire attendu (méthode/action), sans
    # extraction de token CSRF car la page observée n'en contient pas ;
    # si un token apparaissait, on le lit ici avant de continuer.
    form_match = re.search(r'<form[^>]*action="([^"]*login_check[^"]*)"', r_get.text)
    if not form_match:
        raise GedAccessError(
            f"Formulaire de login introuvable sur {login_url} — la page a "
            f"peut-être changé de structure (contenu potentiellement rendu "
            f"en JS). Arrêt, aucune supposition."
        )

    csrf_match = re.search(r'name="(_csrf_token|csrf_token|_token)"[^>]*value="([^"]*)"', r_get.text)
    payload = {"_email": email, "_password": password}
    if csrf_match:
        payload[csrf_match.group(1)] = csrf_match.group(2)
        if verbose:
            print(f"Token CSRF détecté: champ '{csrf_match.group(1)}' inclus dans le POST.")
    elif verbose:
        print("Aucun champ CSRF détecté dans le formulaire (cohérent avec l'exploration précédente).")

    r_post = session.post(
        login_check_url, data=payload, timeout=15, allow_redirects=True,
        headers={"Referer": login_url},
    )
    status_post = r_post.history[0].status_code if r_post.history else r_post.status_code
    final_url = r_post.url

    if verbose:
        print(f"POST {login_check_url} -> HTTP {status_post} (statut de la réponse initiale du POST)")
        print(f"URL finale après redirection(s): {final_url}")
        if r_post.history:
            chain = " -> ".join(f"{h.status_code} {h.url}" for h in r_post.history)
            print(f"Chaîne de redirection: {chain} -> {r_post.status_code} {r_post.url}")

    blocker = detect_blocker(r_post.text, r_post.status_code, r_post.headers.get("Content-Type", ""))
    if blocker:
        raise GedAccessError(f"Blocage détecté après le POST de login: {blocker}")

    parsed_final = urlparse(final_url)
    parsed_login = urlparse(login_url)
    if parsed_final.path == parsed_login.path:
        raise GedAccessError(
            f"Après le POST, l'URL finale est toujours la page de login ({final_url}) "
            f"— login probablement refusé (identifiants invalides ou session rejetée)."
        )

    return final_url, status_post, r_post.text


def list_category_links(html: str, base_url: str):
    """Extrait les liens /category/... de la page d'accueil. Ne fait
    aucune supposition sur leur contenu — ce sont des candidats à
    explorer."""
    hrefs = re.findall(r'href="(/category/[^"]+)"', html)
    unique = sorted(set(hrefs))
    return [urljoin(base_url, h) for h in unique]


def list_reference_links(html: str, base_url: str):
    """Extrait les liens /reference/{sku} d'une page catégorie. C'est à
    ce niveau que se trouvent les fiches produit (une par SKU), chacune
    contenant le tableau réel des fichiers CAO associés."""
    hrefs = re.findall(r'href="(/reference/[^"]+)"', html)
    unique = sorted(set(hrefs))
    return [urljoin(base_url, h) for h in unique]


def detect_pagination(html: str):
    """Signale si des indices de pagination sont présents sur une page
    catégorie, sans les suivre automatiquement — juste pour ne pas
    sous-compter silencieusement si la structure change."""
    hints = re.findall(r'\?page=\d+|&page=\d+|/page/\d+|rel="next"|class="[^"]*pagination[^"]*"', html, re.I)
    return hints


def parse_file_table(html: str, base_url: str):
    """Extrait les lignes du tableau de fichiers CAO d'une page
    /reference/{sku}, tel qu'observé réellement (table#table-products) :
    colonnes Fichier / Fichier(mobile) / Formats / Poids / lien de
    téléchargement. Retourne une liste de dicts
    {filename, ext, size, download_url}."""
    rows = re.findall(
        r'<tr>\s*<td[^>]*>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>\s*<td>\s*<a[^>]*href="(/download/\d+)"',
        html,
    )
    out = []
    for filename, _filename_mobile, ext, size, dl_href in rows:
        out.append({
            "filename": filename.strip(),
            "ext": ext.strip().lower(),
            "size": size.strip(),
            "download_url": urljoin(base_url, dl_href),
        })
    return out


def find_file_links(html: str, base_url: str):
    """Extrait tous les liens vers des fichiers .dwg/.dxf, OU vers des
    endpoints de téléchargement (/download/{id}), présents DIRECTEMENT
    dans une page (hors tableau structuré). Conservé pour la détection
    initiale (page d'accueil), sans supposer où vivent réellement les
    fichiers."""
    links = []
    for m in re.finditer(r'href="([^"]+)"', html):
        href = m.group(1)
        if href.lower().endswith((".dwg", ".dxf")) or "/download/" in href:
            links.append(urljoin(base_url, href))
    return sorted(set(links))


def sku_from_reference_url(ref_url: str):
    m = re.search(r'/reference/([^/?#]+)', ref_url)
    return m.group(1) if m else ref_url


def crawl_full_corpus(session, base_url, verbose=True, delay=0.12):
    """Parcours réel et complet : accueil -> catégories -> fiches
    référence -> tableau de fichiers. Lecture seule stricte (GET
    uniquement). Retourne un dict avec les compteurs et la liste
    ordonnée (déduplication par download_url) des fichiers rencontrés."""
    home_url = urljoin(base_url, "/")
    r_home = session.get(home_url, timeout=15)
    if verbose:
        print(f"GET {home_url} -> HTTP {r_home.status_code}")
    blocker = detect_blocker(r_home.text, r_home.status_code, r_home.headers.get("Content-Type", ""))
    if blocker:
        raise GedAccessError(f"Blocage détecté sur la page d'accueil ({home_url}): {blocker}")

    category_links = list_category_links(r_home.text, base_url)
    if verbose:
        print(f"Nombre de catégories détectées sur la page d'accueil: {len(category_links)}")

    all_reference_urls = set()
    pagination_flagged = []
    for i, cat_url in enumerate(category_links, start=1):
        r_cat = session.get(cat_url, timeout=15)
        if verbose:
            print(f"  [{i}/{len(category_links)}] GET {cat_url} -> HTTP {r_cat.status_code}")
        blocker = detect_blocker(r_cat.text, r_cat.status_code, r_cat.headers.get("Content-Type", ""))
        if blocker:
            raise GedAccessError(f"Blocage détecté sur la catégorie ({cat_url}): {blocker}")
        pag = detect_pagination(r_cat.text)
        if pag:
            pagination_flagged.append((cat_url, len(pag)))
        refs = list_reference_links(r_cat.text, base_url)
        all_reference_urls.update(refs)
        time.sleep(delay)

    if verbose:
        print(f"\nNombre de fiches référence (produits) uniques détectées: {len(all_reference_urls)}")
        if pagination_flagged:
            print(f"ATTENTION — indices de pagination détectés sur {len(pagination_flagged)} page(s) "
                  f"catégorie (non suivie automatiquement, décompte potentiellement incomplet sur ces pages):")
            for u, n in pagination_flagged:
                print(f"    - {u} ({n} indice(s))")

    files_by_download_url = {}
    errors_on_references = []
    ordered_refs = sorted(all_reference_urls)
    for i, ref_url in enumerate(ordered_refs, start=1):
        try:
            r_ref = session.get(ref_url, timeout=15)
        except requests.RequestException as e:
            errors_on_references.append((ref_url, str(e)))
            continue
        if verbose and (i % 25 == 0 or i == len(ordered_refs)):
            print(f"  [{i}/{len(ordered_refs)}] GET fiche référence -> dernier statut HTTP {r_ref.status_code}")
        blocker = detect_blocker(r_ref.text, r_ref.status_code, r_ref.headers.get("Content-Type", ""))
        if blocker:
            raise GedAccessError(f"Blocage détecté sur une fiche référence ({ref_url}): {blocker}")
        sku = sku_from_reference_url(ref_url)
        rows = parse_file_table(r_ref.text, base_url)
        for row in rows:
            row["sku"] = sku
            row["reference_url"] = ref_url
            files_by_download_url[row["download_url"]] = row
        time.sleep(delay)

    all_files = list(files_by_download_url.values())
    dwg_files = [f for f in all_files if f["ext"] == "dwg"]
    dxf_files = [f for f in all_files if f["ext"] == "dxf"]

    return {
        "category_count": len(category_links),
        "reference_count": len(ordered_refs),
        "reference_errors": errors_on_references,
        "pagination_flagged": pagination_flagged,
        "all_files": all_files,
        "dwg_files": dwg_files,
        "dxf_files": dxf_files,
    }


def check_only(base_url, email, password):
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})

    final_url, status_post, home_html = login(session, base_url, email, password, verbose=True)

    print(f"\n=== Login réussi ===")
    print(f"URL après redirection: {final_url}")

    print(f"\n=== Parcours complet (lecture seule) : accueil -> catégories -> fiches référence -> tableau fichiers ===")
    result = crawl_full_corpus(session, base_url, verbose=True)

    print(f"\n=== RÉSULTATS BRUTS (Étape 1) ===")
    print(f"Catégories parcourues: {result['category_count']}")
    print(f"Fiches référence (produits) uniques parcourues: {result['reference_count']}")
    if result["reference_errors"]:
        print(f"Erreurs réseau sur {len(result['reference_errors'])} fiche(s) référence:")
        for url, err in result["reference_errors"][:10]:
            print(f"    - {url}: {err}")
    print(f"Nombre total de fichiers .dwg trouvés (uniques par download_url): {len(result['dwg_files'])}")
    print(f"Nombre total de fichiers .dxf trouvés (uniques par download_url): {len(result['dxf_files'])}")

    print(f"\n20 premiers fichiers .dwg rencontrés (nom, taille, sku, url de téléchargement):")
    for f in result["dwg_files"][:20]:
        print(f"  - [{f['sku']}] {f['filename']} — {f['size']} — {f['download_url']}")

    if result["dxf_files"]:
        print(f"\n20 premiers fichiers .dxf rencontrés (nom, taille, sku, url de téléchargement):")
        for f in result["dxf_files"][:20]:
            print(f"  - [{f['sku']}] {f['filename']} — {f['size']} — {f['download_url']}")
    else:
        print(f"\nAucun fichier .dxf trouvé sur l'ensemble du corpus parcouru.")

    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check-only", action="store_true",
                         help="Étape 1: preuve d'accès uniquement, aucun téléchargement.")
    parser.add_argument("--download", action="store_true",
                         help="Étape 2: inventaire + téléchargement réel (non implémenté dans ce run).")
    args = parser.parse_args()

    try:
        base_url, email, password = load_credentials()
    except GedAccessError as e:
        print(f"ERREUR: {e}", file=sys.stderr)
        sys.exit(1)

    if args.check_only:
        try:
            check_only(base_url, email, password)
        except GedAccessError as e:
            print(f"\nARRÊT — accès bloqué: {e}", file=sys.stderr)
            sys.exit(2)
        return

    if args.download:
        print("ERREUR: --download n'est pas encore implémenté dans cette version "
              "(étape 1 de validation en cours). Utiliser --check-only.", file=sys.stderr)
        sys.exit(1)

    print("ERREUR: fournir --check-only ou --download", file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
