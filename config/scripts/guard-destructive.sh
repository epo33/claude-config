#!/usr/bin/env bash
# Hook PreToolUse — protection contre les commandes destructives.
#
# 1. Blocage dur (exit 2) : commandes git destructives
# 2. Snapshot préventif (exit 0) : si la commande contient rm/mv/del/>/etc.,
#    on sauvegarde les fichiers à risque (modifiés ou non suivis) dans
#    <repo>/.temp/claude-guard-<timestamp>/ avant de laisser passer.
#
# Le JSON de l'appel d'outil arrive sur stdin.

set -euo pipefail

# Lire le JSON stdin
INPUT=$(cat)

# Extraire le nom de l'outil
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Ne s'applique qu'aux outils Bash et PowerShell
if [[ "$TOOL_NAME" != "Bash" && "$TOOL_NAME" != "PowerShell" ]]; then
  exit 0
fi

# Extraire la commande
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ -z "$CMD" ]]; then
  exit 0
fi

# --- 1. Blocage dur : commandes git destructives ---

GIT_PATTERNS=(
  'git[[:space:]]+checkout[[:space:]]+--'
  'git[[:space:]]+restore[[:space:]]+'
  'git[[:space:]]+reset[[:space:]]+--hard'
  'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f'
  'git[[:space:]]+stash[[:space:]]+drop'
  'git[[:space:]]+stash[[:space:]]+clear'
  'git[[:space:]]+branch[[:space:]]+-[dD][[:space:]]+'
  'git[[:space:]]+push[[:space:]]+.*--force'
  'git[[:space:]]+push[[:space:]]+-f([[:space:]]|$)'
)

for pattern in "${GIT_PATTERNS[@]}"; do
  if echo "$CMD" | grep -qEi "$pattern"; then
    cat >&2 <<EOF
COMMANDE DESTRUCTIVE DETECTEE — GIT DESTRUCTIF

Commande bloquee :
  $CMD

Tu ne peux PAS executer cette commande. Fournis-la a l'utilisateur dans un bloc de code pour qu'il la copie et l'execute lui-meme dans son terminal.
EOF
    exit 2
  fi
done

# --- 2. Snapshot préventif : commandes potentiellement destructives sur fichiers ---

# Patterns de commandes qui pourraient détruire/écraser des fichiers
RISKY_PATTERNS=(
  '(^|[;&|[:space:]])rm[[:space:]]+'
  '(^|[;&|[:space:]])rmdir[[:space:]]+'
  '(^|[;&|[:space:]])del[[:space:]]+'
  '(^|[;&|[:space:]])Remove-Item[[:space:]]+'
  '(^|[;&|[:space:]])mv[[:space:]]+'
  '(^|[;&|[:space:]])move[[:space:]]+'
  '(^|[;&|[:space:]])Move-Item[[:space:]]+'
  # Redirection > retirée : trop de faux positifs (2>/dev/null, etc.)
  # La protection repose sur le fait que Claude utilise plutôt Write/Edit pour les fichiers
)

IS_RISKY=false
for pattern in "${RISKY_PATTERNS[@]}"; do
  if echo "$CMD" | grep -qEi "$pattern"; then
    IS_RISKY=true
    break
  fi
done

if [[ "$IS_RISKY" != "true" ]]; then
  exit 0
fi

# Opérations sur .temp/ → laisser passer sans snapshot (nettoyage légitime)
if echo "$CMD" | grep -qE '\.temp(/|[[:space:]])'; then
  exit 0
fi

# Trouver la racine du repo git
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$REPO_ROOT" ]]; then
  # Pas dans un repo git, on laisse passer sans snapshot
  exit 0
fi

# S'assurer que .temp/ est dans .gitignore
GITIGNORE="$REPO_ROOT/.gitignore"
if [[ ! -f "$GITIGNORE" ]] || ! grep -qx '.temp/' "$GITIGNORE" 2>/dev/null; then
  echo '.temp/' >> "$GITIGNORE"
fi

# Timestamp pour identifier ce snapshot
TS=$(date +%Y%m%d-%H%M%S)
TEMP_DIR="$REPO_ROOT/.temp"
GUARD_DIR="$TEMP_DIR/claude-guard-$TS"

# Lister les fichiers à risque : modifiés ou non suivis
# git status --porcelain retourne :
#   XY chemin  (X=index, Y=worktree)
#   ?? chemin  (non suivi)
AT_RISK_FILES=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # Extraire le chemin (commence à la position 3)
  filepath="${line:3}"
  # Ignorer les fichiers dans .temp/ lui-même
  [[ "$filepath" == .temp/* ]] && continue
  AT_RISK_FILES+=("$filepath")
done < <(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)

# Rien à protéger → laisser passer
if [[ ${#AT_RISK_FILES[@]} -eq 0 ]]; then
  exit 0
fi

# Créer le dossier de snapshot et copier les fichiers à risque
COPIED=0
for filepath in "${AT_RISK_FILES[@]}"; do
  fullpath="$REPO_ROOT/$filepath"
  if [[ -f "$fullpath" ]]; then
    target_dir="$GUARD_DIR/$(dirname "$filepath")"
    mkdir -p "$target_dir"
    cp "$fullpath" "$target_dir/"
    COPIED=$((COPIED + 1))
  fi
done

# Si aucun fichier n'a été effectivement copié
if [[ $COPIED -eq 0 ]]; then
  rmdir "$GUARD_DIR" 2>/dev/null || true
  exit 0
fi

echo "[guard] Snapshot de $COPIED fichier(s) a risque dans .temp/claude-guard-$TS/" >&2

exit 0
