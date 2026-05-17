---
description: Synchronise la config Claude depuis claude-config et initialise copilot-instructions.md dans le projet courant
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

2. Si le workspace courant est un projet Dart/Flutter (présence d'un fichier `pubspec.yaml` à la racine) :
   - Vérifier si le fichier `.github/copilot-instructions.md` existe à la racine du projet.
   - S'il n'existe pas, créer le dossier `.github/` si nécessaire, puis créer le fichier `.github/copilot-instructions.md` avec le contenu suivant :
     ```
     Avant toute complétion, lis et respecte le fichier ~/.claude/dart.instructions.md
     ```
   - S'il existe déjà, ne pas le modifier.

3. Afficher un résumé de ce qui a été fait.
