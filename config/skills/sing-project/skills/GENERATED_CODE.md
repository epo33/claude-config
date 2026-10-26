# Generated Code

This document explains how to run the code generator `sing_emit`, how to read its errors, and where each generated symbol lives. Examples use the OrderHub example (`example/` in the Sing sources): model `OrderHub`, root namespace `OrderHubNameSpace`, entity `Order` in namespace `Orders`.

## 1. Running `sing_emit`

### 1.1. Command

From the model package:

```bash
dart run sing_builder:sing_emit
```

Or with the model package as argument (one package only):

```bash
dart run sing_builder:sing_emit path/to/model
```

Source: `sing_builder/bin/sing_emit.dart`. The model package needs `sing_builder` as a dev dependency ([INIT_PROJECT.md](INIT_PROJECT.md)).

Run it after every change to an entity, a field, a namespace, an annotation, a services mixin signature or the `Model(...)` declaration. Services code ([SERVICES.md](SERVICES.md)) uses generated classes, so emit before you write it.

One run emits the model **and every model it mounts** (`subModels`, [SUBMODELS.md](SUBMODELS.md)). Do not emit sub-models first in separate runs.

### 1.2. Options

`dart run sing_builder:sing_emit -h` prints them.

| Option | Default | Effect |
| --- | --- | --- |
| `-s`, `--side` | `server,common,client` | Sides to write. Repeat it or use a comma list: `--side server,common`. The server side is always computed, but written only when selected |
| `--[no-]validate` | on | After writing, run `dart analyze` on the generated folders, then `dart fix --apply` and `dart format` on folders that still have lints. `--no-validate` saves about half the time while you iterate. Run once with validation before you commit |
| `--force` | off | Write the files even when a declaration is refused (`[error]` diagnostic). Use it to inspect the result. The run still fails (exit code 65) |
| `--uuid` | previous value | Version uuid of the model layer. Read back from the previous `server.dart`. On a first run, it is derived from the package name, so it is stable |
| `--compiled-at` | previous value | Compile time of the layer, ISO 8601. Read back from the previous `server.dart`. On a first run: `2026-01-01T00:00:00Z` |
| `--sdk` | from `PATH` | Dart SDK folder. Needed when `dart` is not on the `PATH` |
| `-h`, `--help` | | Print usage |

### 1.3. What a Run Does

1. **Read.** It reads the model source with the Dart analyzer. It never runs the model. It finds the single top-level function under `lib/` that returns a `Model`, then reads every mounted model, the deepest first. Only packages reached through path `dependencies` are read.
2. **Render.** It renders each model from the deepest mounted model up. A model reads the code this run just rendered for the models below it, not the files on disk.
3. **Check.** If any `[error]` diagnostic was raised, it stops and writes nothing (unless `--force`).
4. **Write.** For each generated folder, it writes the files whose content changed, keeps identical files untouched, and **deletes every other file** in the folder. A renamed entity leaves no stale file.
5. **Validate** (unless `--no-validate`). See section 1.4.
6. It touches `.dart_tool/sing_regen.done` in each written package. The VS Code extension in `sing_builder/tools/vscode-analyzer-restart` watches it and restarts the Dart analysis server.

Generated folders:

| Side | Folder |
| --- | --- |
| server | `model/lib/sing/` (or `model/lib/{singSubDir}/`) |
| common | `common/lib/src/sing/` (path from `Model(commonPackagePath:)`) |
| client | `model_sing_client/lib/src/` (path from `Model(clientPackagePath:)`) |

The server folder also holds `model_sources.json`: the list and hash of the model source files of this model and its sub-models.

### 1.4. Output and Exit Codes

Progress goes to stdout:

```
[  ----] reading the models of .../model
[  7.6s] read 1 model(s) of the chain (  7.7s in)
[  0.5s] render the server ( 15.9s in)
[emit--] 11 files in .../model/lib/sing (8 written, 2 unchanged, 1 removed)
[ 17.6s] analyze 3 directories ( 33.8s in)
[analyze] no error, no warning
[ 33.8s] done
```

The last line is `done` or `failed`.

| Exit code | Meaning |
| --- | --- |
| 0 | Files written, and no error or warning in the generated code |
| 64 | Bad command line, or no Dart SDK found (use `--sdk`) |
| 65 | Model refused or unreadable, or the generated code has errors or warnings |
| 66 | The directory does not exist, or `--sdk` is not a Dart SDK |

### 1.5. Diagnostics

Diagnostics go to stderr. There are four kinds.

**Refusal** (a declaration the model cannot honour). Nothing is written. `--force` writes anyway:

```
[error] package:model/model/orders/order.dart:5: OrderEntity publishes services no TokenContext governs: state one on it or on a namespace above it, or an AccessToken on the entity itself
[error] nothing written: emit with --force to see it
```

The same message can appear twice.

**Warning.** The run continues:

```
[diag] package:model/model/orders/order.dart:5: Order is concrete but mounted by no namespace; ...
```

**Read failure** (the model cannot be read). Nothing is written, and `--force` does not help. The message starts with `Model error in`, `Structure error at` or `Field error at`:

```
[error] .../model: Structure error at package:model/model/orders/orders.dart:10: OrderEntity is mounted twice, as orders and as otherOrders; a model holds one instance of an entity
```

**Analysis errors** in the generated code (validation step). The files are written. The folder is left exactly as emitted, without `dart fix`:

```
[analyze] .../model/lib/sing
  error - .../model/lib/sing/server_init.dart:22:25 - The returned type 'Object?' isn't returnable ... - return_of_invalid_type_from_closure
[ -----] model is left as emitted, so nothing is lost
```

Lints that `dart fix` cannot remove are listed after `dart fix left lints only the generator can settle`. They do not fail the run.

### 1.6. Common Failures and Fixes

| Message | Cause | Fix |
| --- | --- | --- |
| `no top-level function returns a Model` | No model function under `lib/`, or `sing_model` not resolved | Declare `Model createXxxModel() => Model(...)` under `lib/`. Run `dart pub get` |
| `several top-level functions return a Model: ...` | Two functions under `lib/` return `Model` | Keep one. Move helpers out of `lib/` or change their return type |
| `... must build its Model in place, as Model createX() => Model(...)` | Body is not `=> Model(...)` or a single `return Model(...)` | Build the `Model` directly in the function |
| `modelName is required and must be written as a literal`, `'...' must be written as a plain string` | A string argument is a variable or an interpolation | Write string literals |
| `rootNameSpace must be written as a constructor call` | `rootNameSpace: someVariable` | `rootNameSpace: OrderHubNameSpace()` |
| `a sub-model must be written as a call to the function building it` | `subModels` element is not a call | `subModels: [createBaseModel()]` |
| `majorVersions must be written as a list of constructor calls`, `... must be written as a plain list, without spread, if or for` | Computed version list | Write a list literal of constructor calls |
| `the models mount each other in a cycle` | Model A mounts B which mounts A | Remove the cycle |
| `... is mounted twice, as ... and as ...` | The same entity class is a field of two namespaces, or twice in one | Mount each entity class once. Use inheritance for shared fields |
| `namespace ... mounts itself` | A namespace contains itself, directly or not | Fix the namespace tree |
| `... must mount its namespace by building it` | A namespace getter does not return a constructor call | `MyNameSpace get x => MyNameSpace();` or `final x = MyNameSpace();` |
| `... references ..., which names no entity` | `ReferenceTo<X>` where `X` is not an entity definition class | Reference an `XxxEntity` class |
| `... descends from an entity without naming it` | Descendant entity without `ancestorEntity` in its super call | See [CONCEPTS_RELATIONSHIPS.md](CONCEPTS_RELATIONSHIPS.md) |
| `... declares descendants without a selectorField` | Ancestor entity without selector field | Declare `selectorField` ([CONCEPTS_RELATIONSHIPS.md](CONCEPTS_RELATIONSHIPS.md)) |
| `... is declared without being written as an expression the builder can read` | A field initializer the generator cannot read statically | Write the field as a direct constructor chain: `StringField(maxLength: 50).nullable()` |
| `... publishes services no TokenContext governs` | `strictAccessTokens: true` and no token context | Add `@TokenContext(...)` on the entity or a namespace above, or `@AccessToken...` on the entity |
| `[diag] ... is concrete but mounted by no namespace` | Entity class not mounted, or missing `Entity` suffix | Mount it in a namespace, declare it `abstract`, or fix the class name ([PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)) |
| `[analyze]` errors on unresolved imports | Packages not resolved | `dart pub get` in `model`, `common` and the client package, then run again |
| `name the Dart SDK with --sdk` | `dart` not on `PATH` | Pass `--sdk <dart-sdk folder>` |

### 1.7. When Generation Fails

1. Read the first `[error]` line. It names a file and a line of the model (`package:model/...:12`). Fix that declaration.
2. For a refusal you do not understand, run with `--force --no-validate` and read the generated files. Then fix the model and run again without `--force`.
3. For `[analyze]` errors, first run `dart pub get` in the three packages and emit again. If the errors remain and the model looks correct, the generator has a bug: report it with the file, line and message. Do not edit the generated file.
4. Recover the previous generated code with git if needed. `sing_emit` keeps no backup.
5. After a successful run, if the IDE still shows errors in generated files, restart the Dart analysis server.

## 2. Generated Files

### 2.1. File Map

Server side, in `model/lib/sing/`:

| File | Content |
| --- | --- |
| `server.dart` | `OrderHub$Layer`, `OrderHubServerRegistry`, enum definitions, JSON adapters of DTOs. Exports the other server files |
| `order_hub.dart` | Root namespace class `OrderHub`, `OrderHub$View`, `OrderHub$Services` |
| `order_hub/orders.dart` | Namespace class `Orders`, `Orders$View`, `Orders$Services` |
| `order_hub/orders/order.dart` | `$Order`, `_Order$Impl`, `Order$Services`, `Order$Tokens` (server) |
| `server_common.dart` | `FieldsExpr$Order` (query expressions), `SearchOnly$Order` (search-only fields) |
| `server_mixins.dart` | `Order$SearchMixin` (the `search` service) |
| `server_searches.dart` | Re-export of `Order$Search` and the other search classes |
| `server_tokens.dart` | `OrderHub$RegistryTokens` (access token constants) |
| `server_exports.dart` | Re-export of the model definition classes and mixins used by the generated code |
| `server_init.dart` | `$ServicesInfos` (service descriptions) |
| `model_sources.json` | Source list and hash of the model |

Common side, in `common/lib/src/sing/`:

| File | Content |
| --- | --- |
| `common.dart` | Entity and tuple interfaces (`Order`), `Order$Instance`, `Order$ReferenceExtension`, `EntityFieldList$Order`, `FieldsView$Order`, `DataRowValues$Order` |
| `searches.dart` | `Order$Search`, `Order$SearchParams` |
| `consts.dart` | `$Identifiers` (string constants of all names) |
| `registry.dart` | `OrderHubRegistry<E>` |
| `sing.dart` | Exports the four files above |

Client side, in `model_sing_client/lib/src/`:

| File | Content |
| --- | --- |
| `client.dart` | `OrderHub$Layer`, `OrderHubClientRegistry`. Exports the other client files |
| `order_hub.dart`, `order_hub/orders.dart` | Client namespace classes |
| `order_hub/orders/order.dart` | Client `$Order`, `_Order$Impl`, `Order$Services`, `Order$Tokens` |
| `client_ent.dart` | `OrderHub$Ent`, `Orders$Ent`: typed access to entity definitions |
| `client_svc.dart` | `OrderHub$Svc`, `Orders$Svc`: typed access to services |
| `client_mixins.dart` | `Order$SearchMixin` and client stubs of custom services mixins (`OrderServices`) |
| `client_common.dart`, `client_searches.dart`, `client_exports.dart` | Re-exports from `common` |
| `client_init.dart`, `client_tokens.dart` | `$ServicesInfos`, `OrderHub$RegistryTokens` |

File paths follow the namespace tree. The root folder is the root namespace name in snake_case (`order_hub`). A namespace file is named after the namespace (`orders.dart`). An entity file is named after the entity class (`order.dart`, `order_line.dart`).

### 2.2. Model-Level Symbols

Names start with `Model(modelName:)`.

| Symbol | File | Use |
| --- | --- | --- |
| `OrderHubServerRegistry` | `server.dart` | Server registry. `OrderHubServerRegistry(dataControler:, debugger:, debugMode:)` ([APP_SERVER.md](APP_SERVER.md)) |
| `OrderHubClientRegistry` | `client.dart` | Client registry. `OrderHubClientRegistry(dataControler:, modelField:, debugger:)` ([APP_CLIENT.md](APP_CLIENT.md)) |
| `OrderHubRegistry<E extends EntityDef>` | `registry.dart` | Interface shared by both registries. Also implements the interfaces of sub-models |
| `OrderHub$Layer` | `server.dart`, `client.dart` | Const description of the model (`name`, `uuid`, `version`, `compiledAt`, `pathInfo`, `enumDefs`, `tupleDefs`, `jsonAdapters`, `registerTokens()`, server `majorVersions`). Listed in `OrderHubServerRegistry.modelLayers` |
| `OrderHub$RegistryTokens` | `server_tokens.dart`, `client_tokens.dart` | Access token constants, e.g. `ordersOrdersRead` |
| `$Identifiers` | `consts.dart` | Name constants (`$Identifiers.orderNumber`) |
| `$ServicesInfos` | `server_init.dart`, `client_init.dart` | Internal |

The registry implementations (`_OrderHub$Registry`) are private. Always use the factory of the interface.

### 2.3. Namespace-Level Symbols

For namespace `Orders` (definition class `OrdersNameSpace`):

| Symbol | Side | Use |
| --- | --- | --- |
| `Orders` | server, client | Namespace class. `Orders.pathInfos`, `Orders.tokens` |
| `Orders$View` | server | Typed access to sub-namespaces: `OrderHub$View.orders` |
| `Orders$Services` | server, client | Namespace services, with the mixin of `@Implementor` on the namespace |
| `Orders$Ent` | client | `OrderHub$Ent(registry).orders.orders` returns `ClientEntityDef<Order, String>` |
| `Orders$Svc` | client | `OrderHub$Svc(registry).orders.orders()` returns `Order$Services` |

### 2.4. Entity-Level Symbols

For entity `Order` (definition class `OrderEntity`, primary key `String`):

| Symbol | File | Use |
| --- | --- | --- |
| `Order` | `common.dart` | Abstract interface: the entity type used in all generic APIs (`DataRowValues<Order>`). `Order.tupleKey == "orders/orders"`, usable with `dataRegistry.tupleDefByKey(Order.tupleKey)` |
| `Order$Instance` | `common.dart` | `typedef Order$Instance = DataRowValues<Order>` |
| `DataRowValues$Order` | `common.dart` | Extension: field values of a row, `row.orderNumber` is `FieldValue<String>`, `row.customer` is `FieldValueRef<Customer, String>` |
| `EntityFieldList$Order` | `common.dart` | Extension: field definitions, `fields.orderNumber` is `StringField` |
| `FieldsView$Order` | `common.dart` | Extension: field paths for navigation (`FieldsChain`) |
| `Order$ReferenceExtension` | `common.dart` | Extension on `Reference<Order>`: typed `primaryKey` |
| `Order$Search` | `searches.dart` | Search filters, one per field (`@Searchable()`). See [SEARCHES.md](SEARCHES.md) |
| `Order$SearchParams` | `searches.dart` | Typed search parameter keys |
| `FieldsExpr$Order` | `server_common.dart` | Extension: field expressions for queries ([QUERIES.md](QUERIES.md)) |
| `SearchOnly$Order` | `server_common.dart` | Extension: values of `@SearchOnlyField` filters |
| `Order$SearchMixin` | `server_mixins.dart`, `client_mixins.dart` | Mixin with the `search(...)` service |
| `$Order` | `order_hub/orders/order.dart` | Static entry points (below) |
| `Order$Services` | `order_hub/orders/order.dart` | Services class: standard services + `@Implementor` mixins. Server: `extends EntityServerServices<Order, String>`. Client: `extends ClientServices` |
| `Order$Tokens` | `order_hub/orders/order.dart` | Extension on `EntityTokens<Order>`: `$Order.tokens.read` (server) |
| `_Order$Impl` | `order_hub/orders/order.dart` | Private entity definition (`ServerEntityDef` / `ClientEntityDef`). Never used directly |

Static members of `$Order`, server side:

| Member | Returns |
| --- | --- |
| `$Order.of(dataRegistry)` | `ServerEntityDef<Order, String>` |
| `$Order.ofContext(callContext)` | `ServerEntityDef<Order, String>` |
| `$Order.query(callContext)` | `Query<Order, String>` ([QUERIES.md](QUERIES.md)) |
| `$Order.existsOrder(callContext)`, `$Order.notExistsOrder(callContext)` | `SelectExists<Order>` |
| `$Order.valueFromOrder<T>(callContext, what:, where:, groupBy:, having:)` | `QueryExpr<T>` |
| `$Order.services(callContext)` | `Order$Services` |
| `$Order.tokens` | `EntityTokens<Order>` |

Client side: `$Order.of(dataRegistry)` returns `ClientEntityDef<Order, String>`, and `$Order.services(dataRegistry)` returns `Order$Services`.

### 2.5. Tuples

A tuple definition (`class TopicCountTuple extends ModelTuple`) generates the interface `TopicCount` in `common.dart` with `TopicCount.tupleKey` (`"topics.topicCount"`), `TopicCount$Instance` and the same field extensions as an entity. Its server file holds `$TopicCount` with `of`, `ofContext`, `define` (listed in `_modelTuples` of `server.dart`), `project` and `partialProject` ([QUERIES.md](QUERIES.md)). It has no `query` and no `$Search` class.

## 3. Finding Things in Generated Code

### 3.1. Lookup Table

| I need | Look in | Search for |
| --- | --- | --- |
| Fields of `Order` and their types | `common/lib/src/sing/common.dart` | `extension DataRowValues$Order` |
| Field definitions of `Order` | `common/lib/src/sing/common.dart` | `extension EntityFieldList$Order` |
| Fields usable in a query | `model/lib/sing/server_common.dart` | `extension FieldsExpr$Order` |
| Search filters of `Order` | `common/lib/src/sing/searches.dart` | `class Order$Search<` |
| Parameters of the `search` service | `model/lib/sing/server_mixins.dart` | `mixin Order$SearchMixin` |
| Services available on `Order` | `model/lib/sing/**/order.dart` | `class Order$Services` (its `with` clause lists the mixins) |
| Namespace of `Order` | `model/lib/sing/**/order.dart` | folder path of the file (section 3.2) |
| Access token of a service | `model/lib/sing/server_tokens.dart` | `class OrderHub$RegistryTokens` |
| Access tokens per service of `Order` | `model/lib/sing/**/order.dart` | `accessTokens:` in `$Order.pathInfos` |
| Registry class names | `model/lib/sing/server.dart`, `model_sing_client/lib/src/client.dart` | `ServerRegistry`, `ClientRegistry` |
| Enum definitions | `model/lib/sing/server.dart` | `_modelEnums` |
| Name constant | `common/lib/src/sing/consts.dart` | `class $Identifiers` |
| Client entity or service access | `model_sing_client/lib/src/client_ent.dart`, `client_svc.dart` | `class Orders$Ent`, `class Orders$Svc` |

### 3.2. Namespace of an Entity

1. Find the file that defines `class _Order$Impl` under `model/lib/sing/`. For `Order`: `model/lib/sing/order_hub/orders/order.dart`.
2. Each folder of the path is a namespace: `order_hub` is the root namespace, `orders` is its sub-namespace. `Order` is in `Orders`.
3. The namespace class is in the file named like the folder, in the parent folder: `model/lib/sing/order_hub/orders.dart` defines `class Orders extends sing.ServerNameSpace`. Its definition class is `OrdersNameSpace` in `model/lib/model/orders/orders.dart`.

### 3.3. Fields and Types of an Entity

Read `extension DataRowValues$Order on sing.DataRowValues<Order>` in `common/lib/src/sing/common.dart`. Each getter is one field:

- `FieldValue<T>`: a field of type `T`.
- `FieldValueRef<R, PK>`: a reference to entity `R` whose primary key type is `PK`.

```dart
extension DataRowValues$Order on sing.DataRowValues<Order> {
  sing.FieldValue<String> get orderNumber =>
      (this[$Identifiers.orderNumber] as sing.FieldValue<String>);

  sing.FieldValue<sing.UtcDateTime> get orderDate =>
      (this[$Identifiers.orderDate] as sing.FieldValue<sing.UtcDateTime>);

  sing.FieldValueRef<Customer, String> get customer =>
      (this[$Identifiers.customer] as sing.FieldValueRef<Customer, String>);
}
```

Fields marked `@serverSideOnly` are in the same extension.

### 3.4. Search Filters of an Entity

Read `class Order$Search<E extends Order> extends sing.SearchOnEntity<E>` in `common/lib/src/sing/searches.dart`:

```dart
class Order$Search<E extends Order> extends sing.SearchOnEntity<E> {
  const Order$Search({
    this.orderNumber,
    this.orderDate,
    this.customer,
    this.refToCustomer,
    // ...
    this.test,
    this.whereOrderLineOrder,
    super.$foreign,
  });

  final sing.SearchOnField<String>? orderNumber;
  final sing.SearchOnField<sing.UtcDateTime>? orderDate;
  final Customer$Search<Customer>? customer;
  final sing.SearchOnField<String>? refToCustomer;
  final bool? test;
  final sing.SearchOnForeignField<E, OrderLine>? whereOrderLineOrder;
  // ...
}
```

- `SearchOnField<T>`: filter on a field of type `T`.
- `Customer$Search<Customer>`: filter through a reference, with the filters of the referenced entity.
- `refToCustomer`: filter on the key value of the reference.
- `whereXxx` (`SearchOnForeignField`): filter on entities that reference this one.
- A plain type (`bool? test`): a `@SearchOnlyField` filter.

See [SEARCHES.md](SEARCHES.md).
