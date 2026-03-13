# Documentation LLM pour Sing - Projet en Cours

Ce document ne donne aucune consigne d'action immédiate. Il permet de connaitre le contexte de travail actuel. Inutile de résumer son contenu après lecture. Il suffit de dire "Compris".

**Projet:** Documentation LLM pour Sing Framework
**Démarrage:** 24 novembre 2024
**État:** Phase de Relecture Systématique
**Objectif Final:** Documentation cohérente, complète et prête pour agents LLM

## Contexte du Projet

### Objectif Principal
Construire une documentation complète et cohérente destinée à des agents LLM pour leur permettre de :
1. **Comprendre rapidement** le framework Sing et ses concepts fondamentaux
2. **Déterminer un plan d'action** à partir d'un prompt développeur (général ou très spécifique)
3. **Savoir où chercher** les informations détaillées nécessaires
4. **Implémenter correctement** en suivant les bonnes pratiques et patterns du framework

### Public Cible
- **Agents LLM** en priorité 
- Développeurs Dart/Flutter en secondaire (les agents peuvent leur fournir des indications)

### Approche Choisie
- **Architecture modulaire** : 1 fichier = 1 concept/sujet
- **Point d'entrée unique** : `C:\Users\emman\.claude\skills\sing-project\SKILL.md`
- **Navigation structurée** : Liens clairs vers les autres fichiers
- **Exemples concrets** : Basés sur `example/orderhub/` (simple) et `C:\Travail\Projets\balossi\gbom\` (complexe). gbom ne doit être utilisé que dans ton travail et **jamais** dans les fichiers markdown sur lesquels nous travaillons.

### Livrables du projet
- tous les fichiers à construire sont placé dans le répertoire C:\Users\emman\.claude\skills\sing-project\skills.
- ce sont des fichiers markdown.
- ils doivent être rédigé dans un anglais efficace pour un LLM.
- le document principal est `C:\Users\emman\.claude\skills\sing-project\SKILL.md`.
- les autres fichiers sont atteint en suivant des liens issus de ce fichier racine.

## Actions

Cette section définit les procédures à suivre lorsque des demandes sont formulées.

Pour chaque action, effectuer directement les modifications dans les fichiers markdown et afficher une liste des points corrigés avec, pour chacun, le motif de la correction et les textes avant/après pour permettre de revenir en arrière.

### "Vérifie le document" 

- Si l'ordre est suivi du nom d'un document, il s'agit d'un des documents du dossier AGENT. S'assurer qu'il existe.
- Si aucun nom de document n'est indiqué, il s'agit du fichier actif de l'éditeur.

Il faut alors :

1. **traduire** en anglais les phrases rédigées en français. **IMPORTANT** : traduire par gros blocs de texte (sections entières ou paragraphes) plutôt que phrase par phrase pour être plus efficace.

2. **traiter les abréviations** :
   - **BDD** -> database
   - **eg** -> e.g.
   - **ie** -> i.e.

3. **corriger** le vocabulaire et la grammaire anglaise. Pour les titres en anglais, privilégier la forme nominale (e.g., "Generated Code" plutôt que "Code Generated", "Search Filters" plutôt que "Filters Searched").

4. **numéroter** les sections, sous-sections, etc. Le titre du document (niveau `#`) n'est pas numéroté. La numérotation commence donc au niveau `##`. Ne pas renuméroter les listes.

5. **vérification de la qualité pour LLM**
   - Le langage est-il clair et efficace pour un agent LLM ?
   - Les concepts sont-ils expliqués de manière exploitable ?
   - Les instructions sont-elles actionnables ?

### "Vérifie la cohérence globale"

Cette vérification porte sur l'ensemble de la documentation AGENT :

1. **Cohérence de la navigation**
   - Vérifier que tous les documents sont accessibles en suivant des liens depuis `AGENT/SKILLS.md`
   - Vérifier que tous les liens entre documents sont valides
   - Identifier les fichiers orphelins (non référencés)

2. **Cohérence terminologique**
   - Les termes clés sont-ils utilisés de manière cohérente ?
   - Les concepts sont-ils nommés uniformément ?
   - Y a-t-il des ambiguïtés ou synonymes problématiques ?

3. **Cohérence des exemples**
   - Les exemples utilisent-ils cohéremment `example/orderhub/` ?
   - Les exemples sont-ils à jour avec le code actuel ?
   - Les patterns montrés sont-ils cohérents entre documents ?

Pour tout problème rencontrer, proposer une correction et un moyen simple pour l'utilisateur de demander une ou plusieurs correction (eg numérotation des problèmes/proposition).

### "Enregistre..." ou "Trace ..."

Dans la section "Actions réalisées" de ce document, ajouter une entrée à la date du jour avec les informations données dans le prompt.

### "Lien vers ..."
Il s'agit d'ajouter, dans le fichier actif dans l'éditeur et à la position du curseur dans cet éditeur, un lien vers un autre document du dossier AGENT.

1. s'assurer que le fichier actif est bien un fichier markdown du répertoire AGENT.
2. depuis le prompt, déterminer le nom du fichier à référencer et (optionel) le texte du lien.
3. insérer un lien markdown vers le fichier indiqué avec le texte donné (`texte` si non renseigner)
4. si le fichier à référencer n'existe pas, le créer

Le nom du fichier à référencer doit avoir l'extension `.md`, entièrement en majuscule, les espaces remplacés par des `_` (eg "services" -> "SERVICES.md").


---


## Consignes valables à tout momemt
- toute modification dans le répertoire `C:\Users\emman\.claude\skills\sing-project\` est **autorisée** sans demande à l'utilisateur.
- lorsque le fichier DOC.md est modifié, le relire pour tenir compte des modifications.
- **ne pas** lire un des fichiers du projets (`C:\Users\emman\.claude\skills\sing-project\*.md`) tant que ce n'est pas explicitement demandé ou nécessaire pour réaliser la tâche demandée.
- après chaque action, afficher le nombre de token émis et reçu (suivi de la consommation des tokens).
- fais des réponses denses en information. Evite le verbiage et les répétitions.
- tu peux utiliser le tutoiement dans tes réponses mais évite de mélanger tu/vous.

### Distinction question / ordre
Lorsque l'utilisateur **pose une question** (reconnaissable par un point d'interrogation ou une formulation interrogative comme "Comment...", "Peux-tu...", "Quelle est...") :
- **NE PAS** effectuer des actions susceptible de modifier des fichiers ou des répertoires
- **RÉPONDRE** d'abord à la question
- **PROPOSER** les actions possibles avec une formulation explicite (ex: "Je peux ajouter cette règle dans DOC.md en modifiant la section X. Veux-tu que je le fasse ?")
- **ATTENDRE** la confirmation avant d'agir

### Style de réponse en cas d'erreur
Lorsque tu ne respectes pas une consigne :
- **NE PAS** valider l'utilisateur avec des phrases comme "Tu as raison", "Excellente remarque", etc.
- **EXPLIQUER** pourquoi tu n'as pas suivi la procédure (ex: "J'ai utilisé Edit au lieu de MCP md-renumber parce que...")
- **PROPOSER** la correction appropriée avec la méthode correcte
- **ATTENDRE** la confirmation avant d'agir
  
## Actions réalisées

- 26/11/25 : début du travail.
- 26/11/25 : documentation complétée pour la définition des espaces de nom, des entités et des champs (fichier DATA_MODEL.md).

---

