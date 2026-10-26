# How to Start a Project Using Sing

This guide creates the three packages a Sing model needs, then runs the first code generation. The result has the same shape as the OrderHub example (`example/` in the Sing sources). The package layout and naming rules are in [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md).

## 1. What You Build

```
orderhub/                  # project root, any name
├── model/                 # the model: you write lib/model/, Sing writes lib/sing/
├── common/                # shared by server and client: Sing writes lib/src/sing/
└── model_sing_client/     # client API: Sing writes lib/src/
```

Later you add a server package (`orderhub_server/`) and client apps. See [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md).

Prerequisites:

- A Dart SDK matching the `environment.sdk` constraint of the Sing packages (`^3.10.0`).
- A local copy of the Sing sources. All Sing packages are used as path dependencies. Below, `SING` stands for the directory that holds `sing_core/`, `sing_model/`, `sing_server/`, `sing_client/` and `sing_builder/`. Write it relative to each package (`../../sing2`) or as an absolute path.

## 2. Create the Packages by Hand

This is the reliable method. Section [3](#3-the-init-command) describes the `init` command, which automates part of it.

### 2.1. Pubspecs

`model/pubspec.yaml`:

```yaml
name: model
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  sing_model:
    path: SING/sing_model
  sing_server:
    path: SING/sing_server
  common:
    path: ../common
dev_dependencies:
  sing_builder:
    path: SING/sing_builder
```

`common/pubspec.yaml`:

```yaml
name: common
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  sing_core:
    path: SING/sing_core
```

`model_sing_client/pubspec.yaml`:

```yaml
name: model_sing_client
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  sing_client:
    path: SING/sing_client
  common:
    path: ../common
  meta: any
```

Rules:

- `common` must be a **path** dependency of `model`. The generator only reads packages reached through path dependencies (`dependencies`, not `dev_dependencies`).
- `model_sing_client` must depend on `common`: the generated client code imports `package:common/common.dart`.
- `sing_builder` is a dev dependency of `model`. It provides `dart run sing_builder:sing_emit`.

### 2.2. Library Entry Points

These files are written once by you. Sing never rewrites them.

| File | Content |
| --- | --- |
| `model/lib/model.dart` | Barrel imported by every model file (see below) |
| `model/lib/server.dart` | `export "sing/server.dart";` |
| `common/lib/common.dart` | `export "src/sing/sing.dart";` plus your own shared code |
| `model_sing_client/lib/client.dart` | `export "src/client.dart";` |

`model/lib/model.dart` (from `example/model/lib/model.dart`):

```dart
export "package:sing_model/sing_model.dart";
export "package:sing_server/sing_server.dart";
export "model/model.dart";
export "package:common/common.dart";
export "sing/server.dart";
```

Every file under `model/lib/model/` imports only `package:model/model.dart`. Before the first emission, `lib/sing/server.dart` does not exist yet. The analyzer reports the missing export, but `sing_emit` still reads the model.

### 2.3. The Model Entry File

`model/lib/model/model.dart` declares the function that builds the model and the root namespace (from `example/model/lib/model/model.dart`):

```dart
import "package:model/model.dart";

export "orders/orders.dart";
export "products/products.dart";

Model createOrderHubModel() => Model(
  modelName: "OrderHub",
  rootNameSpace: OrderHubNameSpace(),
  clientPackagePath: "../model_sing_client",
  commonPackagePath: "../common",
);

@AccessToken.authentified
class OrderHubNameSpace extends ModelNameSpace {
  OrderHubNameSpace();

  final orders = OrdersNameSpace();

  final products = ProductsNameSpace();
}
```

`sing_emit` reads this source with the Dart analyzer. It never runs it. So the declaration must follow these rules, or the run stops with `Model error in ...`:

- Exactly one top-level function under `lib/` returns a `Model`. Its name is free.
- Its body is `=> Model(...)` or a block with a single `return Model(...);`.
- `modelName` is required and is a string literal. Every other string argument (`packageName`, `commonPackagePath`, `clientPackagePath`, `singSubDir`) is also a string literal.
- `rootNameSpace` is a constructor call: `rootNameSpace: OrderHubNameSpace()`.
- `subModels` is a list literal of calls: `subModels: [createBaseModel()]`. See [SUBMODELS.md](SUBMODELS.md).
- `majorVersions` is a list literal of constructor calls: `majorVersions: [OrderHubV0()]`. See [MIGRATIONS.md](MIGRATIONS.md).

Main `Model` arguments:

| Argument | Effect |
| --- | --- |
| `modelName` | Prefix of the model-level generated classes: `OrderHub$Layer`, `OrderHubRegistry`, `OrderHubServerRegistry`, `OrderHubClientRegistry`, `OrderHub$RegistryTokens` |
| `rootNameSpace` | The root namespace. Its class name, without the `NameSpace` suffix, names the root generated namespace (`OrderHub`) and the root folder of generated files (`order_hub/`) |
| `commonPackagePath` | Path of the common package, relative to the model package. Without it, nothing is emitted for the common side |
| `clientPackagePath` | Path of the client package, relative to the model package. Without it, nothing is emitted for the client side |
| `singSubDir` | Folder under `lib/` for the server code. Default `sing` (`lib/sing/`). Use `src/sing` for a `lib/src/` layout |
| `packageName` | Package name used in generated imports. Default: the package that declares the model function |
| `aliases` | Import prefixes for some packages in generated code (`Alias(glob:, package:, alias:)`). Prefixes `core`, `http`, `meta` and `impl` are reserved |
| `subModels`, `isSubModel` | Model composition. See [SUBMODELS.md](SUBMODELS.md) |
| `majorVersions` | Version tree and migration steps. See [MIGRATIONS.md](MIGRATIONS.md) |
| `strictAccessTokens` | When `true`, an entity that publishes services without a `@TokenContext` (on itself or a namespace above) or an `@AccessToken` on itself is refused |

## 3. The `init` Command

`dart run sing_builder:init SING` (`sing_builder/bin/init.dart`), run from `model/`, tries to do section 2.1 and part of 2.2:

- Adds `sing_model`, `sing_server` and `common` to `model/pubspec.yaml`, `sing_core` to `common/pubspec.yaml`, `sing_client` and `meta` to `model_sing_client/pubspec.yaml` (with `dart pub add`).
- Creates `../common` and `../model_sing_client` with `dart create` when they have no pubspec.
- Writes `model/lib/server.dart`, `model/lib/model/model.dart`, `common/lib/common.dart`, `model_sing_client/lib/client.dart` and a `README.md` in each generated folder. A file that already exists is never overwritten.

Limits:

- It may stop with `Error while running dart create ...` or `Error while running dart pub add ...` (for example a `sing_core` path that does not exist). When it does, do section 2 by hand.
- It does not add `common` to `model_sing_client/pubspec.yaml`. Add it by hand.
- The `model.dart` it writes holds only `Model createModelModel() => Model(modelName: 'Model');`. Complete it as in section 2.3: rename the function and the model, add `rootNameSpace`, `commonPackagePath` and `clientPackagePath`.
- The `README.md` files it writes in the generated folders are deleted by the first emission. This is expected.

Do not use `dart run sing_builder:addns`. It does not create usable namespace folders. Create namespace folders and files by hand ([PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)).

## 4. First Emission

1. Run `dart pub get` in `common/`, `model_sing_client/` and `model/`. The generator and its validation step need resolved packages.
2. Define at least one namespace with one entity ([DATA_MODEL.md](DATA_MODEL.md)).
3. From `model/`, run:

```bash
dart run sing_builder:sing_emit
```

A successful run ends like this (paths shortened):

```
[emit--] 11 files in .../model/lib/sing (11 written, 0 unchanged)
[emit--] 5 files in .../common/lib/src/sing (5 written, 0 unchanged)
[emit--] 12 files in .../model_sing_client/lib/src (12 written, 0 unchanged)
[ 17.6s] analyze 3 directories ( 33.8s in)
[analyze] no error, no warning
[ 33.8s] done
```

The exit code is 0. Any other result: see [GENERATED_CODE.md](GENERATED_CODE.md), section 1.

## 5. Next Steps

- Add namespaces and entities: [DATA_MODEL.md](DATA_MODEL.md), layout rules in [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md).
- Add custom services: [SERVICES.md](SERVICES.md).
- Create the server package: [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) section 4 and [APP_SERVER.md](APP_SERVER.md).
- Create a client app: [APP_CLIENT.md](APP_CLIENT.md).
- After each model change, run `sing_emit` again ([GENERATED_CODE.md](GENERATED_CODE.md)).
