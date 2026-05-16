# Règles spécifiques Dart

Appliquer en plus des règles génériques du `SKILL.md` parent quand le fichier audité a l'extension `.dart`.

Certaines règles sont **auto-correctibles textuellement** (le skill applique). D'autres sont **architecturales** (renommage, découpage) : le skill ne corrige pas, il **signale** dans la remontée au LLM (cf. `SKILL.md`, section « Sortie »).

## Conventions de nommage (signaler)

Les identifiants Dart suivent :
- Types, enums, typedefs, extensions : `UpperCamelCase`.
- Packages, fichiers, répertoires : `lowercase_with_underscores`.
- Préfixes d'import : `lowercase_with_underscores`.
- Variables, fonctions, paramètres : `lowerCamelCase`.
- Constantes : `lowerCamelCase` (pas `SCREAMING_CAPS`).

Si un identifiant ne respecte pas sa convention, **signaler** sans renommer (un renommage automatique casserait les usages).

## Ordonnancement des membres de classe

Ordre attendu, de haut en bas :

1. Constantes statiques (`static const`).
2. Variables statiques (`static final`, `static var`).
3. Méthodes statiques (`static`).
4. Constructeurs, dans cet ordre :
   - constructeurs privés (`_`),
   - constructeur par défaut,
   - constructeurs nommés,
   - constructeurs factory.
5. Variables d'instance publiques (`var`, `final`, getters/setters).
6. Méthodes publiques.
7. Méthodes privées (commençant par `_`).
8. Variables d'instance privées (commençant par `_`).

Si l'ordre est incorrect, réordonner. Cas typique à corriger : champs privés groupés avec leur constructeur juste après, au lieu d'être en fin de classe.

## Bornes génériques redondantes

Pour `class C<T extends B>` : ne pas répéter `B` à l'usage. Écrire `C` plutôt que `C<B>`.

Multi-paramètres : omettre le paramètre est impossible si un autre paramètre doit être précisé. Dans ce cas, écrire le bound explicitement pour les paramètres concernés.

Exemples :
- `class Field<T extends Object>` → `Field`, jamais `Field<Object>`.
- `class Pair<K extends Object, V extends Object>`, usage avec K=String, V=int → `Pair<String, int>`.
- `class Map<K extends Object, V>`, usage avec K=Object, V=String → `Map<Object, String>` (K ne peut pas être omis seul).

## Fonctions fléchées

Méthode ou fonction dont le corps est exactement `{ return expr; }` → `=> expr`.

Exemple :
```dart
// Avant
int add(int a, int b) {
  return a + b;
}
// Après
int add(int a, int b) => a + b;
```

Ne pas appliquer si le corps contient plus d'une instruction, ou si la lisibilité en souffre (expression très longue).

## Acronymes

- Acronymes de plus de 2 lettres : capitaliser comme un mot normal. `HttpRequest`, pas `HTTPRequest`. `XmlParser`, pas `XMLParser`.
- Acronymes de exactement 2 lettres : conserver la capitalisation anglaise. `ID`, `UI`, `TV`, `OS`.

## Classe privée — membres

Une classe dont le nom commence par `_` (privée au fichier) ne doit pas redéclarer ses membres en privé.

```dart
// Incorrect
class _Foo {
  final int _x;
  _Foo(this._x);
  int _doSomething() => _x;
}

// Correct
class _Foo {
  final int x;
  _Foo(this.x);
  int doSomething() => x;
}
```

Cas particulier : classes d'état Flutter (`extends State`) attachées à un `StatefulWidget` privé ou public, conventionnellement traitées comme privées dans l'API du widget.

## Records Dart

Les records Dart ne doivent comprendre que des champs nommés.

```dart
// Incorrect
({int, String}) tuple = (42, "hello");

// Correct
({int count, String label}) tuple = (count: 42, label: "hello");
```

## Énumérations — syntaxe abrégée

Préférer la syntaxe abrégée pour accéder aux valeurs d'une énumération quand le type est inféré.

```dart
enum Status { active, inactive, pending }

// Préférer
final Status test = .active;

// À .active si le type est ambigu, conserver
final test = Status.active;
```

## Imports — ordre

Sections séparées par une ligne vide, dans cet ordre :
1. `dart:` imports.
2. `package:` imports.
3. Imports relatifs.
4. Exports (section séparée à la fin).

Chaque section triée alphabétiquement.

## Largeur de ligne

Maximum 80 caractères par ligne. Le formateur `dart format` s'en charge, mais signaler si des lignes débordent après transformation textuelle du skill.

## Documentation Dart

Application stricte de la règle générique « pas de docstring inutile ». Cas typiques à supprimer dans une classe DTO :

```dart
// À supprimer
class User {
  /// Prénom de l'utilisateur
  String firstName;
  /// Nom de l'utilisateur
  String lastName;
  /// Crée un utilisateur à partir d'un JSON
  User.fromJson(Map<String, dynamic> json) : ...;
  /// Convertit l'utilisateur en JSON
  Map<String, dynamic> toJson() => ...;
}
```

Toutes ces docstrings paraphrasent le nom et n'apportent rien.

## Widgets Flutter (signaler, ne pas corriger)

Ces règles guident l'architecture et ne sont pas auto-correctibles. Le skill **signale** dans la remontée au LLM les violations détectées.

- Préférer les widgets `StatelessWidget` chaque fois que possible. Signaler un `StatefulWidget` sans `setState`, animations, controllers ou cycle de vie nécessaire.
- Découper les gros widgets en sous-widgets. Signaler une méthode `build` de plus de ~40 lignes ou une arborescence avec plus de ~6 niveaux d'imbrication.
- Éviter de définir plusieurs widgets dans un même fichier. Signaler les fichiers contenant plus d'une classe widget publique.
- Sous-widgets dédiés à un widget principal : les définir comme classes privées dans un fichier nommé d'après le widget principal avec un suffixe (ex. pour `my_widget.dart`, créer `my_widget.header.dart`, `my_widget.footer.dart`). Si les sous-widgets n'ont pas vocation à être réutilisés ailleurs, les déclarer avec `part of 'my_widget.dart';`. Signaler une déviation de cette organisation.
- Si le package `styled_widget` est utilisé (présence dans `pubspec.yaml`), préférer la syntaxe de composition à la syntaxe de construction. Exemple : `Text("Hello").padding(all: 8)` plutôt que `Padding(padding: EdgeInsets.all(8), child: Text("Hello"))`. Compositions fréquentes : `padding`, `margin`, `backgroundColor`, `borderRadius`, `alignment`, `center()`, `expanded()`. Signaler les usages de la syntaxe de construction quand `styled_widget` est disponible.
- Liste `children` longue (plus de ~20 LoC) dans un `Row`, `Column`, etc. : signaler l'absence de variables locales pour les widgets enfants. Exemple attendu :

```dart
Widget build(BuildContext context) {
  final deviceDropdown = DropdownButton(...);
  final btnPlayPause = IconButton(...);
  final btnStop = IconButton(...);
  return Column(
    children: [deviceDropdown, btnPlayPause, btnStop],
  );
}
```
