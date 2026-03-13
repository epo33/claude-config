---
description: Lire et exécuter un plan depuis un fichier markdown
arguments: chemin optionnel vers le fichier de plan (.md)
---

Exécuter un plan d'implémentation ou de refactoring décrit dans un fichier markdown.

## Détermination du fichier de plan

Appliquer dans l'ordre :

1. **Arguments du prompt** : si `$ARGUMENTS` contient un chemin de fichier, l'utiliser.
3. **Demander à l'utilisateur** en proposant les fichiers présents dans "./.plan" (si le dossier existe) ou dans les plans de "~/.claude/plans". Proposer par ordre de date de création décroissante.

## Lecture et validation du plan

Afficher le moins de retour possible à l'utilisateur avant le lancement du plan.

1. **Lire intégralement** le fichier de plan identifié.
2. **Vérifier** qu'il contient une structure exploitable (étapes, fichiers à modifier, etc.).
4. **Mode d'exécution** : s'assurer d'être en mode édition (pas plan). Si le mode "bypass permission" est autorisé, proposer à l'utilisateur de passer dans ce mode.

Lancer le plan directement.

## Exécution du plan

Afficher la progression à l'utilisateur.

1. **Créer la liste de tâches** (TodoWrite) à partir des étapes du plan.
2. **Exécuter chaque étape** séquentiellement :
   - Marquer l'étape en cours (`in_progress`) avant de commencer.
   - Lire les fichiers concernés avant toute modification.
   - Appliquer les modifications décrites dans le plan.
   - Marquer l'étape terminée (`completed`) une fois réussie.
3. **En cas d'ambiguïté ou de problème** à une étape :
   - Ne pas deviner ni improviser.
   - Expliquer le blocage à l'utilisateur.
   - Proposer des alternatives si pertinent.
   - Attendre les instructions avant de continuer.

## Post-exécution

1. **Lancer `dart analyze`** sur les fichiers modifiés (si projet Dart/Flutter).
2. **Lancer `dart format`** sur les fichiers modifiés (si projet Dart/Flutter).
3. **Corriger** les erreurs d'analyse éventuelles.
4. **Résumer** les actions effectuées et les fichiers modifiés.

## Principes

- **Fidélité au plan** : suivre les instructions du plan telles quelles, sans ajouts ni simplifications non demandés.
- **Pas d'initiative** : ne jamais modifier du code non mentionné dans le plan.
- **Transparence** : signaler tout écart entre le plan et la réalité du code.
- **Validation continue** : en cas de doute, demander plutôt qu'improviser.
