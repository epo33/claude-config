#!/usr/bin/env bash
# Hook PostToolUse — vérifie après une commande Bash/PowerShell si des fichiers
# à risque ont été perdus. Traite tous les snapshots existants dans .temp/.
#
# Pour chaque snapshot claude-guard-*/ :
# - fichier toujours présent dans le repo → supprimer sa copie (non impacté)
# - fichier disparu du repo → conserver sa copie (perte détectée)
# - snapshot entièrement nettoyé → supprimer le dossier
#
# Le JSON de l'appel d'outil arrive sur stdin.

set -euo pipefail

# Lire le JSON stdin (obligatoire)
INPUT=$(cat)

# Extraire le nom de l'outil
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Ne s'applique qu'aux outils Bash et PowerShell
if [[ "$TOOL_NAME" != "Bash" && "$TOOL_NAME" != "PowerShell" ]]; then
  exit 0
fi

# Trouver la racine du repo git
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi

TEMP_DIR="$REPO_ROOT/.temp"

# Pas de dossier .temp → rien à vérifier
if [[ ! -d "$TEMP_DIR" ]]; then
  exit 0
fi

# Traiter tous les snapshots existants
for GUARD_DIR in "$TEMP_DIR"/claude-guard-*/; do
  # Glob sans match retourne le pattern littéral
  [[ ! -d "$GUARD_DIR" ]] && continue

  BASENAME=$(basename "$GUARD_DIR")

  # Lister les fichiers du snapshot et vérifier leur présence dans le repo
  LOST_FILES=()
  while IFS= read -r snapshot_file; do
    # Chemin relatif dans le snapshot → chemin relatif dans le repo
    filepath="${snapshot_file#$GUARD_DIR}"
    fullpath="$REPO_ROOT/$filepath"
    if [[ -f "$fullpath" ]]; then
      # Fichier non impacté → supprimer sa copie du snapshot
      rm -f "$snapshot_file"
    else
      LOST_FILES+=("$filepath")
    fi
  done < <(find "$GUARD_DIR" -type f 2>/dev/null)

  # Nettoyer les dossiers vides dans le snapshot
  find "$GUARD_DIR" -type d -empty -delete 2>/dev/null || true

  if [[ ${#LOST_FILES[@]} -gt 0 ]]; then
    # Des fichiers ont été perdus → avertir
    cat >&2 <<EOF
[guard] ATTENTION — ${#LOST_FILES[@]} fichier(s) a risque supprime(s) :
EOF
    for f in "${LOST_FILES[@]}"; do
      echo "  - $f  →  .temp/$BASENAME/$f" >&2
    done
    cat >&2 <<EOF

Pour restaurer : cp ".temp/$BASENAME/<chemin>" "<chemin>"
EOF
  fi
  # Si le dossier est vide (tout nettoyé), il a déjà été supprimé par find -empty -delete
done

# Si .temp est vide, le supprimer
rmdir "$TEMP_DIR" 2>/dev/null || true

exit 0
