---
applyTo: "**/*.dart"
---

# Identifiants

## Conventions de nommage
- Types, enums, typedefs, extensions: `UpperCamelCase`
- Packages, fichiers, répertoires: `lowercase_with_underscores`
- Préfixes d'import: `lowercase_with_underscores`
- Variables, fonctions, paramètres: `lowerCamelCase`
- Constantes: `lowerCamelCase` (pas `SCREAMING_CAPS`)

## Acronymes
- Acronymes de plus de 2 lettres: capitaliser comme un mot normal (`HttpRequest`, pas `HTTPRequest`)
- Acronymes de 2 lettres: conserver la capitalisation anglaise (`ID`, `UI`, `TV`)

## Paramètres inutilisés
- Utiliser `_` pour les paramètres de callback inutilisés

# Imports

Ordre avec lignes vides entre sections:
1. `dart:` imports
2. `package:` imports
3. imports relatifs
4. exports (section séparée)

Chaque section triée alphabétiquement.

# Formatage

- Utiliser `dart format` comme standard.
- Maximum 80 caractères par ligne.
- Toujours utiliser des accolades dans les structures de contrôle (sauf if simple sans else sur une seule ligne).
- Utiliser SYSTEMATIQUEMENT le guillemet double (`"`) pour les chaînes de caractères, SAUF si la chaîne contient un guillemet double.
- Préférer la syntaxe des fonctions fléchées pour les méthodes simples:
```dart
// Incorrect
int add(int a, int b) {
  return a + b;
}
// Correct
int add(int a, int b) => a + b;
```
- Éviter les sauts de ligne dans l'implémentation des méthodes. Si une ligne vide est insérée, c'est souvent le signe d'une méthode trop longue ou qui fait trop de choses.

- Une classe privée ne doit pas définir de membres privés (redondant).

# Typage

Ne pas typer explicitement les variables ou paramètres où le type est évident:
```dart
// type facultatif, peut être écrit var count = 0;
int count = 0;

calculateSum( a, b) => return a+b; // Incorrect
int calculateSum( int a, int b) => return a+b; // Correct

 // le type des éléments de la list (String) est obligatoire, mais il est inutile de typer items (List<String>)
 final items = <String>[];

// les types de context et child sont inutiles (présent dans la déclaration de la fonction de callback builder)
 AnimatedBuilder( builder:(context, child) { ... } );
```

# Records Dart

Les records Dart ne doivent comprendre que des champs nommés.

# Énumérations

Préférer la syntaxe abrégée pour accéder aux valeurs des énumérations:
```dart
enum Status {
  active,
  inactive,
  pending
}

final Status test = .active;
```

# Documentation

## Contenu d'un docComment

Lors de la rédaction de docComments : 
- **TOUJOURS** expliquer COMMENT UTILISER le code (quoi, quand, pourquoi), - 
- **JAMAIS** expliquer COMMENT EST IMPLÉMENTÉ le code (détails internes, algorithmes),
- Les détails d'implémentation vont dans des commentaires normaux, pas dans des docComments.

## Où ajouter un docComment
- Ajouter un docComment à une classe, méthode ou propriété SI ET SEULEMENT SI son UTILISATION N'EST PAS ÉVIDENTE à partir de son nom ou de sa signature. Par exemple, une méthode `calculateTotalPrice()` n'a pas besoin d'un docComment pour expliquer ce qu'elle fait, mais une méthode `calculate()` pourrait en avoir besoin pour préciser ce qu'elle calcule.

```dart
// Incorrect

/// Utilisateur de l'application
class User {
  /// Prénom de l'utilisateur
  String firstName;
  /// Nom de l'utilisateur
  String lastName;

  User(this.firstName, this.lastName);

  /// Crée un utilisateur à partir d'un JSON
  User.fromJson(Map<String, dynamic> json)
      : firstName = json['firstName'],
        lastName = json['lastName'];

  /// Convertit l'utilisateur en JSON
  Map<String, dynamic> toJson() {
    return {
      'firstName': firstName,
      'lastName': lastName,
    };
  }
}

// Correct

class User {
  User(this.firstName, this.lastName);

  String firstName;

  String lastName;

  User.fromJson(Map<String, dynamic> json)
      : firstName = json["firstName"],
        lastName = json["lastName"];

  Map<String, dynamic> toJson() {
    return {
      "firstName": firstName,
      "lastName": lastName,
    };
  }
}

```

## Commentaires "normaux"

- Utiliser des commentaires normaux (// ou /* */) pour expliquer les détails d'implémentation, les algorithmes, les choix techniques, etc. Ces commentaires sont destinés aux développeurs qui lisent le code, pas aux utilisateurs de la classe ou de la méthode.
- Les commentaires normaux peuvent être placés à l'intérieur des méthodes pour expliquer des étapes spécifiques, ou au-dessus de blocs de code pour expliquer leur but.
- A utiliser **UNIQUEMENT** lorsque : 
  - le code n'est pas suffisamment clair par lui-même (probablement à refactoriser plutôt que commenter)
  - pour citer des références techniques e.g. : 
    - "Cette implémentation est basée sur l'algorithme de Dijkstra" 
    - "voir https://datatracker.ietf.org/doc/html/rfc5322".

# Ordonnancement des lignes de code dans la définition d'une classe

L'ordre des éléments dans la définition d'une classe doit être le suivant:
1. constantes statiques (static const).
2. variables statiques (static final ou static var).
3. méthodes statiques (static).
4. constructeurs: les constructeurs privés, le constructeur par défaut, les constructeurs nommés puis les constructeurs factory.
5. variables publiques (var ou final, get/set).
6. méthodes publiques.
7. méthodes privées (commençant par _).
8. variables privées (commençant par _).

# Widget Flutter

- Utiliser des widgets stateless chaque fois que possible.
- Découper les gros widgets en plusieurs petits widgets pour améliorer la lisibilité et la réutilisabilité du code.
- Il est inutile de déclarer comme privé des membres d'une classe elle même privée (cas courant: les classes d'état (extends State) dans la définition d'un widget StatefulWidget).
- Éviter de définir plusieurs widgets dans un même fichier.
- Si des petits widgets sont nécessaires pour constituer un gros widget, les définir comme des classes privées dans un fichier portant le même nom que le widget principal mais avec identifiant en suffixe. Exemple: pour un widget principal `my_widget.dart`, les petits widgets seront définis dans des fichiers `my_widget.header.dart`, `my_widget.footer.dart`, etc.
- S'ils n'ont pas vocation à être réutilisés ailleurs, les petits widgets peuvent être définis comme des classes privées et leur fichier déclaré comme `part of 'my_widget.dart';`.
- si le package "styled_widget" est utilisé, préférer la syntaxe de composition de widgets plutôt que la syntaxe de construction de widgets. Exemple: `Text("Hello").padding(all: 8)` au lieu de `Padding(padding: EdgeInsets.all(8), child: Text("Hello"))`. Les compositions les plus fréquentes sont: `padding`, `margin`, `backgroundColor`, `borderRadius`, `alignment`, `center()`, `expanded()`, etc.
- si un widget définit une liste "children" (Row, Column, etc.) longue (plus de 20 LoC) déclarer des variables locales pour les widgets enfants (nom déduit du type de widget et de son contenu/rôle) afin d'améliorer la lisibilité. Exemple: 
```dart
Widget build(BuildContext context) {
  final deviceDropdown = DropdownButton(...);
  final btnPlayPause = IconButton(...);
  final btnStop = IconButton(...);

  return Column(
    children: [
      deviceDropdown,
      btnPlayPause,
      btnStop,
    ],
  );
}
```

# Consignes 

**Expressions ternaires, if/else:**
- Préférer les vérifications positives/nullables dans les conditions ternaires ou clause d'un if
- Utiliser `value == null ? ... : ...` plutôt que `value != null ? ... : ...`
- Utiliser `if (value == null) {...} else {...}` plutôt que `if (value != null) {...} else {...}`
- Cela améliore la lisibilité en évitant les négations : if (négation) => else = négation de négation)
- Exemple: `docId == null ? "indexed" : "reindexed"` au lieu de `docId != null ? "reindexed" : "indexed"`