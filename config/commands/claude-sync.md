---
description: Synchronise la config Claude depuis claude-config
---

Exécuter les étapes suivantes dans l'ordre :

1. Dans `~/claude-config`, préparer et committer les modifications locales :
   - Exécuter `git -C ~/claude-config add -A`
   - Si `git -C ~/claude-config diff --cached --quiet` retourne un code non nul (il y a des changements) :
     - Récupérer le diff stagé avec `git -C ~/claude-config diff --cached --stat` et `git -C ~/claude-config diff --cached`
     - Analyser les fichiers ajoutés, modifiés et supprimés pour en déduire un libellé de commit concis et significatif (ex. `"config: add styled_widget.md, update SKILL.md"`)
     - Committer avec ce libellé : `git -C ~/claude-config commit -m "<libellé>"`
     - Pusher si un remote existe : `git -C ~/claude-config push`
   - Sinon, afficher "Aucune modification locale."

2. Exécuter `bash ~/claude-config/sync.sh --skip-commit` pour effectuer le pull depuis le remote et appliquer la config dans `~/.claude/`.

3. Afficher un résumé de ce qui a été fait.
