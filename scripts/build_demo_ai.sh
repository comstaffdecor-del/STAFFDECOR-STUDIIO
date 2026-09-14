#!/usr/bin/env bash
# Build web RELEASE avec l'aperçu IA activé (démo contrôlée uniquement).
#
# SÉCURITÉ (voir issue #2) : l'URL du proxy IA n'est jamais codée en dur
# dans le dépôt (dépôt public). Elle est injectée à la compilation via
# --dart-define=AI_RENDER_PROXY_BASE_URL=<url>, lu dans
# lib/data/ia_ambiance_preview.dart via
# String.fromEnvironment('AI_RENDER_PROXY_BASE_URL', defaultValue: '').
#
# Un build normal (flutter build web --release, sans passer par ce
# script) laisse cette valeur vide : l'aperçu IA est alors proprement
# désactivé, sans aucune URL d'infrastructure dans le bundle.
#
# Usage :
#   AI_RENDER_PROXY_BASE_URL=https://8091-xxx.sandbox.novita.ai \
#     ./scripts/build_demo_ai.sh
#
# Prérequis : le proxy (server/ai_render_proxy/server.js) doit être
# lancé et joignable à cette URL AVANT la démo, et coupé après.

set -euo pipefail

AI_RENDER_PROXY_BASE_URL="${AI_RENDER_PROXY_BASE_URL:-}"

if [ -z "$AI_RENDER_PROXY_BASE_URL" ]; then
  echo "Erreur: AI_RENDER_PROXY_BASE_URL est vide." >&2
  echo "" >&2
  echo "Exemple:" >&2
  echo "  AI_RENDER_PROXY_BASE_URL=https://8091-xxx.sandbox.novita.ai ./scripts/build_demo_ai.sh" >&2
  exit 1
fi

echo "==> Build web RELEASE avec AI_RENDER_PROXY_BASE_URL=${AI_RENDER_PROXY_BASE_URL}"
echo "    (rappel: couper le proxy 8091 apres la demo)"

flutter build web --release \
  --dart-define=AI_RENDER_PROXY_BASE_URL="$AI_RENDER_PROXY_BASE_URL"
