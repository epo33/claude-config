description: Enuméré jsonifiable
---

Ajouter les méthodes `fromJson` et `toJson` à un énuméré Dart.

L'enum cible est : $ARGUMENTS

Si `$ARGUMENTS` est vide, demander à l'utilisateur quel enum modifier (chemin du fichier ou nom de l'enum).

## Étapes

1. **Identifier l'enum** : localiser le fichier et la déclaration de l'enum à partir de l'argument fourni (chemin de fichier, ou nom d'enum à rechercher dans le projet).

2. **Dépendance `collection`** : vérifier dans le `pubspec.yaml` du projet si `collection` est déjà listé dans `dependencies`. Si absent, ajouter :
   ```yaml
   collection: any
   ```
   puis exécuter `dart pub get`.

3. **Import** : dans le fichier contenant l'enum, vérifier si `import 'package:collection/collection.dart';` est déjà présent. Si absent, l'ajouter.

4. **Méthodes JSON** : ajouter dans le corps de l'enum :
   ```dart
   static [ENUM]? fromJson(dynamic value) => values.firstWhereOrNull((e) => e.name == value);
   toJson() => name;
   ```
   où `[ENUM]` est le nom exact de l'enum.

Appliquer les consignes d'ordonnancement des déclarations dans les classes pour déterminer la position d'insertion de chaque méthode.

5. **Vérification** : exécuter `dart analyze` sur le fichier modifié et corriger les éventuelles erreurs.
