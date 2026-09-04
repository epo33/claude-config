# Sing Server Application

## 1. Overview

A Sing server application is **by definition** an application that depends on the model package (e.g. `model/`) and builds its registry through the factory generated during model construction (e.g. `OrderHubServerRegistry(dataControler: ...)`). The `dataControler` parameter provides the `sing_server` framework with access to the database where the data structures (schemas, tables, indexes, ...) of the model are stored.

`OrderHubServerRegistry` (in `model/lib/sing/server.dart`) is an `abstract interface class` stacking `sing.ServerDataRegistry` and the model interface `OrderHubRegistry<ServerEntityDef>` (generated in `common/lib/src/sing/registry.dart`). Its factory has three named parameters: `dataControler` (required, a `ServerDataControler` such as `PgDataControler`), `debugger` (`DebugPrinter?`) and `debugMode` (`bool`). The concrete class `_OrderHub$Registry extends sing.ServerDataRegistryBase` is private to the generated file: application code names the interface only, never extends it, and never writes `ServerDataRegistry(...)`. The static constant `OrderHubServerRegistry.modelLayers` lists the `ServerModelLayer` instances (`OrderHub$Layer` and the layers of its [sub-models](SUBMODELS.md)) the registry is built from.

## 2. Basic Sing Server Application

A Sing server application is generally a Linux, macOS, or Windows application. Example:
```dart
import 'package:model/server.dart';
import 'package:orderhub_server/orderhub_server.dart' as orderhub_server;
import 'package:sing_postgresql/sing_postgresql.dart';

void main(List<String> arguments) async {
  final dataRegistry = await createDataRegistry(arguments);
  // Using the model through dataRegistry.
}

// Could be synchronous. All operations are very fast (no database or IO access)
Future<OrderHubServerRegistry> createDataRegistry( List<String> arguments) async => 
    OrderHubServerRegistry(  
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

An instance of `ServerDataRegistry` is **essential** for any operation on a Sing data model. This instance will be called `dataRegistry` in everything that follows.

It is essential to have a CallContext instance to call a service or execute requests on the database: 
```dart
  await dataRegistry.startOperation(
    "What I need to do",
    executor: (callContext) async {
      // Example
      await $Order
          .services(callContext)
          .addOrder(
            callContext: callContext,
            order: $Order
                .ofContext(callContext)
                .createInstance(
                  filler: (values) => values
                    ..orderDate.setToNow(callContext)
                    ..orderNumber.value = "...",
                ),
            orderLines: [
              // ...
            ],
          );
    },
    userAccount: aUserAccount,
  );
```

## 3. Migrations

Once `dataRegistry` is obtained, the first step of any Sing server application is to ensure that the database is at the version of the model and, if not, [**perform the database migration**](MIGRATIONS.md).

The version reached by the database is the string `dataRegistry.layerVersionChain` (one semantic version per model layer, e.g. `"CoverageBase=1.0.0;Coverage=1.2.0"`). Storing it is the application's job (file, table, ...). `migrateDatabase<R>(callContext, fromVersionChain:)` replays, for each layer, the migration steps above the recorded version, then the DDL orders, and returns `dataRegistry.version` (a `String`). `fromVersionChain: null` (or an unparseable chain) treats the database as never migrated. Example (from `example/orderhub_server/bin/orderhub_server.dart`):

```dart
Future migrateDatabase(
  OrderHubServerRegistry dataRegistry,
  Account migrationAccount,
) async {
  // Obtain the chain recorded by the previous migration (file, database, ...)
  final currentVersionChain = getCurrentVersionChain();
  // Up to date? Nothing to do.
  if (currentVersionChain == dataRegistry.layerVersionChain) return;
  // A CallContext is mandatory for any database operation.
  await dataRegistry.startOperation(
    "Run migration",
    executor: (callContext) async {
      // Do the job
      await dataRegistry.migrateDatabase<OrderHubServerRegistry>(
        callContext,
        fromVersionChain: currentVersionChain,
      );
      // Record the reached chain
      await setCurrentVersionChain(dataRegistry, dataRegistry.layerVersionChain);
    },
    userAccount: migrationAccount,
  );
  // The database is up to date. If it were not, an exception would have been thrown.
}
```

## 4. HTTP Server

If the model must be accessed from a client application, you need to implement a Sing server application that contains an HTTP server (e.g. using the Dart `shelf` package).

### 4.1. HTTP Server Implementation
```dart
void main(List<String> arguments) async {
  final dataRegistry = await createDataRegistry(arguments);
  // Check database model's version
  await migrateDatabase( dataRegistry, [account]);
  // Instanciate a session manager (handles session keys)
  final sessionManager = AppSessionManager( dataRegistry);

  // Initialize Shelf routes and handlers
  final routes = Router( ...)
        ..mount("app", (request) => dataRegistry.processRequest(
            request: request,
            sessionManager: sessionManager,
      ))
        // Others...
        ;
    final handler = const Pipeline()
        .addMiddleware(corsMiddleWare)
        .addMiddleware(gzipMiddleware)
        .addHandler(router.call);

    // Run HTTP server.
    final httpServer = await serve(
      handler,
      [adress],
      [port],
      // Other params...
    );
}

/// For session keys handling (often with an entity "Active Session" defined in the model witch associate a session key to a user account)
class AppSessionManager extends MainSessionManager {
    AppSessionManager( this.dataRegistry);

    final OrderHubServerRegistry dataRegistry;  // For database access

  @override
  Future<sing.Account?> accountFromSessionKey(
    sing.SessionKey sessionKey,
    sing.Operation trace,
  ) async {
    if (sessionKey.isEmpty) return null;
    return await super.accountFromSessionKey(sessionKey, trace) // From cache (handled by ancestor class) ?
           ?? loadUserAccountFromSession(sessionKey, trace)     // From database ?
    ;
  }

  Future<sing.Account?> loadUserAccountFromSession(
    sing.SessionKey sessionKey,
    sing.Operation trace,
  ) async {
    // TODO
  }
}
```

### 4.2. Exception Handling

**When an exception** `e` occurs while `processRequest` handles a request, the Sing framework returns an `HttpResponse` with:
- `statusCode`: 400 if `e is AppError` else 500 (an `HttpResponse` thrown by the code is returned as is)
- `content`: the JSON of `e.toJson()` if `e is AppError` (`HttpResult.json`), else `e.toString()` (`HttpResult.internalServerError`).

Every response carries the headers `X-Sing-Version` (`dataRegistry.version`) and `X-Sing-Model-Version` (`dataRegistry.compiledAt` in ISO 8601), see `DataRegistry.httpHeader`.

## 5. See Also

- [**Migrations**](MIGRATIONS.md)
- [**Data access classes**](DATA_CLASSES.md)
- [**Queries**](QUERIES.md) for querying the database.