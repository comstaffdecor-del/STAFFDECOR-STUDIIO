#!/usr/bin/env bash
# Lance l'app en mode DEBUG (Chrome) avec l'aperçu IA activé (démo
# contrôlée / développement local uniquement).
#
# SÉCURITÉ (voir issue #2) : même principe que scripts/build_demo_ai.sh
# — l'URL du proxy IA est injectée via --dart-define, jamais codée en
# dur. Voir lib/data/ia_ambiance_preview.dart (kAiRenderProxyBaseUrl).
#
# Usage :
#   AI_RENDER_PROXY_BASE_URL=https://8091-xxx.sandbox.novita.ai \
#     ./scripts/run_demo_ai_debug.sh
#
# Prérequis : le proxy (server/ai_render_proxy/server.js) doit être
# lancé et joignable à cette URL AVANT la démo, et coupé après.

set -euo pipefail

AI_RENDER_PROXY_BASE_URL="${AI_RENDER_PROXY_BASE_URL:-}"

if [ -z "$AI_RENDER_PROXY_BASE_URL" ]; then
  echo "Erreur: AI_RENDER_PROXY_BASE_URL est vide." >&2
  echo "" >&2
  echo "Exemple:" >&2
  echo "  AI_RENDER_PROXY_BASE_URL=https://8091-xxx.sandbox.novita.ai ./scripts/run_demo_ai_debug.sh" >&2
  exit 1
fi

echo "==> flutter run (Chrome, debug) avec AI_RENDER_PROXY_BASE_URL=${AI_RENDER_PROXY_BASE_URL}"
echo "    (rappel: couper le proxy 8091 apres la demo)"

flutter run -d chrome \
  --dart-define=AI_RENDER_PROXY_BASE_URL="$AI_RENDER_PROXY_BASE_URL"
