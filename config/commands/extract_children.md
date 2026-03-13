description: Extraire les enfants d'un widget en variables locales
---

Refactoring Flutter : extraire les enfants inline de tout widget définissant une propriété `children` (ex : `Column`, `Row`, `Wrap`, `ListView`, `Stack`, etc.) en variables locales `final` définies avant le widget parent, pour améliorer la lisibilité du `children: [...]`.

## Identification du widget cible

- Utiliser la **sélection IDE** si l'utilisateur a sélectionné du code.
- Sinon, utiliser le **fichier + numéro de ligne** indiqué dans le prompt : $ARGUMENTS
- Si ni l'un ni l'autre n'est disponible, **demander** à l'utilisateur de sélectionner le widget ou d'indiquer le fichier et la ligne.

## Algorithme

1. **Lire le fichier** contenant le widget cible.
2. **Identifier** le widget cible et son paramètre `children: [...]`.
3. **Pour chaque enfant** dans `children` :
   - **Widget trivial** → **laisser inline** dans `children`. Un widget est trivial si :
     - Il tient sur une seule ligne (ex : `vSpace8`, `const Divider()`)
     - C'est déjà une simple référence à une variable existante
   - **Widget non-trivial** (multi-lignes) → **extraire** dans une variable locale `final` avec un nom sémantique.
4. **Récursivité** : si un enfant extrait est lui-même un widget avec `children` dont le corps dépasse **15 lignes de code**, appliquer le même traitement à ses propres `children`.
5. **Placer les variables** avant le `return` (ou avant le widget parent si pas de `return` direct), dans l'ordre où elles apparaissent dans `children`.
6. **Remplacer** les widgets inline par leurs noms de variables dans `children`.

## Nommage des variables

- Noms **sémantiques** déduits du type de widget et de son contenu/rôle.
- Exemples : `btnStop`, `deviceDropdown`, `modeSelector`, `slider`, `title`, `controls`.

## Exemple

Avant :
```dart
return Column(
  children: [
    Text("Titre", style: Theme.of(context).textTheme.titleSmall),
    vSpace8,
    IconButton(
      icon: const Icon(Icons.stop),
      onPressed: onStop,
      tooltip: "Stop",
    ),
  ],
);
```

Après :
```dart
final title = Text("Titre", style: Theme.of(context).textTheme.titleSmall);
final btnStop = IconButton(
  icon: const Icon(Icons.stop),
  onPressed: onStop,
  tooltip: "Stop",
);
return Column(
  children: [
    title,
    vSpace8,
    btnStop,
  ],
);
```

## Post-traitement

- Lancer `dart format` sur le fichier modifié.
- Lancer `dart analyze` sur le fichier modifié.
- Signaler les éventuelles erreurs.
