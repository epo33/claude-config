# Project Structure and Naming Conventions

This document gives the package layout of a Sing project, the file and class naming rules, and where to find each kind of code. Examples come from the OrderHub example (`example/` in the Sing sources).

## 1. Packages

```
project_root/
├── model/                  # The model (source of truth). Written by you, except lib/sing/
├── common/                 # Shared by server and client. lib/src/sing/ is generated
├── model_sing_client/      # Client API. lib/src/ is generated
├── {project}_server/       # Server application. Written by you
└── {project}_client/       # Client apps (Flutter or Dart). Written by you, optional
```

| Package | Depends on | Imported by | Generated folder |
| --- | --- | --- | --- |
| `model` | `sing_model`, `sing_server`, `common` | the server package | `lib/sing/` (or `lib/{singSubDir}/`) |
| `common` | `sing_core` | `model`, `model_sing_client`, client apps | `lib/src/sing/` |
| `model_sing_client` | `sing_client`, `common`, `meta` | client apps | `lib/src/` |
| `{project}_server` | `model`, a data controller package (`sing_postgresql`) | none | none |
| `{project}_client` | `model_sing_client`, `common` | none | none |

All dependencies between these packages are path dependencies. The common and client package paths are set by `Model(commonPackagePath:, clientPackagePath:)`, relative to the model package. The package names are free. In larger projects, a common pattern is `{project}`, `{project}_common`, `{project}_sing_client`, `{project}_server`, `{project}_client`.

**Key principle**: you change the model, then run `dart run sing_builder:sing_emit` from the model package. Sing rewrites the three generated folders. Server and client code use the generated classes.

## 2. Model Package

### 2.1. Layout

```
model/
├── lib/
│   ├── model.dart                     # Barrel: framework, model definitions, common, generated server code
│   ├── server.dart                    # export "sing/server.dart";
│   ├── model/                         # Model definitions (written by you)
│   │   ├── model.dart                 # createXxxModel(), root namespace class, exports of sub-folders
│   │   ├── model_tools/               # Optional: field mixins shared by entities (no namespace)
│   │   │   └── common_fields.dart
│   │   ├── orders/                    # Namespace Orders
│   │   │   ├── orders.dart            # OrdersNameSpace + exports of the folder
│   │   │   ├── order.dart             # OrderEntity (+ export "order.services.dart";)
│   │   │   ├── order.services.dart    # OrderServices mixin (custom services)
│   │   │   └── order_line.dart        # OrderLineEntity
│   │   ├── products/                  # Namespace Products
│   │   │   ├── products.dart
│   │   │   └── product.dart
│   │   └── versions/                  # Optional: MajorVersion subclasses (convention)
│   └── sing/                          # GENERATED. Never edit
└── pubspec.yaml
```

Real files: `example/model/lib/`.

### 2.2. Barrel Rules

- Every file under `lib/model/` imports only `package:model/model.dart`.
- Each folder has a file named like the folder (`orders/orders.dart`). It declares the namespace class and exports every other file of the folder and the barrel of each sub-folder.
- `lib/model/model.dart` exports the barrel of each top-level folder.
- An entity file exports its services file: `export "order.services.dart";` in `order.dart`.
- A services file imports `package:model/model.dart` and `package:model/sing/server.dart` (it uses generated classes such as `Order` and `Order$Search`).

### 2.3. Namespaces

- There is exactly one root namespace. It is declared in `lib/model/model.dart` and passed to `Model(rootNameSpace:)`. In OrderHub: `OrderHubNameSpace`.
- A namespace holds entities and sub-namespaces as `final` fields: `final orders = OrdersNameSpace();`, `final orders = OrderEntity();`. The field name is the path segment of the item. `Order` mounted as `orders` in namespace `orders` gets the key `"orders/orders"` (`Order.tupleKey`).
- Namespaces nest without limit. A namespace can hold entities and sub-namespaces at the same time.
- Each namespace is a folder of its parent namespace folder. The root namespace folder is `lib/model/`.
- A namespace gets its own database schema only with `@DbName` on its class ([DATA_MODEL.md](DATA_MODEL.md)).

### 2.4. Naming Rules

| Item | Class | File | Folder | Generated class |
| --- | --- | --- | --- | --- |
| Entity `Order` | `OrderEntity` | `order.dart` | its namespace folder | `Order` |
| Entity `InvoiceLine` | `InvoiceLineEntity` | `invoice_line.dart` | its namespace folder | `InvoiceLine` |
| Namespace `Orders` | `OrdersNameSpace` | `orders.dart` | `orders/` | `Orders` |
| Tuple `TopicCount` | `TopicCountTuple` | `topic_count.dart` | its namespace folder | `TopicCount` |
| Entity services | `OrderServices` (mixin) | `order.services.dart` | next to the entity | used in `Order$Services` |
| Namespace services | `OrdersServices` (mixin) | `orders.services.dart` | next to the namespace | used in `Orders$Services` |
| Major version | `V1 extends MajorVersion` | `v1.dart` | `versions/` (convention) | none |

Rules:

- **Suffixes are required.** The generator removes `Entity`, `NameSpace` or `Tuple` from the class name to get the generated name. It does not check the suffix. Without it, the generated code is wrong: for example `[diag] ... Order is concrete but mounted by no namespace ...`, then analysis errors in the generated folders.
- Files and folders are snake_case. Classes are PascalCase.
- Entity names are business concepts, in English, singular, not abbreviated: `Order`, `Customer`, `Product`. Not `Ord`, `Entity1`, `Record`.
- Namespace names are plural: the plural of the main entity (`Customers` for `Customer`, `Address`, ...), or a generic term when there is no main entity (`System`).
- Entity, tuple and namespace names must be unique across the model, sub-models included. An entity and a namespace must not share a name. All entity interfaces go to one library (`common/lib/src/sing/common.dart`), so a duplicate name breaks the generated code.
- Identifiers of entities, namespaces, fields and services must not contain `$`. Sing uses `$` in generated names (`Order$Search`, `$Order`) to avoid clashes.
- Service mixin names are not checked. Use `{EntityName}Services` and `{NameSpaceName}Services` with no `Mixin` suffix. The mixin is linked by `@Implementor(OrderServices)` on the definition class. See [SERVICES.md](SERVICES.md).

Entity definition (from `example/model/lib/model/orders/order.dart`, shortened):

```dart
import "package:model/model.dart";

export "order.services.dart";

@Implementor(OrderServices)
@LoadServices()
@Searchable()
class OrderEntity extends ModelEntity with UuidPrimaryKeyMixin {
  OrderEntity();

  final orderNumber = StringField(maxLength: 50).immutable();

  final customer = ReferenceTo<CustomerEntity>(
    onDelete: ReferentialAction.error,
  );

  final totalAmount = DoubleField();
}
```

Services file (from `example/model/lib/model/orders/order.services.dart`, shortened):

```dart
import "package:model/model.dart";
import "package:model/sing/server.dart";

mixin OrderServices on EntityServerServices<Order, String> {
  Future<String> clientBootstrap({required CallContext callContext}) async =>
      testOrderPrefix;
}
```

Put business logic in services mixins, never in the entity definition class. The definition class only declares fields and annotations.

### 2.5. Version Files

[Migration steps](MIGRATIONS.md) belong to model versions: subclasses of `MajorVersion` (with a default constructor) listed in `Model(majorVersions:)`. Each holds its `MinorVersion`s, `PatchVersion`s and migration steps. The file location is free. The convention is one file per major version under `lib/model/versions/` (`v1.dart` for `class V1 extends MajorVersion`).

## 3. Common Package

```
common/
├── lib/
│   ├── common.dart        # Barrel. MUST export "src/sing/sing.dart"
│   └── src/
│       ├── sing/          # GENERATED. Never edit
│       ├── enums/         # Your enums used by fields (EnumField<OrderStatus>)
│       └── dto/           # Your JSON-serializable classes used by services
└── pubspec.yaml
```

Real files: `example/common/lib/`. The example barrel exports `src/common.dart`, which exports `dto/`, `enums/` and `sing/sing.dart`.

- Put here every type that both server and client need: enums of `EnumField`s, DTOs passed to or returned by services ([AUTO_JSON.md](AUTO_JSON.md)).
- `lib/src/sing/` holds the entity interfaces and their extensions, the search classes, `$Identifiers` and the `OrderHubRegistry` interface. Details in [GENERATED_CODE.md](GENERATED_CODE.md).

## 4. Server Package

The server package creates the registry, runs the migrations and serves HTTP. `example/orderhub_server/bin/orderhub_server.dart` shows the minimum: `createDataRegistry` builds `OrderHubServerRegistry(dataControler: PgDataControler(...))`, and `migrateDatabase` upgrades the database. Details in [APP_SERVER.md](APP_SERVER.md).

`orderhub_server/pubspec.yaml` (dependencies part):

```yaml
dependencies:
  model:
    path: ../model
  sing_postgresql:
    path: SING/sing_postgresql
```

Imports: `package:model/server.dart` (generated entities, `$Order`, `Order$Services`, `OrderHubServerRegistry`) and `package:model/model.dart` (framework and model barrel).

A possible layout for a larger server:

```
{project}_server/
├── bin/
│   └── {project}_server.dart   # Entry point: registry, migration, HTTP server
├── lib/
│   ├── handlers/               # HTTP routes outside the Sing services
│   └── ...                     # Your server-only code
├── test/
└── pubspec.yaml
```

Business logic that belongs to an entity or a namespace goes into services mixins in the model package, not here.

## 5. Client Package and Client Apps

```
model_sing_client/
├── lib/
│   ├── client.dart     # export "src/client.dart";
│   └── src/            # GENERATED. Never edit. Sing deletes any other file here
└── pubspec.yaml
```

A client app depends on `model_sing_client` and `common`, imports `package:model_sing_client/client.dart`, and creates `OrderHubClientRegistry`. Details in [APP_CLIENT.md](APP_CLIENT.md).

## 6. Generated Folders

### 6.1. Never Edit

Sing owns these folders completely. Each run writes the changed files and **deletes every other file** in them, including files you add:

- `model/lib/sing/` (or `model/lib/{singSubDir}/`)
- `common/lib/src/sing/`
- `model_sing_client/lib/src/`

Generated Dart files start with `// Generated by SING. DO NOT MODIFY`. To change generated code, change the model and run, from `model/`:

```bash
dart run sing_builder:sing_emit
```

### 6.2. Safe to Edit

- `model/lib/model/**` (definitions, services, versions)
- `model/lib/model.dart`, `model/lib/server.dart`
- `common/lib/common.dart` and everything in `common/lib/src/` except `sing/`
- `model_sing_client/lib/client.dart`
- the server and client app packages

## 7. Adding a Namespace

Example: add namespace `Orders` with entity `Order` to OrderHub.

1. Create `model/lib/model/orders/orders.dart`:

```dart
import "package:model/model.dart";

export "order.dart";

class OrdersNameSpace extends ModelNameSpace {
  OrdersNameSpace();

  final orders = OrderEntity();
}
```

2. Create `model/lib/model/orders/order.dart` with `class OrderEntity extends ModelEntity` ([DATA_MODEL.md](DATA_MODEL.md)).
3. Mount the namespace in its parent: `final orders = OrdersNameSpace();` in `OrderHubNameSpace`.
4. Export the folder barrel from the parent: `export "orders/orders.dart";` in `lib/model/model.dart`.
5. Optional: create `order.services.dart` with `mixin OrderServices`, add `@Implementor(OrderServices)` on `OrderEntity` and `export "order.services.dart";` in `order.dart`.
6. From `model/`, run `dart run sing_builder:sing_emit`.

New generated files:

- `model/lib/sing/order_hub/orders.dart`: namespace class `Orders`
- `model/lib/sing/order_hub/orders/order.dart`: `$Order`, `Order$Services`
- `common/lib/src/sing/common.dart`: `Order`, `Order$Instance`, `DataRowValues$Order`, ...
- `common/lib/src/sing/searches.dart`: `Order$Search`, `Order$SearchParams` (if `@Searchable()`)
- `model_sing_client/lib/src/order_hub/orders/order.dart`: client `$Order`, `Order$Services`

## 8. Locating Code

| Question | Where to look |
| --- | --- |
| Definition of entity `Order` | `model/lib/model/{namespace folders}/order.dart`, class `OrderEntity` |
| Custom services of `Order` | `model/lib/model/{namespace folders}/order.services.dart`, mixin `OrderServices` |
| Generated server code of `Order` | `model/lib/sing/{root}/{namespace folders}/order.dart` |
| Shared interface of `Order` | `common/lib/src/sing/common.dart`, class `Order` |
| Model versions | `MajorVersion` subclasses listed in `Model(majorVersions:)` (`lib/model/versions/` by convention) |
| DDL orders | None generated: `migrateDatabase` computes them at run time from the model and the database |
| HTTP entry point | `{project}_server/bin/{project}_server.dart`. Sing services are served by `dataRegistry.processRequest(...)` ([APP_SERVER.md](APP_SERVER.md)) |

More lookups in generated code: [GENERATED_CODE.md](GENERATED_CODE.md), section 3.
