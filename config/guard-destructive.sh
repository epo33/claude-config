#!/usr/bin/env bash
# Hook PreToolUse — bloque les commandes destructives exécutées par Claude Code.
# Retourne exit 0 (autorisé) ou exit 2 (bloqué avec message).
# Le JSON de l'appel d'outil arrive sur stdin.

set -euo pipefail

# Lire le JSON stdin
INPUT=$(cat)

# Extraire le nom de l'outil
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Ne s'applique qu'à l'outil Bash
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Extraire la commande
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ -z "$CMD" ]]; then
  exit 0
fi

# --- Patterns destructifs ---

# Git destructif
GIT_PATTERNS=(
  'git\s+checkout\s+--'
  'git\s+restore\s+'
  'git\s+reset\s+--hard'
  'git\s+clean\s+-[a-zA-Z]*f'
  'git\s+stash\s+drop'
  'git\s+stash\s+clear'
  'git\s+branch\s+-[dD]\s+'
  'git\s+push\s+.*--force'
  'git\s+push\s+-f\b'
)

# Suppression fichiers/dossiers
DELETE_PATTERNS=(
  '\brm\s+'
  '\brmdir\s+'
  '\bdel\s+'
  '\bRemove-Item\s+'
)

# Écrasement silencieux
OVERWRITE_PATTERNS=(
  '\bmv\s+'
  '[^>]>[^>]'
)

check_patterns() {
  local category="$1"
  shift
  local patterns=("$@")
  for pattern in "${patterns[@]}"; do
    if echo "$CMD" | grep -qPi "$pattern"; then
      echo "BLOCKED"
      echo "$category"
      echo "$pattern"
      return 0
    fi
  done
  return 1
}

# Vérifier chaque catégorie
RESULT=""
if RESULT=$(check_patterns "GIT DESTRUCTIF" "${GIT_PATTERNS[@]}"); then
  :
elif RESULT=$(check_patterns "SUPPRESSION FICHIER/DOSSIER" "${DELETE_PATTERNS[@]}"); then
  :
elif RESULT=$(check_patterns "ÉCRASEMENT POTENTIEL" "${OVERWRITE_PATTERNS[@]}"); then
  :
else
  exit 0
fi

CATEGORY=$(echo "$RESULT" | sed -n '2p')

# Bloquer avec message explicite
cat <<EOF
⛔ COMMANDE DESTRUCTIVE DÉTECTÉE — $CATEGORY

Commande bloquée :
  $CMD

Tu ne peux PAS exécuter cette commande. Fournis-la à l'utilisateur dans un bloc de code pour qu'il la copie et l'exécute lui-même dans son terminal.
EOF

exit 2
