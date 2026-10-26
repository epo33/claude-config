# Errors

This document explains how to raise a business error in a service, what the client receives, and which errors Sing raises itself.

## 1. AppError

`AppError` (`sing_core/lib/src/types.dart`) is the only error that travels from the server to the client with its content.

```dart
AppError("orders.errors.noLine", {"order": order.orderNumber.value}).raise();
```

- `code`: a message key. The client translates it.
- `params`: a `Map<String, String>`. Values are **strings only**: convert numbers and dates yourself (`"$count"`).
- `raise()` throws the error. Its return type is `Never`, so the analyzer knows the code after it does not run.
- `toJson()` gives `{"code": ..., "params": {...}}` (no `params` when empty). `AppError.fromJson(json)` reads it back.
- `AppError` is a `final class`: you cannot subclass it. Put the kind of error in the `code`, and the details in `params`.

Choose codes with a prefix of your application (`orders.errors.noLine`). Sing codes start with `sing.errors.`.

## 2. From the Server to the Client

### 2.1. What the Server Answers

The transaction of the call rolls back in every case below.

| Thrown in the call | HTTP answer | Client throws |
| --- | --- | --- |
| `AppError` | 400, JSON `{"code": ..., "params": {...}}` | `AppError` with the same `code` and `params` |
| `HttpResponse` (thrown, for example `throw HttpResult.notFound()`) | that response, as is | a `String` (text body, or the HTTP reason phrase) |
| any other exception (`StateError`, database exceptions, ...) | 500. The body holds the exception text only when the registry runs with `debugMode: true` | a `String` |

Notes:
- Sing does **not** use 401 or 403. An expired session and a denied access are both `AppError`s with status 400.
- Without `debugMode`, a 500 carries no detail, because an exception text can quote SQL or data. Read the server operations (`dataRegistry.operations`) to find the cause.
- The same rules apply to errors thrown by change listeners and by the `DataLoader` a service returns: they run inside the call.

`HttpResult` is in `sing_server/lib/src/http_result.dart`.

### 2.2. What the Client Receives

`$callService` (`sing_client/lib/src/services.dart`) turns the answer into a result or an exception:

| Server answer | Client throws |
| --- | --- |
| 400 with a JSON object | `AppError` |
| other status >= 400 | a `String` (text body, or the HTTP reason phrase) |
| network failure | the exception of your HTTP library |

So catch `AppError` first, then `Object`:

```dart
try {
  await $Order.services(dataRegistry).loadThisKey(key: uuid).exactlyOne();
} on AppError catch (e) {
  showMessage(translate(e.code, e.params));
} on Object catch (e) {
  showMessage("Unexpected error: $e");
}
```

The data controler is a good single place for errors that every call can get, such as an expired session. See [APP_CLIENT.md](APP_CLIENT.md#3-the-data-controler).

## 3. Errors Sing Raises

Codes are constants in `sing_core/lib/src/types.dart`.

### 3.1. Session and Access

`SessionErrorCodes`:

| Constant | Code | When | What to do |
| --- | --- | --- | --- |
| `codeSessionExpired` | `sing.errors.sessionExpired` | The client sent a session key, and the session manager found no account for it. | Clear the key, show the sign-in screen. |
| `codeAccessDenied` | `sing.errors.accessDenied` | The account lacks the token of the service, or of a field or entity used in a client search. `params["token"]` names the token. | Hide the action, or give the token. See [ACCESS_CONTROL.md](ACCESS_CONTROL.md). |
| `codeTransactionAborted` | `sing.errors.transactionAborted` | The service called `callContext.mustRollback(true)`. | Expected by your code. |
| `codeIncompatibleModelVersion` | `sing.errors.incompatibleVersion` | The client was built from another version. `params`: `expected`, `server`. | Ask the user to update or reload. |

Factories: `AppError.sessionExpired()`, `AppError.transactionAborted()`, `AppError.incompatibleModelVersion(expectedVersion: ..., serverVersion: ...)`, `AppError.invalidServiceSignature(serviceName: ...)`.

### 3.2. Services

`ServiceErrorCodes`:

| Constant | Code | When |
| --- | --- | --- |
| `codeUnknownService` | `sing.errors.unknownService` | No service at this path. |
| `codeNotFoundedService` | `sing.errors.notFoundedService` | A service call by name (`ServiceCallInfos`) names no service. `params["service"]`. |
| `codeInvalidServiceSignature` | `sing.errors.invalidServiceSignature` | The signature of the service changed since the client was generated. `params["service"]`. |
| `codeParameterCantBeNull` | `parameterCantBeNull` | A non-nullable parameter is null. `params["parameter"]`. |
| `codeParameterInvalidValue` | `parameterInvalidValue` | A parameter value is refused. `params`: `parameter`, `value`. |

### 3.3. Data

`DataErrorCodes`:

| Constant | Code | When |
| --- | --- | --- |
| `codeNoDataFound` | `sing.errors.noDataFound` | `exactlyOne()` or `first()` found no row. |
| `codeTooManyRows` | `sing.errors.tooManyRows` | `one()` or `exactlyOne()` found more than one row. |
| `codeRowVersionConflict` | `sing.errors.rowVersionConflict` | An update found that another call changed the row since it was read. `params`: `entity`, `key`. |
| `codeRowDeleted` | `sing.errors.rowDeleted` | Same check, but the row is gone. `params`: `entity`, `key`. |
| `codeUnknownField` | `sing.errors.unknownField` | A row has no field with this name. |
| `codeFieldWithoutValue` | `sing.errors.fieldWithoutValue` | Code read a field that has no value (not loaded, or not set). |

`codeNoDataFound` on `exactlyOne()` is often a normal case (a key sent by the client that no longer exists). Use `one()` and test `null` when the row may be absent.

On `codeRowVersionConflict`, the client should reload the row and ask the user to apply the change again.

### 3.4. Field Validation

A field that refuses a value raises `AppError` with a `FieldErrorCodes` code (`sing.errors.fields.maxLength`, `lowBound`, `highBound`, `minLength`, `singleLine`, `invalidInt`, `invalidDateTime`, ...). `params["field"]` is the field name. Bounds add `params["min"]` or `params["max"]`.

## 4. Database Exceptions

The PostgreSQL controler translates some database errors into exceptions of `sing_server/lib/src/db/db_exceptions.dart`:

| Exception | PostgreSQL error |
| --- | --- |
| `DbUniqueConstraintException` | unique violation (`23505`) |
| `DbForeignKeyViolationException` | foreign key violation (`23503`) |
| `DbQueryCancelledException` | query cancelled (`57014`) |
| `DbTransactionConflictException` | serialization failure or deadlock (`40001`, `40P01`) |

**These are not `AppError`s.** Sing does not translate them: the client gets a 500 without detail. When the user must see the problem, translate it in the service.

### 4.1. Unique Constraints

PostgreSQL aborts the whole transaction on an error. After a caught `DbUniqueConstraintException`, any other statement of the same transaction fails. Two correct ways:

1. Translate and stop:

```dart
try {
  await $Customer.query(callContext).insertRow(customer.$dataRow).execute();
} on DbUniqueConstraintException {
  AppError("orders.errors.customerExists", {"email": email}).raise();
}
```

2. Continue the transaction: run the statement in a savepoint with `callContext.dbConnexion.withSavePoint(() => ..., trace: callContext.runningOperation)`. A failure then rolls back only the statements of the savepoint. See [QUERIES.md](QUERIES.md#72-database-errors-and-savepoints).

A check before the insert (`one()` on the unique key) gives a clearer message, but it does not replace the catch: another call can insert the same key between the check and the insert.

### 4.2. Foreign Keys

Sing creates foreign keys `DEFERRABLE INITIALLY DEFERRED`. PostgreSQL checks them **at commit**, after the service has returned. A `try` in the service cannot catch the violation: the client gets a 500.

So check before you write. Before deleting a `Customer`, look for its orders and raise an `AppError` when some exist. Prefer cascade rules in the model when the children must go with the parent (see [CONCEPTS_RELATIONSHIPS.md](CONCEPTS_RELATIONSHIPS.md)).

### 4.3. Transaction Conflicts

`DbTransactionConflictException` means that two transactions blocked each other. The transaction is lost and Sing does not retry it. Retry the whole call: on the client, or on the server with a new `startOperation` ([TRANSACTIONS.md](TRANSACTIONS.md#21-startoperation)).

## 5. Rolling Back Without an Error

`callContext.mustRollback(true)` (`sing_server/lib/src/call_context.dart`) marks the transaction as doomed. The service goes on and returns normally, then the transaction rolls back and the client gets `AppError.transactionAborted()`. It cannot be undone. Use it for a dry run, or when a service has collected several problems and reports them another way. See [TRANSACTIONS.md](TRANSACTIONS.md#42-mustrollback).

## 6. Testing Errors

Check the code with a matcher:

```dart
Matcher appError(String code) =>
    throwsA(isA<AppError>().having((e) => e.code, "code", code));

expect(
  $Order.query(callContext).load(where: (f) => f.uuid.$equal(missing)).exactlyOne(),
  appError(DataErrorCodes.codeNoDataFound),
);
```

Example: `coverage/coverage_model/test/row_version_test.dart`. Access denied errors happen only over HTTP: see [ACCESS_CONTROL.md](ACCESS_CONTROL.md#6-testing-access-control).

## 7. Pitfalls

- **Throwing an `Exception` or a `String` for a business error.** The client gets a 500 without detail. Throw an `AppError`.
- **Database exceptions reach the client as 500.** Translate them (see [4](#4-database-exceptions)).
- **Foreign key errors happen at commit.** Check before deleting (see [4.2](#42-foreign-keys)).
- **Continuing after a caught database error.** The PostgreSQL transaction is aborted. Raise an `AppError`, or use a savepoint.
- **Non-string params.** `params` is `Map<String, String>`.
- **Waiting for 401 or 403 on the client.** Sing sends 400 with `sing.errors.sessionExpired` or `sing.errors.accessDenied`.

## 8. See Also

- [SERVICES.md](SERVICES.md): writing services.
- [APP_SERVER.md](APP_SERVER.md#6-results-and-errors): HTTP results of a service.
- [APP_CLIENT.md](APP_CLIENT.md#5-errors): errors on the client.
- [ACCESS_CONTROL.md](ACCESS_CONTROL.md): access tokens.
- [TRANSACTIONS.md](TRANSACTIONS.md): transactions, rollback, sub-transactions.
