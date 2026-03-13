# SearchOnField

`SearchOnField<T>` c'est la classe abstraite de base pour les critères de recherche sur un champ d'entité. Elle représente un filtre à appliqué sur unun champ d'une entité.

## Hiérarchie des classes

```
SearchOnField<T> (classe abstraite)
├── SearchOnString extends SearchOnField<String>
├── SearchOnNumeric<T> (classe abstraite)
│   ├── SearchOnInt
│   └── SearchOnFloat
└── SearchOnDateTime<T> (classe sealed)
    ├── SearchOnLocalDateTime
    ├── SearchOnUtcDateTime
    └── SearchOnDateOnly
```
Le type générique est celui du champ de l'entité.

## Égalité / Différence

Filtre sur l'égalité ou la différence par rapport à une valeur.

```dart
Search.equal(42)           // champ == 42
Search.different('admin')  // champ != 'admin'
```

## Valeur nulle

Filtre sur les valeurs nulles.

```dart
Search.isNull<String>()     // champ IS NULL
Search.isNotNull<int>()     // champ IS NOT NULL
```

## Appartenance à une liste

Filtre si le champ est dans ou hors d'une liste.

```dart
Search.inList(['Alice', 'Bob', 'Charlie'])   // champ IN (...)
Search.notInList([1, 2, 3, 4, 5])           // champ NOT IN (...)
```

## SearchOnString - Texte

Types de comparaison :
- `.equal` (défaut) - Égalité exacte
- `.prefix` - Commence par
- `.suffix` - Se termine par
- `.contains` - Contient
- `.words` - Recherche par mots

```dart
SearchOnString(text: 'admin', type: .equal)
SearchOnString(text: 'john', type: .prefix, caseSensitive: false)
SearchOnString(text: 'test', type: .contains)
SearchOnString(text: 'hello world', type: .words)
SearchOnString(text: 'café', type: .contains, collation: 'utf8_general_ci')
```

## SearchOnNumeric - Nombres

Types de comparaison :
- `.equal` (défaut)
- `.lessThan` - <
- `.lessOrEqualTo` - <=
- `.greaterThan` - >
- `.greaterOrEqualTo` - >=
- `.between` - entre deux valeurs

**SearchOnInt** :
```dart
SearchOnInt.value(42)
SearchOnInt(value: 100, type: .greaterThan)
SearchOnInt.between(10, 20)
```

**SearchOnFloat** (avec option `round` pour arrondir) :
```dart
SearchOnFloat(value: 3.14159, type: .equal, round: true)
SearchOnFloat.between(1.5, 2.5, round: true)
```

## SearchOnDateTime - Dates et heures

Supporte `DateOnly`, `LocalDateTime`, `UtcDateTime`.

Types de comparaison :
- `.equal` (défaut)
- `.before` - <
- `.beforeOrEqual` - <=
- `.after` - >
- `.afterOrEqual` - >=
- `.between` - entre deux dates

Option `ignoreTime` : comparer seulement les dates, ignorer l'heure.

```dart
SearchOnDateTime.equal<DateOnly>(DateOnly(2024, 12, 31), ignoreTime: true)
SearchOnDateTime.before<DateOnly>(DateOnly(2024, 12, 31), ignoreTime: true)
SearchOnDateTime.afterOrEqual<LocalDateTime>(LocalDateTime(2024, 1, 1, 0, 0))
SearchOnDateTime.between<UtcDateTime>(
  UtcDateTime(2024, 1, 1, 0, 0, 0),
  UtcDateTime(2024, 12, 31, 23, 59, 59)
)
SearchOnLocalDateTime(date: LocalDateTime(2024, 6, 15, 14, 30), type: .equal, ignoreTime: true)
```

Le paramètre générique (eg equal<DateOnly>) n'est pas nécessaire dans la plupart des cas en raison du contexte connu du compilateur.

## CompoundSearchOnField - Combinaisons de conditions

Combinaisons de critères créées avec `&`, `|`, `not()`.

```dart
// ET logique
Search.greaterThan(10) & Search.lessThan(100)
// > 10 AND < 100

// OU logique
Search.equal('premium') | Search.equal('vip')
// = 'premium' OR = 'vip'

// NON logique
(Search.equal('admin') | Search.equal('guest')).not()
// NOT (= 'admin' OR = 'vip')

// Expressions complexes
(Search.greaterThan(0) & Search.lessThan(100))
  | (Search.greaterThan(200) & Search.lessThan(300))
// (> 0 AND < 100) OR (> 200 AND < 300)
```

## Utilisation

Utilisés avec les opérations de recherche des entités pour filtrer les données.

```dart
// Recherche de produits
final results = await db.products.search(
  stockQuantity: SearchOnInt(value: 50, type: SearchOnNumericType.greaterThan)
  & SearchOnString(text: 'active', type: .equal)
);
```

## Comportement

- **`acceptValue(value)`** : Valide une valeur côté client (sans base de données), retourne `true` ou `false`.
- **`applyFilters(expression)`** : Génère un prédicat SQL pour la base, retourne `null` si le critère est vide.

## Notes importantes

- **Valeurs null** : Par défaut rejetées (sauf `SearchNull`).
- **Critères vides** : N'appliquent pas de filtre (`isEmpty == true`), acceptent toutes les valeurs.
- **Chaînes vides** : Considérées comme vides dans `SearchOnString`.
- **Option `round`** : Arrondit les nombres pour éviter les problèmes de précision.
- **Option `ignoreTime`** : Compare seulement la date pour `SearchOnDateTime`.
