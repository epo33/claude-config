#!/usr/bin/env bash
set -euo pipefail

# push.sh — Applique la config localement, commit et pousse sur le remote
# Usage : bash ~/claude-config/push.sh

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Appliquer la config
source "$REPO_DIR/_apply.sh"
apply_config

# Git : add, commit, push
cd "$REPO_DIR"
git add -A

if git diff --cached --quiet; then
  echo "Rien à synchroniser (aucun changement)."
else
  msg="sync: $(hostname) $(date +%Y-%m-%d_%H:%M)"
  git commit -m "$msg"

  if git remote | grep -q .; then
    git push
    echo "Synchronisation terminée et poussée sur le remote."
  else
    echo "Commit créé. Aucun remote configuré, push ignoré."
  fi
fi
