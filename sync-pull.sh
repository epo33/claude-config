#!/usr/bin/env bash
set -euo pipefail

# sync-pull.sh — Récupère la config depuis le remote et l'applique localement
# Usage : bash ~/claude-config/sync-pull.sh

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

# Fichiers nécessitant une substitution de chemins
PATH_SUBST_FILES=(
  "settings.json"
  "mcp.json"
)

# --- Substitution de chemins selon l'OS ---
apply_path_substitutions() {
  local file="$1"
  local os_type
  os_type="$(uname -s)"

  case "$os_type" in
    Darwin)
      # Sur macOS : remplacer les chemins Windows par les chemins Mac
      # Chemins Windows format JSON (doubles backslashes)
      sed -i '' 's|c:\\\\Travail\\\\Projets|'"$HOME"'/Projects|g' "$file"
      sed -i '' 's|c:\\\\travail\\\\projets|'"$HOME"'/Projects|gi' "$file"
      # Chemins Windows format Unix (slashes)
      sed -i '' 's|/c/Travail/Projets|'"$HOME"'/Projects|g' "$file"
      sed -i '' 's|/c/Users/emman|'"$HOME"'|g' "$file"
      sed -i '' 's|C:/Users/emman|'"$HOME"'|g' "$file"
      echo "    → chemins adaptés pour macOS"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      # Sur Windows (Git Bash) : remplacer les chemins Mac par les chemins Windows
      # Chemins Mac dans JSON
      mac_home_pattern="$HOME/Projects"
      # On ne fait la substitution que si le fichier contient des chemins Mac
      if grep -q "$HOME/Projects\|~/Projects" "$file" 2>/dev/null; then
        sed -i 's|'"$HOME"'/Projects|/c/Travail/Projets|g' "$file"
        sed -i 's|~/Projects|/c/Travail/Projets|g' "$file"
        echo "    → chemins adaptés pour Windows"
      fi
      ;;
    *)
      echo "    → OS non reconnu ($os_type), pas de substitution"
      ;;
  esac
}

echo "=== sync-pull : remote → $CLAUDE_DIR ==="

# Pull depuis le remote si configuré
cd "$REPO_DIR"
if git remote | grep -q .; then
  echo "Pull depuis le remote..."
  git pull
else
  echo "Aucun remote configuré, utilisation des fichiers locaux."
fi

# Vérifier que config/ existe
if [ ! -d "$CONFIG_DIR" ]; then
  echo "Erreur : $CONFIG_DIR n'existe pas. Exécutez d'abord sync-push.sh."
  exit 1
fi

# Copier les fichiers individuels
for f in "${FILES[@]}"; do
  src="$CONFIG_DIR/$f"
  if [ -f "$src" ]; then
    cp "$src" "$CLAUDE_DIR/$f"
    echo "  ✓ $f"

    # Appliquer les substitutions de chemins si nécessaire
    for pf in "${PATH_SUBST_FILES[@]}"; do
      if [ "$f" = "$pf" ]; then
        apply_path_substitutions "$CLAUDE_DIR/$f"
      fi
    done
  else
    echo "  ⚠ $f absent du dépôt, ignoré"
  fi
done

# Copier les dossiers en miroir
for d in "${DIRS[@]}"; do
  src="$CONFIG_DIR/$d"
  dst="$CLAUDE_DIR/$d"
  if [ -d "$src" ]; then
    rm -rf "$dst"
    cp -r "$src" "$dst"
    echo "  ✓ $d/"
  else
    echo "  ⚠ $d/ absent du dépôt, ignoré"
  fi
done

echo ""
echo "Synchronisation terminée."
