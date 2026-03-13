#!/usr/bin/env bash
set -euo pipefail

# pull.sh — Récupère la config depuis le remote et l'applique localement
# Usage : bash ~/claude-config/pull.sh

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Pull depuis le remote si configuré
cd "$REPO_DIR"
if git remote | grep -q .; then
  echo "Pull depuis le remote..."
  git pull
else
  echo "Aucun remote configuré, utilisation des fichiers locaux."
fi

# Appliquer la config
source "$REPO_DIR/_apply.sh"
apply_config
