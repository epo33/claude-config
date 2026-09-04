# Sing Sub-models

## 1. Concept

A sub-model is a Sing model package (e.g. `coverage/coverage_base`, model `CoverageBase`) mounted inside a host model (e.g. `coverage/coverage_model`, model `Coverage`). The host application then exposes the entities, services, enums and tuples of both models through a single registry.

### 1.1. Declaration in the host model

```dart
// coverage/coverage_base/lib/model/model.dart
Model createCoverageBaseModel() => Model(
  modelName: "CoverageBase",
  packageName: "coverage_base",
  isSubModel: true,
  rootNameSpace: CoverageBaseNameSpace(),
  commonPackagePath: "../coverage_base_common",
  // ...
);

// coverage/coverage_model/lib/model/model.dart
Model createCoverageModel() => Model(
  modelName: "Coverage",
  subModels: [createCoverageBaseModel()],
  rootNameSpace: CoverageNameSpace(),
  commonPackagePath: "../coverage_common",
  // ...
);

class CoverageNameSpace extends CoverageBaseNameSpace { ... }
```

- `Model.subModels` lists the mounted models.
- The host root namespace **extends** the sub-model root namespace, so the host inherits the sub-model namespaces and entities.
- The host model package depends on the sub-model model package (`coverage_model` on `coverage_base`) and the host common package depends on the sub-model model package too (`coverage_common` imports `package:coverage_base/model.dart`).
- An entity of the host can reference an entity of the sub-model (`ReferenceTo<TopicEntity>()` in `coverage_model/lib/model/notes/tagged_note.dart`).
- The sub-model's `lib/model.dart` exports its model definitions; its generated `server.dart` re-exports `../model/model.dart` (effect of `isSubModel: true`), so importing the host's `server.dart` gives access to the sub-model definitions.
- Entity inheritance is limited to two levels (checked by `sing_builder`).

### 1.2. Generated registries

Each model `Xxx` yields:

| Generated symbol | File | Role |
|---|---|---|
| `Xxx$Layer` (`const`) | `server.dart` (`ServerModelLayer`), client `client.dart` (`ModelLayer`) | What the model brings to a registry: `name`, `uuid`, `version`, `compiledAt`, `pathInfo`, `enumDefs`, `tupleDefs`, `jsonAdapters`, `registerTokens()`, plus `majorVersions` on the server |
| `XxxRegistry<E extends EntityDef>` | common `src/sing/registry.dart` | Model interface, implementing `DataRegistry<E>` and the interfaces of the sub-models (`CoverageRegistry<E> implements sing.DataRegistry<E>, base.CoverageBaseRegistry<E>`) |
| `XxxServerRegistry` | `server.dart` | `abstract interface class` implementing `ServerDataRegistry`, `XxxRegistry<ServerEntityDef>` and the server interfaces of the sub-models (`CoverageServerRegistry implements ..., CoverageBaseServerRegistry`). Carries the factory and `static const modelLayers` |
| `XxxClientRegistry` | client `client.dart` | Same on the client side (`ClientDataRegistry`, `XxxRegistry<ClientEntityDef>`) |
| `_Xxx$Registry` | `server.dart` / `client.dart` | Private implementation, `extends ServerDataRegistryBase` (or `ClientDataRegistryBase`), built with `layers: XxxServerRegistry.modelLayers` |

```dart
// coverage/coverage_model/lib/sing/server.dart (generated)
abstract interface class CoverageServerRegistry
    implements
        sing.ServerDataRegistry,
        common.CoverageRegistry<sing.ServerEntityDef>,
        _p1.CoverageBaseServerRegistry {
  factory CoverageServerRegistry({
    required sing.ServerDataControler dataControler,
    sing.DebugPrinter? debugger,
    bool debugMode,
  }) = _Coverage$Registry;

  static const modelLayers = <sing.ServerModelLayer>[
    ..._p1.CoverageBaseServerRegistry.modelLayers,
    Coverage$Layer(),
  ];
}
```

`modelLayers` spreads the `modelLayers` of the direct sub-models, then the model's own layer: the list goes from the lowest layer to the model's own. A `CoverageServerRegistry` is usable wherever a `CoverageBaseServerRegistry` is expected.

## 2. Layer stacking in `DataRegistryBase`

`DataRegistryBase(layers:)` (sing_core) receives the layers and:

- keeps the first occurrence of a layer stacked twice (same `uuid`, e.g. two sub-models mounting the same base) and refuses two distinct layers with the same `name`;
- takes identity (`uuid`, `version`, `compiledAt`) from the **last** layer (the model's own); `versionChain` joins the `version` of every layer with `-`; `layers` is the deduplicated list;
- builds `pathInfo` from the last layer's `pathInfo`, with `items` = the model's own items **followed by** the items of every lower layer (**flattened** under the host root);
- registers each lower layer's root `PathInfo` as a sub-model root (used by the path lookup fallbacks below, and so that `nameSpaces` can build the sub-model root namespace type);
- merges `enumDefs`, registers the `jsonAdapters` and `tupleDefs` of all layers (a duplicated tuple key, or a tuple key equal to an entity path, throws a `StateError`), then calls `registerTokens()` on each layer.

`ServerDataRegistryBase` also computes `modelVersions` (the `majorVersions` of all server layers, numbered as one chain) and `layerVersions` (each layer numbered independently), see [MIGRATIONS.md](MIGRATIONS.md).

## 3. The two hierarchies

| Hierarchy | Used by | Resulting path |
|---|---|---|
| Namespaces (`NameSpace.parent`) | `entity.fullName` (i18n key of model documentation only) | `/coveragebase/topics/topics` |
| PathInfo (`pathInfo.items`) | `DataRegistry.findObject(path)`, `tupleDefByKey`, `Xxx.tupleKey` | `coverage/topics/topics`, `topics/topics` |

`entity.fullName` walks up the namespace chain to the sub-model root (`CoverageBase.parent == null`), while the pathInfo tree has the host root with the sub-model items flattened beneath it. The sub-model root is **not** a node of the pathInfo tree.

### 3.1. Path resolution (`findPathInfos`)

`DataRegistryBase.findPathInfos(segments)` tries, in order:

1. the direct search from the host root (`coverage/topics/topics`);
2. each registered sub-model root (`coveragebase/topics/topics`, the `fullName` form);
3. root-less paths (`topics/topics`, the `tupleKey` form): the first segment is matched against the children of the host root, then against the children of each sub-model root.

Sub-models nested in sub-models are handled the same way: every lower layer of the flattened `layers` list registers its root on the same registry.

### 3.2. Inherited entities in a namespace

The generated namespace class of the host lists the inherited namespaces and entities: `Coverage.subNameSpaces` includes `dataRegistry.nameSpaces<Topics>()` although `Topics` is declared by `CoverageBase`, and a namespace overriding a sub-model namespace lists the parent entities before its own in its `entities` getter. Walking the namespaces of the registry (`visitModel`, `rootNameSpace`) therefore reaches the whole stack.

## 4. Client side

The client registry stacks the same way: `CoverageClientRegistry.modelLayers` spreads the sub-model client layers, and the generated access chains `Xxx$Ent` / `Xxx$Svc` type their `$dataRegistry` on `XxxClientRegistry`.

## 5. Test bench

`coverage/coverage_model/test/layer_stack_test.dart` exercises a sub-model mounted by the coverage model against a real database: registry construction through `CoverageServerRegistry(dataControler: PgDataControler(...))`, `migrateDatabase`, the three path forms of `findObject` (`topics/topics`, `coveragebase/topics/topics`, `coverage/topics/topics`), `tupleDefByKey(TopicCount.tupleKey)`, the sub-model namespaces and enum tables.

## 6. Quick diagnosis

If an entity or a service of a sub-model is not found:

1. Check that the sub-model layer is in `dataRegistry.layers` (and in `XxxServerRegistry.modelLayers`).
2. Check `dataRegistry.pathInfo?.name` (host root) and `dataRegistry.pathInfo?.items` (own items first, then the sub-model items).
3. Resolve the entity with `dataRegistry.tupleDefByKey(Entity.tupleKey)`: the root-less `tupleKey` form is resolved by the third lookup fallback.
4. Two layers with the same `name` but different `uuid` throw at registry construction.
