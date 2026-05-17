---
name: relecture-code
description: "Relecture corrective de fichiers source produits par le LLM. Applique les règles d'écriture (génériques + spécifiques au langage) et corrige en place."
disable-model-invocation: true
---

Relecture des fichiers source modifiés depuis la dernière exécution du skill. Détecte et corrige en place les violations des règles d'écriture portées par ce skill.

## Délégation

**Règle** : déléguer systématiquement l'exécution à un sous-agent `general-purpose`. Pas d'exception, pas de mode inline. Quand l'utilisateur lance une relecture, c'est pour un volume qui justifie toujours la délégation, et le bénéfice en préservation de contexte est constant.

### Consignes à transmettre au sous-agent

Le prompt de délégation doit inclure ces instructions mot pour mot :

> Tu exécutes le skill `relecture-code` en mode silencieux. Tu détermines la liste des fichiers, tu lis les règles, tu audites, tu appliques les corrections via Edit, tu mets à jour le marqueur `.claude/last-relecture`.
>
> Tu ne remontes au LLM principal **que** :
>
> 1. La ligne de bilan : `Relecture : N fichier(s) audité(s)[, V violation(s) architecturale(s) à traiter]`.
> 2. Le bloc des violations architecturales s'il y en a (format dans la section « Sortie » du skill).
>
> Tu ne rapportes **pas** : la liste des fichiers lus, les règles consultées ou recopiées, les corrections appliquées fichier par fichier, les diffs, les explications de tes choix, un résumé de ce que tu as fait, un « voici ce qui a été corrigé ». Le LLM principal lit le diff git s'il veut connaître les changements.
>
> Aucun préambule, aucun épilogue, aucune phrase de transition. La sortie tient en quelques lignes maximum : bilan + éventuel bloc de violations, rien d'autre.

### Côté LLM principal

- Ne **pas** lire les fichiers audités.
- Ne **pas** relire ni paraphraser les règles du skill.
- Ne **pas** enrichir la sortie du sous-agent. La relayer telle quelle.

## Entrées

1. Argument optionnel : liste de fichiers à auditer (chemins absolus ou relatifs au workspace courant), un par ligne.
2. Si aucun argument : le skill détermine lui-même la liste à partir du marqueur d'état `<workspace>/.claude/last-relecture`. Dans tous les cas, inclure :
   - les fichiers suivis modifiés (`git diff --name-only HEAD`),
   - les fichiers nouvellement créés non encore stagés (`git ls-files --others --exclude-standard`),
   - et, si le marqueur contient une entrée pour le workspace courant, les fichiers touchés par les commits postérieurs au timestamp (`git log --since="<ts>" --name-only --pretty=format:`).
     Fusionner les trois listes, dédupliquer.

## Marqueur d'état

Fichier : `.claude/last-relecture` à la racine du workspace courant.

Format : une seule ligne, timestamp ISO 8601 UTC (ex. `2026-05-16T18:42:01Z`).

Mise à jour : après audit (avec ou sans corrections), réécrire le fichier avec le timestamp UTC du moment. Créer le dossier `.claude/` s'il n'existe pas. Écriture **bash uniquement**, UTF-8, LF.

## Périmètre des fichiers

Filtrer la liste candidate aux extensions de fichiers source :

- `.dart`
- `.ts`, `.tsx`, `.js`, `.jsx`
- `.py`
- `.go`
- `.rs`
- `.java`, `.kt`
- `.cs`
- `.cpp`, `.cc`, `.c`, `.h`, `.hpp`

Exclure :

- Fichiers de test (`*_test.*`, `*.test.*`, `*.spec.*`) — hors V1.
- Fichiers générés (`*.g.dart`, `*.freezed.dart`, sous `dist/`, `build/`, `generated/`).
- Fichiers couverts par `.gitignore`.

## Règles génériques (tous langages)

### Code muet — principe

Par défaut, aucun commentaire ni docstring. Le nom des identifiants, la signature et la structure suffisent. Un commentaire est acceptable uniquement pour : contrainte cachée, invariant non évident, contournement de bug précis, référence externe (RFC, algorithme nommé), comportement qui surprendrait un lecteur. Si le code semble nécessiter un commentaire pour être clair → refactor, pas commentaire.

Docstrings : expliquent **comment utiliser**, jamais comment c'est implémenté. Si l'usage est évident à partir du nom et de la signature, pas de docstring.

### Code muet — commentaires

Supprimer les commentaires qui :

- paraphrasent le nom de la variable, fonction, classe juste à côté ;
- décrivent ce que fait le code ligne par ligne au lieu de pourquoi ;
- justifient un fix ou un refactor (info qui appartient au commit, pas au code) ;
- documentent un comportement déductible de la signature.

**Conserver** : contrainte cachée, invariant non évident, contournement de bug précis avec référence (issue, RFC), comportement qui surprendrait un lecteur.

### Code muet — docstrings

Supprimer les docstrings qui :

- paraphrasent le nom et la signature ;
- décrivent l'implémentation (« calcule X en itérant sur Y ») au lieu de l'usage (« retourne la somme des Y ») ;
- listent les callers ou les usages (information qui rote) ;
- documentent des champs publics dont le nom est explicite.

**Conserver** : usage non évident, contrat avec l'appelant (préconditions, postconditions), effets de bord non triviaux.

### Lignes vides dans le corps des méthodes

Supprimer. Une méthode qui aurait besoin de respiration interne doit être refactorée, pas aérée.

### Guillemets de chaîne

Doubles par défaut dans les langages qui l'autorisent. Exception : chaîne contenant des `"` mais aucun `'` → guillemets simples (pour éviter les échappements).

### Accents français

Tout texte en français (commentaires, docstrings, chaînes de log, messages d'erreur) porte ses accents. Détecter les mots français sans accent qui devraient en porter un et corriger.

### Doubles négations

Privilégier la vérification positive. `value != null ? B : A` → `value == null ? A : B`. Formes équivalentes (`!isEmpty`, `!isAbsent`…) à inverser quand le résultat est plus lisible.

### Accolades et blocs

Toute structure de contrôle (`if`, `else`, `for`, `while`, `do`) doit utiliser des accolades, même pour une seule instruction. Pas de forme inline sans bloc.

```dart
// Incorrect
while (x > 0) doSomething();

// Correct
while (x > 0) {
  doSomething();
}
```

**Exception** : un `if` sans `else` suivi d'une instruction courte doit être sur une seule ligne, sans accolade.

```dart
// Correct
if (isEmpty) return 0;
```

### Paramètres de callback inutilisés

Remplacer les paramètres non utilisés par `_`, `__`, etc., dans les langages qui acceptent cette convention (Dart, TypeScript, JavaScript, Python, Rust…).

### Typage explicite redondant

Si le type est trivialement inférable du membre droit (`int x = 0;`), retirer le type explicite (`var x = 0;` ou `final x = 0;`). **Sauf** aux frontières publiques (paramètres et retours de fonctions/méthodes publiques) où le typage est obligatoire.

Exemple Dart :

```dart
// Frontière publique : type obligatoire
int parseCount(String raw) => int.parse(raw);

// Variable locale : type inutile, l'inférence suffit
final count = parseCount("42");
```

## Règles spécifiques au langage

Chargées en plus des règles génériques selon l'extension du fichier audité.

| Extension | Fichier de règles |
| --------- | ----------------- |
| `.dart`   | `skills/dart.md`  |

(Autres langages à ajouter au besoin.)

Si l'extension du fichier ne figure pas dans la table, n'appliquer que les règles génériques.

## Étapes

Les étapes ci-dessous sont exécutées **par le sous-agent**, jamais par le LLM principal (cf. « Délégation »).

1. Déterminer la liste des fichiers à auditer.
2. Filtrer par extension et exclusions.
3. Si la liste est vide après filtrage : afficher « Aucun fichier source à relire. », mettre à jour le marqueur, sortir.
4. Pour chaque fichier :
   - lire le contenu,
   - appliquer les règles génériques,
   - charger et appliquer le fichier de règles spécifique si l'extension est mappée,
   - corriger via Edit (ou Write si rewrite massif).
5. Mettre à jour le marqueur `<workspace>/.claude/last-relecture`.
6. Afficher la ligne de sortie (cf. « Sortie console »).

## Sortie

Deux flux distincts :

### 1. Corrections textuelles automatiques

Appliquées directement via Edit/Write. Aucun détail rapporté à l'utilisateur. L'utilisateur lit le diff git s'il veut savoir ce qui a changé.

Ligne console unique à la fin : `Relecture : {N} fichier(s) audité(s), {V} violation(s) architecturale(s) à traiter.` (omettre la partie violations si zéro).

### 2. Remontée des violations architecturales

Certaines règles ne sont pas auto-correctibles (renommage d'identifiant, découpage d'un widget Flutter en sous-composants, choix stateless/stateful, etc.). Pour ces cas, le skill **signale** sans corriger.

Forme : à la fin de l'exécution, retourner au LLM un bloc structuré listant les violations à traiter, par exemple :

```
Violations architecturales à traiter :

- {fichier.dart}:{ligne} — nommage : la classe `myClass` devrait suivre la convention `UpperCamelCase` (`MyClass`).
- {widget.dart}:{ligne} — widget Flutter : `BigWidget` dépasse {seuil} lignes dans `build`, envisager un découpage en sous-widgets.
- {widget.dart}:{ligne} — widget Flutter : `Row` avec 24 enfants inline, déclarer des variables locales pour améliorer la lisibilité.
```

Le LLM principal lit ce bloc et décide d'agir ou non (validation de l'utilisateur attendue avant tout renommage ou refactor architectural — cf. consignes générales).

## Garde-fous

- Ne pas toucher les fichiers couverts par `.gitignore`.
- Ne pas toucher les fichiers générés.
- Ne pas toucher les commentaires qui correspondent aux cas autorisés (contrainte cachée, invariant, workaround référencé, RFC). Dans le doute, conserver.
- Ne pas refactoriser au-delà des règles listées. Pas d'amélioration spontanée.
- Ne pas exécuter de tests, formateurs ou linters. Transformations textuelles ciblées uniquement.

## État final

- Le marqueur `<workspace>/.claude/last-relecture` est à jour.
- Les fichiers audités contiennent les corrections appliquées.
