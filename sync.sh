#!/usr/bin/env bash
set -euo pipefail

# sync.sh — Synchronisation bidirectionnelle de la config Claude
# Usage : bash ~/claude-config/sync.sh
#
# 1. Commit + push des modifications locales (s'il y en a)
# 2. Pull depuis le remote (s'il y en a)
# 3. Application de la config vers ~/.claude/

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$REPO_DIR/_apply.sh"

cd "$REPO_DIR"

HAS_REMOTE=false
if git remote | grep -q .; then
  HAS_REMOTE=true
fi

# --- Étape 1 : commit + push des modifications locales ---
git add -A

if ! git diff --cached --quiet; then
  msg="sync: $(hostname) $(date +%Y-%m-%d_%H:%M)"
  git commit -m "$msg"
  echo "Commit local créé."

  if $HAS_REMOTE; then
    git push
    echo "Push effectué."
  fi
else
  echo "Aucune modification locale."
fi

# --- Étape 2 : pull depuis le remote ---
if $HAS_REMOTE; then
  echo "Pull depuis le remote..."
  git pull
fi

# --- Étape 3 : appliquer la config ---
apply_config
