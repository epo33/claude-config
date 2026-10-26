# Data Classes

Sing moves entity data with a small set of classes, the same on the client and on the server:

| Class                      | Role                                                                                   |
| -------------------------- | -------------------------------------------------------------------------------------- |
| `DataRowValues<E>`         | Typed view of one row. `Order$Instance` is a generated alias. The class you use most.   |
| `FieldValue<T>`            | The value of one field of a row, with its state (has a value, null, updated).           |
| `DataRow<E>`               | The row itself: field values, state, version. `DataRowValues<E>` wraps it.             |
| `DataLoader<E>`            | A promise of rows, returned by searches, services and queries.                         |
| `DataPacket<E>`            | The result of a load: the result rows plus the rows resolved through references.        |
| `PagedDataLoader<E>`       | Reads a `DataLoader` page by page.                                                     |
| `DataRowCache<E, PK>`      | Client-side cache of rows by primary key.                                              |
| `Expect<E>`                | What a load returns: fields, resolutions, sorts, limit.                                |

Sources: `sing_core/lib/src/data_row/` (`data_row.dart`, `data_row_values.dart`, `intfs.dart`, `scalar.dart`, `data_loader.dart`, `paginated_data_loader.dart`, `data_packet.dart`, `data_row_cache.dart`, `expect.dart`). References (`Reference<E>`, `FieldValueRef`) are described in [Relationships](CONCEPTS_RELATIONSHIPS.md#3-references-at-runtime).

## 1. `DataRowValues<E>` and `Xxx$Instance`

### 1.1. Typed Access to Fields

For each entity, the build generates in the common package:

- `typedef Order$Instance = DataRowValues<Order>;`
- `extension DataRowValues$Order on DataRowValues<Order>` with one getter per field.

The getter returns the `FieldValue` of the field, typed by the field:

| Field in the model                     | Getter type on `Order$Instance`         |
| -------------------------------------- | --------------------------------------- |
| `StringField(...)`                     | `FieldValue<String>`                    |
| `DateTimeField.utc()`                  | `FieldValue<UtcDateTime>`               |
| `EnumField<OrderStatus>()`             | `FieldValue<OrderStatus>`               |
| `ReferenceTo<CustomerEntity>()`        | `FieldValueRef<Customer, String>`       |
| array field                            | `FieldValueList<T>`                     |

The Dart compiler then checks every field access:

```dart
Order$Instance order = ...;

order.orderNumber.value = "QF-1254-5689";     // OK
order.orderNumber.value = 123456789;          // compile error: int is not String
order.orderNum.value = "QF-1254-5689";        // compile error: no such field
order.orderDate.value = DateTime.now();       // compile error: DateTime is not UtcDateTime
order.orderDate.value = UtcDateTime.now();    // OK
```

After a model change and a rebuild (`dart run sing_builder:sing_emit`), the compiler reports every access to a removed or retyped field, in services, servers and clients.

`order["orderNumber"]` gives the same `FieldValue` untyped. Use it only in generic code.

### 1.2. Members

| Member                | Type / effect                                                                      |
| --------------------- | ---------------------------------------------------------------------------------- |
| `$dataRow`            | The wrapped `DataRow<E>`.                                                          |
| `$state`              | `DataRowState` of the row (section 3.2).                                           |
| `$rowVersion`         | `int?` (section 4).                                                                |
| `$asReference`        | `Reference<E>` to this row (entities only).                                        |
| `operator [](name)`   | Untyped `FieldValue`.                                                              |
| `$extract((f) => [...])` | The values of a list of field chains, following resolved references. Every reference on a chain must be resolved. |
| `==` / `hashCode`     | Two values are equal when they wrap the same row or have the same primary key. Without a primary key: identity. |

Conversions: `rows.toValuesList()` (`Iterable<DataRow<E>>` to `List<DataRowValues<E>>`), `values.toDataRows()` (the reverse), `row.values`, `values.$dataRow`.

### 1.3. Creating a New Row

Ask the entity definition for a row: `$Order.of(dataRegistry)` on both sides, or `$Order.ofContext(callContext)` on the server.

```dart
// Then fill it through the typed view
final order = Order$Instance($Order.of(dataRegistry).createDataRow());
order.orderNumber.value = "QF-1254-5689";
order.orderDate.value = UtcDateTime.now();
order.customer.primaryKey = customerUuid;

// Same thing in one expression
final order = $Order.of(dataRegistry).createInstance(
  filler: (order) => order
    ..orderNumber.value = "QF-1254-5689"
    ..orderDate.value = UtcDateTime.now()
    ..customer.primaryKey = customerUuid,
);

// Or on the DataRow
final row = $Order.of(dataRegistry).createDataRow()
  ..fill((order) => order.orderNumber.value = "QF-1254-5689");
```

A new row:

- has the state `inserted`;
- holds the default value of fields that declare one, `null` in nullable fields, and **no value** in the other fields;
- already holds its key when the key is `UuidField(autoAllocate: true)`.

Then save it:

```dart
// Server
final saved = await $Order.query(callContext).insertRow(order.$dataRow).exactlyOne();
final saved = await $Order.query(callContext)
    .insertNewRow((order) => order..orderNumber.value = "QF-1254-5689" /* ... */)
    .exactlyOne();

// Client: OrderHub's Order has only @LoadServices, so it saves through
// its custom service OrderServices.addOrder
final saved = await $Order
    .services(dataRegistry)
    .addOrder(order: order, orderLines: lines)
    .exactlyOne();

// Client: entity with @StdEntityServices or @InsertServices
// (hypothetical here: OrderHub entities only carry @LoadServices)
final saved = await $Product.services(dataRegistry).insertThis(data: product.$dataRow).exactlyOne();
```

The returned row is the row as the database stored it (state `initial`). Keep using it, not the row you sent. See [queries](QUERIES.md) and [services](SERVICES.md) for the other write verbs.

### 1.4. Reading and Writing a `FieldValue`

| Member                       | Behavior                                                                                         |
| ---------------------------- | ------------------------------------------------------------------------------------------------ |
| `hasValue`                   | `false` when the field was never set or was not loaded (section 2.4).                            |
| `value` (get)                | The value. **Throws** `AppError` `fieldWithoutValue` when `hasValue` is false. On a null nullable field, returns the technical default (`""`, `0`...), not `null`. |
| `valueOrNull` (get)          | The value, or `null` when the field is null or has no value. **Use it for nullable fields.**    |
| `value = x` / `setValue(x)`  | Sets the value (checked by the field: length, bounds...). Marks the field as updated.            |
| `valueOrNull = x`            | Same, and accepts `null`.                                                                        |
| `clear()`                    | Empties the field: `null` for a nullable field, "no value" for a mandatory one.                  |
| `isNull` / `isNotNull`       | `isNull` is also true when `hasValue` is false.                                                  |
| `updated`                    | `true` when the field was set since the row was created or read.                                 |
| `isNullable`, `isImmutable`, `isReadOnly`, `field`, `fieldName` | Field properties.                                              |

```dart
final notes = order.notes.valueOrNull;          // String?, nullable field
order.notes.valueOrNull = null;                 // clear a nullable field
final total = order.totalAmount.value;          // double, mandatory field
```

**Immutable fields** (`.immutable()`) accept one assignment. Assigning a different value to a field that already holds one throws `"Field x can be assigned only once."`. On a new row, an immutable field that has a default value, or an immutable nullable field (it holds `null`), already holds a value: it cannot be changed.

`DataRow.missingMandatoryFields` lists the mandatory fields still without value. Check it before sending a new row; the server refuses the row otherwise.

## 2. `DataLoader<E>`

### 2.1. A Promise, Not Data

Searches, load services, query verbs and most custom services return a `DataLoader<E>`:

```dart
// Client
final orders = $Order.services(dataRegistry).search(status: Search.equal(OrderStatus.pending));

// Server
final orders = $Order.query(callContext).load(where: (f) => f.status.$equal(OrderStatus.pending));
```

Nothing runs yet. The call (HTTP or SQL) happens when you call a terminal method. Shaping methods (`fields`, `resolve`, `sort`) return a new loader; they are marked `@useResult`.

### 2.2. Terminal Methods

| Method                     | Returns                          | Behavior                                                                  |
| -------------------------- | -------------------------------- | ------------------------------------------------------------------------- |
| `listValues({int? limit})` | `Future<List<DataRowValues<E>>>` | All rows. Most used.                                                      |
| `list({int? limit})`       | `Future<List<DataRow<E>>>`       | All rows, as `DataRow`.                                                   |
| `exactlyOne()`             | `Future<DataRowValues<E>>`       | Throws `AppError` `noDataFound` when empty, `tooManyRows` when more than one row. |
| `one()`                    | `Future<DataRowValues<E>?>`      | `null` when empty. Throws `tooManyRows` when more than one row.           |
| `first()`                  | `Future<DataRowValues<E>>`       | First row (reads with limit 1). Throws `noDataFound` when empty.          |
| `firstOrNull()`            | `Future<DataRowValues<E>?>`      | First row or `null`.                                                      |
| `loadDataPacket({int? limit})` | `Future<DataPacket<E>>`      | The whole packet, resolved rows included (section 5).                     |
| `count()`                  | `Future<int>`                    | Read loader: number of matching rows. Write loader: number of rows written. |
| `execute()`                | `Future`                         | Same as `count()`, result ignored. Use it to run a write without reading rows back. |
| `pages({int? rowPerPage})` | `PagedDataLoader<E>`             | Page-by-page reading (section 2.6).                                       |

```dart
// Client
final order = await $Order.services(dataRegistry).loadThisKey(key: uuid).exactlyOne();
final maybe = await $Order.services(dataRegistry).loadThisKey(key: uuid).one();
final pending = await $Order.services(dataRegistry)
    .search(status: Search.equal(OrderStatus.pending))
    .listValues();

// Server
final pendingCount = await $Order.query(callContext)
    .load(where: (f) => f.status.$equal(OrderStatus.pending))
    .count();
await $Order.query(callContext)
    .delete(where: (f) => f.status.$equal(OrderStatus.cancelled))
    .execute();
```

`first()` and `firstOrNull()` do not sort: add `sort(...)` when the order matters.

### 2.3. Shaping Results: `fields`, `resolve`, `sort`

All three take a builder `(fields) => [...]` that receives the typed field view of the entity. A reference in this view is navigable: `fields.customer.name` (see [Relationships](CONCEPTS_RELATIONSHIPS.md#5-navigating-through-references)).

```dart
final orders = await $Order
    .query(callContext)
    .load(where: (f) => f.status.$equal(OrderStatus.pending))
    .fields((f) => [f.orderNumber, f.orderDate, f.customer.name])
    .resolve((f) => [f.shippingAddress])
    .sort((f) => [-f.orderDate, f.orderNumber])
    .listValues(limit: 100);
```

| Method          | Effect                                                                                                                       |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `fields(...)`   | Reads only these fields (section 2.4). Primary keys are always added. A chain through a reference also resolves the reference. |
| `resolve(...)`  | Loads the rows the listed references point to, in the same call (one transaction for a client call). Read them with `order.customer.dataRowValues`. |
| `sort(...)`     | Sort order, applied by the database. Prefix `-` for descending. `f.notes.withNullsFirst(true)` sets the place of nulls. A chain through a reference also resolves the reference. |
| `expect(fields:, resolutions:, sorts:, limit:)` | The three above in one call, plus a default limit.                                             |

Each call replaces the previous list of the same kind: `.sort(a).sort(b)` sorts on `b` only.

`limit` only cuts the result. It does not add a sort. Without `sort(...)`, the row order is not defined.

### 2.4. Partial Rows

With `fields(...)`, the other fields are **not loaded**: their `hasValue` is false, `value` throws and `valueOrNull` returns `null`.

```dart
final order = await $Order
    .services(dataRegistry)
    .loadThisKey(key: uuid)
    .fields((f) => [f.orderNumber, f.customer.name])
    .exactlyOne();
order.orderNumber.value;                       // OK
order.customer.dataRowValues.name.value;       // OK: customer resolved by the chain
order.orderDate.value;                         // throws: not loaded
```

Do not send a partial row back for an update expecting the missing fields to be kept or written: only the loaded and updated fields travel.

### 2.5. Building a Loader in a Service

A service can return a loader that runs its own code first. `DataLoader.defered` receives the expectations of the caller (`fields`, `resolve`, `sort`, limit) and must apply them to the loader it returns. From `example/model/lib/model/orders/order.services.dart`:

```dart
DataLoader<Order> addOrder({
  required CallContext callContext,
  required Order$Instance order,
  required Iterable<OrderLine$Instance> orderLines,
}) {
  return DataLoader<Order>.defered($Order.ofContext(callContext), (expect) async {
    order = await $Order.query(callContext).insertRow(order.$dataRow).exactlyOne();
    for (final line in orderLines) {
      line.order.primaryKey = order.uuid.value;
    }
    await $OrderLine.query(callContext)
        .insertRows(orderLines.map((line) => line.$dataRow))
        .execute();
    return $Order.query(callContext).loadRef(order.$asReference).withExpectations(expect);
  });
}
```

Other constructors and helpers:

- `DataLoader.fromRows(entityDef, rows)`: a loader over rows already in memory. `fields`, `resolve`, `sort` and `limit` have no effect on it.
- `loader.withExpectations(expect)`: the same loader with other expectations.

### 2.6. Pages: `PagedDataLoader<E>`

```dart
final pager = $Order
    .services(dataRegistry)
    .search(status: Search.equal(OrderStatus.pending))
    .sort((f) => [-f.orderDate])
    .pages(rowPerPage: 50);              // default 100

while (pager.hasMoreData) {
  final rows = await pager.nextPage();   // Iterable<DataRow<Order>>
  // ...
}
final total = await pager.totalRowCount;
```

| Member                         | Behavior                                                                          |
| ------------------------------ | --------------------------------------------------------------------------------- |
| `nextPage()`                   | Next rows. Returns an empty list when no more data or when a page is loading.     |
| `hasMoreData`, `rowsRead`, `loading` | Progress.                                                                   |
| `totalRowCount`                | `Future<int>`: a `count()` call, or `rowsRead` once all pages are read.           |
| `reset({pageSize})`            | A new pager from the first page.                                                  |
| `PagedDataLoader.empty(entityDef)` | A pager with no rows.                                                         |

Rules:

- `pages()` **throws** "Paginated result needs a predictive sort order" when no `sort(...)` is set (except on `DataLoader.fromRows`).
- The primary key is appended to the sort, so pages never overlap.
- When the service does not apply the limit and offset (for example a deferred loader that computes all rows), the first page holds all the rows and `hasMoreData` becomes false.

See also [search results and pages](SEARCHES.md#32-result-sort-limit-pages).

## 3. `DataRow<E>` and `DataRowState`

### 3.1. `DataRow<E>`

`DataRow<E>` holds the field values, the state and the version of a row. Write services take a `DataRow` (`insertRow(row)`, `insertThis(data: row)`); otherwise prefer `DataRowValues<E>`.

| Member                                | Behavior                                                                                   |
| ------------------------------------- | ------------------------------------------------------------------------------------------ |
| `values`                              | `DataRowValues<E>` view.                                                                   |
| `state`, `stateBeforeDelete`          | Current state; state before `delete()`.                                                    |
| `fromDataStore`                       | `true` unless the state is `inserted`.                                                     |
| `hasChange`                           | `true` when the state is not `initial` and at least one field is updated.                  |
| `updatedFields(withPrimaryKeys: bool)`| The updated `FieldValue`s, plus the keys when asked.                                       |
| `missingMandatoryFields`              | Mandatory fields without value (server-only fields excluded).                              |
| `delete()` / `undelete()`             | Marks the row as deleted / restores the previous state. Nothing is written.               |
| `forceUpdated()`                      | Marks every field as updated (state `initial` becomes `updated`).                          |
| `fill((values) => ...)`               | Runs the filler on `values`, returns the row.                                              |
| `asReference`                         | `Reference<E>` to the row.                                                                 |
| `dataPacket`                          | The packet holding the row, `null` for a row from `createDataRow()`.                       |
| `copyWith({initializer, dataPacket})` | A new row with the same values. Cannot target the packet of the source row.                |
| `inDataPacket(packet)`                | The copy of this row in another packet (created once).                                     |
| `toJson()` / `DataRow.fromJson(dataRegistry, json)` | Wire form (see [JSON](AUTO_JSON.md)).                                        |
| `$rowVersion`, `$checkRowVersion`, `adoptRowVersion(saved)` | Section 4.                                                           |

### 3.2. States

`DataRowState` has four values, each with a test getter (`isInitialState`, `isInserted`, `isUpdated`, `isDeleted`):

| State      | Meaning                                  | Reached by                                                                 |
| ---------- | ---------------------------------------- | -------------------------------------------------------------------------- |
| `inserted` | New row, not stored yet.                 | `createDataRow()`, `createInstance()`, `DataRow(entityDef)`.               |
| `initial`  | Row read from storage, not modified.     | Any read (search, load, query, the row returned by a write).               |
| `updated`  | Row read from storage, then modified.    | Setting a field of an `initial` row. `forceUpdated()`.                     |
| `deleted`  | Row marked for deletion.                 | `delete()`. `undelete()` goes back to the previous state.                  |

Rules:

- An `inserted` row stays `inserted` when you set its fields.
- Setting a field back to its old value does not return the row to `initial`.
- The state travels in JSON (`$state`). A server receiving a row trusts it to choose the write.

### 3.3. Saving Rows by State (Server)

`postChanges(callContext)` (an extension on `Iterable<DataRow<E>>`, `sing_server/lib/src/post_data_rows.dart`) writes a list of rows of one entity according to their state: inserts the `inserted` rows, updates the `updated` rows (updated fields only), deletes the `deleted` rows. `initial` rows are ignored.

```dart
final lines = await $OrderLine.query(callContext)
    .load(where: (f) => f.order.$pointToKey(orderUuid))
    .list();
lines.first.values.quantity.value = 3;     // -> updated
lines.last.delete();                       // -> deleted
await lines.postChanges(callContext);
```

## 4. Row Version

A row of a versioned entity (see [row version column](DATA_MODEL.md#9-row-version-column)) carries its version as metadata, beside its state, not as a field value:

| Member | Role |
| ------ | ---- |
| `DataRow.$rowVersion` / `DataRowValues.$rowVersion` | `int?`, the `_version` read with the row; `null` for a row never read (new row, entity not versioned) |
| `DataRow.$checkRowVersion` | `bool`, set by the caller to have the next update refused when the stored version differs |
| `DataRow.adoptRowVersion(saved)` | takes the version of the row the server returned after a save |

Every read of a versioned entity returns the version, whatever the fields asked for (`fields(...)`, references resolved, RETURNING of writes). It travels in JSON under `$rowVersion` and `$checkRowVersion`, follows `copyWith` and `inDataPacket`, and is never counted as a change (`hasChange`, `updatedFields`).

The client services `updateThis`/`updateThose` and `upsertThis`/`upsertThose` call `adoptRowVersion` on the rows you sent, so a second update of the same row checks against the new version.

`DataRow.metadataKeys` lists every metadata key of the JSON form (`$entity`, `$state`, `$updated`, `$rowVersion`, `$checkRowVersion`). Code that hashes or compares `toJson()` must leave them out: the version changes on every write.

See also [optimistic locking](QUERIES.md#38-optimistic-locking-row-version).

## 5. `DataPacket<E>`

Every load produces a `DataPacket<E>`. The rows you get from `list()` or `listValues()` belong to it (`row.dataPacket`). It holds:

- the **result** rows, of type `E`;
- the rows loaded by `resolve(...)`, of any entity, indexed by reference;
- the **masked** references: references the server did not resolve on purpose (see [masked references](CONCEPTS_RELATIONSHIPS.md#33-loading-the-referenced-row-resolve)).

A reference field finds its target row through the packet of its own row. This is why `order.customer.dataRowValues` works only on rows read with `resolve(...)`.

```dart
final packet = await $Order.services(dataRegistry)
    .search(status: Search.equal(OrderStatus.pending))
    .resolve((f) => [f.customer])
    .loadDataPacket();

final orders = packet.result.toValuesList();                 // the orders
final customers = packet.dataRowValuesOf<Customer>();        // every customer in the packet
final customer = packet.dataRowValues(orders.first.customer.value);  // DataRowValues<Customer>?
```

| Member                                        | Behavior                                                                       |
| --------------------------------------------- | ------------------------------------------------------------------------------ |
| `result`                                      | Result rows (`Iterable<DataRow<E>>`).                                          |
| `dataRows`                                    | All rows, result and resolved.                                                 |
| `dataRowsOf<T>()` / `dataRowValuesOf<T>()`    | All rows of entity `T`.                                                        |
| `dataRow(ref)` / `dataRowValues(ref)`         | The row a reference points to, or `null`.                                      |
| `contains(ref)`, `isMasked(ref)`, `markMasked(refs)` | Lookup and masking of references.                                      |
| `appendRows(rows, {inResult})`, `appendRowValues(values)`, `append(packet)` | Copies rows into the packet (rows already in another packet are copied, once). Returns the copies. |
| `loadDataRow(loader)` / `loadDataRowValues(loader)` | Runs a loader and appends its rows.                                      |
| `addToResult(row)`                            | Adds a row of the packet to the result.                                        |
| `changeStream`                                | `Stream<DataRowChange>` (`({DataRow row, FieldValue? field})`), events grouped and sent after the current microtasks. |
| `paginated`                                   | `true` when the server applied limit, offset and sort (pages).                 |
| `clear()`                                     | Empties the packet.                                                            |

A packet travels in JSON as `{"$entity", "resultRows", "dataRows", "paginated", "maskedRefs"}` (see [JSON](AUTO_JSON.md)).

## 6. `DataRowCache<E, PK>`

A client-side cache of rows of one entity, indexed by primary key. All the rows share one `DataPacket`, so references between cached rows resolve.

```dart
final customers = DataRowCache<Customer, String>(
  $Customer.of(dataRegistry),
  dataLoader: (keys) => $Customer.services(dataRegistry).loadThoseKeys(keys: keys),
);

await customers.needRows([customerUuid]);          // loads only the missing keys
final customer = customers[customerUuid];           // DataRowValues<Customer>?
final row = customers(customerUuid);                // DataRow<Customer>?
```

| Member                                     | Behavior                                                             |
| ------------------------------------------ | -------------------------------------------------------------------- |
| `needRows(keys)`                           | Returns the rows, loading the missing ones through `dataLoader`.     |
| `load(keys)` / `reload(key)`               | Loads (again) through `dataLoader`.                                  |
| `addDataLoaderRows(loader)` / `add(rows)`  | Adds rows from a loader / from memory.                               |
| `[key]`, `call(key)`, `contains(key)`      | Lookup.                                                              |
| `dataRows`, `dataValues`                   | All cached rows.                                                     |
| `remove(key)`, `removeWhere(test)`, `clear()` | Removal.                                                          |
| `changeStream`                             | `Stream<Iterable<DataRow<E>>>` of added rows.                        |
| `dispose()`                                | Closes the streams and the dependent caches.                         |

The `expect:` constructor parameter applies the same `fields`/`resolve`/`sort` to every load. `primaryKey:` selects another key field (a reference field is accepted).

**Dependent cache.** `DataRowCache.keepInSync` shares the packet of a master cache and loads its own rows each time rows are added to the master:

```dart
final addresses = DataRowCache<Address, String>.keepInSync(
  $Address.of(dataRegistry),
  masterCache: customers,
  whenMasterRowsChange: (rows) => $Address.services(dataRegistry).loadThoseKeys(
    keys: rows.cast<Customer$Instance>().map((c) => c.address.primaryKey!),
  ),
);
// After customers.needRows(...), customer.address.dataRowValues works.
```

The master's `entityDataLoaded<Address>()` is false while the dependent load runs or after it failed. Failures go to the master's `errorStream` and to the current `Zone`.

## 7. `Expect<E>`

`Expect<E>` is the object behind `fields`, `resolve`, `sort` and `limit`: `fieldList`, `resolutions`, `sorts`, `limit`, `firstRow`. It travels from the client to the server with each data loader call. You build one directly only for low-level APIs (`DataRowCache(expect:)`, `resolveReferences(..., Expect())`, `loader.withExpectations(...)`):

```dart
final expect = Expect<Order>(
  fieldList: [$Order.of(dataRegistry).fieldsView.orderNumber],
);
```

Field chains of an `Expect` must start on `E` (or a descendant entity of `E`).
