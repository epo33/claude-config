# Refactoring : Décomposition d'un widget Flutter

Sous-compétence du skill `widget_decomposition`. Ce document décrit l'algorithme
pas à pas pour transformer un widget existant en appliquant le pattern de
décomposition en fichiers `part of`.

## Prérequis

- Le widget cible est identifié (fichier + classe).
- Au moins un critère de complexité est rempli (voir SKILL.md § Critères de complexité).

## Algorithme

### Étape 1 — Analyse

Lire le fichier du widget et classer chaque membre de la classe State (ou du
widget si StatelessWidget) dans l'une des catégories suivantes :

| Catégorie | Destination | Exemples |
|-----------|-------------|----------|
| **Plomberie Flutter** | Fichier principal | `initState`, `dispose`, `build`, `didUpdateWidget`, `didChangeDependencies`, `createState`, constructeurs, variables d'état |
| **Handlers d'événements** | `*.events.dart` (extension) | `onTap...`, `onChanged...`, `onSubmitted...`, toute méthode appelée par un callback de widget et contenant de la logique non triviale |
| **Sous-widgets feuilles** | `*.parts.dart` (mixin) | Méthodes `build*()` retournant des widgets "feuilles" (Text, IconButton, Slider…) ou des sous-arbres intermédiaires ne relevant pas de la mise en page structurelle |

**Règles de classement :**
- Un handler est **trivial** s'il tient sur une seule expression simple (ex: `() => context.pop()`, `() => setState(() => x = !x)`). Les handlers triviaux restent inline dans `build()`.
- Les structures de mise en page (Column, Row, Stack, Scaffold, StreamBuilder…) restent dans `build()`. Ce sont les feuilles et sous-arbres intermédiaires qui vont dans le mixin.
- Ne pas tomber dans l'excès inverse : une imbrication Column > Row > Column doit rester visible dans `build()`.

### Étape 2 — Organisation en dossier

Proposer de créer un dossier dédié portant le nom du widget pour y regrouper
tous les fichiers (principal, events, parts, et tout autre `part of` existant).

**Placement** : le dossier du widget doit être créé **dans le dossier de son
unique consommateur** si le widget n'est utilisé que par un seul parent
(voir SKILL.md § Placement des sous-widgets dédiés). Si le widget est
partagé entre plusieurs consommateurs, le placer dans `lib/widgets/`.

Exemple widget dédié : `AudioControlPanel` utilisé uniquement par `FilteringTab`
→ `lib/screens/page_filter/audio_control_panel/audio_control_panel.dart`

Exemple widget partagé : `SpectrumView` utilisé par plusieurs écrans
→ `lib/widgets/spectrum/spectrum.dart`

**Attendre la validation de l'utilisateur.** S'il refuse, conserver
l'emplacement actuel.

Si accepté :
1. Créer le dossier au bon emplacement (dossier consommateur ou `lib/widgets/`)
2. Déplacer le fichier principal dans le dossier
3. Mettre à jour les imports dans les fichiers qui référencent ce widget
4. Les fichiers `part of` seront créés directement dans le dossier

### Étape 3 — Proposition de décomposition

Présenter à l'utilisateur un tableau récapitulatif :

```
Fichier principal (my_widget.dart) :
  - initState, dispose, build
  - Variables d'état : x, y, z

Extension _MyWidgetEvents (my_widget.events.dart) :
  - onTapSave(...)
  - onFilterChanged(...)

Mixin _MyWidgetParts (my_widget.parts.dart) :
  - final title = Text(...)          ← indépendant du state/context
  - Widget statusBadge() => ...      ← dépend du state/context
```

**Attendre la validation explicite de l'utilisateur avant de continuer.**

### Étape 4 — Créer le fichier événements

Créer `my_widget.events.dart` :

```dart
part of "my_widget.dart";

extension _MyWidgetEvents on _MyWidgetState {
  Future<void> onTapSave() async {
    // ... code déplacé depuis le fichier principal
    // Accès direct à widget, context, setState, mounted
  }

  void onFilterChanged(String value) {
    // ...
  }
}
```

### Étape 5 — Créer le fichier sous-widgets

Créer `my_widget.parts.dart` :

```dart
part of "my_widget.dart";

mixin _MyWidgetParts on State<MyWidget> {
  // Sous-widgets sans dépendance à l'état ou au contexte → champ final
  final title = Text("Mon titre",
    style: TextStyle(fontSize: 24),
  );

  // Sous-widgets avec dépendance à l'état ou au contexte → fonction
  Widget statusBadge() => Badge(
    label: Text(statusLabel),  // statusLabel = variable d'état
    backgroundColor: isActive ? Colors.green : Colors.grey,
  );
}
```

### Étape 6 — Modifier le fichier principal

1. Ajouter les directives `part` après les imports :
   ```dart
   part "my_widget.events.dart";
   part "my_widget.parts.dart";
   ```

2. Ajouter le mixin à la classe State :
   ```dart
   class _MyWidgetState extends State<MyWidget> with _MyWidgetParts {
   ```

3. Supprimer les handlers et sous-widgets déplacés.

4. Dans `build()`, remplacer les appels :
   - Handlers : `onPressed: onTapSave` (l'extension rend les méthodes accessibles directement)
   - Sous-widgets : `title` (champ du mixin) ou `statusBadge()` (fonction du mixin)

### Étape 7 — Post-traitement

Exécuter sur les 3 fichiers (principal, events, parts) :

```bash
dart format <fichier_principal> <fichier_events> <fichier_parts>
dart analyze <fichier_principal> <fichier_events> <fichier_parts>
```

Signaler toute erreur à l'utilisateur.

## Variante StatelessWidget

Pour un StatelessWidget sans classe State :

- **Extension** : `extension _MyWidgetEvents on MyWidget { ... }`
- **Mixin** : `mixin _MyWidgetParts on StatelessWidget { ... }`
  - Tous les sous-widgets dépendant de propriétés du widget doivent être des fonctions (pas de champs `final` accédant à `this` dans un mixin).
- La classe widget déclare `with _MyWidgetParts`.

## Cas particuliers

### Widget avec un seul type de contenu à extraire

Si le widget n'a que des handlers à extraire (pas de sous-widgets complexes) ou
inversement, ne créer que le fichier pertinent (events OU parts, pas les deux).

### Fichiers `part of` existants

Si le widget a déjà des fichiers `part of` (ex: un dialog séparé), les conserver
et ajouter les nouveaux fichiers events/parts en complément.
