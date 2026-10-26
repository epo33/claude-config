# View Entities

A view entity is an entity whose rows are computed by your code. It has fields and a primary key like any entity, but **no table and no SQL view** in the database. Use it for derived data: totals per order, statistics per customer.

Sources: `sing_model/lib/src/annotations.dart` (`ViewEntity`), `sing_server/lib/src/services.dart` (`$viewSource`, `$resolveViewKeys`), `sing_server/lib/src/entity.dart`. Example: `example/model/lib/model/orders/order_summary.dart` and `order_summary.services.dart`.

## 1. How Do I Declare a View Entity?

```dart
// order_summary.dart
import "package:model/model.dart";

export "order_summary.services.dart";

@ViewEntity()
@Implementor(OrderSummaryServices)
@TokenContext(mapping: {"read": AccessToken.me})
class OrderSummaryEntity extends ModelEntity {
  OrderSummaryEntity();

  final order = UuidField(autoAllocate: false).primaryKey();

  final lineCount = IntField();
}
```

Register it in its namespace like any entity: `final orderSummaries = OrderSummaryEntity();`.

- `@ViewEntity()` takes no argument.
- Give it a primary key. Here the key is the key of the order it summarizes: `UuidField(autoAllocate: false)`, because the view never creates keys.
- `@Implementor` names the mixin that computes the rows (section 2).
- Tokens work as for any entity (see [ACCESS_CONTROL.md](ACCESS_CONTROL.md)).
- Migrations create nothing for it. A normal reference to a view gets no foreign key.

## 2. How Do I Compute the Rows?

The mixin is `on EntityServerServices<View, PK>`. It can override two hooks. Each one answers a different need.

| Hook | Called when | Return | Default |
| --- | --- | --- | --- |
| `$resolveViewKeys(callContext, keys)` | Sing resolves references to the view (a `resolutions:` expectation, see 3.1) | `DataLoader<View>` with the rows of these keys | throws `StateError` |
| `$viewSource(callContext)` | a query reads the view fields through a reference (see 3.2) | `CteSource<View>` | `null`: the query throws `StateError` |

Override the hooks your application uses. Override both if you are not sure.

```dart
// order_summary.services.dart
import "package:model/model.dart";
import "package:model/sing/server.dart";

mixin OrderSummaryServices on EntityServerServices<OrderSummary, String> {
  @override
  CteSource<OrderSummary> $viewSource(CallContext callContext) =>
      TupleSelect<OrderLine>($OrderLine.of(callContext.dataRegistry))
          .groupBy((fields) => [fields.order])
          .project(
            (fields) => $OrderSummary.project(
              order: fields.order.$keyValue,
              lineCount: fields.uuid.$count(),
            ),
          )
          .asCte();

  @override
  DataLoader<OrderSummary> $resolveViewKeys(
    CallContext callContext,
    Iterable<String> keys,
  ) {
    final lines = TupleSelect<OrderLine>(
      $OrderLine.of(callContext.dataRegistry),
    )..where((fields) => fields.order.$keyValue.$isInList(keys));
    return lines
        .groupBy((fields) => [fields.order])
        .project(
          (fields) => $OrderSummary.project(
            order: fields.order.$keyValue,
            lineCount: fields.uuid.$count(),
          ),
        )
        .fetch(callContext);
  }
}
```

The building blocks (see [QUERIES.md](QUERIES.md)):
- `TupleSelect<E>(entityDef)` starts a select. `where(...)` adds a predicate and returns the same select.
- `groupBy(...)` then `project(...)` shape each row as a view row. `$OrderSummary.project(...)` is generated: it takes one named argument per view field.
- `.asCte()` turns the select into a `CteSource` for `$viewSource`.
- `.fetch(callContext)` turns it into a `DataLoader` for `$resolveViewKeys`.
- `fields.order.$keyValue` is the key held by a reference field.

`$resolveViewKeys` must return only the rows of `keys`. Both hooks must compute the same values: keep them in sync.

## 3. How Do I Use a View?

### 3.1. Through an Own-Key Reference

`ReferenceTo<View>.ownKey()` on a table entity points at the view row that has **the same key as the current row**:

```dart
class OrderEntity extends ModelEntity with UuidPrimaryKeyMixin {
  // ...
  final summary = ReferenceTo<OrderSummaryEntity>.ownKey();
}
```

Load an order and resolve its summary. Sing calls `$resolveViewKeys` with the keys it needs:

```dart
final orders = await $Order
    .query(callContext)
    .loadKey(orderUuid)
    .expect(
      fields: (fields) => [fields.uuid],
      resolutions: (fields) => [fields.summary],
    )
    .listValues();
final lineCount = orders.single.summary.dataRowValues.lineCount.value;
```

Rules of an own-key reference (checked by the generator):
- it points only at a `@ViewEntity`;
- the view key has the same type as the key of the row;
- it cannot be the primary key.

The reference has no column and is not sent in the row JSON. Its value is the row key. Setting it throws a `StateError`.

### 3.2. In a Query

A query can filter or sort on view fields through the reference. Sing joins the CTE of `$viewSource` with a `LEFT JOIN`:

```dart
final busyOrders = await $Order
    .query(callContext)
    .load(where: (fields) => fields.summary.lineCount.$greaterThan(10))
    .listValues();
```

### 3.3. From a Custom Service

A service can return view rows directly. Build them with `project(...)` and `fetch(callContext)`, as in `$resolveViewKeys` (see [SERVICES.md](SERVICES.md)):

```dart
DataLoader<OrderSummary> summariesOf({
  required CallContext callContext,
  required String customerUuid,
}) => TupleSelect<OrderLine>($OrderLine.ofContext(callContext))
    .where((fields) => fields.order.customer.$keyValue.$equal(customerUuid))
    .groupBy((fields) => [fields.order])
    .project(
      (fields) => $OrderSummary.project(
        order: fields.order.$keyValue,
        lineCount: fields.uuid.$count(),
      ),
    )
    .fetch(callContext);
```

## 4. Pitfalls

- **No direct SQL access.** A view has no table: `qualifiedName` throws `StateError` ("resolve it instead of querying it"). Do not insert, update or delete view rows.
- **Missing `$resolveViewKeys`.** Resolving a reference to the view throws `StateError` ("must override `$resolveViewKeys`").
- **Missing `$viewSource`.** A query that reads view fields throws `StateError` ("has no SQL source").
- **No call context.** `$viewSource` needs a `CallContext`. Rendering such a query outside a call (for example `toSql()` with no context) throws `StateError`.
- **Missing view rows.** The join is a `LEFT JOIN` and a view may have no row for a key. View fields can then be `null` in a query. After resolution, check `summary.hasDataRow` before `summary.dataRowValues`: reading a row that was not resolved throws.
- **Two hooks, one truth.** If `$viewSource` and `$resolveViewKeys` compute different values, filters and loaded values disagree.

## 5. See Also

- [DATA_MODEL.md](DATA_MODEL.md): entities and annotations.
- [CONCEPTS_RELATIONSHIPS.md](CONCEPTS_RELATIONSHIPS.md): reference fields.
- [QUERIES.md](QUERIES.md): `TupleSelect`, `groupBy`, `project`, CTEs.
- [DATA_CLASSES.md](DATA_CLASSES.md): `DataLoader` and resolutions.
