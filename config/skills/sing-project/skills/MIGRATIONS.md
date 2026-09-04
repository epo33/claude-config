# Migrations & Schema Evolution

This document explains how Sing brings a database up to the version of the model.

## 1. Overview

Sing's migration (`sing_server/lib/src/migration/`):
- **computes the DDL orders** by comparing the model with the introspected database (schemas, tables, columns, indexes, foreign keys, enum tables);
- **executes custom migration steps** declared in the model, before and after the DDL orders;
- **tracks versions** per model layer to determine which steps to run;
- **runs when the application calls it**, typically at server startup, inside one operation and one transaction.

Key principle: **the model is the source of truth for the database schema**.

## 2. Model versions

### 2.1. Declaration

Versions are declared on the model through `Model.majorVersions` (`sing_model`). The version tree is `MajorVersion` → `MinorVersion` → `PatchVersion`, and a patch carries the steps:

```dart
// model/lib/model/model.dart
Model createOrderHubModel() => Model(
  modelName: "OrderHub",
  rootNameSpace: OrderHubNameSpace(),
  majorVersions: [V1()],
  // ...
);

// model/lib/model/versions/v1.dart
class V1 extends MajorVersion {
  V1()
    : super(
        description: "Initial release",
        minorVersions: [
          MinorVersion(
            description: "Order status",
            patches: [
              PatchVersion(
                steps: [
                  BeforeMigrationStep(
                    description: "Rename the status column",
                    execute: (callContext) async {
                      await callContext.dbConnexion.executeQuery(
                        "ALTER TABLE orders RENAME COLUMN status TO order_status;",
                        trace: callContext.runningOperation,
                      );
                    },
                  ),
                  AfterMigrationStep(
                    description: "Default status of legacy orders",
                    execute: (callContext) async {
                      await callContext.dbConnexion.executeQuery(
                        "UPDATE orders SET order_status = 'pending' WHERE order_status IS NULL;",
                        trace: callContext.runningOperation,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      );
}
```

- `MajorVersion` is abstract: declare one class per major version, with a **default (no-argument) constructor**. The generator instantiates it through this constructor to compute the model version and emits `Xxx$Layer.majorVersions` from it.
- Every `ModelVersion` (`MajorVersion`, `MinorVersion`, `PatchVersion`) accepts `description`, `releaseDate`, `releaseNotes` and `executeOnEmptyDb` (default `true`; when `false`, the version and everything under it is skipped on a database that has never been migrated).
- `PatchVersion(steps:)` holds the `MigrationStep`s. Its `description` defaults to the descriptions of its steps.
- `BeforeMigrationStep` and `AfterMigrationStep` take `description`, `execute` (`Future Function(CallContext context)`) and `alwaysExecute` (default `false`; when `true` the step runs on every migration whatever the recorded version).

### 2.2. Numbering

Versions are **numbered by position**, never by hand (`SemanticVersion` `major.minor.patch`): the first `MajorVersion` is `0.0.0`, the next ones increment the major number; each `MinorVersion` increments the minor number, each `PatchVersion` the patch number. `ModelVersions.lastVersion` is the version of the model and `Xxx$Layer.version` carries it as a string (`"0.0.0"` for a model without any version).

### 2.3. Versions and registry

- `ServerDataRegistry.version` / `ownVersion`: the version of the model's own layer (same value).
- `ServerDataRegistry.modelVersions`: the `majorVersions` of every server layer, numbered as one chain.
- `ServerDataRegistry.layerVersions`: one `ModelLayerVersions(modelName:, versions:)` per layer, each numbered **independently**, lowest layer first.
- `ServerDataRegistry.layerVersionChain`: `layerVersions` in the form recorded by the application, `"Base=1.1.1;OrderHub=2.1.8"` (`formatVersionChain`, parsed back by `parseVersionChain`).

A [sub-model](SUBMODELS.md) numbers its versions without knowing the applications built on it: its patches are compared to its own layer's recorded version.

## 3. Running a migration

### 3.1. Application side

The framework does not store the reached version: the application records `layerVersionChain` where it wants (file, table, ...) and passes it back. `migrateDatabase` requires a `CallContext`, obtained from `startOperation` (from `example/orderhub_server/bin/orderhub_server.dart`):

```dart
Future migrateDatabase(
  OrderHubServerRegistry dataRegistry,
  Account migrationAccount,
) async {
  final currentVersionChain = getCurrentVersionChain();
  if (currentVersionChain == dataRegistry.layerVersionChain) return;
  await dataRegistry.startOperation(
    "Run migration",
    executor: (callContext) async {
      await dataRegistry.migrateDatabase<OrderHubServerRegistry>(
        callContext,
        fromVersionChain: currentVersionChain,
      );
      await setCurrentVersionChain(dataRegistry, dataRegistry.layerVersionChain);
    },
    userAccount: migrationAccount,
  );
}
```

`migrateDatabase<R extends ServerDataRegistry>(callContext, {String? fromVersionChain})` returns `dataRegistry.version`. `fromVersionChain` null, empty or unparseable means an empty database: every step runs (except versions with `executeOnEmptyDb: false`). A layer missing from the chain replays all of its steps.

### 3.2. Execution order

```
startOperation(...) → CallContext
  │
  ▼
Migration(dataRegistry:, fromVersionChain:).migrateDatabase(callContext)
  │
  ├─ 1. every BeforeMigrationStep of the selected patches, layer by layer
  ├─ 2. DDL orders computed from the model vs. the introspected database
  │       (create/drop schemas and tables; add, update and DROP columns absent
  │        from the model; primary keys; indexes; enum rows; foreign keys
  │        created DEFERRABLE INITIALLY DEFERRED NOT VALID)
  ├─ 3. every AfterMigrationStep of the selected patches, layer by layer
  └─ 4. SET CONSTRAINTS ALL IMMEDIATE, then VALIDATE CONSTRAINT on the foreign
        keys still unvalidated
```

A step is selected when `alwaysExecute` is true or when its patch version is greater than the version recorded for its layer. Selected steps run in declaration order.

Everything runs on the connection of `callContext`, in **one transaction**: the DDL orders see what a `BeforeMigrationStep` wrote, an `AfterMigrationStep` can repopulate the tables the DDL created, and a failure at any step rolls back the whole migration (PostgreSQL DDL is transactional). The operation is traced under `OperationType.migration`.

### 3.3. Writing a step

`execute` receives the `CallContext` of the migration. Raw SQL goes through `callContext.dbConnexion.executeQuery(sql, trace: callContext.runningOperation, params:, rowCount:)`; the [query API](QUERIES.md) and the [services](SERVICES.md) of the model are usable as in any operation, on the structures existing at that point (before or after the DDL orders).

Steps must be **idempotent** (a step can be replayed when the recorded chain is lost or when `alwaysExecute` is true): use `IF EXISTS` / `IF NOT EXISTS`, `ON CONFLICT DO NOTHING`, or check the state before writing.

## 4. Typical cases

### 4.1. Additive change

Adding a nullable field, an entity, an index: no step needed, the DDL orders cover it.

### 4.2. Renaming or removing a field with data to keep

The model only knows the target name: without a step, the DDL orders add the target column and **drop** the old one (a column absent from the model is dropped, a table absent from the model too). Declare a `BeforeMigrationStep` that renames the old column (or copies its data elsewhere): the DDL orders are computed after the `BeforeMigrationStep`s and then see the renamed column as already there (see § 2.1). An `AfterMigrationStep` completes the data once the structures exist.

### 4.3. Seed data

An `AfterMigrationStep` with `ON CONFLICT DO NOTHING`, or `alwaysExecute: true` when the data must be reconciled on every migration.

### 4.4. Data conversion irrelevant on a fresh database

Set `executeOnEmptyDb: false` on the version: its steps only make sense to convert pre-existing rows, and would otherwise act on seed data that nothing references yet.

## 5. Troubleshooting

- **Migration fails**: nothing is committed. Fix the step or the data, restart the application; the whole migration runs again.
- **Chain recorded in an older or unknown form**: `parseVersionChain` returns null and the database is migrated as an empty one (all steps of all layers run). Make sure they are idempotent.
- **`Sub-version ... already has a version assigned`**: a `ModelVersion` instance is shared between two trees. `Xxx$Layer.majorVersions` must return fresh instances on every read (the registry numbers them twice: merged chain, then per layer); the generated layer does so as long as each `MajorVersion` subclass builds its tree in its default constructor.

## 6. See Also

- [Server application](APP_SERVER.md) for the startup sequence.
- [Sub-models](SUBMODELS.md) for layer versions.
- Migration implementation: `sing_server/lib/src/migration/migration.dart`, `sing_server/lib/src/migration/migrator/`.
