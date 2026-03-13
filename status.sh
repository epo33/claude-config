#!/usr/bin/env bash
set -euo pipefail

# status.sh — Vérifie si le dépôt claude-config est synchronisé avec le remote
# Usage : bash ~/claude-config/status.sh

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

if ! git remote | grep -q .; then
  echo "Aucun remote configuré."
  exit 0
fi

git fetch --quiet

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")

if [ -z "$REMOTE" ]; then
  echo "Pas de branche upstream configurée."
  exit 0
fi

if [ "$LOCAL" = "$REMOTE" ]; then
  echo "À jour."
else
  AHEAD=$(git rev-list --count "$REMOTE".."$LOCAL")
  BEHIND=$(git rev-list --count "$LOCAL".."$REMOTE")

  if [ "$AHEAD" -gt 0 ] && [ "$BEHIND" -gt 0 ]; then
    echo "Divergent (${AHEAD} en avance, ${BEHIND} en retard). Pull puis push recommandé."
  elif [ "$AHEAD" -gt 0 ]; then
    echo "En avance de ${AHEAD} commit(s). Push recommandé."
  else
    echo "En retard de ${BEHIND} commit(s). Pull recommandé."
  fi
fi
