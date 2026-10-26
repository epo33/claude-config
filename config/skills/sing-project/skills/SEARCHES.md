# Standard Search Services

Sing generates a `search` service for every entity marked `@Searchable()`. The service exists on the server and on the client. It takes one optional criterion per field and returns a `DataLoader<E>`.

```dart
// Server side
$Order.services(callContext).search(callContext: callContext, status: Search.equal(OrderStatus.pending))

// Client side
$Order.services(dataRegistry).search(status: Search.equal(OrderStatus.pending))
```

Sources: `sing_core/lib/src/search*.dart` (search classes), `sing_core/lib/src/std/search/` (field criteria), `sing_server/lib/src/expressions/search_filters.dart` (criteria to SQL), `sing_server/lib/src/query/entity_where.dart` (composition of a search), `sing_server/lib/src/search_on_foreign_key.dart` (reverse criteria).

## 1. Declaring a Searchable Entity

### 1.1. `@Searchable()`

```dart
@Implementor(OrderServices)
@LoadServices()
@Searchable()
class OrderEntity extends ModelEntity with UuidPrimaryKeyMixin { ... }
```

- Put it on an entity or on an entity mixin.
- A descendant entity is searchable when its ancestor is. `@Searchable(searchable: false)` opts it out.
- Rebuild the model (`dart run sing_builder:sing_emit` from the model package) to generate the search class and the service.

### 1.2. Field Annotations

| Annotation | Effect on the search |
| --- | --- |
| none | The field gets one criterion parameter. |
| `@AutoSearch.no` | The field gets no criterion (use it for memo and comment fields). |
| `@SearchOnlyField()` | The field has **no column**. It becomes a raw value parameter (`bool? test`), read only by your server code (section 6). |
| `@NoReverseSearch()` | On a reference field: the referenced entity gets no `whereXxx` criterion for this field (section 5.2). |

A server-only field (`@serverSideOnly`) never gets a criterion: a caller could read its value back one prefix at a time.

## 2. The Generated Search Class

### 2.1. Parameters

For `Order`, Sing generates `class Order$Search<E extends Order> extends SearchOnEntity<E>` in `common/lib/src/sing/searches.dart`. Read this file to get the exact parameters of a search (see [generated code](GENERATED_CODE.md#34-search-filters-of-an-entity)). Each parameter is an optional named constructor parameter and a `final` field:

| Entity field | Parameter in `Order$Search` |
| --- | --- |
| Scalar field (`orderNumber`, `status`, `orderDate`, `uuid`, ...) | `SearchOnField<T>? orderNumber`, `T` is the Dart value type (`String`, `OrderStatus`, `UtcDateTime`, ...). A `UuidField` gives `SearchOnField<String>`. |
| Array field | `SearchOnField<T>`, `T` is the item type. |
| Reference to a searchable entity (`customer`) | `Customer$Search<Customer>? customer`: criteria on the referenced row (section 5.1). |
| Any reference (`customer`, `summary`) | `SearchOnField<PK>? refToCustomer`: criterion on the stored key. `PK` is the key type of the referenced entity. A reference to a non-searchable entity (`summary` points at the view `OrderSummary`) only gets `refToSummary`. |
| Reference field of another entity pointing at this one (`OrderLine.order`) | `SearchOnForeignField<E, OrderLine>? whereOrderLineOrder` (section 5.2). |
| `@SearchOnlyField()` scalar | The raw nullable value: `bool? test`. |
| `@SearchOnlyField()` reference | `Reference? xxx` (untyped: cast it on the server). |
| always | `List<SearchOnForeignField<E, Entity>> $foreign` (section 5.3). |

When the key of the referenced entity is itself a reference (`ParentProfile` keyed by `ReferenceTo<ParentEntity>().primaryKey()` in `coverage/coverage_model`), the `refTo` parameter is typed on the entity that key points at: `SearchOnField<Reference<Parent>>? refToProfile`.

### 2.2. Members

- The constructor is `const`: `const Order$Search(status: ...)` is valid when the criteria are const.
- `copyWith(...)` returns a new search. A non-null argument replaces the current value. A `null` argument keeps the current value: `copyWith` cannot remove a criterion.
- `filters` (`Map<String, SearchOn?>`): the criteria, keyed by parameter name. `searchOnlyValues` (`Map<String, Object?>`): the `@SearchOnlyField` values. They are not in `filters`.
- `isEmpty`: true when no criterion, no search-only value and no `$foreign` criterion holds something.
- `Order$Search.params` and `Order$Search.buildFrom(...)`: see section 7.

### 2.3. Entity Inheritance

In an [entity inheritance chain](DATA_MODEL.md#7-polymorphic-entities-ancestor-and-descendants), the search class of a descendant extends the one of its ancestor (`Cat$Search<E extends Cat> extends Animal$Search<E>`). It holds the ancestor's criteria plus its own.

The `search` service of every entity of the chain declares `filters` on the **root** class (`Animal$Search<Animal>? filters`), because Dart forbids narrowing a parameter type in an override. The `Cat` search uses `filters` only if it is a `Cat$Search`. **Any other value is silently ignored.** Always pass the search class of the searched entity.

### 2.4. JSON Form

A search travels as a JSON object. Each criterion carries a `$kind` key naming its class (`equal`, `null`, `in`, `string`, `int`, `float`, `duration`, `localDate`, `utcDate`, `dateOnly`, `all`, `one`, `none`, `foreign`). `Order$Search.fromJson` refuses a key that the class does not declare (`FormatException: unknown search key`). See [Data exchange](AUTO_JSON.md).

## 3. Calling the Search Service

### 3.1. Parameters of the Service

The service takes the same parameters as `Order$Search`, plus `filters` (a whole `Order$Search`), plus `callContext` on the server. The service merges them: `filters.copyWith(<individual parameters>)`. An individual parameter wins over the same criterion in `filters`. All criteria are combined with `AND`.

```dart
// Server side: callContext is required twice
final pending = await $Order.services(callContext).search(
  callContext: callContext,
  status: Search.equal(OrderStatus.pending),
  orderDate: SearchOnDateTime.afterOrEqual(UtcDateTime(DateTime.utc(2026, 1, 1))),
).listValues();

// Client side: same parameters, no callContext
final pending = await $Order.services(dataRegistry).search(
  filters: const Order$Search(status: Search.equal(OrderStatus.pending)),
  customer: Customer$Search(name: SearchOnString(text: "Du", type: .prefix)),
).listValues();
```

On the server, `$Order.services(callContext)` returns `Order$Services`. Inside a service mixin of `Order`, call `search(...)` directly on `this`.

### 3.2. Result: Sort, Limit, Pages

`search` returns a `DataLoader<E>`. Nothing runs until you call a terminal method. Shape the result on the loader (see [DataLoader](DATA_CLASSES.md#2-dataloadere)):

```dart
final orders = await $Order.services(dataRegistry)
    .search(status: Search.inList([OrderStatus.pending, OrderStatus.processing]))
    .resolve((fields) => [fields.customer])
    .sort((fields) => [-fields.orderDate])
    .listValues(limit: 50);
```

- Terminal methods: `list()`, `listValues()`, `one()` (null or one row, error when more), `exactlyOne()`, `first()`, `firstOrNull()`, `count()`.
- `limit:` on `list`/`listValues`; `pages(rowPerPage: n)` returns a `PagedDataLoader<E>`.
- With a limit, Sing appends the primary key to the sort.

### 3.3. Access Control on Client Searches

The server checks a search received from a client before it runs it:

- A criterion on a field guarded by an access token requires that token.
- A nested search on a referenced entity (`customer: Customer$Search(...)`) requires the read token of `Customer`.
- A `whereXxx` or `$foreign` criterion requires the read token of the referencing entity.

A missing token fails the call with an access-denied error. A search built by server code is not checked.

## 4. Criteria on a Field

### 4.1. Which Criterion for Which Field

`SearchOnField<T>` is the base class of all field criteria. `T` is the value type of the field, so the compiler rejects a criterion of the wrong type.

| Field type | Criteria |
| --- | --- |
| any | `Search.equal`, `Search.different`, `Search.inList`, `Search.notInList`, `Search.isNull`, `Search.isNotNull` |
| `StringField`, `UuidField` | + `SearchOnString` |
| `IntField` | + `SearchOnInt` |
| `DoubleField` | + `SearchOnFloat` |
| `DurationField` | + `SearchOnDuration` |
| `DateTimeField.utc()` / `.local()` / `.dateOnly()` | + `SearchOnDateTime.*` (builds `SearchOnUtcDateTime` / `SearchOnLocalDateTime` / `SearchOnDateOnly`) |
| `BoolField`, `EnumField` | the generic criteria only |
| any criterion | combine with `&`, `\|`, `.not()` (section 4.7) |

```
SearchOnField<T>
├── SearchEquality<T>       Search.equal / Search.different
├── SearchNull<T>           Search.isNull / Search.isNotNull
├── SearchIn<T>             Search.inList / Search.notInList
├── SearchOnString          SearchOnField<String>
├── SearchOnNumeric<T>      (abstract)
│   ├── SearchOnInt
│   └── SearchOnFloat
├── SearchOnDuration        SearchOnField<Duration>
├── SearchOnDateTime<T>     (sealed)
│   ├── SearchOnLocalDateTime
│   ├── SearchOnUtcDateTime
│   └── SearchOnDateOnly
└── CompoundSearchOnField<T>
```

### 4.2. Equality, Null, List

```dart
Search.equal(OrderStatus.shipped)                 // status = 'shipped'
Search.different("admin")                         // field <> 'admin'
Search.isNull<UtcDateTime>()                      // field IS NULL
Search.isNotNull<UtcDateTime>()                   // field IS NOT NULL
Search.inList([OrderStatus.pending, OrderStatus.processing])   // field IN (...)
Search.notInList([1, 2, 3])                       // field NOT IN (...)
SearchEquality(value: "dupont", collation: "und-x-icu")         // equality under a database collation
```

The type argument is usually inferred from the parameter. Write it when the value does not give it (`Search.isNull<UtcDateTime>()`).

### 4.3. Strings: `SearchOnString`

`SearchOnString({String? text, SearchOnStringType? type, bool? caseSensitive, String? collation})`

| `type` | SQL |
| --- | --- |
| `.equal` (default) | `= text`; `ILIKE text` when `caseSensitive: false` |
| `.prefix` | starts with `text` |
| `.suffix` | ends with `text` |
| `.contains` | contains `text` |
| `.words` | contains every space-separated word of `text`, **in this order** (`%word1%word2%`) |

```dart
SearchOnString(text: "ORD-2026", type: .prefix)
SearchOnString(text: "dupont", type: .contains, caseSensitive: false)
SearchOnString(text: "rue paris", type: .words, caseSensitive: false)
```

- `caseSensitive` defaults to `true`.
- `collation` is the name of a database collation.
- On a field declared with a collation, the comparison is always made through that collation, and `caseSensitive: false` has no effect.
- The text goes through the field control first (the same control as a written value). If the control rejects the text, the criterion is dropped and filters nothing.

### 4.4. Numbers: `SearchOnInt`, `SearchOnFloat`

`type` (`SearchOnNumericType`): `.equal` (default), `.lessThan`, `.lessOrEqualTo`, `.greaterThan`, `.greaterOrEqualTo`, `.between` (inclusive bounds `value` and `other`).

```dart
SearchOnInt.value(42)                              // = 42
SearchOnInt.value(5, type: .lessThan)              // < 5
SearchOnInt(value: 100, type: .greaterOrEqualTo)   // >= 100
SearchOnInt.between(10, 20)                        // BETWEEN 10 AND 20
SearchOnFloat.value(99.5, type: .greaterThan)
SearchOnFloat.between(1.5, 2.5, round: true)
SearchOnFloat(value: 3.14159, round: true)         // ROUND(field) = 3
```

- `round` exists on `SearchOnFloat` only. It rounds the column and the bounds to integers before comparing.
- `.between` without `other` behaves as `.equal`.

### 4.5. Durations: `SearchOnDuration`

Same operators as numbers (`SearchOnNumericType`), with `Duration` values:

```dart
const SearchOnDuration(value: Duration(hours: 4), type: .lessThan)
const SearchOnDuration(value: Duration(minutes: 30), other: Duration(hours: 2), type: .between)
```

### 4.6. Dates: `SearchOnDateTime`

`type` (`SearchOnDateTimeType`): `.equal` (default), `.before`, `.beforeOrEqual`, `.after`, `.afterOrEqual`, `.between` (inclusive bounds). Build criteria with the static helpers. They pick the right class from the type of the value:

```dart
SearchOnDateTime.equal(DateOnly(DateTime(2026, 6, 15)))
SearchOnDateTime.after(UtcDateTime(DateTime.utc(2026, 1, 1)))
SearchOnDateTime.beforeOrEqual(LocalDateTime(DateTime(2026, 6, 15, 18)))
SearchOnDateTime.between(
  UtcDateTime(DateTime.utc(2026, 1, 1)),
  UtcDateTime(DateTime.utc(2026, 2, 28)),
)
SearchOnDateTime.equal(someUtcDateTime, ignoreTime: true)   // same day
SearchOnUtcDateTime(date: from, other: to, type: .between) // direct constructor
SearchOnDateTime.ofType<UtcDateTime>(date: from)            // generic code
```

- `ignoreTime: true` compares the date part of the column and of the bounds.
- `.between` with no `other` keeps one day: `>= date AND < date + 1 day`.
- `.between` with `date == other` behaves as `.equal`.

### 4.7. Combining Criteria on One Field

`&` builds an `AND`, `|` an `OR`, `.not()` a negation. The result is a `CompoundSearchOnField<T>` and goes in the same parameter.

```dart
SearchOnInt.value(10, type: .greaterThan) & SearchOnInt.value(100, type: .lessThan)
// > 10 AND < 100

Search.equal(OrderStatus.pending) | Search.equal(OrderStatus.processing)
// = 'pending' OR = 'processing'

(Search.equal("admin") | Search.equal("guest")).not()
// NOT (= 'admin' OR = 'guest')

(SearchOnString(text: "FG-", type: .prefix) | SearchOnString(text: "FH-", type: .prefix))
// starts with 'FG-' OR starts with 'FH-'
```

Criteria on **different** fields are always combined with `AND`. To get an `OR` between fields, write a `@SearchOnlyField` and its server filter (section 6).

### 4.8. Empty Criteria and Null Values

A criterion that holds no value is **empty**: it filters nothing and keeps every row.

| Criterion | Empty when |
| --- | --- |
| `Search.equal(null)`, `Search.different(null)` | always (it does **not** test `IS NULL`) |
| `Search.inList([])`, `Search.notInList([])` | always (`inList([])` keeps every row, not none) |
| `SearchOnString(text: "")` | always |
| numeric, duration, date criteria | `value` / `date` is null |
| compound | it holds no condition |

Use `Search.isNull()` / `Search.isNotNull()` to test null values. An equality never matches a `NULL` column (SQL semantics). Guard an empty list yourself when "no value" must mean "no row".

## 5. Searching Through References

### 5.1. Nested Search and `refTo`

```dart
// Orders of customers whose name starts with "Du"
$Order.services(callContext).search(
  callContext: callContext,
  customer: Customer$Search(name: SearchOnString(text: "Du", type: .prefix)),
);

// Orders of a known customer: criterion on the stored key
$Order.services(callContext).search(
  callContext: callContext,
  refToCustomer: Search.equal(customerUuid),
);

// Orders with no shipping address
$Order.services(callContext).search(
  callContext: callContext,
  refToShippingAddress: Search.isNull(),
);
```

- Prefer `refToXxx` when you know the key: it compares the column and needs no join.
- A nested search applies the **whole** search of the referenced entity: its criteria, its reverse criteria, its `$applySearchOnlyFilters` and its `$applyMixinFilters`. A visibility filter of `Customer` therefore also applies to orders searched through `customer`.

### 5.2. Reverse Criteria: `whereXxx`

For each reference field of a searchable entity pointing at this entity, the search class gets `where<Entity><Field>`: `OrderLine.order` gives `Order$Search.whereOrderLineOrder`. It keeps the rows that at least one matching row points at (`EXISTS`).

```dart
// Orders having at least one line of a given product
$Order.services(callContext).search(
  callContext: callContext,
  whereOrderLineOrder: SearchOnForeignField(
    fieldName: "order",
    filters: OrderLine$Search(refToProduct: Search.equal(productUuid)),
  ),
);

// Orders with no line at all
$Order.services(callContext).search(
  callContext: callContext,
  whereOrderLineOrder: SearchOnForeignField(
    fieldName: "order",
    filters: const OrderLine$Search(),
    none: true,
  ),
);
```

- `SearchOnForeignField<PK, FK>`: `PK` is the searched entity, `FK` the entity holding the reference, `fieldName` the field of `FK` pointing at `PK`.
- `none: true` keeps the rows that **no** matching row points at (`NOT EXISTS`). With empty `filters`, it keeps the rows nothing points at. A negation requires that `PK` has a single-field primary key (the server throws otherwise).
- The criterion is not generated for a field marked `@NoReverseSearch()`, for an `ownKey()` reference, or from a server-only entity. A descendant of `FK` gets its own `where<Descendant><Field>` criterion.
- See also [reverse lookups](CONCEPTS_RELATIONSHIPS.md#4-finding-children-reverse-lookups).

### 5.3. Criteria From an Upper Layer: `$foreign`

A `whereXxx` criterion is generated only in the model that owns the searched entity. An entity of an upper model layer that references it is unknown there. Every `X$Search` therefore has `$foreign`, a list where any layer adds its own reverse criteria:

```dart
// Customers (lower layer) that no LoyaltyCard (upper layer) points at
Customer$Search(
  $foreign: [
    SearchOnForeignField<Customer, LoyaltyCard>(
      fieldName: "customer",
      filters: const LoyaltyCard$Search(),
      none: true,
    ),
  ],
)
```

A `$foreign` criterion travels with the path of `FK` (`entityPath`). The server uses it to read the criterion back typed. The server refuses a `fieldName` that is not a reference to `PK`.

## 6. Server Filters: `$applySearchOnlyFilters`

### 6.1. The Hook

Every standard search of an entity calls `$applySearchOnlyFilters` on the services of that entity. This includes a search that reaches the entity through a reference field (section 5.1) or a reverse criterion (section 5.2). The returned predicate is added with `AND` to the generated criteria. Use it to:

- implement the `@SearchOnlyField` fields (they have no column, so nothing else reads them);
- add a filter to every search of the entity (hidden rows, visibility).

To override it, [add a service mixin to the entity](SERVICES.md) (`@Implementor(OrderServices)`) and override:

```dart
@override
Predicate? $applySearchOnlyFilters(
  CallContext callContext,
  Order$Search filters,          // narrow to the generated class to read search-only values
  EntityFieldsExpr<Order> fields,
) => ...;
```

- Return a [predicate](QUERIES.md) built on `fields`, or `null` for no filter.
- Call `super.$applySearchOnlyFilters(...)` and keep its result when another mixin may also override the method.

`$applyMixinFilters(callContext, filters, fields)` is a separate hook reserved for generic service mixins (validity, active, ...). It is always applied, so an entity override of `$applySearchOnlyFilters` cannot drop it.

### 6.2. Example: a Search-Only Flag

`example/model/lib/model/orders/order.services.dart`, with `@SearchOnlyField() final test = BoolField();` in `OrderEntity`:

```dart
@override
Predicate? $applySearchOnlyFilters(
  CallContext callContext,
  Order$Search filters,
  EntityFieldsExpr<Order> fields,
) {
  final test = filters.test;
  return Predicate.and([
    super.$applySearchOnlyFilters(callContext, filters, fields),
    if (test == true) fields.orderNumber.$startsWith(testOrderPrefix),
    if (test == false) fields.orderNumber.$startsWith(testOrderPrefix).$not(),
  ]);
}
```

A search-only field is a natural way to search several columns at once (`text` matching `orderNumber` or `notes`) with `Predicate.or([...])`.

### 6.3. Example: a Correlated Subquery on Children

`coverage/coverage_model/lib/model/relations/parent.services.dart`, with `@SearchOnlyField() final childLabel = StringField(maxLength: 50);` in `ParentEntity`:

```dart
@override
Predicate? $applySearchOnlyFilters(
  CallContext callContext,
  Parent$Search filters,
  EntityFieldsExpr<Parent> fields,
) {
  final childLabel = filters.childLabel;
  if (childLabel == null) return null;
  return $Child.existsChild(callContext)(
    where: (child) =>
        child.parent.$keyValue.$equalExpr(fields.uuid) &
        child.label.$equal(childLabel),
  );
}
```

### 6.4. Example: a Permanent Filter and a Search-Only Reference

```dart
@SearchOnlyField()
final handledBy = ReferenceTo<CustomerEntity>();   // in an entity: parameter `Reference? handledBy`
```

```dart
@override
Predicate? $applySearchOnlyFilters(
  CallContext callContext,
  Order$Search filters,
  EntityFieldsExpr<Order> fields,
) {
  final handledBy = filters.handledBy;
  return Predicate.and([
    fields.status.$different(OrderStatus.cancelled),     // applied to every search
    if (handledBy != null)
      fields.customer.$pointToReference(handledBy as Reference<Customer>),
  ]);
}
```

On a reference field expression, compare to a key with `$pointToKey(key)`, to a row with `$pointToRow(row)`, to a reference with `$pointToReference(ref)`. `$keyValue` reads the stored key as a `ValueExpr<PK>` for correlations and `$isInList`. See [reference operations](QUERY_EXPRESSIONS.md#8-references) and [EXISTS](QUERIES.md#41-exists--not-exists).

### 6.5. Applying a Search in a Custom Service

A custom service can take a search as a parameter (`Order$Search? filters`) and apply it in its own query. `buildEntityWhere` composes the full search (criteria, reverse criteria, search-only filters, mixin filters), as the generated `search` does:

```dart
DataLoader<Order> ordersToShip({
  required CallContext callContext,
  Order$Search? filters,
}) => $query.load(
  where: (fields) => Predicate.and([
    fields.status.$equal(OrderStatus.processing),
    if (filters != null) buildEntityWhere<Order>(callContext, this, filters, fields),
  ]),
);
```

- `buildEntityWhereOn<E>(callContext, entityDef, filters, fields)` does the same from an entity definition (`$Order.of(callContext.dataRegistry)`), for example in a `TupleSelect` of another service.
- `filters.applyFilters(callContext, fields)` applies only the declared criteria. It skips the reverse criteria and the server filters, which can bypass a visibility filter: prefer `buildEntityWhere`.
- A criterion alone applies to a field expression with `criterion.applyFilters(fields.orderNumber)`. It returns `null` for an empty criterion.

## 7. Building a Search From a Form

Each search class has a static `params` getter (`Order$Search.params`, type `Order$SearchParams`) and a static `buildFrom(SearchCriteria)`. A search form uses them to build a search from editor values without writing the search class by hand (`sing_core/lib/src/search.param.dart`).

- `Order$Search.params.orderNumber` is a `SearchParam` that knows its key (`"orderNumber"`), its source entity and field (for labels: `resolveField(registry)`).
- Kinds: `StringSearchParam` (mode `.equal()` by default; `.prefix()`, `.suffix()`, `.contains()`, `.words()`), `NumericSearchParam`, `DateSearchParam` (equality), `EqualitySearchParam` (bool, enum, ...), `ReferenceSearchParam` (a picked `Reference`, sent as `refToXxx`), `RawSearchParam` (`@SearchOnlyField`).
- A reference parameter gives the params of the referenced entity: `params.customer.name` has the key `"customer.name"`; `params.customer.$ref` is the `refToCustomer` parameter. A reverse criterion gives the params of the referencing entity: `params.whereOrderLineOrder.quantity`.
- `param.buildCriterion(value)` turns an editor value into the criterion (or the raw value for a search-only field). `null` means no filter.

```dart
final params = Order$Search.params;
final number = params.orderNumber.prefix();
final customerName = params.customer.name.contains();
final criteria = SearchCriteria({
  number.key: number.buildCriterion("ORD-2026"),
  customerName.key: customerName.buildCriterion("Dupont"),
  params.status.key: params.status.buildCriterion(OrderStatus.pending),
  params.test.key: params.test.buildCriterion(false),
});
final filters = Order$Search.buildFrom(criteria);
final orders = await $Order.services(dataRegistry).search(filters: filters).listValues();
```
