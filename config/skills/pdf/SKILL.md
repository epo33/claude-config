---
name: pdf
description: "Instructions pour la production de PDF via pandoc + xelatex. Auto-détecté quand l'utilisateur demande de générer, convertir ou produire un fichier PDF."
---

Use this skill when the user asks to generate, convert, or produce a PDF file (e.g., from markdown). Triggers on keywords: PDF, pandoc, xelatex, "convertir en PDF", "générer un PDF".

**Style de réponse — CRITIQUE** :
- **ZÉRO narration** : ne JAMAIS commenter les étapes internes. L'utilisateur ne doit voir que le résultat final.
- **Ne JAMAIS afficher** les noms de variables du script (TEX_FILE, TEX_SOURCE, FIRST_RUN, VIOLATIONS, TEX_CONTENT). Interpréter silencieusement la sortie et ne montrer que le message destiné à l'utilisateur.
- **Sortie attendue** : uniquement les violations (si présentes) et/ou la question first-run (si applicable) et/ou la confirmation de conversion. Rien d'autre.

## Étape 1 : Pré-vérification

Lancer directement via Bash (essayer `python3`, sinon `python`) :

```bash
python3 ~/.claude/skills/pdf/pdf-check.py "<chemin/fichier.md>" "<memory_dir>" "<repo_root>"
```

- `<memory_dir>` : répertoire mémoire projet Claude (ex : `~/.claude/projects/<project-id>/memory`)
- `<repo_root>` : racine du dépôt courant

## Étape 2 : Réponse à l'utilisateur

Interpréter la sortie du script **sans la montrer** :

1. **FIRST_RUN=false ET VIOLATIONS=none** : lancer directement la conversion.

2. **VIOLATIONS présentes** : lister chaque violation, ne PAS lancer pandoc, proposer les corrections. Ne corriger qu'après accord explicite.

3. **FIRST_RUN=true ET TEX_SOURCE=global ET VIOLATIONS=none** : analyser TEX_CONTENT, décrire en une phrase concise en langage courant ce qu'il fait (ne jamais montrer le code LaTeX). Introduire par « La mise en page qui sera appliquée inclut ... ». Puis demander :
   - **OBLIGATOIRE** : utiliser l'outil `AskUserQuestion` (ne JAMAIS poser cette question en texte libre). Paramètres :
     - `question` : « La mise en page qui sera appliquée inclut : {description}. Souhaitez-vous personnaliser la mise en forme ? »
     - `header` : « Mise en page »
     - `multiSelect` : false
     - `options` :
       - label: « Fichier » / description: « Surcharge .tex dédiée à ce document »
       - label: « Projet » / description: « Surcharge overrides.tex pour tout le dépôt »
       - label: « Défaut » / description: « Lancer la conversion telle quelle »
   - Après la réponse, enregistrer le flag `pdf_first_run_done:<nom_fichier.md>` en mémoire projet.

4. **FIRST_RUN=true ET TEX_SOURCE!=global** : enregistrer le flag et lancer la conversion.

## Étape 3 : Conversion

```bash
pandoc "<fichier.md>" -o "<fichier.pdf>" --pdf-engine=xelatex -V geometry:margin=2.5cm -V lang=fr -V mainfont="Segoe UI" -H "<TEX_FILE>"
```
