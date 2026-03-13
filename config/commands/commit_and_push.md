---
description: Commit de tous les changements et push dans le dépôt GitHub
arguments: message optionnel décrivant les changements
---

Commiter tous les changements (fichiers modifiés, ajoutés et supprimés, hors .gitignore) et pousser sur le dépôt GitHub.

## Étapes

1. Lancer `git status` et `git diff` pour analyser les changements en cours.

2. **Déterminer le message de commit :**
   - Si l'utilisateur a fourni un message dans ses arguments : l'utiliser comme message de commit.
   - Si l'utilisateur n'a pas fourni de message : analyser les changements (diff, fichiers modifiés/ajoutés/supprimés), puis proposer 3 messages de commit possibles en français. L'utilisateur peut choisir l'un des 3, demander un mix/reformulation, ou proposer le sien. Itérer jusqu'à validation.
   - **Style des messages** : courts et orientés objectif (le "quoi/pourquoi"), jamais les détails d'implémentation (le "comment"). Exemples :
     - Bon : "Splash screen", "Persistance des réglages", "Séquence d'initialisation"
     - Mauvais : "Ajout du splash screen avec icône CustomPaint ondes brutes/filtrées", "Splash screen animé avec visuel brut/filtré et support dans AppRoot"

3. **Détecter les changements disjoints :**
   - Si les changements couvrent plusieurs aspects techniques et/ou fonctionnels indépendants, proposer à l'utilisateur de les séparer en commits distincts, regroupés par thème.
   - Sur accord de l'utilisateur, proposer un message pour chaque commit thématique. Itérer avec l'utilisateur pour valider chaque message.
   - Effectuer le staging et le commit de chaque groupe de fichiers séparément.

4. **Staging et commit :**
   - Ajouter tous les fichiers concernés au staging (`git add` par noms de fichiers).
   - Créer le(s) commit(s) avec le(s) message(s) validé(s), en français.

5. **Push :** pousser sur le dépôt distant (`git push`).

## Règles

- Les messages de commit sont toujours rédigés en français.
- Ne **JAMAIS** ajouter de ligne "Co-Authored-By".
- Ne pas inclure les fichiers couverts par `.gitignore`.
- En cas de doute ou d'ambiguïté, toujours demander confirmation à l'utilisateur avant de commiter.
