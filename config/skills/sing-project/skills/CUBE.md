# Cubes: Multidimensional Aggregation

A cube groups the rows of an entity by some fields (the dimensions) and computes aggregates on other fields (the measures). Sing turns it into one SQL `SELECT ... GROUP BY`. Use it for statistics, charts and pivot tables.

Sources: `sing_core/lib/src/cube/` (definition, result, transforms), `sing_server/lib/src/query/cube_query_builder.dart` (execution). Sample: `example/model/test/cube_sql_test.dart`.

## 1. Key Facts

- A cube needs **no declaration in the model**. Nothing is generated for it.
- A `CubeDefinition` is a plain runtime value. You build it in Dart code, on the client or on the server.
- `CubeDefinition` and `CubeResult` are serializable: they can be a service parameter, a service return type, or the type of a `JsonField<CubeDefinition>`.
- The server runs a definition with `executeCubeDefinition(callContext: ..., definition: ...)`. This function is **not a service**. Your application exposes it through a service of its own.

## 2. How Do I Expose Cubes to the Client?

The usual pattern: the client builds the definition and sends it to one generic service. Put that service on a namespace (see [SERVICES.md](SERVICES.md)):

```dart
// orders.services.dart
mixin OrdersServices on ServerServices {
  @AccessToken.authentified
  Future<CubeResult> orderCube({
    required CallContext callContext,
    required CubeDefinition definition,
  }) => executeCubeDefinition(callContext: callContext, definition: definition);
}
```

The service token only says who may call the service. The cube itself checks the read rights of the caller on every entity and field it reads (see [5](#5-access-control)). So a generic service does not open more data than the standard `load` services.

A service can also build the definition itself (fixed report, cached result) and call `executeCubeDefinition` inside its body.

## 3. How Do I Build a Definition?

### 3.1. Root, Dimensions, Measures

```dart
CubeDefinition ordersByStatus(DataRegistry dataRegistry) {
  final fields = $Order.of(dataRegistry).fieldsView;
  return CubeDefinition(
    Order.tupleKey,
    filter: Order$Search(status: Search.equal(OrderStatus.pending)),
    dimensions: [CubeDimension(fields.status, alias: "status")],
    measures: [
      CubeMeasure(fields.uuid.count, alias: "orderCount"),
      CubeMeasure(fields.totalAmount.sum, alias: "total"),
    ],
  );
}
```

- First argument: the root entity path. Pass the generated constant `Order.tupleKey`, not a hand-written string.
- `fieldsView` (on any `EntityDef`, client or server) gives typed field chains: `fields.status`, `fields.customer.name`.
- `filter`: the generated search class of the root entity (`Order$Search`). It is applied before aggregation (SQL `WHERE`). Search-only fields work too.
- `CubeDimension(chain, {source, alias, transforms, labelResolution})`: one `GROUP BY` column.
- `CubeMeasure(chainAggregate, {source, alias, transforms})`: one aggregate column.
- Aggregate getters on a `FieldsChain`: `.count`, `.countDistinct`, `.min`, `.max`, `.sum`, `.avg`. `.sum` and `.avg` are not type-checked at compile time: a sum on a `String` field fails only at execution.

Constructor: `CubeDefinition(rootEntityPath, {filter, joins, dimensions, measures, having, groupingSets})`.

### 3.2. Fields Behind a Forward Reference

A chain can cross `toOne` reference fields. Sing adds the join for you (outer join when the reference is nullable):

```dart
final fields = $Order.of(dataRegistry).fieldsView;
CubeDimension(fields.customer.name, alias: "customer");
CubeDimension(fields.shippingAddress.city, alias: "city");
```

To show a referenced row, point the dimension at a label field of the target (`fields.customer.name`), not at the reference field itself.

### 3.3. Fields Behind a Reverse Join (`CubeSource`)

To aggregate the children of the root (here the lines of each order), declare a `CubeSource` and list it in `joins`:

```dart
final orderFields = $Order.of(dataRegistry).fieldsView;
final lineDef = $OrderLine.of(dataRegistry);
final lines = CubeSource<OrderLine>(
  OrderLine.tupleKey,
  referenceField: lineDef.fieldList.order,
  outer: true,
  filter: OrderLine$Search(quantity: SearchOnInt.value(1)),
);
final definition = CubeDefinition(
  Order.tupleKey,
  joins: [lines],
  dimensions: [CubeDimension(orderFields.status, alias: "status")],
  measures: [
    CubeMeasure(lineDef.fieldsView.uuid.count, source: lines, alias: "lineCount"),
    CubeMeasure(lineDef.fieldsView.quantity.sum, source: lines, alias: "quantity"),
  ],
);
```

- `CubeSource<E>(entityPath, {parent, referenceField, outer, filter})`.
- `referenceField`: the foreign key **declared on `E`** that points back to the parent source. It is required.
- `parent`: the source this one joins to. `null` means the root. A parent must appear before its children in `joins`.
- `outer: true` gives a `LEFT JOIN`: parents without children are kept.
- `filter` is placed in the `ON` clause, so an outer join stays outer.
- A dimension or measure on a joined entity must give `source: lines`. Its chain starts from that entity.

`CubeSource` is only for reverse (`toMany`) joins. Never use it for a forward reference: use the chain of 3.2.

### 3.4. Transforms

`transforms` apply a closed list of SQL functions to the field before grouping or aggregation:

```dart
CubeDimension(
  fields.orderDate,
  alias: "month",
  transforms: [CubeTransform.truncDate(DatePart.month)],
);
CubeDimension(
  fields.paidAt,
  alias: "paid",
  transforms: const [CubeTransform(CubeFunction.isNotNull)],
);
```

`CubeFunction` values: `truncDate`, `round`, `trunc`, `abs`, `lowerCase`, `upperCase`, `capitalize`, `length`, `subString`, `isNull`, `isNotNull`, `ifNull`. Arguments go in `args` (scalar constants only). A transform on the wrong input type (for example `truncDate` on a `String`) fails at execution.

### 3.5. Conditions After Aggregation (`having`)

```dart
final total = CubeMeasure(fields.totalAmount.sum, alias: "total");
final definition = CubeDefinition(
  Order.tupleKey,
  dimensions: [CubeDimension(fields.customer.name, alias: "customer")],
  measures: [total],
  having: [
    CubeCondition.on(
      total,
      operator: CubeConditionOperator.greaterThan,
      values: const [1000],
    ),
  ],
);
```

- `CubeCondition.on(dimensionOrMeasure, {operator, values})` reads the alias from the object. Do not type the alias by hand.
- Operators: `equal`, `different`, `lessThan`, `lessOrEqual`, `greaterThan`, `greaterOrEqual`, `between` (2 values), `isNull`, `isNotNull`, `isIn`.
- Values are JSON values (`String`, `num`, `bool`). Write a date as an ISO string: `"2026-03-01T00:00:00.000Z"`. The server converts it with the field type.
- `having` needs at least one dimension.

### 3.6. Subtotals (`groupingSets`)

`groupingSets` lists subsets of dimension indexes. Each subset is one aggregation level:

```dart
CubeDefinition(
  Order.tupleKey,
  dimensions: [
    CubeDimension(fields.status, alias: "status"),
    CubeDimension(fields.shippingMethod, alias: "shipping"),
  ],
  measures: [CubeMeasure(fields.uuid.count, alias: "orderCount")],
  groupingSets: const [[0, 1], [0], []],
);
```

`[[0, 1], [0], []]` is a rollup: detail rows, one subtotal per status, one grand total. An empty `groupingSets` gives a plain `GROUP BY` on all dimensions. With grouping sets, the result gets one more column, last, with `grouping: true`. It is a bit mask: it tells which dimensions are aggregated on the row. Rows are sorted by that column, then by the dimensions.

### 3.7. Labels for Codes (`labelResolution`)

When a dimension holds a code without a reference (a denormalized value), `CubeLabelResolution(entityPath, codeField: ..., labelField: ...)` reads a label from another entity after aggregation. The result gets an extra column whose `labelOfAlias` is the dimension alias. The raw code column stays. Use it only for such codes: for a reference, use a chain to the label field (3.2).

## 4. How Do I Read the Result?

`CubeResult` has `columns` (`List<CubeColumnInfo>`) and `rows` (`List<List<dynamic>>`). Columns come in this order: dimensions, measures, the `grouping` column if any, then label columns if any.

Find a column by alias, not by position:

```dart
final result = await Orders$Services(dataRegistry).orderCube(definition: definition);
final status = result.columns.indexWhere((column) => column.alias == "status");
final count = result.columns.indexWhere((column) => column.alias == "orderCount");
for (final row in result.rows) {
  print("${row[status]}: ${row[count]}");
}
```

`CubeColumnInfo` fields: `entityPath`, `fieldName`, `typeName`, `alias`, `aggregate` (`null` for a dimension), `transforms`, `grouping`, `labelOfAlias`.

## 5. Access Control

`executeCubeDefinition` checks:
- the read token (`readToken`, the token of the standard `load` service) of the root entity, of each `CubeSource` entity, and of each label entity;
- the `accessToken` of every field it reads: dimensions, measures, filter fields, join fields.

An entity reached only through a forward chain (3.2) gets no read-token check. Only the access tokens of its fields are checked.

A refused check raises an `AppError` with code `sing.errors.accessDenied`. See [ACCESS_CONTROL.md](ACCESS_CONTROL.md).

## 6. Pitfalls

- **Aliases.** The default alias is long and technical: `<entityPath>.<fieldName>`, plus the transform name and arguments, plus `_<aggregate>` for a measure (for example `orders/orders.paidAt_isNotNull`). Give an explicit `alias` to every dimension and measure, and read columns by alias.
- **`typeName` of a measure.** It is the type of the source field after transforms, not the type of the aggregate. A `count` on `uuid` reports `"String"`, but the cells hold numbers. Use `aggregate` to know that a `count`, `countDistinct`, `sum` or `avg` cell is a number.
- **Cells are raw values.** The server does not convert them with the field adapter. On the client, cells are JSON values (strings, numbers, booleans, `null`). Convert them yourself with `typeName` and `transforms`. An enum cell holds its stored form, not an enum value.
- **`having` on an enum dimension.** The value is bound as it is, so the enum name does not match the stored value and the condition matches no row. Filter enums before aggregation with `filter`.
- **Every `source` must be in `joins`.** A dimension or measure whose `source` is missing from `joins` makes `toJson` throw. Declare a parent before its children.
- **`fromJson` needs a registry.** A definition with a `filter` can only be read back through a registry: the filter type depends on the entity. Read it through a service parameter or a `JsonField<CubeDefinition>`. A detached `JsonReader` throws a `StateError`.
- **Definition errors are plain strings.** An unknown entity, a bad field path, a bad transform, an unknown `having` alias, a bad grouping index: `executeCubeDefinition` throws a `String`, not an `AppError`. Over HTTP the client gets a 500 error with no message, unless the server registry runs with `debugMode: true` (see [DEBUGGING.md](DEBUGGING.md)). Only access errors are `AppError`s.
- **Abstract root.** A cube on an abstract entity fails. Use a concrete entity as root.

## 7. Testing a Cube

Run `executeCubeDefinition` inside `registry.startOperation(...)` on a registry with a fake data controler, and check the SQL. See [TESTING.md](TESTING.md) and `example/model/test/cube_sql_test.dart`.

## 8. See Also

- [QUERIES.md](QUERIES.md): `TupleSelect`, `groupBy`, aggregates in hand-written queries.
- [SEARCHES.md](SEARCHES.md): the generated `$Search` classes used as filters.
- [SERVICES.md](SERVICES.md): how to declare the service that exposes cubes.
