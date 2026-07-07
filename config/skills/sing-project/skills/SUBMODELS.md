# Sing Sub-models

## 1. Concept

A sub-model is an existing `DataRegistry` (e.g. `Socle`) reused inside a host application (e.g. `Builder`). The generated class `Builder$Registry` extends `Socle$RegistryBase` and merges both models.

## 2. PathInfo architecture in a multi-sub-model app

### 2.1. What is generated

`Builder$Registry` builds its `pathInfo` tree by **flattening** the sub-model items directly under the app root:

```dart
// In builder_sing_client/lib/src/client.dart (generated)
@override
sing.PathInfo get pathInfo => _pathInfo ??= sing.PathInfo(
  Builder.pathInfos.name,        // "builder" — app root
  ...
  items: Builder.pathInfos.items.followedBy(
    _p3.Socle$RegistryBase.subModelPathInfoItems,  // Socle items, flattened
    // → Security, System, etc. are direct children of "builder"
    // → The "socle" node does NOT exist in the pathInfo tree
  ),
);
```

`subModelPathInfoItems = Socle.pathInfos.items` — the children of Socle, **not Socle itself**.

The sub-model root node (`Socle`) is registered separately:

```dart
registerSubModelRoot(_p3.Socle$RegistryBase.subModelPathInfo);
```

### 2.2. The two hierarchies

| Hierarchy | Used by | Resulting path |
|---|---|---|
| Namespaces (`NameSpace.parent`) | `entity.fullName` | `/socle/security/sessions` |
| PathInfo (`pathInfo.items`) | `DataRegistry.findObject(path)` | `builder/security/sessions` |

These two hierarchies **diverge** in sub-model apps: `entity.fullName` walks up to the namespace root (`Socle.parent = null`), producing `/socle/...`, while the pathInfo tree has `"builder"` as root with Socle's items flattened beneath it.

## 3. Impact on `Expect` and `.resolve()`

`Expect.toJson()` emits:
```json
{ "entityDef": "/socle/security/sessions", "resolutions": [...], ... }
```

On the server, `Expect.fromJson()` calls:
```dart
dataRegistry.findObject<EntityDef>("/socle/security/sessions")
// → pathSegments = ["socle", "security", "sessions"]
// → "socle" ≠ root "builder" → BEFORE FIX: null → resolutions ignored
```

**Symptom**: `.resolve((fields) => [fields.user, ...])` does not transmit resolutions to the server. `session.user.dataRowValues` crashes (User not loaded).

## 4. Fix applied in `DataRegistry` (sing_core)

`registerSubModelRoot` now also populates `_subModelRoots` in addition to `_constructors`. `findPathInfos` first attempts the direct search from the main root, then falls back to each registered root:

```dart
// data_registry.dart
final _subModelRoots = <PathInfo>{};

void registerSubModelRoot(PathInfo subModelRoot) {
  if (subModelRoot.nameSpaceBuilder != null) {
    _constructors[subModelRoot.type] = subModelRoot.nameSpaceBuilder!;
  }
  _subModelRoots.add(subModelRoot);  // new
}

@protected
PathInfo? findPathInfos(Iterable<String> pathSegments) {
  // ... searchIn() unchanged ...
  final direct = searchIn(pathSegments, info);
  if (direct != null) return direct;
  // Fallback: try each registered submodel root
  for (final subRoot in _subModelRoots) {
    final result = searchIn(pathSegments.toList(growable: false), subRoot);
    if (result != null) return result;
  }
  return null;
}
```

### Automatic recursion

If `Socle` itself embeds a sub-model `Plugin`, the `Socle$RegistryBase` constructor calls `registerSubModelRoot(Plugin.pathInfos)` on `this` (= the `Builder$Registry` instance). All sub-model levels end up in `_subModelRoots` of the app registry with no additional code.

## 5. Unchanged behavior

`findObject("builder/security/sessions")` — used in `$callService` via:
```dart
final rootName = $dataRegistry.pathInfo?.name;  // "builder"
final onEntity = $dataRegistry.findObject<EntityDef>("$rootName$servicesPath");
// → "builder/security/sessions" → direct hit in the flattened tree → OK
```

This path bypasses the fallback (found on first attempt) — no regression.

## 6. Quick diagnosis

If `.resolve()` does not work on sub-model entities:

1. Check `entity.fullName` for the entity in question (e.g. `HttpSession`)
2. Check `dataRegistry.pathInfo?.name` (app root)
3. If the first segment of `fullName` ≠ root, the hierarchy divergence bug is the cause
4. Ensure the `sing_core` version includes the `_subModelRoots` fix

## 7. Inherited entities missing from `allEntities()` (sing_builder fix)

### Symptom

When a child model overrides a sub-model namespace (e.g. `PatientActivitiesNmclsNameSpace extends NmclsNameSpace`), the generated `ChildNmcls.entities` getter only lists the entities declared in the child class. The parent namespace's entities (e.g. `AppMessagesContext`, `AppMessagesLocale`, `PrintingSourceType` from socle's `NmclsNameSpace`) are absent.

`allEntities()` / `entitiesOf<Nmcl>()` therefore misses them — the migration finds only N entities instead of N+M.

### Root cause

In `ObjectGenerator.canGenerate`:

```dart
bool canGenerate(GenerateFor generateFor) =>
    subModel == null && super.canGenerate(generateFor);
```

Entities inherited from a sub-model have `subModel != null`, so `canGenerate` returns `false`. The `entities` getter is built from `subGenerators(builder)` which calls `g.canGenerate(builder.generateFor)` and therefore excludes these inherited entities.

The namespace generators are handled correctly by `_inheritedSubNameSpaces` which deliberately calls `subGenerators()` **without** a builder argument (bypassing `canGenerate`) and then filters `g.subModel != null`. There was no equivalent for entity generators.

### Fix in `sing_builder` (`name_space.dart`)

Add `_inheritedEntities` (symmetric with `_inheritedSubNameSpaces`) and include it in the `entities` getter:

```dart
// In NameSpaceGenerator.getLibrary — entities getter body
..body = CodeBuilder(
  [
    "[",
    [
      ..._inheritedEntities(builder),           // new: inherited from sub-model
      ...subGenerators(builder)
          .whereType<EntityGenerator>()
          .where((e) => !e.propName.startsWith("_") && !e.isMixin),
    ]
        .map((e) => "dataRegistry.entities<${e.className}>(),")
        .join(),
    "]",
  ],
).code,

// New method at the end of NameSpaceGenerator
Iterable<EntityGenerator> _inheritedEntities(
  ExpressionBuilderContext builder,
) =>
    subGenerators()                     // no builder → includes subModel generators
        .whereType<EntityGenerator>()
        .where((g) => g.subModel != null)
        .where((g) => !g.propName.startsWith("_"))
        .where((g) => !g.isMixin)
        .where((g) => builder.generateForServer || !_onServerSide(g));
```

After the fix, `PatientsActivitiesNmcls.entities` produces the parent entities first, then the child's own entities:

```dart
Iterable<sing.EntityDef> get entities => [
  dataRegistry.entities<AppMessagesContext>(),   // from NmclsNameSpace (socle)
  dataRegistry.entities<AppMessagesLocale>(),
  dataRegistry.entities<PrintingSourceType>(),
  dataRegistry.entities<Bed>(),                  // from PatientsActivitiesNmclsNameSpace
  // ... 9 more
];
```

### Windows rename fallback (`generate_model.dart`)

On Windows, the atomic directory rename used to save generated files can fail with `PathAccessException` when an IDE (e.g. VS Code Dart language server) holds files in `lib/src/sing` open. Added a recursive copy+delete fallback:

```dart
Future _renameDir(String oldPath, String newPath) async {
  ...
  try {
    await d.rename(newPath);
  } on PathAccessException {
    await _copyDir(oldPath, newPath);
    await _deleteDir(oldPath);
  }
}
```
