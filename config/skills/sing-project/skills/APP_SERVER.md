# Sing Server Application

## 1. Overview

A Sing server application is **by definition** an application that depends on the model package (e.g. `model/`) and instantiates the class derived from `ServerDataRegistry` produced during model construction (e.g. `OrderHub$Registry(dataControler:...)`). The `dataControler` parameter provides the `sing_server` framework with access to the database where the data structures (schemas, tables, indexes, ...) of the model are stored. 

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
Future<OrderHub$Registry> createDataRegistry( List<String> arguments) async => 
    OrderHub$Registry(  
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

```dart
Future migrateDatabase(
  OrderHub$Registry dataRegistry,
  Account migrationAccount,
) async {
  // Obtain the current version from the database (from file or database or ...)
  final currentVersion = getCurrentVersion();
  // The version of the model is its last rebuild timestamp.
  final registryVersion = dataRegistry.version;
  // Up to date? Nothing to do.
  if (currentVersion == registryVersion) return;
  // The database is newer than the model (invalid model package referenced, old app version, ...). This is an error.
  if (currentVersion != null && currentVersion.isAfter(registryVersion)) {
    throw "Database version $registryVersion is newer than the model version $currentVersion.";
  }
  await dataRegistry.startOperation(
    "Run migration",
    executor: (callContext) async {
      // Do the job
      final version = await dataRegistry.migrateDatabase<OrderHub$Registry>(
        callContext,
        fromVersion: currentVersion,
      );
      // Save the new version
      await setCurrentVersion(dataRegistry, version);
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

    final OrderHub$Registry dataRegistry;  // For database access

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

**When an exception** `e` occurs during a service call, the Sing framework returns a `Response` object with:
- `statusCode`: 400 if `e is AppError` else 500
- `content`: `e.message` if `e is AppError` else nothing ("Internal error" with no details).

## 5. See Also

- [**Migrations**](MIGRATIONS.md)
- [**Data access classes**](DATA_CLASSES.md)
- [**Queries**](QUERIES.md) for querying the database.