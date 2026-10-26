# Migrations and Model Versions

This document explains how Sing brings a PostgreSQL database up to the model: what the migration does on its own, how to declare model versions, and how to write the steps it cannot infer.

## 1. Overview

The model is the source of truth for the database schema. A migration (`sing_server/lib/src/migration/migration.dart`) does three things, in one transaction:

1. it runs the custom `BeforeMigrationStep`s declared in the model versions;
2. it introspects the database and runs the **DDL orders** that align it on the model (schemas, tables, columns, primary keys, indexes, foreign keys, enum tables);
3. it runs the custom `AfterMigrationStep`s, then validates the foreign keys.

What is **automatic**: everything the model describes (structure, enum rows). What is **manual**: any data the DDL cannot infer (renames, type conversions, filling NULL values, seed data). You write it as a migration step attached to a model version.

The application calls the migration itself, usually at server startup. Sing does not store the version reached by the database: the application does.

## 2. Model versions

### 2.1. Declaration

Versions are declared with `Model(majorVersions:)`. The tree is `MajorVersion` → `MinorVersion` → `PatchVersion`. Only a `PatchVersion` carries steps. The classes come from `sing_server` (exported by the model package's `lib/model.dart`).

```dart
// model/lib/model/model.dart
Model createOrderHubModel() => Model(
  modelName: "OrderHub",
  rootNameSpace: OrderHubNameSpace(),
  majorVersions: [V1()],
  clientPackagePath: "../model_sing_client",
  commonPackagePath: "../common",
);

// model/lib/model/versions/v1.dart
class V1 extends MajorVersion {
  V1()
    : super(
        description: "First release",
        minorVersions: [
          MinorVersion(
            description: "Order notes are mandatory",
            executeOnEmptyDb: false,
            patches: [
              PatchVersion(
                steps: [
                  BeforeMigrationStep(
                    description: "Fill empty order notes",
                    execute: (callContext) => callContext.dbConnexion.executeQuery(
                      "UPDATE ${$Order.ofContext(callContext).qualifiedName} "
                      "SET notes = '' WHERE notes IS NULL;",
                      trace: callContext.runningOperation,
                    ),
                  ),
                ],
              ),
            ],
          ),
          lowStockVersion(),
        ],
      );
}

MinorVersion lowStockVersion() => MinorVersion(
  description: "Default low stock threshold",
  patches: [
    PatchVersion(
      steps: [
        AfterMigrationStep(
          description: "Low stock threshold of tracked products",
          execute: (callContext) => callContext.dbConnexion.executeQuery(
            "UPDATE ${$Product.ofContext(callContext).qualifiedName} "
            "SET low_stock_threshold = 5 "
            "WHERE track_inventory AND low_stock_threshold IS NULL;",
            trace: callContext.runningOperation,
          ),
        ),
      ],
    ),
  ],
);
```

- The column names in SQL are the snake_case field names (see [field naming](DATA_MODEL.md#10-database-names)). `$Order.ofContext(callContext).qualifiedName` gives the `schema.table` name of an entity in the current model.
- The first minor version only converts existing rows: `executeOnEmptyDb: false` skips it on an empty database, where the order table does not exist yet when the `BeforeMigrationStep`s run.
- Both steps are idempotent: running them twice changes nothing.

### 2.2. Rules the builder enforces

`sing_emit` computes the layer version by reading the source code, without running it (`sing_builder/lib/analyser/entry/model_reader.dart`). So the declaration must have a fixed shape:

- `majorVersions:` is a plain list literal of constructor calls: `[V0(), V1()]`. No spread, no `if`, no `for`, no variable.
- Each `MajorVersion` subclass has a **default constructor without arguments**. It passes `minorVersions:` as a plain list in its `super(...)` call. The generated `Xxx$Layer.majorVersions` calls this constructor (`[V0(), V1()]`), so it returns fresh instances on every read.
- A minor version is written `MinorVersion(...)`, or as a call to a function whose body is `=> MinorVersion(...)` (like `lowStockVersion()` above).
- `patches:` is a plain list. The builder only counts the patches, so a patch can come from any function call.

A declaration that breaks these rules stops `sing_emit` with a `ModelEntryError`. After any change to the versions, run `dart run sing_builder:sing_emit` again: `Xxx$Layer.version` is a generated constant.

### 2.3. Options of a version and of a step

- Every version (`MajorVersion`, `MinorVersion`, `PatchVersion`) accepts `description`, `releaseDate`, `releaseNotes` and `executeOnEmptyDb` (default `true`). With `executeOnEmptyDb: false`, the version and everything under it is skipped when the database is migrated as an empty one (see § 3.2).
- `PatchVersion(steps:)` holds the steps. Its `description` defaults to the descriptions of its steps.
- `BeforeMigrationStep` and `AfterMigrationStep` take `description` (required), `execute` (required, `Future Function(CallContext context)`) and `alwaysExecute` (default `false`). With `alwaysExecute: true`, the step runs on every migration, whatever the recorded version.

### 2.4. Numbering

Versions are numbered **by position**, never by hand (`SemanticVersion`, `major.minor.patch`, see `sing_server/lib/src/migration/migrator/version.dart`):

- the first `MajorVersion` is `0.0.0`, the next ones are `1.0.0`, `2.0.0`, ...;
- each `MinorVersion` adds one to the minor number: `x.1.0`, `x.2.0`, ...;
- each `PatchVersion` adds one to the patch number: `x.y.1`, `x.y.2`, ...

The version of the model is its last patch (or last minor, or last major when it has no child). In the example of § 2.1, `V1` is `0.0.0`, its two minors are `0.1.0` and `0.2.0`, their patches are `0.1.1` and `0.2.1`, and `OrderHub$Layer.version` is `"0.2.1"`. A model without versions has version `"0.0.0"`.

**Only append.** A step runs on an existing database only if its patch number is greater than the recorded one. A patch inserted into an older minor gets a number lower than the recorded version: it never runs on existing databases. Put each new step in a new `PatchVersion` at the end of the last `MinorVersion`, or in a new `MinorVersion` or `MajorVersion`. Never remove or reorder a version that a database has already reached.

### 2.5. Versions in the registry

| Member | Value |
|---|---|
| `Xxx$Layer.version` | the model's own version, as a string (`"0.2.1"`) |
| `ServerDataRegistry.version`, `ownVersion` | the version of the top layer (the model itself) |
| `ServerDataRegistry.versionChain` | the version of each layer joined by `-` (`"0.0.0-0.2.1"`) |
| `ServerDataRegistry.layerVersions` | one `ModelLayerVersions(modelName:, versions:)` per layer, lowest layer first, each numbered on its own |
| `ServerDataRegistry.layerVersionChain` | `layerVersions` as the string to store: `"CoverageBase=0.0.0;Coverage=0.2.1"` (`formatVersionChain`, read back by `parseVersionChain`) |
| `ServerDataRegistry.modelVersions` | the `majorVersions` of all layers, numbered as one chain (not used to select steps) |

A [sub-model](SUBMODELS.md) has its own `majorVersions`. It numbers them without knowing the models that mount it: its patches are compared to the version recorded for its own layer name.

## 3. Running a migration

### 3.1. At server startup

`migrateDatabase` needs a `CallContext`. Get one with `startOperation`. Record the new chain in the same operation, so it is committed with the migration:

```dart
Future<void> migrateDatabase(
  OrderHubServerRegistry dataRegistry,
  Account migrationAccount,
) async {
  await dataRegistry.startOperation(
    "Run migration",
    userAccount: migrationAccount,
    executor: (callContext) async {
      final fromVersionChain = await readVersionChain(callContext);
      await dataRegistry.migrateDatabase<OrderHubServerRegistry>(
        callContext,
        fromVersionChain: fromVersionChain,
      );
      await writeVersionChain(callContext, dataRegistry.layerVersionChain);
    },
  );
}
```

`readVersionChain` and `writeVersionChain` are application code (see § 3.3). `example/orderhub_server/bin/orderhub_server.dart` shows the same structure with stubs.

- Signature: `Future<String> migrateDatabase<T extends ServerDataRegistry>(CallContext callContext, {String? fromVersionChain})`. It returns `dataRegistry.version`.
- **Call it on every startup.** On an up-to-date database it runs no DDL order and no step (except `alwaysExecute` steps). If you skip the call when the stored chain equals `layerVersionChain`, a model change made without a new version is never applied to the database.
- A dedicated migration process run before the server also works: the server binary then does not need the migration code.

### 3.2. Which steps run

`fromVersionChain` is the `layerVersionChain` stored after the previous migration.

- `null`, empty, or not readable by `parseVersionChain`: the database is treated as **empty**. Every step of every layer runs, except the versions declared `executeOnEmptyDb: false`.
- A layer missing from the chain: all steps of that layer run.
- Otherwise a step runs when `alwaysExecute` is `true`, or when its patch version is greater than the version recorded for its layer.

Selected steps run in declaration order, layer by layer, lowest layer first.

### 3.3. Storing the version chain

Sing does not store the chain. Use a file, or a table. Pitfall: the migration **drops every table it does not know** in the schemas of the model and in the system schema (`sing` by default, `SqlNames.systemSchema`). A hand-made table in one of these schemas is dropped at the next migration. Put it in a schema that no entity uses, or make it an entity of the model.

### 3.4. Execution order

```
startOperation(...) → CallContext
  └─ dataRegistry.migrateDatabase(callContext, fromVersionChain: ...)
       ├─ 1. every selected BeforeMigrationStep
       ├─ 2. introspect the database, compute and run the DDL orders
       ├─ 3. every selected AfterMigrationStep
       └─ 4. SET CONSTRAINTS ALL IMMEDIATE, then VALIDATE CONSTRAINT
             on every foreign key still not validated
```

Everything runs on the connection of `callContext`, in **one transaction**, without sub-transactions. Consequences:

- the DDL orders are computed **after** the `BeforeMigrationStep`s, so they see what these steps changed (a renamed column is already in place);
- an `AfterMigrationStep` sees the final structure and can fill tables the DDL just created;
- a failure at any point rolls back everything (PostgreSQL DDL is transactional). Fix the cause and restart: the whole migration runs again.

The operation is traced with `OperationType.migration`; each step appears under its `description`.

### 3.5. Inspecting a migration without running it

`Migration` exposes what a migration would do:

```dart
final migration = Migration<ServerDataRegistry>(
  dataRegistry: dataRegistry,
  fromVersionChain: storedChain,
);
final orders = await migration.getDdlOrders(callContext);
for (final order in orders) {
  print(order.description);
}
final steps = migration.migrationSteps;
```

On a migrated database, `getDdlOrders` returns no order. Tests use this to check that a migration is idempotent (`coverage/coverage_model/test/migration_idempotence_test.dart`).

## 4. What the DDL orders do

The orders are computed in `sing_server/lib/src/migration/model.dart` and formatted in `sing_server/lib/src/db/ddl_formater.dart`.

### 4.1. Automatic changes

| Model change | DDL order |
|---|---|
| New schema (namespace with a new `@DbName`) | `CREATE SCHEMA` |
| New entity | `CREATE TABLE`, its foreign keys and indexes |
| New field | `ADD COLUMN` (with `NOT NULL` and `DEFAULT` from the model) |
| Field type, length, default or nullability change | `ALTER COLUMN ... SET DATA TYPE / SET DEFAULT / DROP DEFAULT / SET NOT NULL / DROP NOT NULL` |
| New or removed index | `CREATE INDEX` / `DROP INDEX` (an existing index on the same columns with the same uniqueness is kept) |
| New or removed reference | `ADD FOREIGN KEY ... DEFERRABLE INITIALLY DEFERRED NOT VALID` / `DROP CONSTRAINT` |
| Primary key change | drop and create the primary key, then drop and recreate the foreign keys that point to it |
| Enum value added, changed or removed | `INSERT` / `UPDATE` / `DELETE` in the enum table (see § 4.4) |

### 4.2. Destructive changes

Sing never refuses a change. It never renames anything either: there is no `RENAME` and no `SET SCHEMA` in the DDL orders. So:

- a **column** that is not in the model is **dropped** (`DROP COLUMN`);
- a **table** that is not in the model, in one of the model's schemas or in the system schema, is **dropped** (`DROP TABLE ... CASCADE`);
- a renamed field, a renamed entity, a changed `@DbName`, or an entity moved to another namespace (another schema) all look like "drop the old one, create the new one": **the data is lost** unless a `BeforeMigrationStep` renames or moves it first (§ 5.2).

Not touched: schemas (never dropped) and tables in schemas that the model does not use.

### 4.3. NOT NULL transitions

- **New column, not nullable, with a constant `defaultValue`**: a single `ADD COLUMN ... NOT NULL DEFAULT <value>`. PostgreSQL fills the existing rows. The [row version column](DATA_MODEL.md#9-row-version-column) `_version` is added to existing tables this way.
- **New column, not nullable, without default**: `ADD COLUMN ... NOT NULL` fails if the table has rows. Add a `defaultValue`, or add the column nullable in one version and make it not nullable in a later one, after an `AfterMigrationStep` fills it.
- **Existing column becoming not nullable, with a `defaultValue`**: Sing first runs one `UPDATE ... SET col = <default> WHERE col IS NULL` per column, then one `SET NOT NULL` order for all of them.
- **Existing column becoming not nullable, without default**: `SET NOT NULL` fails if NULL values remain. Fill them in a `BeforeMigrationStep` (example in § 2.1).

### 4.4. Type changes and enums

A type change is a plain `ALTER COLUMN ... SET DATA TYPE <type>`, without `USING`. The only exception is a change to `uuid`, which adds `USING col::uuid`. So:

- casts that PostgreSQL does implicitly work (a longer `varchar`, `int2` to `int4`, ...);
- other conversions fail (`varchar` to `int`, text that is not a UUID to `uuid`), and so does a shorter `varchar` when longer values exist. Convert or clean the data in a `BeforeMigrationStep`. If the conversion needs a new structure, add a new column, fill it in an `AfterMigrationStep`, and drop the old field in a later version.

An `EnumField` stores the enum `key` (`varchar` or `int2`), with a foreign key to an enum table `<systemSchema>.<ident>` (columns `uuid`, `key`, `name`, `index`), `ON UPDATE CASCADE`. The migration aligns the rows of this table on the Dart enum **by `uuid`**:

- new value: `INSERT`;
- value with a changed key, name or index: `UPDATE` of that row; `ON UPDATE CASCADE` updates the data columns;
- value removed from the enum: `DELETE`. If rows still use it, the `onDelete` rule of the `EnumField` applies. The default (`ReferentialAction.error`) makes the migration fail: move these rows to another value in a `BeforeMigrationStep`.

So keep the `uuid` of an enum value stable: a new uuid means "remove the old value, add a new one".

For legacy columns, `sing_server/lib/src/migration/enum_conversion.dart` provides helpers to call from a `BeforeMigrationStep`:

- `convertNativeEnumColumn(callContext, qualifiedTable:, columnName:, def:)`: native PostgreSQL `ENUM` column to `varchar`, labels remapped to keys;
- `remapLegacyEnumIntColumn(callContext, qualifiedTable:, columnName:, def:)`: integer column holding the enum index, remapped to keys;
- `dropNativeEnumType(callContext, qualifiedTypeName)`: drops the native type after its last column is converted.

`def` is the `DbEnumDef` of the enum. These helpers are idempotent.

## 5. Writing steps

### 5.1. Rules

- `execute` receives the migration `CallContext`. Raw SQL goes through `callContext.dbConnexion.executeQuery(sql, trace: callContext.runningOperation, params:, rowCount:)`. The [query API](QUERIES.md) and the [services](SERVICES.md) work as in any operation, but only on the structures that exist at that moment.
- In a `BeforeMigrationStep`, the database has the **old** structure. Use raw SQL, and check that the objects exist (`IF EXISTS`): on an empty database the tables do not exist yet. The query API describes the new model and can fail on the old structure.
- In an `AfterMigrationStep`, the database has the **new** structure: the query API and services are safe.
- Steps must be **idempotent**. A step runs again when the stored chain is lost or unreadable, on an empty database, and on every migration with `alwaysExecute: true`. Use `IF EXISTS` / `IF NOT EXISTS`, `ON CONFLICT DO NOTHING`, or read the state before writing.
- Steps are Dart code compiled with the model: a step that uses the query API breaks at compile time when the field it names is renamed. Keep all steps since the first version.

### 5.2. Rename a field, an entity or a schema without losing data

The model only knows the new name. Rename in a `BeforeMigrationStep`: the DDL is computed afterwards and finds the structure already conform.

```dart
PatchVersion renameOrderNotes() => PatchVersion(
  steps: [
    BeforeMigrationStep(
      description: "Rename column comment to notes",
      execute: (callContext) async {
        final table = $Order.ofContext(callContext).qualifiedName;
        final found = await callContext.dbConnexion.executeQuery(
          "SELECT 1 FROM information_schema.columns "
          "WHERE table_schema || '.' || table_name = '$table' "
          "AND column_name = 'comment';",
          trace: callContext.runningOperation,
        );
        if (found.isEmpty) return;
        await callContext.dbConnexion.executeQuery(
          "ALTER TABLE $table RENAME COLUMN comment TO notes;",
          trace: callContext.runningOperation,
        );
      },
    ),
  ],
);
```

- Entity renamed: `ALTER TABLE <schema>.<old> RENAME TO <new>`.
- Entity moved to another schema: `CREATE SCHEMA IF NOT EXISTS <new>`, then `ALTER TABLE <old_schema>.<table> SET SCHEMA <new>`.
- Always guard with an existence check, as above: the step also runs on an empty database (unless its version has `executeOnEmptyDb: false`), and runs again when the chain is lost.
- `ofContext(callContext).qualifiedName` gives the **new** names only. Write the old names as literals. Sing adds `_` to a name that is a reserved SQL word (`order` becomes `order_`): check the real names in the database.

### 5.3. Seed or reference data

An `AfterMigrationStep` that inserts with `ON CONFLICT DO NOTHING` (or `ON CONFLICT ... DO UPDATE`), or the query API, which is safe after the DDL. Use `alwaysExecute: true` when the data must be reconciled on every migration (reference tables loaded from a file, for example).

### 5.4. Conversion of existing data only

Set `executeOnEmptyDb: false` on the version (often a whole `MinorVersion`). Its steps only convert rows of older versions. On an empty database the DDL already creates the final structure, and the steps would only act on seed data.

## 6. Troubleshooting

- **The migration fails**: nothing is committed. Read the failing SQL in the operation trace (`OperationType.migration`), fix the step or the data, restart.
- **A new step does not run**: its patch number is not greater than the recorded version (patch inserted into an older minor, see § 2.4), or `sing_emit` was not run after the change.
- **A model change is not applied**: the application skipped `migrateDatabase` because the stored chain was equal to `layerVersionChain` (see § 3.1).
- **Data disappeared after a rename**: the DDL dropped the old column or table (§ 4.2). Restore it and add a `BeforeMigrationStep` that renames it.
- **All steps ran again**: the stored chain was `null`, empty or not readable. Make sure steps are idempotent.
- **`Sub-version ... already has a version assigned`**: one `ModelVersion` instance belongs to two trees. Build every version inside the default constructor of its `MajorVersion` (or in a function called there), never in a shared `final` or `static` variable.
- **`ModelEntryError` from `sing_emit`**: the version declaration breaks a rule of § 2.2.

## 7. See also

- [Server application](APP_SERVER.md): startup sequence.
- [Sub-models](SUBMODELS.md): layers and their versions.
- [Testing](TESTING.md): resetting a test database with a migration.
- Source: `sing_server/lib/src/migration/migration.dart`, `sing_server/lib/src/migration/model.dart`, `sing_server/lib/src/migration/migrator/`, `sing_server/lib/src/migration/enum_conversion.dart`, `sing_server/lib/src/db/ddl_formater.dart`.
