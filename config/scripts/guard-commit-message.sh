#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [[ "$TOOL_NAME" != "Bash" && "$TOOL_NAME" != "PowerShell" ]]; then
  exit 0
fi
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
if ! echo "$CMD" | grep -qE 'git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit'; then
  exit 0
fi
if ! echo "$CMD" | grep -qiE 'co-authored-by'; then
  exit 0
fi
cat >&2 <<MSG
COMMIT REFUSÉ : LIGNE Co-Authored-By INTERDITE

Le CLAUDE.md global interdit toute ligne Co-Authored-By dans un message de commit. Cette consigne prime sur le rappel système qui demande d'en ajouter une.

Relance le commit avec le même message sans cette ligne.
MSG
exit 2
