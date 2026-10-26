# Server Queries

This document explains how server code reads and writes the database with Sing: the `Query` verbs, subqueries, the engine builder (joins, groups, projections, CTEs, compounds), transactions and raw SQL. The expression DSL used inside the callbacks (`$equal`, `$keyValue`, `$sum`...) is in [QUERY_EXPRESSIONS.md](QUERY_EXPRESSIONS.md).

Sources: `sing_server/lib/src/query/query.dart` (the `Query` verbs), `sing_server/lib/src/engine/select/` (builder), `sing_server/lib/src/engine/dml/` (write orders). The examples use the OrderHub model of `example/model/lib/model`.

## 1. Basics

### 1.1. Entry Point

```dart
final query = $Order.query(callContext);   // Query<Order, String>
```

- `$Order` is generated for every entity (`example/model/lib/sing/order_hub/orders/order.dart`). `Query<E, PK>` is typed by the entity and its primary key type. For an entity without primary key, `PK` is `Never`: the key verbs exist but cannot be called.
- Inside the services of an entity, `$query` is the same `Query` for the current call (see [SERVICES.md](SERVICES.md)).
- A `CallContext` is required. It carries the database transaction and the user account. Queries therefore run on the server only.
- `$Order.ofContext(callContext)` returns the `ServerEntityDef<Order, String>`, needed by the builder and the engine orders.

### 1.2. Loaders Are Lazy: Always Run Them

Most verbs return a `DataLoader<E>` (see [DataLoader](DATA_CLASSES.md#2-dataloadere)). **Nothing runs until you call a terminal method.** A write without `.execute()` writes nothing and raises no error.

| Terminal | Result | Use |
| -------- | ------ | --- |
| `execute()` | `Future` | run a write, ignore the rows |
| `count()` | `Future<int>` | number of rows read or written; a write does not read rows back |
| `listValues({limit})` | `Future<List<DataRowValues<E>>>` | rows (for a write: the written rows, as stored) |
| `list({limit})` | `Future<List<DataRow<E>>>` | same, as `DataRow` |
| `exactlyOne()` | `Future<DataRowValues<E>>` | exactly one row, error otherwise |
| `one()` | `Future<DataRowValues<E>?>` | zero or one row |
| `first()` / `firstOrNull()` | `Future<DataRowValues<E>>` / `?` | first row |

Before the terminal, the expectations `fields(...)`, `resolve(...)`, `sort(...)` shape the result (columns, resolved references, extra sorts). A service returns the `DataLoader` itself: the caller's expectations then apply.

### 1.3. Callbacks Receive Expressions

Every `where`, `orderBy`, `what`... callback receives the field **expressions** of the entity and returns a `Predicate`, a `ValueExpr` or a list of them. A `where` callback may return `null`: no condition. See [QUERY_EXPRESSIONS.md](QUERY_EXPRESSIONS.md).

```dart
where: (fields) => fields.status.$equal(OrderStatus.pending)   // not ==
```

## 2. Reading

### 2.1. Load with a Filter

```dart
final orders = await $Order.query(callContext).load(
  where: (fields) =>
      fields.status.$equal(OrderStatus.pending) &
      fields.totalAmount.$greaterOrEqual(100.0),
  orderBy: (fields) => [fields.orderDate.$desc, fields.orderNumber.$asc],
  limit: 20,
  offset: 0,
).listValues();
```

All parameters are optional: `load()` reads every row. The loader's `sort(...)` expectations are added after `orderBy`. `listValues(limit: n)` and the loader's pagination replace `limit` and `offset`.

### 2.2. Load by Key or Reference

```dart
final order = await $Order.query(callContext).loadKey(orderId).exactlyOne();
final maybe = await $Order.query(callContext).loadKey(orderId).one();
final orders = await $Order.query(callContext).loadKeys(orderIds).listValues();
final byRef = await $Order.query(callContext).loadRef(orderRef).exactlyOne();
final byRefs = await $Order.query(callContext).loadRefs(orderRefs).listValues();
```

An empty key list returns an empty loader without querying.

### 2.3. Count

```dart
final pending = await $Order.query(callContext).count(
  where: (fields) => fields.status.$equal(OrderStatus.pending),
);

// COUNT(DISTINCT customer)
final customers = await $Order.query(callContext).count(
  what: (fields) => fields.customer,
  distinct: true,
);
```

`count` returns a `Future<int>` directly. `load(where: ...).count()` gives the same `COUNT(*)`.

### 2.4. Raw Column Values

`values` reads columns without building rows. The result is a `List<List>`: one inner list per row, one value per column, in column order. Each value is decoded by the type of its column when that type is known.

```dart
final rows = await $Order.query(callContext).values(
  columns: (fields) => [fields.orderNumber, fields.totalAmount],
  where: (fields) => fields.status.$equal(OrderStatus.shipped),
);
final firstNumber = rows.first[0] as String;

// Aggregated columns
final totals = await $Order.query(callContext).values(
  columns: (fields) => [fields.customer.$keyValue, fields.totalAmount.$sum()],
  groupBy: (fields) => [fields.customer],
  having: (fields) => fields.totalAmount.$sum().$greaterThan(1000.0),
);
```

For typed rows of computed columns, use a projection (section 5.4).

### 2.5. One Value

`oneValue` builds a scalar subquery (`QueryExpr<T>`). `getValue()` runs it on its own:

```dart
final average = await $Order.query(callContext).oneValue(
  what: (fields) => fields.totalAmount.$avg(),
  where: (fields) => fields.status.$equal(OrderStatus.delivered),
).getValue();   // Future<double?>
```

`getValue()` returns `null` unless the query gives exactly one row with one value of type `T`. It works only on `Query.oneValue` and the generated `valueFromX`, not on the builder's `oneValue`. The same `QueryExpr` also fits inside another query (section 4.2).

### 2.6. What a Read Applies

- **Field access tokens**: a field the user may not read is not returned (its value is absent from the row).
- **Inheritance**: loading a descendant entity filters on its selector. Loading an ancestor returns each row as its own descendant type.
- **Not applied**: the entity read token and the filters of the search services (mixin filters). `$X.query(...)` reads every row the predicate selects. A service that exposes query results must check what the caller may see.

### 2.7. Automatic Joins

Navigating a reference in an expression adds the join:

```dart
// Orders of French customers shipped abroad
final orders = await $Order.query(callContext).load(
  where: (fields) =>
      fields.customer.address.country.$equal("FR") &
      fields.shippingAddress.country.$ifNullThen("FR").$different("FR"),
).listValues();

// SELECT T1.* FROM order T1
//   INNER JOIN customer T2 ON T2.uuid = T1.customer
//   INNER JOIN address T3 ON T3.uuid = T2.address
//   LEFT JOIN address T4 ON T4.uuid = T1.shipping_address
// WHERE T3.country = ?p1 AND COALESCE(T4.country, ?p2) != ?p3      (simplified)
```

- A non-null reference gives an `INNER JOIN`, a nullable one a `LEFT JOIN`.
- One path is joined once, however many times it is used.
- To join in the other direction (the lines of an order), use an EXISTS subquery (section 4.1) or an explicit join (section 5.2).

## 3. Writing

All write verbs return a `DataLoader<E>`. Call `execute()` or `count()` to run them, or `listValues()`/`exactlyOne()` to run them and get the written rows back as the database stored them (defaults applied, generated keys, new row version).

### 3.1. Insert

```dart
// One row
final order = await $Order.query(callContext).insertRow(orderRow).exactlyOne();

// A new row filled in place
final created = await $Order.query(callContext).insertNewRow(
  (values) => values
    ..orderNumber.value = "ORD-001"
    ..orderDate.setToNow(callContext)
    ..customer.primaryKey = customerId
    ..taxRate.value = 0.2
    ..subtotal.value = 100.0
    ..taxAmount.value = 20.0
    ..shippingCost.value = 5.0
    ..totalAmount.value = 125.0,
).exactlyOne();

// Several rows
final inserted = await $OrderLine.query(callContext).insertRows(lineRows).count();
```

- `insertNewRow` creates the row through the entity definition: an auto-allocated `UuidField` key is already set.
- Each row is checked before the write: a required field without value raises `AppError(DataErrorCodes.codeFieldWithoutValue)` (`sing.errors.fieldWithoutValue`, parameter `field`).
- `setToNow(callContext)` on a date field value is a server extension (`sing_server/lib/src/extensions.dart`); `setToNowIfNull` also exists.

### 3.2. Update Loaded Rows

```dart
final order = await $Order.query(callContext).loadKey(orderId).exactlyOne();
order.status.value = OrderStatus.shipped;
order.shippedAt.setToNow(callContext);
await $Order.query(callContext).updateRow(order.$dataRow).execute();
```

- Only the **modified** fields are written. The row is located by its primary key.
- A row with no modified field writes nothing.
- `updateRows(rows)` updates several rows.
- With `where:`, each row is located by a predicate built from its values instead of its key:

```dart
await $Order.query(callContext).updateRows(
  rows,
  where: (row, fields) =>
      fields.orderNumber.$equal(row.values.orderNumber.value),
).execute();
```

### 3.3. Update with a Predicate

`updateWhere` sets columns on every row that `where` selects, without loading them.

```dart
final cancelled = await $Order.query(callContext).updateWhere(
  set: (fields, set) => set.setValue(fields.status, OrderStatus.cancelled),
  where: (fields) =>
      fields.status.$equal(OrderStatus.pending) &
      fields.orderDate.$daysTo(UtcDateTime.now()).$greaterThan(30),
).count();
```

The `set` callback receives the entity **fields** (`Field` objects, from `EntityFieldsList<E>`) and a `FieldSetter<E>`:

| Method | SQL |
| ------ | --- |
| `set.setValue(field, value)` | `field = ?value` (a Dart value; `null` gives NULL; a reference field takes a `Reference<E>`) |
| `set.setExpr(field, (row) => expr)` | `field = expr`; `row` holds the **expressions** of the updated row |
| `set.setNull(field)` | `field = NULL` |
| `set.increment(field, n)` | `field = field + n` (numeric fields) |

Call several setters in the callback to set several columns:

```dart
// Recompute the totals of an order from its lines
await $Order.query(callContext).updateWhere(
  set: (fields, set) {
    set.setExpr(
      fields.subtotal,
      (order) => $OrderLine.query(callContext).oneValue(
        what: (line) => (line.quantity.$asDouble * line.unitPrice).$sum(),
        where: (line) => line.order.$keyValue.$equalExpr(order.uuid),
      ).$ifNullThen(0.0),
    );
    set.setExpr(
      fields.totalAmount,
      (order) => order.subtotal + order.taxAmount + order.shippingCost,
    );
  },
  where: (fields) => fields.uuid.$equal(orderId),
).execute();

// Decrease a stock
await $Product.query(callContext).updateWhere(
  set: (fields, set) => set.increment(fields.stockQuantity, -quantity),
  where: (fields) => fields.uuid.$equal(productId),
).execute();
```

- In one statement, every `setExpr` reads the values **before** the update: above, `totalAmount` uses the old `subtotal`. Run two updates when one column depends on another new value.
- `where` may navigate references (`fields.customer.address.country`). A `setExpr` may **not** navigate a reference (`StateError`): use a subquery or `updateSelect` (section 3.6).
- `updateWhere` is refused on an entity with change listeners unless `ignoreListeners: true` (section 3.7).
- On an entity stored in several tables (inheritance), each table gets its own UPDATE.

### 3.4. Upsert

Insert the row, or update the stored row that matches it.

```dart
final order = await $Order.query(callContext).upsertRow(orderRow).exactlyOne();
await $Order.query(callContext).upsertRows(orderRows).execute();
```

Three ways to find the stored row:

| Parameter | Matching | SQL | Notes |
| --------- | -------- | --- | ----- |
| none | same primary key | `INSERT ... ON CONFLICT (pk) DO UPDATE` | safe against concurrent inserts |
| `conflictOn: (fields) => [...]` | same values in these columns | `INSERT ... ON CONFLICT (cols) DO UPDATE` | a unique index must cover the columns; single-table entity only |
| `on: (row, stored) => predicate` | the row the predicate matches | `MERGE` (PostgreSQL 15+) | the predicate must match at most one row; no lock against a concurrent insert |

```dart
// Hypothetical DailySale entity: one row per (product, day), a unique index covers both columns
await $DailySale.query(callContext).upsertRows(
  rows,
  conflictOn: (fields) => [fields.product, fields.day],
).execute();

// Match on a business key without unique index
await $Order.query(callContext).upsertRows(
  rows,
  on: (row, stored) => stored.orderNumber.$equal(row.values.orderNumber.value),
).execute();
```

- `on` and `conflictOn` cannot be used together (`ArgumentError`).
- On conflict, every written column outside the key is rewritten from the new row.
- A batch that repeats the same conflict key runs row by row; the last row wins.
- On an entity stored in several tables, `on` reads the stored row first, then updates or inserts.

### 3.5. Delete

```dart
await $Order.query(callContext).deleteKey(orderId).execute();
await $Order.query(callContext).deleteKeys(orderIds).execute();
await $Order.query(callContext).deleteRef(orderRef).execute();
await $Order.query(callContext).deleteRefs(orderRefs).execute();

final deleted = await $Order.query(callContext).delete(
  where: (fields) =>
      fields.status.$equal(OrderStatus.cancelled) &
      fields.orderDate.$daysTo(UtcDateTime.now()).$greaterThan(90),
).count();
```

- `count()` deletes without reading the rows, unless a listener or a multi-table entity needs them. `listValues()` returns the deleted rows.
- `delete(where:)` is refused on an entity with change listeners unless `ignoreListeners: true`. Even then, the delete listeners still run: the rows are loaded first and passed to them. `deleteKey(s)` and `deleteRef(s)` always run the listeners.
- The `onDelete` action of each reference to the deleted entity applies (`ReferentialAction.cascade`, `setToNull`, `setDefault`, `error`). In OrderHub, deleting an order deletes its lines (`cascade`); deleting a customer that has orders fails (`error`), see section 7.2.

### 3.6. Insert or Update from a Select

`insertSelect` writes the rows of a select shaped as the target entity. Build the shape with the generated `$Target.project(...)` (every field) or `$Target.partialProject(...)` (some fields; the others get the database default). Section 5 explains the builder.

```dart
// Trace every shipped order
await $OrderAuditTrace.query(callContext).insertSelect(
  $Order.query(callContext)
      .select(where: (o) => o.status.$equal(OrderStatus.shipped))
      .projectPartial(
        (o) => $OrderAuditTrace.partialProject(
          uuid: SqlExpr<String>("gen_random_uuid()", const [], $adapter: null),
          orderNumber: o.orderNumber,
          newStatus: o.status,
          occurredAt: o.shippedAt,
          actor: "shipping-batch".toExpression(),
        ),
      ),
).execute();
```

A `UuidField(autoAllocate: true)` key is allocated by Dart when a row is created, not by the database: an INSERT from a select must compute it (above with `gen_random_uuid()`).

`updateSelect` sets columns from a select correlated to the updated row. The `source` callback receives the order: `order.subquery<S>(def, where:)` opens a select that may read `order.fields`. The select must give one row per updated row.

```dart
// Default the shipping address to the customer's address
await $Order.query(callContext).updateSelect(
  source: (order) => order
      .subquery<Customer>(
        $Customer.ofContext(callContext),
        where: (c) => c.uuid.$equalExpr(order.fields.customer.$keyValue),
      )
      .projectPartial(
        (c) => $Order.partialProject(shippingAddress: c.address.$keyValue),
      ),
  where: (o) => o.shippingAddress.$isNull,
).execute();
```

A projection takes a reference as its key (`$keyValue`). Both verbs are refused on an entity with change listeners (unless `ignoreListeners: true`) and on an entity stored in several tables.

### 3.7. Change Listeners and `ignoreListeners`

An entity may have change listeners (`EntityChangesListener`, `sing_server/lib/src/change_listener.dart`) for `before`/`after` insert, update, upsert and delete. The row verbs (`insertRow(s)`, `updateRow(s)`, `upsertRow(s)`, `deleteKey(s)`, `deleteRef(s)`) run them with the rows. The set verbs (`updateWhere`, `delete(where:)`, `insertSelect`, `updateSelect`) never see the rows, so they throw when listeners exist. Pass `ignoreListeners: true` only when skipping the listeners is correct for this write. Exception: `delete(where:, ignoreListeners: true)` still runs the delete listeners (it only removes the refusal).

### 3.8. Optimistic Locking (row version)

Every write that changes a row of a versioned entity increments its `_version` (see [row version](DATA_CLASSES.md#4-row-version)): update by key, `updateWhere`, `updateSelect`, upsert, merge. An insert stores 0. An update with no modified field writes nothing and keeps the version. On an entity stored in several tables, the root table is incremented even when only a descendant column changes.

The version is **checked only on demand**, row by row:

```dart
final order = await $Order.query(callContext).loadKey(orderId).exactlyOne();
order.status.value = OrderStatus.shipped;
order.$dataRow.$checkRowVersion = true;
await $Order.query(callContext).updateRow(order.$dataRow).execute();
```

The update then adds `AND _version = <read version>`. When no row is written, a second read finds the cause and raises an `AppError`, which rolls the transaction back (the whole batch of an `updateRows`):
- `DataErrorCodes.codeRowVersionConflict` (`sing.errors.rowVersionConflict`): the row was modified since it was read;
- `DataErrorCodes.codeRowDeleted` (`sing.errors.rowDeleted`): the row was deleted since it was read.

Both carry `entity` and `key` as parameters. A row asking for the check without a read version, or on an entity that is not versioned, is refused with an `ArgumentError`.

Rules:
- `updateWhere`, `updateSelect`, `updateRows(where:)` and the upsert of unchecked rows increment without checking.
- An upsert of a row that asks for the check and carries a read version runs as a checked update: a row deleted meanwhile raises `rowDeleted` and is not inserted again. These rows come back first and run the update listeners, not the upsert ones.
- Deletes are not checked.
- `fields.$rowVersion` is the version expression in a select or a predicate (on the queried entity only, not through a reference).

Client side, the standard services `updateThis`, `updateThose`, `upsertThis` and `upsertThose` copy the returned version into each sent row that asks for the check, so a second save of the same row does not conflict with the first:

```dart
row.$checkRowVersion = true;
await services.updateThis(data: row).execute();
```

### 3.9. Complete Example: Order with Lines

From `example/model/lib/model/orders/order.services.dart`. A service that must run `await` before it has a loader to return uses `DataLoader.defered`:

```dart
DataLoader<Order> addOrder({
  required CallContext callContext,
  required Order$Instance order,
  required Iterable<OrderLine$Instance> orderLines,
}) {
  return DataLoader<Order>.defered($Order.ofContext(callContext), (expect) async {
    if (orderLines.isEmpty) throw AppError("orderWithoutLines");
    order = await $Order.query(callContext).insertRow(order.$dataRow).exactlyOne();
    for (final line in orderLines) {
      line.order.primaryKey = order.uuid.value;
    }
    await $OrderLine
        .query(callContext)
        .insertRows(orderLines.map((line) => line.$dataRow))
        .execute();
    return $Order
        .query(callContext)
        .loadRef(order.$asReference)
        .withExpectations(expect);
  });
}
```

An `AppError` thrown in a service rolls the call back and reaches the client with its code and parameters.

## 4. Subqueries

A subquery built with `$X.query(callContext)` is **correlated** to the query it is rendered in: its callbacks may read the fields of the outer query.

### 4.1. EXISTS / NOT EXISTS

Sing generates three shortcuts per entity on `$X`:

| Generated | Same as | Returns |
| --------- | ------- | ------- |
| `$OrderLine.existsOrderLine(ctx)(where: ...)` | `$OrderLine.query(ctx).exists(where: ...)` | `Predicate` |
| `$OrderLine.notExistsOrderLine(ctx)(where: ...)` | `$OrderLine.query(ctx).notExists(where: ...)` | `Predicate` |
| `$OrderLine.valueFromOrderLine<T>(ctx, what:, where:, groupBy:, having:)` | `$OrderLine.query(ctx).oneValue(...)` | `QueryExpr<T>` |

```dart
// Orders with at least one line of more than 10 units
final orders = await $Order.query(callContext).load(
  where: (fields) => $OrderLine.existsOrderLine(callContext)(
    where: (line) =>
        line.order.$keyValue.$equalExpr(fields.uuid) &
        line.quantity.$greaterThan(10),
  ),
).listValues();

// Orders without lines
where: (fields) => $OrderLine.notExistsOrderLine(callContext)(
  where: (line) => line.order.$keyValue.$equalExpr(fields.uuid),
)
```

The correlation is the reference read as a key: `line.order.$keyValue.$equalExpr(fields.uuid)`. Navigation also works inside a subquery, which often removes a nested EXISTS:

```dart
// Products ordered in pending orders
final products = await $Product.query(callContext).load(
  where: (fields) => $OrderLine.existsOrderLine(callContext)(
    where: (line) =>
        line.product.$keyValue.$equalExpr(fields.uuid) &
        line.order.status.$equal(OrderStatus.pending),
  ),
).listValues();
```

### 4.2. Scalar Subqueries

`oneValue` (or `valueFromX`) gives a `QueryExpr<T>`, a `ValueExpr<T>` usable wherever a value fits:

```dart
// Orders whose total is above the sum of their lines
final orders = await $Order.query(callContext).load(
  where: (fields) => fields.totalAmount.$greaterThanExpr(
    $OrderLine.query(callContext).oneValue(
      what: (line) => (line.quantity.$asDouble * line.unitPrice).$sum(),
      where: (line) => line.order.$keyValue.$equalExpr(fields.uuid),
    ),
  ),
).listValues();
```

A scalar subquery must return at most one row. With `groupBy`, it returns one row per group: use it with `IN` (section 4.3), never as a single value.

### 4.3. IN and Quantified Comparisons

```dart
// Customers with more than 5 orders
final busy = $Order.query(callContext).oneValue(
  what: (o) => o.customer.$keyValue,
  groupBy: (o) => [o.customer],
  having: (o) => o.uuid.$count().$greaterThan(5),
);
final customers = await $Customer.query(callContext).load(
  where: (c) => c.uuid.$isInSelect(busy),
).listValues();

// Orders larger than every order of a customer
where: (o) => o.totalAmount.$greaterThanAll(
  $Order.query(callContext).oneValue(
    what: (other) => other.totalAmount,
    where: (other) => other.customer.$pointToKey(customerId),
  ),
)
```

Also `$isNotInSelect`, and `$lessThanAny/All`, `$lessOrEqualAny/All`, `$greaterThanAny/All`, `$greaterOrEqualAny/All` (see [QUERY_EXPRESSIONS.md](QUERY_EXPRESSIONS.md#24-subqueries)).

## 5. Engine Builder (select)

`query.select()` returns a `TupleSelect<E>`: the select of the entity rows, ready to run. Joins, filters, sorts, groups, projections, CTEs and compounds build up on it. The verbs of sections 2 and 3 are built on it. Use it when a verb is not enough.

- Clause methods change the select and return it, so calls chain: `where`, `orderBy`, `distinct`, `distinctOn`, `limit`, `offset` on `TupleSelect`; `having`, `groupBy` on `GroupedSelect`; `orderBy`, `limit`, `offset` on `CompoundSelect`.
- Transitions return a new object: `groupBy`, `groupingSets` (→ `GroupedSelect`), `project` (→ `ProjectedSelect`), `projectPartial`, `asCte` (→ `CteSource`), `union`/`intersect`/`except` (→ `CompoundSelect`).
- `select.fields` are the expressions of the root entity, usable in any later callback.
- A select built on its own with `TupleSelect<Order>($Order.ofContext(callContext))` is the same as `$Order.query(callContext).select()`.

### 5.1. Clauses and Fetch

```dart
final select = $Order.query(callContext)
    .select(where: (o) => o.status.$equal(OrderStatus.pending))
    .where((o) => o.totalAmount.$greaterThan(100.0))   // added with AND
    .orderBy((o) => [o.orderDate.$desc])
    .limit(20);

final orders = await select.fetch(callContext).listValues();   // DataLoader<Order>
final total = await select.count(callContext);                  // COUNT(*)
final rows = await select.values(callContext, (o) => [o.orderNumber, o.totalAmount]);
```

- `select(where:, orderBy:, limit:, offset:)` applies these clauses at once.
- `fetch(callContext)` returns the same `DataLoader<E>` as `load`.
- `count(callContext, what:, distinct:)` counts.
- `values` decodes each column by its type. `rawValues` returns the driver values as they are.
- `distinct()` adds `DISTINCT`. `distinctOn((o) => [...])` adds `DISTINCT ON`: the `orderBy` must start with the same expressions.

```dart
// Latest order of each customer
final latest = $Order.query(callContext)
    .select()
    .distinctOn((o) => [o.customer])
    .orderBy((o) => [o.customer.$asc, o.orderDate.$desc]);
```

### 5.2. Explicit Joins

`join<J>(def, on:, outer:)` joins another entity and returns its field expressions. They are usable in every later clause of the select.

```dart
final orders = $Order.query(callContext).select();
final lines = orders.join<OrderLine>(
  $OrderLine.ofContext(callContext),
  on: (line) => line.order.$keyValue.$equalExpr(orders.fields.uuid),
);
orders.where((o) => lines.quantity.$greaterThan(10)).distinct();
```

`outer: true` gives a `LEFT JOIN`. A join to children repeats the parent row once per child: add `distinct()` or prefer EXISTS (section 4.1) when you only filter.

### 5.3. Subqueries in the Builder

`subquery<S>(def, where:)` opens a select correlated to the current one. End it with `exists()`, `notExists()` or `oneValue((s) => expr)`:

```dart
final orders = $Order.query(callContext).select();
final bigLines = orders
    .subquery<OrderLine>(
      $OrderLine.ofContext(callContext),
      where: (line) => line.order.$keyValue.$equalExpr(orders.fields.uuid),
    )
    .where((line) => line.quantity.$greaterThan(10));
orders.where((_) => bigLines.exists());
```

The `existsX`, `notExistsX` and `valueFromX` of section 4 also work inside builder callbacks.

### 5.4. GROUP BY and Projections

`groupBy` returns a `GroupedSelect`. It accepts `having`, more `groupBy`, `values`, `oneValue`, `exists` and projections. To fetch typed rows, **project** them into a tuple. A tuple is a `ModelTuple` of the model: a row shape with fields and no table (see [Tuples](DATA_MODEL.md#8-tuples)).

```dart
// In the model
class CustomerStatTuple extends ModelTuple {
  CustomerStatTuple();

  @override
  String get tupleKey => "orders.customerStat";

  final customer = ReferenceTo<CustomerEntity>();

  final orderCount = IntField();

  final total = DoubleField();
}
```

Sing generates `$CustomerStat.project(...)` (non-null fields required, nullable fields optional) and `$CustomerStat.partialProject(...)` (all optional), with one `ValueExpr` parameter per field. Entities get the same two methods (`$Order.project`, `$Order.partialProject`). A reference parameter takes the **key** (`ValueExpr<String>` here): pass `$keyValue` of a reference field or a primary key expression.

```dart
ProjectedSelect<Order, CustomerStat> customerStats(CallContext callContext) {
  final orders = $Order.query(callContext)
      .select(where: (o) => o.status.$different(OrderStatus.cancelled));
  return orders
      .groupBy((o) => [o.customer])
      .having((o) => o.uuid.$count().$greaterThan(1))
      .project(
        (o) => $CustomerStat.project(
          customer: o.customer.$keyValue,
          orderCount: o.uuid.$count(),
          total: o.totalAmount.$sum(),
        ),
      );
}

final stats = await customerStats(callContext)
    .fetch(callContext)
    .resolve((s) => [s.customer])
    .listValues();
```

- `ProjectedSelect<S, P>`: `fetch(callContext)` returns a `DataLoader<P>` (references can be resolved; `sort(...)` works on the projected fields only); `count(callContext)` counts the rows (groups).
- `project` also works without `groupBy`, to fetch computed columns.
- `projectPartial` returns a `PartialProjectedSelect`, used only by `insertSelect` and `updateSelect`.
- Set `where` and `orderBy` **before** `groupBy`: the grouped select copies the clauses at that moment.
- `Expression.dbDefaut` as a projected value means "column default" in an INSERT from a select.

**Grouping sets** (`GROUP BY GROUPING SETS`): one aggregation level per set; the empty set is the grand total. `GroupingExpr([dims...])` tells the levels apart (a bit is set when the dimension is aggregated in that row). A select grouped by sets takes no further `groupBy`.

```dart
final levels = $Order.query(callContext).select().groupingSets((o) => [
  [o.customer, o.status],
  [o.customer],
  [],
]);
final rows = await levels.values(callContext, (o) => [
  o.customer.$keyValue,
  o.status,
  GroupingExpr([o.customer, o.status]),
  o.totalAmount.$sum(),
]);
```

### 5.5. Common Table Expressions

`asCte(name:)` turns a select with a full shape (an entity select, a `ProjectedSelect` or a compound) into a `CteSource<P>`. `TupleSelect<P>.onCte(cte)` selects from it. `joinCte<P>(cte, on:, outer:)` joins it. A source is declared once per statement, however many times it is used. Without `name`, a name is allocated.

```dart
final stats = customerStats(callContext).asCte(name: "stats");

// Select from the CTE
final big = TupleSelect<CustomerStat>.onCte(stats)
    .where((s) => s.total.$greaterThan(10000.0));
final rows = await big.fetch(callContext).listValues();

// Join the CTE
final customers = $Customer.query(callContext).select();
final joined = customers.joinCte<CustomerStat>(
  stats,
  on: (s) => s.customer.$keyValue.$equalExpr(customers.fields.uuid),
);
customers.where((_) => joined.orderCount.$greaterThan(3));
```

`RecursiveCteSource<P>(roots:, recurse: (self) => ..., all: true, name:)` builds a `WITH RECURSIVE`. `roots` and the select that `recurse` builds on `self` have the same shape `P`. The recursive branch must use `self` and may not group or aggregate. Example in `coverage/coverage_model/test/engine_render_test.dart` (search `RecursiveCteSource`).

### 5.6. Compounds (UNION, INTERSECT, EXCEPT)

Two selects of the same shape combine with `union`, `intersect` and `except` (`all: true` for the `ALL` variants). The `CompoundSelect<P>` takes `orderBy`, `limit` and `offset` on the shape fields. It runs with `fetch(callContext)` or `count(callContext)`, and can become a CTE.

```dart
final pending = $Order.query(callContext)
    .select(where: (o) => o.status.$equal(OrderStatus.pending));
final unpaid = $Order.query(callContext)
    .select(where: (o) => o.paidAt.$isNull);
final orders = await pending
    .union(unpaid)
    .orderBy((o) => [o.orderDate.$desc])
    .fetch(callContext)
    .listValues();
```

### 5.7. Reading the SQL

`toSql()` on a select, a projection, a compound or a write order returns the SQL text without running it. Pass `formatter: SqlFormatter.readable` for an indented text, and `context: SqlRenderContext()` to read the bound parameters.

```dart
print(select.toSql(formatter: SqlFormatter.readable));
```

## 6. Engine Write Orders (advanced)

The write verbs run engine orders (`sing_server/lib/src/engine/dml/`) that you may use directly on a `ServerEntityDef`: `InsertRows`, `InsertSelect`, `UpdateRow`, `UpdateWhere`, `UpdateSelect`, `UpsertRow`/`UpsertRows` (`ON CONFLICT`), `DeleteWhere` (also `.keys` and `.rows`), `MergeRows` (`MERGE`, PostgreSQL 15+). Each has `execute(callContext)` (row count), `returning(fields)` then `fetch(callContext)` (a `DataPacket<E>` of the returned rows) and `toSql()`.

**They skip** change listeners, field access tokens, required field checks, the row version check and the per-table dispatch of inherited entities. Prefer the verbs of section 3. Use an order only for a branch the verbs do not offer.

```dart
// Upsert that keeps the larger stock
final def = $Product.ofContext(callContext);
final upsert = UpsertRows<Product>(def, rows)
  ..doUpdateOnConflict(
    (existing, proposed, set) => set.setExpr(
      def.fieldList.stockQuantity,
      (_) => proposed.stockQuantity,
    ),
    where: (existing, proposed) =>
        existing.stockQuantity.$lessThanExpr(proposed.stockQuantity),
  );
await upsert.execute(callContext);

// MERGE on a business key
final merge = MergeRows<Order>.rows($Order.ofContext(callContext), rows)
  ..on((stored, incoming) => stored.orderNumber.$equalExpr(incoming.orderNumber))
  ..whenMatchedRewrite()
  ..whenNotMatchedInsert();
final written = await merge.execute(callContext);
```

- `UpsertRows`: the conflict target is the primary key unless `target:` is given. Without action, every inserted column outside the target and the key is rewritten. `doNothingOnConflict()` or `doUpdateOnConflict(build, where:)` replace this default.
- `MergeRows` branches: `whenMatchedUpdate`, `whenMatchedRewrite`, `whenMatchedDelete`, `whenMatchedDoNothing`, `whenNotMatchedInsert`, `whenNotMatchedDoNothing`, `whenNotMatchedBySourceDelete`, `whenNotMatchedBySourceUpdate` (PostgreSQL 17). Each takes an optional `and:` condition. `onPrimaryKey()` joins on the key. `MergeRows.select(def, (order) => ...)` takes a select source opened with `order.subquery`.
- `UpdateWhere` and the update branches take a `ColumnSetter` (`setValue`, `setExpr`, `setNull`, `increment`), the engine form of `FieldSetter`.

## 7. Transactions, Errors and Raw SQL

### 7.1. Transaction of a Call

- One service call runs in **one transaction**, on one connection. All queries made with its `CallContext` share it.
- The transaction commits when the call returns. It rolls back when the call throws.
- `callContext.mustRollback(true)` marks the transaction for rollback without throwing; the call then ends with `AppError.transactionAborted()`.
- `callContext.subTransaction((ctx) async { ... })` runs the callback in a **separate** transaction on its own connection, with its own `CallContext`. It commits on its own: it survives a later rollback of the parent. Use it for work that must be kept even when the call fails (a log, a counter). Inside, use only `ctx`, never the parent context.

### 7.2. Database Errors and Savepoints

The PostgreSQL driver turns some errors into typed exceptions (`sing_server/lib/src/db/db_exceptions.dart`):

| Exception | Cause |
| --------- | ----- |
| `DbUniqueConstraintException` | unique index violated (SQL state 23505) |
| `DbForeignKeyViolationException` | foreign key violated, e.g. deleting a row still referenced with `ReferentialAction.error` (23503) |
| `DbQueryCancelledException` | statement cancelled (57014) |
| `DbTransactionConflictException` | serialization failure or deadlock (40001, 40P01) |

After a failed statement, PostgreSQL refuses every other statement of the transaction. To catch the error and continue, run the statement in a savepoint:

```dart
try {
  await callContext.dbConnexion.withSavePoint(
    () => $Customer.query(callContext).deleteKey(customerId).execute(),
    trace: callContext.runningOperation,
  );
} on DbForeignKeyViolationException {
  throw AppError("customerHasOrders");
}
```

### 7.3. Raw SQL

Raw SQL runs on the connection of the call, in its transaction:

```dart
final def = $Order.ofContext(callContext);
final rows = await callContext.dbConnexion.executeQuery(
  "SELECT count(*) FROM ${def.qualifiedName} WHERE order_number LIKE ?prefix",
  trace: callContext.runningOperation,
  params: {"prefix": "TEST-%"},
);
```

- Parameters are named and written `?name` in the SQL. Never concatenate a user value into the SQL text.
- `rowCount: true` returns the number of affected rows instead of rows.
- Raw SQL skips everything Sing checks: listeners, access tokens, row versions, inheritance. Use it for database administration or statements the DSL cannot express. For a missing SQL function inside a typed query, prefer `SqlExpr` / `SqlPredicate` (see [Custom SQL](QUERY_EXPRESSIONS.md#14-custom-sql-fragments)).
- Table names come from `def.qualifiedName`; a column name from `def.fieldList.orderNumber.dbName`.

## 8. Security and Pitfalls

- Run every loader: a write without `execute()` / `count()` / `listValues()` does nothing.
- Use expression methods (`$equal`), never `==`, in callbacks.
- Values are always bound as parameters. Only `SqlExpr`, `SqlPredicate` templates and `executeQuery` take SQL text: never build that text from user input.
- `Query` applies field access tokens but not the entity read token nor the search filters (section 2.6). Check the caller's rights in the service.
- Prefer the verbs of section 3 to the engine orders and raw SQL: they run listeners, check required fields and keep row versions.
- Set `ignoreListeners: true` only after checking that skipping the listeners is correct.
- `$different(v)` drops NULL rows; use `nullSafe: true` when they must be kept.
- An aggregate over zero rows is NULL: add `$ifNullThen(...)` before writing it into a non-null column.
- A scalar subquery must return at most one row.
- `$asInt` / `$asDouble` / `$asA` change the Dart type only; `$cast` converts in SQL.
- Prefer `$daysTo(now)` for "how old"; `$daysFrom(now)` is negative for past dates.
- Use `exactlyOne()` when a row is required: it fails clearly instead of returning `null`.

## 9. Cheat Sheet

```dart
await $Entity.query(callContext)       // Query<E, PK>
    .verb(...)                         // load(where:), loadKey(pk), insertRows(rows), updateWhere(set:, where:), delete(where:)...
    .fields(...).resolve(...).sort(...)   // optional expectations (DATA_CLASSES.md)
    .listValues();                     // or exactlyOne(), one(), execute(), count()

$Entity.query(callContext).select()    // builder: TupleSelect<E>
    .where(...).orderBy(...)           // then join, groupBy, project, asCte, union...
    .fetch(callContext);               // DataLoader<E>
```

| Need | Code | Result |
| ---- | ---- | ------ |
| rows | `.load(where: ...).listValues()` | `List<DataRowValues<E>>` |
| row by key | `.loadKey(pk).exactlyOne()` / `.loadRef(ref).one()` | `DataRowValues<E>` / `?` |
| count | `.count(where: ...)` | `int` |
| columns | `.values(columns: ..., where: ...)` | `List<List>` |
| one value | `.oneValue(what: ..., where: ...).getValue()` | `T?` |
| insert | `.insertRow(row).exactlyOne()` / `.insertRows(rows).execute()` | row / - |
| insert new | `.insertNewRow((v) => v..f.value = x).exactlyOne()` | row |
| update rows | `.updateRow(row).execute()` / `.updateRows(rows).execute()` | - |
| update by predicate | `.updateWhere(set: (f, set) => ..., where: ...).count()` | `int` |
| upsert | `.upsertRows(rows).execute()`, `conflictOn:` or `on:` | - |
| delete | `.deleteKey(pk).execute()` / `.delete(where: ...).count()` | - / `int` |
| copy rows | `.insertSelect(select.projectPartial(...)).execute()` | - |
| update from select | `.updateSelect(source: (order) => ..., where: ...).execute()` | - |
| EXISTS | `$X.existsX(ctx)(where: ...)` | `Predicate` |
| scalar subquery | `$X.query(ctx).oneValue(...)` / `$X.valueFromX(ctx, ...)` | `QueryExpr<T>` |
| group | `.select().groupBy(...).project((f) => $T.project(...)).fetch(ctx)` | `DataLoader<T>` |
| separate transaction | `callContext.subTransaction((ctx) async { ... })` | `Future<T>` |

---

**See also:**
- [QUERY_EXPRESSIONS.md](QUERY_EXPRESSIONS.md) - the expression DSL
- [DATA_CLASSES.md](DATA_CLASSES.md) - DataRowValues, DataLoader, DataRow
- [SERVICES.md](SERVICES.md) - define and implement services
- [CONCEPTS_RELATIONSHIPS.md](CONCEPTS_RELATIONSHIPS.md) - entity relationships
- [TRANSACTIONS.md](TRANSACTIONS.md) - transactions, sub-transactions, `afterCommit`
- [ERRORS.md](ERRORS.md) - `AppError` and database exceptions
- [VIEW_ENTITIES.md](VIEW_ENTITIES.md) - entities computed by a CTE
- [CUBE.md](CUBE.md) - multidimensional aggregates without writing `groupBy`
- [DEBUGGING.md](DEBUGGING.md) - seeing the generated SQL
