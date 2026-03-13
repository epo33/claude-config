#!/usr/bin/env bash
set -euo pipefail

# sync-push.sh — Copie la config Claude locale vers le dépôt et pousse sur le remote
# Usage : bash ~/claude-config/sync-push.sh

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CONFIG_DIR="$REPO_DIR/config"

# Fichiers individuels à synchroniser
FILES=(
  "CLAUDE.md"
  "dart.instructions.md"
  "settings.json"
  "mcp.json"
  "statusline-command.sh"
)

# Dossiers à synchroniser (miroir complet)
DIRS=(
  "commands"
  "skills"
)

echo "=== sync-push : $CLAUDE_DIR → $CONFIG_DIR ==="

# Créer config/ si nécessaire
mkdir -p "$CONFIG_DIR"

# Copier les fichiers individuels
for f in "${FILES[@]}"; do
  src="$CLAUDE_DIR/$f"
  if [ -f "$src" ]; then
    cp "$src" "$CONFIG_DIR/$f"
    echo "  ✓ $f"
  else
    echo "  ⚠ $f non trouvé, ignoré"
  fi
done

# Copier les dossiers en miroir
for d in "${DIRS[@]}"; do
  src="$CLAUDE_DIR/$d"
  dst="$CONFIG_DIR/$d"
  if [ -d "$src" ]; then
    rm -rf "$dst"
    cp -r "$src" "$dst"
    echo "  ✓ $d/"
  else
    echo "  ⚠ $d/ non trouvé, ignoré"
  fi
done

# Git : add, commit, push
cd "$REPO_DIR"
git add -A

if git diff --cached --quiet; then
  echo ""
  echo "Rien à synchroniser (aucun changement)."
else
  msg="sync: $(hostname) $(date +%Y-%m-%d_%H:%M)"
  git commit -m "$msg"

  # Push seulement si un remote est configuré
  if git remote | grep -q .; then
    git push
    echo ""
    echo "Synchronisation terminée et poussée sur le remote."
  else
    echo ""
    echo "Commit créé. Aucun remote configuré, push ignoré."
    echo "Configurez un remote avec : git remote add origin <url>"
  fi
fi
