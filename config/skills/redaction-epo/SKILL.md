---
name: redaction-epo
description: "Relecture et correction de documents destinés à être émis (CR, courriels, rapports, recommandations). Applique les conventions de rédaction EPO : style, typographie française, registre soutenu."
---

Use this skill when the user explicitly invokes `/redaction-epo` on a document.

**Style de réponse** :
- Ne JAMAIS modifier le document sans validation explicite de l'utilisateur.
- Présenter l'analyse de façon structurée puis attendre l'aval.

## Étape 1 : Lire le document cible

Lire intégralement le document passé en paramètre ou le document actuellement ouvert dans l'IDE.

## Étape 2 : Appliquer les règles de `prompt.md`

Analyser le document selon les règles définies dans `prompt.md` (même répertoire que ce fichier).

## Étape 3 : Présenter l'analyse

### Corrections directes (typo, orthographe, accords)

Lister les corrections factuelles sous forme de tableau :

| Ligne | Original | Correction |
|-------|----------|------------|
| ... | ... | ... |

### Suggestions de reformulation (style, vocabulaire, structure)

Pour chaque passage améliorable, utiliser `AskUserQuestion` avec :
- `question` : citation du passage original + 2-3 variantes proposées
- `options` : chaque variante en option + une option « Conserver l'original »
- `multiSelect` : false

Si le document est long (> 50 lignes), proposer un découpage par section avant de commencer.

## Étape 4 : Appliquer les modifications

Après validation, appliquer toutes les corrections et les choix de reformulation.

Ajouter le marqueur `<!-- redaction-epo -->` en fin de document s'il n'est pas déjà présent.
