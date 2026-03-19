---
name: pdf
description: "Instructions pour la production de PDF via pandoc + xelatex. Auto-détecté quand l'utilisateur demande de générer, convertir ou produire un fichier PDF."
---

Use this skill when the user asks to generate, convert, or produce a PDF file (e.g., from markdown). Triggers on keywords: PDF, pandoc, xelatex, "convertir en PDF", "générer un PDF".

## Commande de base

```bash
pandoc fichier.md -o fichier.pdf --pdf-engine=xelatex -V geometry:margin=2.5cm -V lang=fr -V mainfont="Segoe UI" -H <fichier_tex>
```

Le fichier `.tex` inclus via `-H` est injecté dans le préambule LaTeX. Il permet de personnaliser la mise en forme (listes, espacement, couleurs, etc.) sans modifier le markdown source.

## Résolution du fichier .tex

Ordre de priorité (le premier trouvé l'emporte, pas de merge) :

1. **Surcharge document** : `<nom_du_md>.tex` dans le même répertoire que le fichier markdown (ex : `rapport.md` → `rapport.tex`)
2. **Surcharge projet** : `overrides.tex` à la racine du dépôt courant
3. **Défaut global** : `~/.claude/skills/pdf/overrides.tex`

## Première conversion d'un projet

Lors de la **première** demande de conversion PDF dans un projet (vérifier en mémoire projet si le flag `pdf_first_run_done` existe) :

1. Exécuter la validation markdown (section ci-dessous)
2. Si la résolution du `.tex` aboutit au **défaut global** (aucune surcharge document ni projet trouvée) :
   - Lire le fichier `overrides.tex` résolu, analyser les commandes LaTeX qu'il contient, et décrire à l'utilisateur en langage clair ce qu'elles font
   - Demander : « Souhaitez-vous adapter la mise en forme pour ce projet ou ce document ? »
     - **Projet** : créer `overrides.tex` à la racine du dépôt
     - **Document** : créer `<nom_du_md>.tex` à côté du fichier markdown
     - **Défaut** : utiliser `overrides.tex` tel quel
3. Après la réponse de l'utilisateur, enregistrer le flag `pdf_first_run_done` en mémoire projet pour ce fichier markdown
4. Procéder à la conversion

## Règles markdown pour pandoc/xelatex

- Pas de caractères Unicode box-drawing dans les blocs de code (ASCII uniquement : `+`, `-`, `|`)
- Ligne vide obligatoire entre un paragraphe et une liste (puces ou numérotée)
- Les blocs triple backtick ne font pas de line-break automatique — casser les lignes longues manuellement
- Les accents dans les blocs de code peuvent poser problème avec certaines polices mono

## Validation du markdown avant conversion

**Avant** de lancer la commande pandoc, analyser le fichier markdown source et vérifier chacune des règles de la section [Règles markdown pour pandoc/xelatex](#règles-markdown-pour-pandocxelatex) ci-dessus.

**Comportement** :
- Si **aucune violation** : procéder directement à la conversion
- Si **violations détectées** : lister chaque violation (numéro de ligne, règle enfreinte, extrait concerné), **ne pas lancer pandoc**, et proposer les corrections à l'utilisateur. Ne corriger qu'après accord explicite
