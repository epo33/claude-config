---
description: Clôturer proprement la session en mettant à jour les traces du projet (encours, RàF, plan, WIP) pour qu'une session suivante puisse reprendre par « on continue ».
argument-hint: "optionnel : note libre à intégrer au résumé d'encours."
---

Préparer la fin de session de façon à ce qu'une session suivante puisse reprendre en lisant uniquement le `CLAUDE.md` local et les fichiers qu'il référence.

## Principe directeur

Le `CLAUDE.md` à la racine du projet est la source unique de vérité pour savoir **quoi mettre à jour**. Il liste les fichiers de trace utilisés par le projet (encours, RàF, plan, WIP, journal de session, etc.). Si un fichier n'est pas mentionné dans `CLAUDE.md`, il n'est pas touché par cette commande.

Si `CLAUDE.md` est absent ou ne décrit aucun fichier de trace : voir « Cas particuliers » plus bas.

## Étapes

### 1. Lire le `CLAUDE.md` du projet

Lire `./CLAUDE.md` (racine du workspace courant). En extraire :
- la liste des fichiers de trace que le projet maintient (encours, RàF, WIP, plan, journal…),
- pour chacun, ce qu'il est censé contenir et comment il est mis à jour,
- toute consigne explicite sur la clôture de session.

Ne pas inventer de fichiers, ne pas en supposer. Si la convention ne mentionne que `WIP.md` et `RAF.md`, ne pas créer un `JOURNAL.md` au passage.

### 2. Établir l'état de fin de session

Sans modifier de fichier, lister mentalement :
- ce qui a été fait pendant la session (décisions tranchées, modifications appliquées, vérifications passées),
- ce qui reste à faire (tâche en cours interrompue, points soulevés mais non traités, dette adjacente repérée),
- ce sur quoi je bute, le cas échéant (hypothèse non confirmée, attente d'arbitrage),
- la prochaine action concrète pour reprendre.

Si la session a touché à un plan (`./.plan/*.md`), repérer où on en est dans son exécution.

### 3. Présenter le résumé à l'utilisateur

Avant toute écriture, afficher un récapitulatif court :
- fichiers de trace identifiés dans `CLAUDE.md` qui seront mis à jour,
- pour chacun, un résumé de ce qui va y être écrit ou modifié,
- éventuelles consignes du `CLAUDE.md` qui demandent un traitement particulier (ex. nettoyer une section au démarrage de la session suivante),
- demander confirmation avant d'écrire.

Si l'utilisateur a passé un argument à la commande, l'intégrer au résumé d'encours.

### 4. Écrire après confirmation

Une fois la confirmation reçue :
- mettre à jour chaque fichier de trace selon les conventions du projet,
- préserver l'historique existant (pas de réécriture destructive d'un journal),
- texte français accentué, conventions typographiques du `CLAUDE.md` global respectées,
- manipulation par bash, jamais PowerShell.

Si une consigne du `CLAUDE.md` local doit être ajoutée pour piloter le démarrage suivant (par exemple : « au prochain démarrage, lire `WIP.md` puis `RAF.md` »), l'écrire dans le `CLAUDE.md` local, dans une section identifiable, et indiquer dans le résumé que cette section devra être nettoyée au prochain démarrage.

### 5. Préparer la reprise de la prochaine session

Inscrire dans le `CLAUDE.md` local, sous une section dédiée (titre suggéré : `## Reprise de session`), une consigne courte et explicite à destination du LLM qui démarrera la prochaine session :

> Au démarrage, lire les fichiers de trace listés ci-dessus. Produire **une synthèse très courte** de ce qu'il reste à faire (3 à 5 lignes maximum, pas de récapitulatif de ce qui a été fait, pas de détail : l'utilisateur sort de la session précédente et connaît l'état). Puis proposer de lancer un point précis du RàF (ou équivalent), en attendant l'arbitrage avant d'exécuter.

Cette section est à nettoyer dès que la reprise a eu lieu (à mentionner explicitement dans la synthèse de reprise).

### 6. ACK

Une phrase factuelle listant les fichiers effectivement mis à jour. Puis rendre la main.

## Cas particuliers

**Pas de `CLAUDE.md` local** : signaler à l'utilisateur que le projet n'a pas de convention déclarée. Proposer deux options :
- A. créer un `CLAUDE.md` minimal qui pointe vers un `WIP.md` à créer,
- B. consigner l'état uniquement dans la réponse, sans écrire de fichier.

Ne pas trancher seul.

**`CLAUDE.md` présent mais muet sur les traces** : même logique, demander si on ajoute la convention au `CLAUDE.md` ou si on se contente d'un résumé en réponse.

**Session sans modification notable** : ne rien écrire, le signaler en une phrase et rendre la main.

**Conflit entre l'état perçu et ce qui est déjà dans les fichiers de trace** (ex. `WIP.md` décrit une tâche A, la session a porté sur une tâche B) : signaler le conflit avant d'écrire, demander si on remplace, on fusionne ou on archive.

## Anti-patterns

- Écrire avant confirmation.
- Créer des fichiers non prévus par le `CLAUDE.md` local.
- Refondre l'organisation des traces « au passage ».
- Produire un résumé verbeux : une dizaine de lignes pour l'état, pas une dissertation.
- Supposer une convention (`WIP.md`, `RAF.md`…) si elle n'est pas déclarée localement.
