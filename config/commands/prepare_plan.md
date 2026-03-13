description: Préparation d'un plan de réalisation d'une fonctionnalité ou refactoring
---

L'utilisateur souhaite développer une nouvelle fonctionnalité ou refactorer un point. L'objectif est de produire un plan détaillé et non ambigu, mais **seulement après avoir clarifié tous les aspects de la demande**.

## Méthodologie : Itérations Question/Réponse

### Phase 1 : Compréhension initiale

1. **Lire la demande** de l'utilisateur attentivement
2. **Explorer le code existant** pour comprendre le contexte :
   - Lire les fichiers mentionnés ou concernés
   - Utiliser Grep/Glob pour identifier les impacts potentiels
   - Comprendre l'architecture actuelle
3. **Formuler ta compréhension** de façon structurée :
   - Récapituler ce que tu as compris
   - Identifier les zones d'incertitude
   - Lister les questions à poser

### Phase 2 : Itérations de clarification

**Cycle itératif** jusqu'à ce que tout soit clair :

1. **Poser des questions ciblées** regroupées par thème :
   - Architecture (approche technique, patterns)
   - Nommage (classes, méthodes, concepts)
   - Scope (ce qui est inclus/exclu)
   - Impacts (fichiers, dépendances, tests)
   - Stratégie (ordre des opérations, migration)

2. **Proposer des alternatives** quand pertinent :
   - Présenter 2-3 options viables
   - Expliquer les avantages/inconvénients
   - Recommander une approche (avec justification)

3. **Structurer la présentation** :
   - Utiliser des sections claires (## Ma compréhension, ## Questions)
   - Numéroter les questions pour faciliter les réponses
   - Utiliser des exemples de code quand nécessaire

4. **Lire les réponses** et reprendre au point 1

### Phase 3 : Validation finale

Avant de produire le plan :

1. **Récapituler l'ensemble** des décisions prises
2. **Vérifier la cohérence** globale
3. **Proposer** explicitement de "compléter la compréhension" ou "préparer le plan"
4. **Attendre la validation** explicite de l'utilisateur

## Production du plan

**Ne produire le plan final que lorsque l'utilisateur le demande explicitement EN FIN DE PHASE 3.**

### Structure du plan

Le plan doit contenir :

1. **Context** : Pourquoi cette modification (problème à résoudre, besoin)
2. **Overview** : Vue d'ensemble des changements (créations, suppressions, renommages)
3. **Detailed Changes** : Détails techniques avec exemples de code
4. **Implementation Steps** : Étapes numérotées et séquencées
5. **Critical Files** : Liste des fichiers à créer/modifier/supprimer avec chemins complets
6. **Verification** : Commandes et vérifications pour valider le résultat

### Format du plan

- **Markdown** avec sections claires
- **Code blocks** pour les exemples
- **Chemins complets** pour tous les fichiers
- **Commandes vérifiables** (dart analyze, grep, etc.)
- **Concis mais complet** : assez détaillé pour exécuter, assez bref pour scanner

### Enregistrement

- Le plan est d'abord créé dans le fichier officiel de plan mode
- Le plan doit être auto-suffisant (compréhensible sans le contexte de la conversation)
- le plan doit TOUJOURS être enregistré dans le répertoire "./.plan" dans un fichier markdown. Déterminer le nom du fichier à partir de l'objectif. 
- Une fois créé et enregistré dans "./.plan", informer l'utilisateur("plan enregistré dans ...). 
- inutile d'afficher le plan. L'utilisateur DOIT lire le fichier à tête reposée. 
- inutile de proposer l'exécuter le plan. 

## Principes directeurs

1. **Clarté avant action** : Mieux vaut une itération de plus qu'un plan ambigu
2. **Questions structurées** : Grouper par thème, numéroter, être précis
3. **Exploration du code** : Toujours lire avant de proposer
4. **Alternatives éclairées** : Proposer des options avec recommandations justifiées
5. **Validation explicite** : Ne jamais supposer, toujours confirmer
6. **Plan exécutable** : Détaillé, séquencé, vérifiable

## Exemple de progression

```
User: "Je veux refondre X"
Assistant: [Lit le code] "Voici ma compréhension... Questions: 1. Architecture? 2. Nommage?"

User: [Réponses]
Assistant: "OK, compréhension mise à jour... Nouvelles questions: 3. Stratégie? 4. Ordre?"

User: [Réponses]
Assistant: "Récapitulatif complet. Veux-tu ajouter des points ou préparer le plan?"

User: "Prépare le plan"
Assistant: [Crée le plan détaillé avec les 6 sections]
```

## Anti-patterns à éviter

- ❌ Produire un plan trop tôt (sans clarification suffisante)
- ❌ Poser trop de questions d'un coup (max 5 par itération)
- ❌ Proposer des solutions sans explorer le code d'abord
- ❌ Faire des suppositions sur des choix architecturaux
- ❌ Créer un plan trop verbeux ou trop succinct
- ❌ Oublier la section Verification
