# Sing Server Application

A Sing server application depends on the model package (e.g. `model/`). It builds one registry, migrates the database, and usually exposes the services over HTTP with `shelf`.

## 1. The Registry

### 1.1. Build It

Build the registry with the factory generated in `model/lib/sing/server.dart` (exported by `package:model/server.dart`):

```dart
import "package:model/server.dart";
import "package:sing_postgresql/sing_postgresql.dart";

OrderHubServerRegistry createDataRegistry() => OrderHubServerRegistry(
  dataControler: PgDataControler(
    endpoint: Endpoint(
      host: "localhost",
      database: "orderhub",
      username: "orderhub",
      password: "orderhub",
    ),
  ),
);
```

Building the registry opens no connection and does no I/O.

`OrderHubServerRegistry` is an `abstract interface class`. It implements `sing.ServerDataRegistry` and the model interface `OrderHubRegistry<ServerEntityDef>` (generated in `common/lib/src/sing/registry.dart`). Its factory parameters:

| Parameter | Type | Role |
| --- | --- | --- |
| `dataControler` | `ServerDataControler` (required) | Database access, e.g. `PgDataControler`. |
| `debugger` | `DebugPrinter?` | Receives every operation and SQL order, for a debug console or logs. |
| `debugMode` | `bool` | When `true`, an HTTP 500 response carries the exception text. Keep it `false` in production. |

The concrete class is private. Use the interface type, never extend it, never write `ServerDataRegistry(...)`. `OrderHubServerRegistry.modelLayers` lists the layers the registry is built from (`OrderHub$Layer` and the layers of its [sub-models](SUBMODELS.md)).

Create **one** registry per process and keep it for the life of the process. In the rest of this document it is called `dataRegistry`.

### 1.2. PostgreSQL Data Controler

`PgDataControler` (`sing_postgresql/lib/src/controler.dart`):

| Parameter | Default | Role |
| --- | --- | --- |
| `endpoint` | required | `Endpoint` of `package:postgres` (re-exported by `sing_postgresql`). |
| `defaultSchema` | `null` | Schema of tables without an explicit schema. |
| `settings` | `null` | `PoolSettings` of `package:postgres`, re-exported by `sing_postgresql`: `maxConnectionCount` (default 10), `sslMode`, `timeZone`, `applicationName`, ... |
| `idleTimeout` | 5 minutes | Idle connections are closed after this delay. |

Rules:
- The PostgreSQL server must be version 18 or later.
- Never connect with the `postgres` account (assertion).
- `dataControler.poolState` gives the pool state; `limitPool(n)` caps the pool at run time.

### 1.3. Shut Down

Call `await dataRegistry.onTerminate()` before the process ends. It closes the database connections.

## 2. Running Code: CallContext and Operations

Every database access needs a `CallContext`. One `CallContext` is one database transaction plus the `Account` of the caller (`sing_server/lib/src/call_context.dart`).

### 2.1. Start an Operation

Outside of an HTTP call (startup, batch, timer), open a transaction with `startOperation`:

```dart
final order = await dataRegistry.startOperation(
  "Load one order",
  userAccount: Account.system("orderhub_batch"),
  executor: (callContext) => $Order
      .services(callContext)
      .loadThisKey(callContext: callContext, key: orderUuid)
      .exactlyOne(),
);
```

- `lib` (first argument): label of the operation in traces.
- `userAccount` (required): who runs the code. Use `Account.system(...)` for technical work. `Account.system` holds `AccessToken.system`, which grants every token.
- The transaction commits when `executor` returns, and rolls back when it throws. The exception is then rethrown.
- `startOperation` returns what `executor` returns.

`dataRegistry.call(executor, userAccount: ..., operation: Operation.root(dataRegistry, "label"))` does the same with an operation you created yourself.

`dataRegistry.startGlobalOperation(lib, executor: (trace) async {...})` gives an `Operation` without transaction. Use it to group several transactions under one trace.

### 2.2. Inside a Transaction

The `CallContext` gives the caller `userAccount`, the `dataRegistry`, the services (`services<S>()`), and the transaction tools: `mustRollback(true)`, `subTransaction(...)`, `afterCommit(...)`, `TransactionEnded` hooks, the environment (`setEnvironment`, `fromEnvironment<T>`, `getEnvironment<T>`), `clientClock` and traces.

[TRANSACTIONS.md](TRANSACTIONS.md) describes each member, the order of events at the end of a transaction, sub-transactions and their pitfalls.

## 3. Migrations at Startup

Before serving requests, bring the database to the model version. [MIGRATIONS.md](MIGRATIONS.md) explains versions, steps and DDL orders.

- `dataRegistry.layerVersionChain`: the version reached by the model, one version per layer, e.g. `"OrderHub=1.2.0"` or `"CoverageBase=1.0.0;Coverage=1.2.0"`.
- `migrateDatabase<R extends ServerDataRegistry>(callContext, fromVersionChain:)` runs, in one transaction: the before-steps above the recorded version, then the DDL orders, then the after-steps. It returns `dataRegistry.version`.
- `fromVersionChain: null`, an empty string or an unreadable chain means the database was never migrated.
- Storing the reached chain is the job of the application (a table, a file, ...). Store it in the same operation, so it commits with the migration.
- **Call `migrateDatabase` at every startup.** Do not skip it when the stored chain equals `layerVersionChain`: a model change made without a new version would never reach the database. On an up-to-date database the call runs no DDL order.

```dart
Future<void> migrateDatabase(OrderHubServerRegistry dataRegistry) =>
    dataRegistry.startOperation(
      "Run migration",
      userAccount: Account.migration,
      executor: (callContext) async {
        await dataRegistry.migrateDatabase<OrderHubServerRegistry>(
          callContext,
          fromVersionChain: await readVersionChain(callContext),
        );
        await writeVersionChain(callContext, dataRegistry.layerVersionChain);
      },
    );
```

`readVersionChain` and `writeVersionChain` are your code. `Account.migration` is a system account. A failed migration throws and rolls back.

The registry factory returns `OrderHubServerRegistry`, which implements `ServerDataRegistry`. Both types work for the registry variable and for the type argument `R` (`example/orderhub_server/bin/orderhub_server.dart` uses `ServerDataRegistry`). Prefer `OrderHubServerRegistry` in application code: it also gives the typed model interface.

## 4. HTTP Exposure

### 4.1. Mount the Handler

`dataRegistry.processRequest(request:, sessionManager:)` takes a `shelf` `Request` and returns a `shelf` `Response` (`HttpRequest` and `HttpResponse` are typedefs of them). Mount it under a path prefix with `shelf_router`:

```dart
import "dart:io" show ProcessSignal;

import "package:model/server.dart";
import "package:shelf/shelf.dart";
import "package:shelf/shelf_io.dart";
import "package:shelf_router/shelf_router.dart";

Future<void> main(List<String> arguments) async {
  final dataRegistry = createDataRegistry();
  await migrateDatabase(dataRegistry);
  final sessionManager = OrderHubSessionManager(dataRegistry);
  final router = Router()
    ..mount(
      "/app",
      (request) => dataRegistry.processRequest(
        request: request,
        sessionManager: sessionManager,
      ),
    );
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);
  final server = await serve(handler, "0.0.0.0", 8080);
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close();
    await dataRegistry.onTerminate();
  });
}
```

Sing reads `request.url`, which is relative to the mount point. The client then uses `https://host/app` as `singServerUri`.

### 4.2. Routes Served Under the Mount Point

| Route | Method | Answer |
| --- | --- | --- |
| `<mount>/` | GET | `{"uuid": ..., "version": ...}` of the model. No session needed. |
| `<mount>/_model.json` | GET | Model description for the client bootstrap. No session needed. `ETag` + `Cache-Control: no-cache`; answers 304 when `If-None-Match` matches. |
| `<mount>/_openapi.json` | GET | OpenAPI document, filtered by the tokens of the caller. `?ns=<namespace>` limits it to one namespace. Only services under `@openApi` appear. |
| `<mount>/<namespace>/.../<entity>/<service>` | POST | Service call. Example: `/app/orders/orders/addOrder`. |

Service call details:
- Body: a JSON object with one key per parameter (`Content-Type: application/json`), max 32 MiB (413 above).
- GET is also accepted when all required parameters can be read from a query string (strings, numbers, dates, enums, ...).
- `_expect` (body or query): fields, resolutions, sort and page wanted for a `DataLoader` result. The client sets it for you.
- Session key: header `Authorization: Bearer <session key>`.
- Optional checks sent by the client: `X-Sing-Version`, `X-Sing-Model-Version`, `X-Sing-Service-Signature`. A mismatch answers an `AppError` (`sing.errors.incompatibleVersion` or `sing.errors.invalidServiceSignature`).
- `processRequest` answers `OPTIONS` and adds CORS headers (`Access-Control-Allow-Origin: *`, ...) to every Sing response.

Every response carries `X-Sing-Version` (`dataRegistry.version`) and `X-Sing-Model-Version` (`dataRegistry.compiledAt`, ISO 8601).

### 4.3. What a Service Call Does

1. Find the service from the path. Unknown path: `AppError` `sing.errors.unknownService`.
2. Check the service signature header, if present.
3. Get the `Account` from the session key with `sessionManager.accountFromSessionKey`. No key: `Account.anonymous`. A non-empty key with no account: `AppError.sessionExpired()`.
4. Check the access token of the service against the account. Denied: `AppError` `sing.errors.accessDenied`. Search criteria sent by the client are also checked against field and entity read tokens.
5. Open a transaction, decode the parameters, call the service, run the returned `DataLoader`, encode the result.
6. Commit, send the notifications, run the `afterCommit` callbacks.
7. Call `sessionManager.recordHttpCall(sessionKey, duration)`.

## 5. Sessions and Authentication

Sing does not store sessions or check passwords. The application does it, with a session manager and a sign-in service.

### 5.1. Session Manager

Extend `MainSessionManager` (`sing_server/lib/src/session.dart`). It keeps a cache `SessionKey -> Account` (60 minutes after last use by default, `sessionCacheTimeout`). Override `accountFromSessionKey` to load unknown keys from the database:

```dart
class OrderHubSessionManager extends MainSessionManager {
  OrderHubSessionManager(this.dataRegistry);

  final OrderHubServerRegistry dataRegistry;

  @override
  Future<Account?> accountFromSessionKey(
    SessionKey sessionKey,
    Operation trace,
  ) async {
    if (sessionKey.isEmpty) return null;
    final cached = await super.accountFromSessionKey(sessionKey, trace);
    if (cached != null) return cached;
    final account = await dataRegistry.call(
      (callContext) => loadAccountOfSession(callContext, sessionKey),
      userAccount: Account.sessions,
      operation: trace.add("Load session"),
    );
    if (account != null) keepSessionInfo(sessionKey, account);
    return account;
  }
}
```

`loadAccountOfSession` is your code: read the session row, check that it is still open, read the user, and build an `Account` with its tokens.

`MainSessionManager` members:
- `accountFromSessionKey(key, trace)`: the default reads the cache only (`accountFromCache` refreshes the cache delay).
- `keepSessionInfo(key, account)`: put an account in the cache.
- `sessionClosed(key)`: remove a key from the cache (sign-out, revoked rights).
- `recordHttpCall(key, duration)`: called after each service call, outside the transaction. Override it to record activity. Do not write one row per call: batch the writes.

### 5.2. Accounts

`Account` (`sing_core/lib/src/control_access/account.dart`):
- `Account(uuid, displayName: ..., tokens: [...])`: a user. Sing adds `AccessToken(uuid)` to its tokens.
- `Account.system(uuid)`: technical account with `AccessToken.system` (grants everything).
- Predefined: `Account.anonymous` (only `AccessToken.anonymous`), `Account.sessions`, `Account.migration`, `Account.authentificator` (system accounts).

Give a signed-in user `AccessToken.authentified` plus the tokens of the services it can call: Sing does not add `authentified`. See [ACCESS_CONTROL.md](ACCESS_CONTROL.md#13-account).

### 5.3. Sign-In Service

A sign-in service must be callable without session: mark it `@AccessToken.anonymous`. It checks the credentials, stores a new session and returns the key. Sketch, on a session entity `UserSession` of the model:

```dart
mixin UserSessionServices on EntityServerServices<UserSession, String> {
  @AccessToken.anonymous
  Future<String?> signIn({
    required CallContext callContext,
    required String login,
    @notTraced required String password,
  }) async {
    final user = await checkCredentials(callContext, login, password);
    if (user == null) return null;
    final key = SessionKey.generate();
    await $query
        .insertNewRow(
          (values) => values
            ..sessionKey.value = key.sessionKey
            ..user.value = user.$asReference
            ..start.setToNow(callContext),
        )
        .execute();
    return key.sessionKey;
  }

  Future<void> signOut({required CallContext callContext}) async {
    final sessions = callContext.getEnvironment<SessionManager>();
    await closeSession(callContext, sessions.sessionKey);
    sessions.sessionClosed(sessions.sessionKey);
  }
}
```

The client sends the key in the `Authorization: Bearer <key>` header of the next calls. The first call loads the account through `accountFromSessionKey`.

## 6. Results and Errors

### 6.1. Results

| Service returns | HTTP answer |
| --- | --- |
| `DataLoader<E>` | 200, JSON data packet (or a count when the client asks for one). |
| `Future<T>` | 200, JSON of `T`; 204 when the value is `null`. |
| `Future<void>` | 204. |
| `Future<Uint8List>` | 200, `application/octet-stream`. |
| `Future<HttpResponse>` | The response as is. Build it with `HttpResult` (`sing_server/lib/src/http_result.dart`): `HttpResult.json(...)`, `HttpResult.binary(...)`, `HttpResult.badRequest(...)`, ... |

### 6.2. Errors

An `AppError` thrown in the call answers 400 with `{"code": ..., "params": {...}}`; the client gets the same `AppError`. A thrown `HttpResponse` is sent as is. Any other exception, database exceptions included, answers 500, with the exception text only when `debugMode` is `true`. The transaction rolls back in all cases. Error codes, database exceptions and pitfalls: see [ERRORS.md](ERRORS.md).

## 7. Notifications

Notifications send events to server-side subscribers after a commit. Each subscriber processes them in its own transaction. Build every `Notifier` once at startup, before serving requests: a notification without a registered notifier is lost. See [NOTIFICATIONS.md](NOTIFICATIONS.md#3-notifications).

## 8. Monitoring

- `dataRegistry.operations`: stream of every `Operation` (HTTP calls, transactions, SQL orders), with `type` (`OperationType.httpRequest`, ...), `duration`, `error`.
- `debugger` (registry factory): receives `DebugMessage`s for a debug console.

Details, pitfalls and the `sing_debug` package: [DEBUGGING.md](DEBUGGING.md).

## 9. See Also

- [SERVICES.md](SERVICES.md): writing services, tokens.
- [TRANSACTIONS.md](TRANSACTIONS.md): `CallContext`, operations, transactions.
- [NOTIFICATIONS.md](NOTIFICATIONS.md): change listeners and notifications.
- [ACCESS_CONTROL.md](ACCESS_CONTROL.md): access tokens, accounts, token contexts.
- [ERRORS.md](ERRORS.md): `AppError`, error codes, database exceptions.
- [MIGRATIONS.md](MIGRATIONS.md): model versions and migration steps.
- [QUERIES.md](QUERIES.md): database queries.
- [DATA_CLASSES.md](DATA_CLASSES.md): `DataLoader`, `DataRowValues`, `DataRow`.
- [APP_CLIENT.md](APP_CLIENT.md): the client side of the HTTP exchange.
- [DEBUGGING.md](DEBUGGING.md): SQL traces and debug printers.
- [TESTING.md](TESTING.md): tests against a fake controler or a real database.
