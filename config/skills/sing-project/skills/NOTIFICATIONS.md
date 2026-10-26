# Change Listeners and Notifications

Sing has two ways to react to data changes on the server:

- **Entity change listeners** run on every write of an entity, synchronously, **inside** the transaction of the write.
- **Notifications** are events your code sends. They are dispatched to subscribers **after the commit**, each subscriber in its own transaction.

Read [TRANSACTIONS.md](TRANSACTIONS.md) first: both depend on how a transaction ends.

## 1. Choose the Mechanism

| Need | Use |
| --- | --- |
| Set a default, normalize a value, check a rule before a write | Change listener, `before*` |
| Write related rows that must commit or roll back with the write (history, totals) | Change listener, `after*` (or a `TransactionEnded` hook for once-per-transaction work) |
| Refuse a write | Change listener, `before*`, throw an `AppError` |
| React later, in another transaction, only when the data is committed | Notification |
| Decouple modules: the sender does not know who reacts | Notification |
| Side effect outside the database (e-mail, push to clients), once per call | `afterCommit` ([TRANSACTIONS.md](TRANSACTIONS.md#6-aftercommit)) |

A failing listener makes the write fail. A failing subscriber does not affect the sender: the data is already committed.

## 2. Entity Change Listeners

Sources: `sing_server/lib/src/entity_controler.dart`, `sing_server/lib/src/change_listener.dart`, `sing_server/lib/src/query/handle_listeners.dart`.

### 2.1. Write a Controler

A controler extends `EntityControler<E>` and returns its listeners from `getChangeListeners`:

```dart
// lib/model/orders/order.listeners.dart
import "package:model/model.dart";

class OrderControler extends EntityControler<Order> {
  const OrderControler();

  @override
  List<EntityChangesListener<Order>> getChangeListeners(
    CallContext callContext,
  ) => [
    ...super.getChangeListeners(callContext),
    EntityChangesListener<Order>(
      beforeInsert: _setOrderDate,
      beforeUpsert: _setOrderDate,
    ),
  ];

  Future _setOrderDate(
    CallContext callContext,
    Iterable<DataRow<Order>> rows,
  ) async {
    for (final row in rows) {
      row.values.orderDate.setToNowIfNull(callContext);
    }
  }
}
```

Rules:

- The controler needs a `const` constructor **without parameters**. The generated code builds it as a constant.
- `getChangeListeners` is called at **each write**, with the `CallContext` of the write. It may return different listeners depending on the context (the account, an object in the environment...).
- Keep `...super.getChangeListeners(callContext)` when you extend another controler.
- A callback is an `EntityChangeCallback<E>`: `Future Function(CallContext callContext, Iterable<DataRow<E>> rows)`. It receives all the rows of one write at once.

### 2.2. Attach It to the Entity

Put the controler on the entity class as an annotation, then regenerate the model (`dart run sing_builder:sing_emit`):

```dart
// lib/model/orders/order.dart
import "package:model/model.dart";
import "order.listeners.dart";

export "order.services.dart";

@OrderControler()
@Implementor(OrderServices)
@LoadServices()
@Searchable()
class OrderEntity extends ModelEntity with UuidPrimaryKeyMixin { ... }
```

- Without regeneration, the listeners never run. Nothing warns you.
- An entity may carry several controlers. They all run.
- A controler annotation on a model mixin used by the entity also applies.
- Controlers of an ancestor entity also run for its descendants.
- Controlers run only on the server. The client code never sees them.

### 2.3. Callbacks and Their Rows

`EntityChangesListener<E>` takes eight optional callbacks:

| Callback | Runs | Rows received |
| --- | --- | --- |
| `beforeInsert`, `beforeUpdate`, `beforeUpsert` | Before the SQL order | The rows passed to the write. **Values you set here are written.** |
| `afterInsert`, `afterUpdate`, `afterUpsert` | After the SQL order | New rows, read back from the database with all their fields (the access tokens of the account apply). |
| `beforeDelete` | Before the SQL order | The rows to delete, loaded from the database with all their fields. |
| `afterDelete` | After the SQL order | The same rows. They no longer exist in the database. |

All callbacks run inside the transaction of the write. A callback that throws makes the write throw, and the transaction rolls back. Throw an `AppError` to send a business error to the client.

A `before*` callback for an update receives the row of the caller, not the stored row. The stored values are not in it. In `after*`, the previous state is gone. To compare old and new values, load the stored rows in `before*` (section 2.6).

### 2.4. Which Write Triggers Which Callback

| Write (`Query` verb or standard service) | Callbacks |
| --- | --- |
| `insertRow`, `insertRows`, `insertNewRow` | `beforeInsert`, `afterInsert` |
| `updateRow`, `updateRows` | `beforeUpdate`, `afterUpdate` |
| `upsertRow`, `upsertRows` (by key, `on:` or `conflictOn:`) | `beforeUpsert`, `afterUpsert` **only** |
| `upsertRow(s)` of a row with `$checkRowVersion` and a `$rowVersion` | `beforeUpdate`, `afterUpdate` (the row is updated, see [row version](DATA_CLASSES.md#4-row-version)) |
| `deleteKey`, `deleteKeys`, `deleteRef`, `deleteRefs` | `beforeDelete`, `afterDelete` |
| `updateWhere`, `insertSelect`, `updateSelect`, `delete(where:)` | Refused (see section 2.5) |

The standard CRUD services (`insertThis`, `updateThis`, `upsertThis`, `deleteThis`...) use these verbs, so they run the same callbacks. See [QUERIES.md](QUERIES.md#3-writing) for the verbs.

**Pitfall: upsert.** An upsert runs **only** the `*Upsert` callbacks, never the `*Insert` or `*Update` ones. When a rule must apply to every write, give the same function to `beforeInsert`, `beforeUpdate` and `beforeUpsert` (same for `after*`).

**Pitfall: lazy writes.** A write verb returns a `DataLoader`. The callbacks run only when a terminal method runs the write (`execute()`, `count()`, `exactlyOne()`...).

### 2.5. Set Writes and `ignoreListeners`

The set writes (`updateWhere`, `insertSelect`, `updateSelect`, `delete(where:)`) do not hold the rows. When the entity has a listener for that kind of write, they throw: `Entity X has listeners. UPDATE WHERE can't be used.`

Options:

- Load the rows, change them, and use `updateRows` / `deleteKeys`. The listeners run.
- Pass `ignoreListeners: true` when skipping the listeners is correct for this write. Then `updateWhere`, `insertSelect` and `updateSelect` run **without** listeners.
- `delete(where:, ignoreListeners: true)` is different: it still loads the matching rows and **runs** the delete listeners.

### 2.6. Keep State Between `before` and `after`

`getChangeListeners` runs once per write, and the same listener serves the `before*` and `after*` callbacks of that write. A variable declared in `getChangeListeners` is therefore private to one write. Use it to pass data from `before*` to `after*`.

Example: trace every status change of an order in `OrderAuditTrace`.

```dart
class OrderControler extends EntityControler<Order> {
  const OrderControler();

  @override
  List<EntityChangesListener<Order>> getChangeListeners(
    CallContext callContext,
  ) {
    final storedStatus = <String, OrderStatus>{};
    Future readStoredStatus(
      CallContext callContext,
      Iterable<DataRow<Order>> rows,
    ) async {
      final keys = [for (final row in rows) row.values.uuid.value];
      final stored = await $Order.query(callContext).loadKeys(keys).listValues();
      for (final order in stored) {
        storedStatus[order.uuid.value] = order.status.value;
      }
    }
    Future traceStatusChange(
      CallContext callContext,
      Iterable<DataRow<Order>> rows,
    ) async {
      for (final row in rows) {
        final order = row.values;
        final previous = storedStatus[order.uuid.value];
        if (previous == order.status.value) continue;
        await $OrderAuditTrace
            .query(callContext)
            .insertNewRow(
              (trace) => trace
                ..occurredAt.setToNow(callContext)
                ..actor.valueOrNull = callContext.userAccount.displayName
                ..orderNumber.value = order.orderNumber.value
                ..previousStatus.valueOrNull = previous
                ..newStatus.value = order.status.value,
            )
            .execute();
      }
    }
    return [
      ...super.getChangeListeners(callContext),
      EntityChangesListener<Order>(
        afterInsert: traceStatusChange,
        beforeUpdate: readStoredStatus,
        afterUpdate: traceStatusChange,
        beforeUpsert: readStoredStatus,
        afterUpsert: traceStatusChange,
      ),
    ];
  }
}
```

The audit rows are written in the same transaction: they commit or roll back with the order.

Do **not** keep state in fields of the controler: it is a constant shared by every call.

### 2.7. Pitfalls

- **Recursion.** A listener that writes its own entity with a row verb runs the listeners again. Guard against it, or write with `updateWhere(..., ignoreListeners: true)`.
- **Cost.** Listeners run inside the transaction and hold its connection. A slow listener slows every write of the entity. Move work that may wait to a notification or to `afterCommit`.
- **Bulk writes refused.** Adding a listener makes the existing `updateWhere` / `delete(where:)` calls on the entity throw at run time. Search them before adding a listener.
- **Side effects.** A listener runs before the commit. An e-mail sent from it is sent even if the transaction rolls back. Use `callContext.afterCommit(...)` from the listener, with a `key` to send it once.
- **Once per transaction.** Listeners run once per write, so several writes of one call run them several times. For work to do once per transaction, collect keys in a `TransactionEnded` hook ([TRANSACTIONS.md](TRANSACTIONS.md#7-transactionended-hooks)).

## 3. Notifications

Sources: `sing_server/lib/src/notifications/`.

### 3.1. Define a Notification

A notification extends `Notification`. It has two constructors: one to send, one to rebuild from JSON.

```dart
class OrderPaid extends Notification {
  OrderPaid.send(super.callContext, this.orderUuid) : super.send();

  OrderPaid.fromJson(super.userAccount, super.at, super.uuid, this.orderUuid)
    : super.fromJson();

  final String orderUuid;

  @override
  dynamic toJson() => orderUuid;
}
```

`Notification` gives `uuid` (generated), `at` (UTC time of sending), `userAccount` (uuid of the sender account) and `notifier` (known once the notification is sent).

### 3.2. Define and Register a Notifier

A notifier dispatches one notification type to its subscribers:

```dart
class OrderPaidNotifier extends Notifier<OrderPaid> {
  OrderPaidNotifier(ServerDataRegistry dataRegistry)
    : super(
        dataRegistry: dataRegistry,
        identifier: "orders.orderPaid",
        name: "Order paid",
      );

  @override
  OrderPaid fromJson({
    required dynamic json,
    required String userAccount,
    required String uuid,
    required DateTime sentAt,
  }) => OrderPaid.fromJson(userAccount, sentAt, uuid, json as String);
}
```

- Building the notifier registers it in `dataRegistry.notifiers`. Build it once, at startup, **before** serving requests.
- `identifier` must be unique and stable between runs: persisted data refers to it.
- One notifier per notification type. A second one for the same type fails an assertion.
- `asyncDispatching` (default `true`): keep the default.

### 3.3. Subscribe

```dart
class ShipmentPlanner implements NotificationSubscriber<OrderPaid> {
  @override
  String get identifier => "shipping.planner";

  @override
  String get name => "Shipment planner";

  @override
  final userAccount = Account.system("shipment_planner");

  @override
  Future process(CallContext callContext, OrderPaid notification) async {
    try {
      await planShipment(callContext, notification.orderUuid);
    } catch (e, s) {
      logError("Shipment planning failed", e, s);
    }
  }
}
```

At startup:

```dart
final dataRegistry = createDataRegistry();
OrderPaidNotifier(dataRegistry);
final subscription = dataRegistry.notifiers
    .getNotifier<OrderPaid>()
    .subscribe(ShipmentPlanner());
```

- `subscribe` returns a `NotifierSubscription`. `await subscription.cancel()` stops the deliveries.
- `notifiers.findNotifier<N>()` returns `null` when the notifier is not registered. `getNotifier<N>()` throws.
- `notifiers.getSubscribers(...)` lists the current subscriptions.
- `process` runs in a **new transaction**, with the `userAccount` of the subscriber, not the account of the sender. The sender account uuid is in `notification.userAccount`.

### 3.4. Send

Build the notification with its `send` constructor, anywhere a `CallContext` is available (service, listener, hook):

```dart
Future<void> markPaid({
  required CallContext callContext,
  required String orderUuid,
}) async {
  final order = await $Order.query(callContext).loadKey(orderUuid).exactlyOne();
  order
    ..status.value = OrderStatus.processing
    ..paidAt.value = UtcDateTime.now();
  await $Order.query(callContext).updateRow(order.$dataRow).execute();
  OrderPaid.send(callContext, orderUuid);
}
```

Building the object is enough: it queues the notification in the `CallContext`.

### 3.5. Delivery Rules

- A notification is dispatched **after the commit** of the transaction that sent it. It is never visible before the data it reports.
- If the transaction rolls back (exception, `mustRollback(true)`, failing `TransactionEnded` hook), the queue is cleared: nothing is sent.
- A notification sent in a sub-transaction is dispatched when the sub-transaction commits, even if the parent rolls back later.
- Each subscriber processes its notifications **one at a time**, in sending order, each in its own transaction (`OperationType.notify` in traces). Different subscribers run in parallel.
- Processing is asynchronous. The sender call does not wait for the subscribers. Do not expect their work to be done when the call returns.
- A notification is delivered only to the notifier registered for its **exact** runtime type. A notification without a registered notifier is silently lost. A subclass of `OrderPaid` does not reach the `OrderPaid` notifier.
- Nothing is persisted. A notification not processed when the process stops is lost (section 3.6).
- Nothing is sent to clients (section 3.8).

### 3.6. Persist and Replay

`dataRegistry.notifiers` (also `callContext.notifiers`) offers three streams:

| Stream | Event |
| --- | --- |
| `onNotification` | Each notification dispatched after a commit. Use it to persist notifications. |
| `onSubscribe` | Each new `NotifierSubscription`. Use it to replay what the subscriber has not processed. |
| `onNotificationProcessed` | Each `NotificationResult` (`notification`, `notifier`, `subscriber`, `callContext`, `trace`). `callContext` is `null` when the processing failed. This stream is synchronous: keep its listeners fast. |

A possible design, all in your code:

1. Listen to `onNotification` and store `notifier.identifier`, `uuid`, `at`, `userAccount` and `toJson()` in a table, with `dataRegistry.startOperation(...)`.
2. In `process`, mark the notification as processed for this subscriber, in the subscriber transaction: the mark commits with the work.
3. Listen to `onSubscribe` before calling `subscribe`. For each subscription, load the notifications not processed by `subscription.subscriber.identifier`, rebuild them with `subscription.notifier.fromJson(...)`, and call `subscription.process(notification)`.

`subscription.process` runs outside the queue of the subscriber, so it may run in parallel with new notifications. `notifier.notify(notification)` dispatches to all subscribers at once, outside any transaction, and does not emit `onNotification`.

### 3.7. React at Commit Time

To react at once to each committed notification without a transaction (for example to clear a cache), override `notify` in the notifier and call `super.notify`:

```dart
@override
void notify(OrderPaid notification) {
  orderCache.remove(notification.orderUuid);
  super.notify(notification);
}
```

`notify` runs synchronously in the call that committed, before its `afterCommit` callbacks. Keep it fast and never let it throw: the data is committed, but the exception would make the call fail.

### 3.8. Push to Clients

Sing has no transport from server to clients. Build it in the application, for example a WebSocket hub in the server process:

- From a subscriber or an overridden `notify`, forward the notification to the hub, or
- From the service, register `callContext.afterCommit(() => hub.broadcast(...), key: ...)`.

In both cases, the push happens only after the commit.

### 3.9. Pitfalls

- **Notifier not registered yet.** A notification sent before its notifier is built is lost without error. Build every notifier at startup, before the HTTP server and before the batches.
- **Exception in `process`.** The subscriber transaction rolls back. The exception is then reported as an uncaught error of the zone where `subscribe` was called. In a plain `main()`, this can stop the server. Catch errors inside `process`.
- **Pool use.** Each subscriber holds a connection while it processes. Many subscribers and many notifications compete with HTTP calls for the pool.
- **Account.** `process` runs with the subscriber account. Give it the tokens it needs; `Account.system(...)` grants all.
- **Order between subscribers.** There is none. Do not make one subscriber depend on the work of another.

## 4. See Also

- [TRANSACTIONS.md](TRANSACTIONS.md): end of a transaction, `afterCommit`, `TransactionEnded`, sub-transactions.
- [QUERIES.md](QUERIES.md): write verbs and `ignoreListeners`.
- [SERVICES.md](SERVICES.md): writing services.
- [APP_SERVER.md](APP_SERVER.md): building the registry at startup.
