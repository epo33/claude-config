# Sing Sub-models

A sub-model is a Sing model, in its own packages, that another model mounts. The host application then serves the entities, services, enums and tuples of all mounted models through one registry, and migrates them into one database.

The examples come from the coverage project:

- `coverage/coverage_base`: model `CoverageBase`, a base sub-model;
- `coverage/coverage_side`: model `CoverageSide`, a sub-model that mounts `CoverageBase` and grafts an entity into it;
- `coverage/coverage_model`: model `Coverage`, the host, which mounts both (a diamond).

## 1. Declaring a sub-model

### 1.1. The sub-model

```dart
// coverage/coverage_base/lib/model/model.dart
Model createCoverageBaseModel() => Model(
  modelName: "CoverageBase",
  packageName: "coverage_base",
  isSubModel: true,
  rootNameSpace: CoverageBaseNameSpace(),
  clientPackagePath: "../coverage_base_client",
  commonPackagePath: "../coverage_base_common",
);

@AccessToken.authentified
class CoverageBaseNameSpace extends ModelNameSpace {
  CoverageBaseNameSpace();

  TopicsNameSpace get topics => TopicsNameSpace();
}
```

- A sub-model has the same three packages as any model: model, common, client.
- `packageName` is needed when the package name is not `modelName.toLowerCase()`.
- `isSubModel: true` only makes `sing_builder:init` write `lib/model.dart`. No generator reads it.
- `lib/model.dart` of the sub-model exports what a host needs to declare its own model:

```dart
// coverage/coverage_base/lib/model.dart
export "package:sing_model/sing_model.dart";
export "package:sing_server/sing_server.dart";
export "package:coverage_base_common/coverage_base_common.dart";
export "model/model.dart";
```

- A namespace that the host may override is declared as a **getter** (`TopicsNameSpace get topics => ...`), so that a subclass can override it (see § 1.2).

### 1.2. The host

```dart
// coverage/coverage_model/lib/model/model.dart
Model createCoverageModel() => Model(
  modelName: "Coverage",
  subModels: [createCoverageBaseModel(), createCoverageSideModel()],
  rootNameSpace: CoverageNameSpace(),
  clientPackagePath: "../coverage_client",
  commonPackagePath: "../coverage_common",
);

@AccessToken.authentified
class CoverageNameSpace extends CoverageBaseNameSpace {
  CoverageNameSpace();

  @override
  TopicsNameSpace get topics => CoverageTopicsNameSpace();

  final notes = NotesNameSpace();
  // ...
}

class CoverageTopicsNameSpace extends TopicsNameSpace {
  CoverageTopicsNameSpace();
}
```

- `subModels:` is a plain list of calls to the functions that build the sub-models: `[createCoverageBaseModel()]`. `sing_emit` reads it from the source code and refuses any other form.
- The host root namespace **extends** the root namespace of its main sub-model. It inherits its namespaces and entities, and can override a namespace with a subclass (`CoverageTopicsNameSpace`) to add entities to it.
- An entity of the host references an entity of a sub-model like any other entity: `ReferenceTo<TopicEntity>()` (`coverage_model/lib/model/notes/tagged_note.dart`).
- The host `lib/model.dart` re-exports the sub-models with `hide $Identifiers`: each common package generates its own `$Identifiers` class, and the names would clash.

```dart
// coverage/coverage_model/lib/model.dart
export "package:sing_model/sing_model.dart";
export "package:sing_server/sing_server.dart";
export "package:coverage_common/coverage_common.dart";
export "package:coverage_base/model.dart" hide $Identifiers;
export "package:coverage_side/model.dart" hide $Identifiers;
export "model/model.dart";
// ...
```

### 1.3. Package dependencies

| Host package | Depends on |
|---|---|
| model (`coverage_model`) | the model, common and client packages of every sub-model (the generated server and client code imports them) |
| common (`coverage_common`) | the common package of a sub-model whose types it uses |
| client (`coverage_client`) | the client and common packages of every sub-model |

A sub-model that mounts another one (`coverage_side` mounts `coverage_base`) depends on its packages the same way.

### 1.4. Code generation

Run `dart run sing_builder:sing_emit` from the **host** model package. It reads the whole chain of models and regenerates **every layer**: the generated code of the sub-model packages is rewritten too. Nothing is written if one layer has an error.

- Each layer keeps its own `uuid`. `sing_emit` reads it back from the previous generation (`lib/sing/server.dart`), or derives a UUID v5 from the package name (`"sing:<packageName>"`).
- `--uuid` and `--compiled-at` apply to the top layer only.

## 2. Generated code

Each model `Xxx` generates:

| Symbol | File | Role |
|---|---|---|
| `Xxx$Layer` | server `lib/sing/server.dart` (`extends ServerModelLayer`), client `lib/src/client.dart` (`extends ModelLayer`) | What the model brings to a registry: `name`, `uuid`, `version`, `compiledAt`, `pathInfo`, `grafts`, `enumDefs`, `tupleDefs`, `jsonAdapters`, `registerTokens()`, plus `majorVersions` on the server |
| `XxxRegistry<E extends EntityDef>` | common `lib/src/sing/registry.dart` | Model interface, `implements sing.DataRegistry<E>` |
| `XxxServerRegistry` | `lib/sing/server.dart` | `abstract interface class` implementing `ServerDataRegistry`, `XxxRegistry<ServerEntityDef>` and the `...ServerRegistry` interface of each direct sub-model. Holds the factory and `static const modelLayers` |
| `XxxClientRegistry` | client `lib/src/client.dart` | The same on the client side (`ClientDataRegistry`, `XxxRegistry<ClientEntityDef>`, sub-model `...ClientRegistry` interfaces) |
| `_Xxx$Registry` | same files | Private implementation, `extends ServerDataRegistryBase` (or `ClientDataRegistryBase`), built with `layers: XxxServerRegistry.modelLayers` |

```dart
// coverage/coverage_model/lib/sing/server.dart (generated)
abstract interface class CoverageServerRegistry
    implements
        sing.ServerDataRegistry,
        CoverageRegistry<sing.ServerEntityDef>,
        coverageBase.CoverageBaseServerRegistry,
        coverageSide.CoverageSideServerRegistry {
  factory CoverageServerRegistry({
    required sing.ServerDataControler dataControler,
    sing.DebugPrinter? debugger,
    bool debugMode,
  }) = _Coverage$Registry;

  static const modelLayers = <sing.ServerModelLayer>[
    ...coverageBase.CoverageBaseServerRegistry.modelLayers,
    ...coverageSide.CoverageSideServerRegistry.modelLayers,
    Coverage$Layer(),
  ];
}
```

- `modelLayers` spreads the `modelLayers` of each direct sub-model, then adds the model's own layer. It goes from the lowest layer to the model's own. In a diamond the list holds a layer twice (`CoverageBase$Layer` here): the registry keeps it once (§ 3).
- A `CoverageServerRegistry` is usable wherever a `CoverageBaseServerRegistry` or a `CoverageBaseRegistry` is expected. Code written for a sub-model works on the host registry.
- The import prefix of a sub-model is its model name with a lower-case first letter (`coverageBase`).
- The client side is built the same way: `CoverageClientRegistry.modelLayers` spreads the sub-model client layers. The access chains `Xxx$Ent` / `Xxx$Svc` type their `$dataRegistry` on `XxxClientRegistry`.

## 3. Layer stacking in the registry

`DataRegistryBase(layers:)` (`sing_core/lib/src/data_registry.dart`) receives the layers and:

- keeps the **first** occurrence of a layer listed twice (same `uuid` and same `name`), which is the lowest one. Two layers with the same `uuid` but different names, or the same `name` but different `uuid`s, throw a `StateError`;
- takes `uuid`, `version` and `compiledAt` from the **last** layer (the model's own). `versionChain` joins the `version` of every layer with `-`. `layers` is the list without duplicates;
- builds `pathInfo` from the last layer's root: its own items **first**, then the items of every lower layer, all flattened under the host root, then places the grafts (§ 5);
- registers the root `PathInfo` of each lower layer as a sub-model root (used by path lookup, § 4.1);
- merges `enumDefs`, registers the `jsonAdapters` and `tupleDefs` of all layers (two tuples with the same key, or a tuple key equal to an entity path, throw a `StateError`), then calls `registerTokens()` on each layer, lowest first.

`ServerDataRegistryBase` adds the versions: `layerVersions` (one entry per layer, numbered on its own) and `layerVersionChain` (`"CoverageBase=0.0.0;CoverageSide=0.0.0;Coverage=0.0.0"`). See [migrations](MIGRATIONS.md#25-versions-in-the-registry).

## 4. Paths and namespaces

Two hierarchies coexist:

| Hierarchy | Used by | Path of `Topic` |
|---|---|---|
| Namespaces (`NameSpace.parent`) | `entity.fullName` (i18n key of the model documentation only) | `/coveragebase/topics/topics` |
| PathInfo (`pathInfo.items`) | `DataRegistry.findObject(path)`, `tupleDefByKey`, `Xxx.tupleKey` | `coverage/topics/topics`, `topics/topics` |

`entity.fullName` walks up the namespaces to the sub-model root (`CoverageBase.parent == null`). The pathInfo tree has the host root, with the sub-model items flattened under it. The sub-model root is **not** a node of the pathInfo tree.

### 4.1. Path resolution

`DataRegistryBase.findPathInfos(segments)` tries, in order:

1. from the host root (`coverage/topics/topics`);
2. from each registered sub-model root (`coveragebase/topics/topics`, the `fullName` form);
3. root-less paths (`topics/topics`, the `tupleKey` form): the first segment is matched against the children of the host root, then against the children of each sub-model root.

The first match wins. Because the host items come first, a host namespace that overrides a sub-model namespace (`CoverageTopics` over `Topics`) is found first: `findObject<NameSpace>("topics")` returns the `CoverageTopics` instance.

### 4.2. Inherited entities in a namespace

The generated namespace class of the host lists the inherited namespaces and entities. `Coverage.subNameSpaces` includes `dataRegistry.nameSpaces<Topics>()` although `Topics` is declared by `CoverageBase`. A namespace that overrides a sub-model namespace lists the parent entities before its own in `entities`. Walking the namespaces of the registry (`visitModel`, `rootNameSpace`) therefore reaches the whole stack.

## 5. Several sub-models, diamonds and grafts

### 5.1. Diamond

A model can mount several sub-models side by side. `Coverage` mounts `[createCoverageBaseModel(), createCoverageSideModel()]`, and `CoverageSide` mounts `CoverageBase` too. The builder and the registry keep each model once, at its lowest position: the layers are `[CoverageBase, CoverageSide, Coverage]`.

- List the shared base first in `subModels`.
- Every layer needs its own `uuid` (§ 1.4). Two layers sharing a uuid would make one of them disappear.
- The host root namespace extends the root of one sub-model only (here `CoverageBaseNameSpace`). The direct children of the root of another mounted model (`sideNotes` of `CoverageSideNameSpace`) are mounted under the host root automatically: `sideNotes/sideNotes` and `coverage/sideNotes/sideNotes` both resolve. No getter to write.

### 5.2. Grafts

A graft adds an entity or a namespace to a namespace of a **mounted** model, without subclassing it. It is declared on a property of the **root namespace** of the model that brings it, with `@GraftedInto(TargetNameSpace)` (from `sing_model`):

```dart
// coverage/coverage_side/lib/model/model.dart
@AccessToken.authentified
class CoverageSideNameSpace extends ModelNameSpace {
  CoverageSideNameSpace();

  @GraftedInto(TopicsNameSpace)
  final topicTags = TopicTagEntity();

  final sideNotes = SideNotesNameSpace();
}
```

- The grafted item takes the path, schema (`@DbName` of the target chain) and token context of the target: path and `tupleKey` `topics/topicTags`, tokens `/topics/topicTags/read` and `/topics/topicTags/write`.
- The layer publishes it in `grafts`: `PathGraft("topics", $TopicTag.pathInfos)`. The registry places it under its target in `pathInfo`. `visitModel` and `getDbTables` see it once. `modelDefinition()` lists it under the target.
- The target namespace class lists it at run time: `Topics.entities` (and `subNameSpaces` for a grafted namespace) include it through `dataRegistry.graftedEntitiesOf(this)` / `graftedNameSpacesOf(this)`.
- Typed getters depend on who generates the class. `Topics$View`, generated by `CoverageBase`, has no `topicTags` getter. `CoverageTopics$View`, generated by the host, has one. The client access chains of the target (`CoverageTopics$Ent`) have none. Reach a grafted entity with `$TopicTag.of(registry)`, `$TopicTag.ofContext(callContext)`, by path, or through the access chain of the model that declares it (`CoverageSide$Ent(registry).topicTags`).

`sing_emit` refuses:

- a graft on a property of a namespace that is not a model root;
- a target that is not a namespace of a model mounted by the declaring model;
- a name that the target already holds;
- a grafted property that is neither an entity nor a namespace.

Examples: `coverage/coverage_side`, and the builder fixtures `sing_builder/test/analyser/fixtures/diamond_*` and `graft_collision` (`sing_builder/test/analyser/diamond_test.dart`).

## 6. Entity inheritance across models

An ancestor entity declared in a sub-model can have descendants declared in the host (see [entity inheritance](DATA_MODEL.md#7-polymorphic-entities-ancestor-and-descendants)). The usual form: the sub-model declares the ancestor and an abstract class that names it, the host extends that class.

```dart
// in the sub-model
abstract class TopicDescendant extends ModelDescendantEntity<String> {
  TopicDescendant({required String kind, super.shareStorage})
    : super(ancestorEntity: TopicEntity(), selectorValue: kind);
}

// in the host
@StdEntityServices()
class FaqTopicEntity extends TopicDescendant {
  FaqTopicEntity() : super(kind: "faq", shareStorage: true);
  final question = StringField(maxLength: 500);
}
```

`TopicEntity` must then extend `ModelAncestorEntity<String>` and declare its `selectorField`. The builder walks the constructors of the descendant's superclasses until one passes `ancestorEntity:` to `super`. A descendant with `shareStorage: true` adds its columns to the ancestor's table, which belongs to the sub-model: they are created by the host migration.

## 7. Migrations

The host migration creates and updates the tables of **every** layer: there is no separate migration per sub-model. Each layer has its own `majorVersions`, numbered on its own and compared to its own entry in the stored `layerVersionChain`. The `BeforeMigrationStep`s of all layers run first (lowest layer first), then the DDL, then the `AfterMigrationStep`s. See [migrations](MIGRATIONS.md).

Pitfall: a sub-model step written in raw SQL runs on every host. It must not assume tables or columns that only one host adds.

## 8. Test bench

- `coverage/coverage_model/test/layer_stack_test.dart`: one sub-model against a real database. Registry construction (`CoverageServerRegistry(dataControler: PgDataControler(...))`), `migrateDatabase`, the three path forms of `findObject`, `tupleDefByKey(TopicCount.tupleKey)`, sub-model namespaces, enum tables, `layerVersions`.
- `coverage/coverage_model/test/diamond_stack_test.dart`: the diamond and the graft. Layer order, graft paths, entities of the target namespace, second migration without DDL order, references across layers.

## 9. Quick diagnosis

If an entity or a service of a sub-model is not found:

1. Check that the sub-model layer is in `dataRegistry.layers` (and in `XxxServerRegistry.modelLayers`). If not, run `sing_emit` again from the host package.
2. Check `dataRegistry.pathInfo?.items`: the host items first, then the sub-model items.
3. Resolve the entity with `dataRegistry.tupleDefByKey(Entity.tupleKey)`: the root-less form is resolved by the third lookup step (§ 4.1).
4. `StateError` at registry construction: two layers share a `name` or a `uuid` (§ 3).
5. A grafted entity missing from a `$View` or from an access chain can be expected (§ 5.2).
