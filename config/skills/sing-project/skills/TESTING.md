# Testing a Sing Application

Sing exports **no test helper**. This page shows the patterns to copy into your own test folder. They come from the tests of the Sing repository: `example/model/test/cube_sql_test.dart`, `example/model/test/view_resolution_test.dart`, `coverage/coverage_model/test/support.dart`.

## 1. Which Kind of Test?

| Goal | Setup | Database |
| --- | --- | --- |
| Check the SQL a service or query builds | server registry over a fake `ServerDataControler` (section 2) | none |
| Feed canned rows to server code | same fake, with an answer per SQL order (2.3) | none |
| Check real behavior: constraints, migrations, results | server registry over `PgDataControler` (section 3) | PostgreSQL |
| Build client objects without a server | client registry over `DebugClientDataControler` (section 5) | none |

All server tests run code the same way: `registry.startOperation(...)` gives a `CallContext`, as in production (see [APP_SERVER.md](APP_SERVER.md)).

## 2. Server Registry Without a Database

### 2.1. The Fake Controler

Copy these two classes into a test support file. They capture the last SQL order instead of running it:

```dart
import "package:model/model.dart";
import "package:model/sing/server.dart";

class CapturingConnexion extends DbConnexion {
  String? sql;
  Map<String, dynamic>? params;

  @override
  final String transactionUuid = "test-transaction";

  // A fresh provider per connexion: bound parameters must not pile up.
  @override
  SqlProvider get sqlProvider => _sqlProvider ??= SqlProvider();
  SqlProvider? _sqlProvider;

  @override
  Future<List<List>> executeQuery<E extends ServerEntityDef>(
    String sql, {
    required Operation trace,
    Map<String, dynamic>? params,
    bool rowCount = false,
  }) async {
    this.sql = sql;
    this.params = params;
    return const [];
  }

  @override
  Future executeDdlOrders(Iterable<DdlOrder> orders, Operation trace) async =>
      throw UnimplementedError();

  @override
  Future<Iterable<DbTable>> getDbTables({
    required Operation trace,
    Iterable<String>? inSchemas,
    String? tableName,
  }) async => const [];

  @override
  Future<Set<String>> getDbSchemas(Operation trace) async => const {};
}

class FakeControler extends ServerDataControler {
  FakeControler(this.connexion);

  final CapturingConnexion connexion;

  @override
  final SqlNames sqlNames = SqlNames();

  @override
  void initCallContext(CallContext context) {}

  @override
  Future<R> openConnexion<R>(
    TransactionedExecution<R> onConnected,
    Operation trace, {
    bool nested = false,
  }) => onConnected(connexion);

  @override
  Future onTerminate() async {}
}
```

`package:model/sing/server.dart` is the generated server library of your model. It exports `sing_server`.

### 2.2. Run Code and Check the SQL

```dart
test("pending orders filter on status", () async {
  final connexion = CapturingConnexion();
  final registry = OrderHubServerRegistry(dataControler: FakeControler(connexion));
  await registry.startOperation(
    "pending orders test",
    userAccount: Account.system("test"),
    executor: (callContext) => $Order
        .services(callContext)
        .search(
          callContext: callContext,
          filters: Order$Search(status: Search.equal(OrderStatus.pending)),
        )
        .list(),
  );
  final sql = connexion.sql!.replaceAll(RegExp(r"\s+"), " ");
  expect(sql, contains("WHERE"));
  expect(sql, contains("status ="));
});
```

- Collapse white space before `contains`: the SQL is formatted on several lines.
- `connexion.params` holds the bound values. Check them to catch a value bound with the wrong type.
- `CapturingConnexion` keeps only the last order. To keep all of them, store a list.

### 2.3. Feed Canned Rows

Return rows from `executeQuery`. Each row is a list of column values, in the order of the `SELECT`:

```dart
typedef Answer = List<List> Function(String sql);

// In the connexion:
@override
Future<List<List>> executeQuery<E extends ServerEntityDef>(
  String sql, {
  required Operation trace,
  Map<String, dynamic>? params,
  bool rowCount = false,
}) async {
  journal.add(sql);
  return answer(sql);
}
```

Answer by SQL content when one operation runs several queries, for example `sql.contains("order_line") ? [[orderUuid, 2]] : [[orderUuid]]`. These tests depend on the column order Sing generates: keep them few and focused.

## 3. Server Registry on a Real PostgreSQL

### 3.1. Read the Connection From the Environment

```dart
import "dart:io";

import "package:sing_postgresql/sing_postgresql.dart";

({Endpoint endpoint, SslMode sslMode})? testEndpoint() {
  final env = Platform.environment;
  final database = env["SING_TEST_PG_DATABASE"];
  if (database == null || database.isEmpty) return null;
  return (
    endpoint: Endpoint(
      host: env["SING_TEST_PG_HOST"] ?? "localhost",
      port: int.tryParse(env["SING_TEST_PG_PORT"] ?? "") ?? 5432,
      database: database,
      username: env["SING_TEST_PG_USER"] ?? "sing_test",
      password: env["SING_TEST_PG_PASSWORD"] ?? "sing_test",
    ),
    sslMode: SslMode.values.firstWhere(
      (mode) => mode.name == (env["SING_TEST_PG_SSLMODE"] ?? "disable"),
      orElse: () => SslMode.disable,
    ),
  );
}
```

The `SING_TEST_PG_*` names are a convention of the Sing repository. Your application can choose its own names.

### 3.2. Reset the Schema, Migrate, Seed

```dart
@Tags(["postgres"])
library;

import "package:model/model.dart";
import "package:model/sing/server.dart";
import "package:sing_postgresql/sing_postgresql.dart";
import "package:test/test.dart";

import "support.dart";

void main() {
  final config = testEndpoint();

  group(
    "orders against a real database",
    skip: config == null ? "set SING_TEST_PG_DATABASE to run" : null,
    () {
      late ServerDataRegistry registry;

      Future<T> run<T>(Future<T> Function(CallContext callContext) body) =>
          registry.startOperation(
            "orders test",
            userAccount: Account.system("test"),
            executor: body,
          );

      setUpAll(() async {
        registry = OrderHubServerRegistry(
          dataControler: PgDataControler(
            endpoint: config!.endpoint,
            settings: PoolSettings(sslMode: config.sslMode),
          ),
        );
        await run((callContext) async {
          for (final schema in ["orders", "products"]) {
            await callContext.dbConnexion.executeQuery(
              'drop schema if exists "$schema" cascade;',
              trace: callContext.runningOperation,
            );
          }
        });
        await run(
          (callContext) =>
              registry.migrateDatabase<ServerDataRegistry>(callContext),
        );
        await run((callContext) async {
          final customer = Customer$Instance(
            $Customer.ofContext(callContext).createDataRow(),
          );
          customer.name.value = "test customer";
          // Set every required field, then insert.
          await $Customer.query(callContext).insertRow(customer.$dataRow).execute();
        });
      });

      test("...", () async {
        await run((callContext) async {
          // Query and expect.
        });
      });
    },
  );
}
```

- The schema list must name the schemas of your namespaces (their `dbName`). Use a dedicated test database: this drops data.
- Run each step in its own `startOperation`: each one is its own transaction.
- Give test data a marker (a name prefix) and filter on it. Tests of one file share the database.

### 3.3. `dart_test.yaml`

```yaml
tags:
  postgres: {}
concurrency: 1
```

`concurrency: 1` is required: test files that drop and migrate the same schemas must not run at the same time.

### 3.4. Capture the SQL of a Real Run

`registry.operations` streams every operation. SQL orders are `SqlOperation`s with `sqlOrder` and `params`:

```dart
Future<({T result, List<String> statements})> traced<T>(
  Future<T> Function(CallContext callContext) body,
) async {
  final operations = <SqlOperation>{};
  final subscription = registry.operations
      .where((operation) => operation is SqlOperation)
      .listen((operation) => operations.add(operation as SqlOperation));
  final result = await run(body);
  await pumpEventQueue();
  await subscription.cancel();
  return (
    result: result,
    statements: [for (final operation in operations) operation.sqlOrder],
  );
}
```

- Each operation is emitted twice (at start and at end). Collect them in a `Set` to keep one copy.
- `await pumpEventQueue()` before `cancel()`: the stream delivers events later.

## 4. Access Rights and Errors

Run as a real user to test token checks:

```dart
Account("stranger", displayName: "Stranger");
Account("reader", displayName: "Reader", tokens: [$Order.tokens.read]);
```

`Account.system(...)` bypasses token checks. Do not use it to test access rights.

Expect an `AppError` by its code:

```dart
expect(
  () => run((callContext) => /* call */),
  throwsA(
    isA<AppError>().having((e) => e.code, "code", "sing.errors.accessDenied"),
  ),
);
```

Some framework errors are plain `String`s (for example cube definition errors): use `throwsA(contains("..."))`. A missing view hook throws a `StateError`: use `throwsStateError`. See [ERRORS.md](ERRORS.md) and [ACCESS_CONTROL.md](ACCESS_CONTROL.md).

## 5. Client Registry Without a Server

`DebugClientDataControler` (from `sing_client`) is a client controler with no network. Service calls throw `UnimplementedError`. Version checks are off. Use it to build client rows, field views, search filters or a `CubeDefinition` in a test.

The client registry needs the model definition the server publishes. Take it from a server registry, through JSON:

```dart
import "dart:convert";

import "package:model_sing_client/client.dart" as client;
import "package:sing_client/sing_client.dart" show DebugClientDataControler;

final server = OrderHubServerRegistry(dataControler: FakeControler(CapturingConnexion()));
final modelField =
    jsonDecode(jsonEncode(server.modelDefinition())) as Map<String, Object?>;
final registry = client.OrderHubClientRegistry(
  dataControler: DebugClientDataControler(),
  modelField: modelField,
);
```

Adapt the client import to the library your generated client package exports.

## 6. Pitfalls

- **Silent skip.** Without the database variables, the database groups are skipped and `dart test` still ends with "All tests passed". Check the skip count, or make CI fail when the variables are missing.
- **Parallel files.** Without `concurrency: 1`, two files drop and migrate the same schemas at the same time and fail at random.
- **System account hides access bugs.** Use an `Account` with explicit tokens for access tests.
- **Duplicate operations.** `registry.operations` emits each operation twice.
- **Canned rows are fragile.** They depend on the generated column order. Prefer SQL checks or a real database.
- **A fake controler checks SQL text, not behavior.** A query can render and still fail on PostgreSQL. Keep a few real-database tests for each important query.

## 7. See Also

- [APP_SERVER.md](APP_SERVER.md): registry, operations, `PgDataControler`.
- [MIGRATIONS.md](MIGRATIONS.md): `migrateDatabase`.
- [DEBUGGING.md](DEBUGGING.md): watch the SQL and the traces.
- [CUBE.md](CUBE.md): testing a cube definition.
