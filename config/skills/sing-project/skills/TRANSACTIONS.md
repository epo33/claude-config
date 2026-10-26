# Transactions and CallContext

Every database access on the server goes through a `CallContext`. This document explains how a transaction starts and ends, what runs before and after the commit, and how to run work in a separate transaction.

Sources: `sing_server/lib/src/call_context.dart`, `sing_server/lib/src/data_registry.dart`, `sing_core/lib/src/with_environment_mixin.dart`.

## 1. Core Rules

- One `CallContext` is one database transaction, on one connection, plus the `Account` of the caller.
- Every query made with a `CallContext` runs in its transaction. See [QUERIES.md](QUERIES.md).
- An HTTP service call runs in one transaction. The framework opens it before the service and closes it after. A `DataLoader` returned by the service runs before the commit, inside the transaction.
- The transaction commits when the code returns normally. It rolls back when the code throws. The exception is then rethrown to the caller.
- Outside of HTTP (startup, batch, timer), open the transaction yourself with `startOperation` (section 2).
- Never keep a `CallContext` after its transaction has ended. Never share it between two concurrent tasks.

## 2. Start an Operation Outside HTTP

### 2.1. `startOperation`

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

`ServerDataRegistry.startOperation<T>(lib, {executor, userAccount, type, level})`:

| Parameter | Role |
| --- | --- |
| `lib` (positional) | Label of the operation in traces and in the debug console. |
| `executor` (required) | `Future<T> Function(CallContext)`. Runs inside the transaction. |
| `userAccount` (required) | Who runs the code. Use `Account.system("name")` for technical work. A system account holds `AccessToken.system`, which grants every token. `Account.migration` is a ready-made system account. |
| `type` | `OperationType` shown in traces. Optional. |
| `level` | `OperationLevel` of the trace. Default `.trace`. |

`startOperation` returns what `executor` returns.

### 2.2. `call` with Your Own Operation

`dataRegistry.call(executor, userAccount: ..., operation: ...)` does the same with an `Operation` you created yourself. Use it to put the transaction under an existing trace.

### 2.3. `startGlobalOperation`

`dataRegistry.startGlobalOperation(lib, executor: (operation) async {...})` gives an `Operation` and **no transaction**. Use it to group several transactions under one trace:

```dart
await dataRegistry.startGlobalOperation(
  "Nightly order cleanup",
  executor: (operation) async {
    for (final batch in batches) {
      await dataRegistry.call(
        (callContext) => cleanBatch(callContext, batch),
        userAccount: Account.system("orderhub_batch"),
        operation: operation.add("Batch ${batch.index}"),
      );
    }
  },
);
```

Each batch commits on its own. A failing batch does not undo the previous ones.

## 3. `CallContext` Members

| Member | Use |
| --- | --- |
| `userAccount` | The `Account` of the caller (`uuid`, `displayName`, `tokens`, `tokenGranted(token)`). |
| `dataRegistry` | The `ServerDataRegistry`. |
| `services<S>()` | The services class `S` bound to this context. Generated accessors (`$Order.services(callContext)`) call it. |
| `notifiers` | The notifiers of the registry. See [NOTIFICATIONS.md](NOTIFICATIONS.md#3-notifications). |
| `mustRollback(true)` | Roll back at the end without throwing (section 4.2). |
| `subTransaction(fn, lib:, userAccount:)` | Run work in a separate transaction (section 5). |
| `afterCommit(fn, key:)` | Run work after the commit (section 6). |
| `setEnvironment`, `fromEnvironment<T>`, `getEnvironment<T>`, `deleteEnvironment<T>`, `withEnvironmentAsync`, `withEnvironmentSync` | Attach objects to the call (section 8). |
| `clientClock` | Time zone of the HTTP client (section 9). |
| `trace`, `traceCall`, `traceCallAsync`, `debugPrint` | Add lines to the trace of the call (section 10). |
| `httpRequest` | The `shelf` request of the call. Outside HTTP, a fake `GET` request. |
| `dbConnexion`, `sqlProvider` | Low-level access for raw SQL. See [QUERIES.md](QUERIES.md#73-raw-sql). |
| `runningOperation` | The current trace node. Some low-level APIs ask for it. |

## 4. End of a Transaction

### 4.1. What Happens, in Order

When the executor (or the HTTP service) ends:

1. The `TransactionEnded` hooks run, **inside** the transaction, with `willCommit` (section 7).
2. If the code threw, or `mustRollback(true)` was called, or a hook threw: the notifications and `afterCommit` callbacks of the call are dropped, then the transaction rolls back.
3. Otherwise the transaction commits.
4. After the commit: the notifications of the call are dispatched ([NOTIFICATIONS.md](NOTIFICATIONS.md#35-delivery-rules)).
5. Then the `afterCommit` callbacks run, one after the other.
6. Then the call returns its result.

So the caller gets the result only after the `afterCommit` callbacks have finished.

### 4.2. `mustRollback`

```dart
if (!stockAvailable) {
  callContext.mustRollback(true);
  return;
}
```

- The transaction rolls back when the call ends. The code keeps running until then.
- The call then throws `AppError.transactionAborted()` (code `sing.errors.transactionAborted`) instead of returning its result. Over HTTP, the client receives this `AppError`.
- Once set, it cannot be unset. `mustRollback()` without argument only reads the flag.
- Prefer throwing an `AppError` with a business code when the user must know why. Use `mustRollback` when the code must run to its end (for example to fill a report) and still write nothing.

### 4.3. Database Errors

After a failed SQL statement, PostgreSQL refuses every other statement of the transaction. Catching the exception in Dart does not repair the transaction. Use a savepoint when you want to continue. See [QUERIES.md](QUERIES.md#72-database-errors-and-savepoints).

A serialization failure or deadlock raises `DbTransactionConflictException`. Sing does not retry the transaction. Retry it yourself if needed, with a new `startOperation`.

## 5. Sub-Transactions

```dart
await callContext.subTransaction(
  (sub) => $OrderAuditTrace
      .query(sub)
      .insertNewRow(
        (trace) => trace
          ..occurredAt.setToNow(sub)
          ..actor.valueOrNull = sub.userAccount.displayName
          ..orderNumber.value = order.orderNumber.value
          ..newStatus.value = OrderStatus.cancelled,
      )
      .execute(),
  lib: "Audit cancel attempt",
);
```

`subTransaction<T>(fn, {lib, userAccount})` runs `fn` in a **new, independent** transaction:

- It uses its own connection and its own `CallContext`. Inside `fn`, use only that context (`sub` above), never the parent one.
- It commits when `fn` returns, before the parent ends. A later rollback of the parent does **not** undo it.
- If `fn` throws, the sub-transaction rolls back and the exception reaches the parent. The parent can catch it and continue.
- `userAccount` defaults to the account of the parent. `lib` labels the trace.
- It inherits the client clock of the parent. Its environment falls back to the parent environment (section 8).
- Its own `afterCommit` callbacks and notifications run when **it** commits, not when the parent commits.
- The `TransactionEnded` hooks of the parent do not run for it.

Use it for work that must be kept even when the call fails: an audit line, a counter, a log.

**Pitfall: deadlock.** The sub-transaction does not see the uncommitted writes of the parent, and it waits on their row locks. If the parent has updated or deleted a row and the sub-transaction writes the same row, the sub-transaction waits for the parent, and the parent waits for the sub-transaction. The call hangs. Do not touch, in a sub-transaction, rows the parent has written.

**Pool.** A sub-transaction never waits for a free connection: it may open one connection above the pool limit. This avoids a pool starvation where every connection waits for its own sub-transaction.

## 6. `afterCommit`

```dart
callContext.afterCommit(
  () => mailer.sendOrderConfirmation(order.orderNumber.value),
  key: "confirmation-${order.uuid.value}",
);
```

`afterCommit(callback, {key})`:

- `callback` runs once the transaction has committed, **outside** of it. The data of the call is visible to other transactions.
- It is dropped when the transaction rolls back.
- With a `key`, a second registration under the same key is ignored. Use it when several rows or listeners may ask for the same work.
- Callbacks run one after the other, in registration order. The call returns only after all of them.
- A failing callback is traced. It does not fail the call (the data is already committed) and the next callbacks still run. **Handle errors yourself** when the failure matters.
- The callback has no `CallContext`. To read or write the database, open a new transaction with `dataRegistry.startOperation(...)`.

Use it for side effects that must not happen before the data is committed: e-mails, messages to other processes, pushes to clients, cache updates.

## 7. `TransactionEnded` Hooks

To run code at the end of a transaction, still inside it, put an object that implements `TransactionEnded` in the environment of the call:

```dart
class OrderTotalsRecompute implements TransactionEnded {
  final orderUuids = <String>{};

  @override
  Future endOfTransaction(CallContext callContext, bool willCommit) async {
    if (!willCommit || orderUuids.isEmpty) return;
    await recomputeTotals(callContext, orderUuids);
  }
}

OrderTotalsRecompute totalsOf(CallContext callContext) =>
    callContext.fromEnvironment<OrderTotalsRecompute>(
      ifAbsent: OrderTotalsRecompute.new,
    )!;
```

Code that changes order lines calls `totalsOf(callContext).orderUuids.add(...)`. The totals are then computed once per transaction, not once per line.

Rules:

- `endOfTransaction(callContext, willCommit)` runs before the commit or rollback. `willCommit` is `false` when the call failed or `mustRollback(true)` was called.
- Writes made in the hook are part of the transaction and commit with it.
- A hook that throws makes the call fail and roll back. Each hook runs once.
- Only hooks set on **this** `CallContext` run. A hook set on the registry or on a parent context is not run, unless `fromEnvironment` has copied it into this context (section 8).
- Hooks run in the order they were added.

## 8. Environment

The environment attaches objects to a call, found by type. The registry also has an environment.

| Member | Behavior |
| --- | --- |
| `setEnvironment(obj)` | Adds `obj`. When several objects match a type, the last added wins. |
| `fromEnvironment<T>()` | The last `T` of this context. If none: looks in the parent context, then in the registry. A value found there is copied into this context. Returns `null` if absent. |
| `fromEnvironment<T>(ifAbsent: f)` | The last `T` of this context. If none: calls `f`, stores and returns its result. **Does not look in the parent context or the registry.** |
| `getEnvironment<T>()` | Like `fromEnvironment<T>()`, but throws when absent. |
| `deleteEnvironment<T>([obj])` | Removes the last `T` (or `obj`) from this context. |
| `withEnvironmentAsync(objects, fn)` | Adds `objects`, runs `fn`, then removes them, even on error. `withEnvironmentSync` is the synchronous form. |

During an HTTP call, the framework puts the `SessionManager` and the client clock in the environment. `callContext.getEnvironment<SessionManager>()` gives the session manager and the session key. See [APP_SERVER.md](APP_SERVER.md#5-sessions-and-authentication).

**Pitfall.** `fromEnvironment(ifAbsent: ...)` never reads the registry environment. Do not use `ifAbsent` to read an object you put on the registry at startup.

## 9. Client Clock

`callContext.clientClock` is a `CallContextClock` (`timeZoneName`, `timeZoneOffset`, `now`, `today`).

- During an HTTP call, it comes from the request headers `X-Sing-Client-Timezone-Name` and `X-Sing-Client-Timezone-Offset` (minutes). The Sing client sends them. A missing header falls back to the server clock.
- Outside HTTP, it is the local clock of the server.
- `fieldValue.setToNow(callContext)` and `setToNowIfNull(callContext)` use it for `LocalDateTime` and `DateOnly` fields. `UtcDateTime` fields take the UTC time.

## 10. Traces

| Member | Behavior |
| --- | --- |
| `trace("text")` | Adds a line to the trace of the call. |
| `traceCall("label", fn)` / `traceCallAsync("label", fn)` | Runs `fn` under a trace node. |
| `debugPrint("text")` | Sends a `DebugMessage` to the registry `debugger`, if any. |

**Pitfall.** `traceCall` and `traceCallAsync` **catch and swallow** the exception of `fn`. They record it in the trace and return normally. The transaction then commits as if nothing failed. Use them only for work whose failure is acceptable. Otherwise call the code directly.

## 11. Connection Pool

`PgDataControler` holds the pool: by default 10 connections, idle ones closed after 5 minutes. See [APP_SERVER.md](APP_SERVER.md#12-postgresql-data-controler) for its parameters.

- Each open transaction holds one connection until it ends. Long work inside a transaction (HTTP calls to other systems, big computations) keeps a connection busy. Move it to `afterCommit` or before the transaction.
- When all connections are busy, a new transaction waits. After the connect timeout (`PoolSettings.connectTimeout`, default 60 seconds) it fails with `Timeout waiting for database connexion (...)`.
- Each notification subscriber uses one connection while it processes a notification.
- `dataControler.poolState` gives the counts (`idle`, `borrowed`, `opening`, `waiting`, `limit`). `dataControler.limitPool(n)` caps the pool at run time; `null` removes the cap.

## 12. Common Pitfalls

- **Using a context after its end.** A `CallContext` kept in a field, a closure run later, or an `afterCommit` callback is no longer valid. Open a new operation.
- **Unawaited futures.** A query started without `await` may run after the commit or fail silently. Await every database call.
- **Lazy loaders.** A write verb returns a `DataLoader`. Nothing is written until a terminal method runs (`execute()`, `count()`, `exactlyOne()`...). See [QUERIES.md](QUERIES.md#12-loaders-are-lazy-always-run-them).
- **Catching a database exception and continuing.** The transaction is broken. Use a savepoint (section 4.3).
- **Side effects inside the transaction.** An e-mail sent in the service is sent even if the transaction rolls back later. Use `afterCommit`.
- **Sub-transaction on rows the parent wrote.** Deadlock (section 5).
- **`traceCall` hides errors** (section 10).

## 13. See Also

- [NOTIFICATIONS.md](NOTIFICATIONS.md): change listeners (inside the transaction) and notifications (after the commit).
- [APP_SERVER.md](APP_SERVER.md): registry, data controler, HTTP exposure.
- [SERVICES.md](SERVICES.md): writing services.
- [QUERIES.md](QUERIES.md): queries, savepoints, raw SQL.
