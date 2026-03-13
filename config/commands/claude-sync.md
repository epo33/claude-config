---
description: Synchronise la config Claude depuis claude-config et initialise copilot-instructions.md dans le projet courant
---

Exécuter les étapes suivantes dans l'ordre :

1. Exécuter `bash ~/claude-config/sync.sh` pour synchroniser la configuration Claude de manière bidirectionnelle (commit+push des modifications locales, pull depuis le remote, application dans `~/.claude/`).

2. Si le workspace courant est un projet Dart/Flutter (présence d'un fichier `pubspec.yaml` à la racine) :
   - Vérifier si le fichier `.github/copilot-instructions.md` existe à la racine du projet.
   - S'il n'existe pas, créer le dossier `.github/` si nécessaire, puis créer le fichier `.github/copilot-instructions.md` avec le contenu suivant :
     ```
     Avant toute complétion, lis et respecte le fichier ~/.claude/dart.instructions.md
     ```
   - S'il existe déjà, ne pas le modifier.

3. Afficher un résumé de ce qui a été fait.
