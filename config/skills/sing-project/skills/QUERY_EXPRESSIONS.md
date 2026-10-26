# Query Expressions

This document lists the expression DSL used in server queries: `where`, `having`, `orderBy`, projections, `setExpr`, subqueries. How to run a query is in [QUERIES.md](QUERIES.md).

Sources: `sing_server/lib/src/expressions/` (classes in `expressions.dart`, `predicate.dart`, `sql_expr.dart`; methods in `extensions/*.dart`) and `sing_server/lib/src/engine/select/select.dart` (`SortSpec`).

## 1. Basics

### 1.1. Expressions, Not Values

A query callback receives the **expressions** of the entity fields, not their values. Every method of the DSL starts with `$` so it never collides with a field name.

```dart
// Wrong: `==` compares Dart objects, the result is a bool, not a predicate
where: (fields) => fields.status == OrderStatus.pending

// Right
where: (fields) => fields.status.$equal(OrderStatus.pending)
```

The main types:

| Type | Meaning | Example |
| ---- | ------- | ------- |
| `ValueExpr<T>` | an SQL value of Dart type `T` | `fields.totalAmount`, `fields.subtotal + fields.taxAmount` |
| `FieldExpr<T>` | a column (a `ValueExpr<T>`) | `fields.orderNumber` |
| `EnumFieldExpr<T>` | an enum column | `fields.status` |
| `RefFieldExpr<E, PK>` | a reference column, a `ValueExpr<Reference<E>>` that also navigates to `E` | `fields.customer` |
| `QueryExpr<T>` | a scalar subquery (a `ValueExpr<T>`) | `$OrderLine.query(ctx).oneValue(...)` |
| `Predicate` | an SQL condition | `fields.paidAt.$isNull` |
| `EntityFieldsExpr<E>` | the field expressions of an entity, the `fields` parameter | `(fields) => ...` |

The callbacks are typed by these typedefs (`sing_server/lib/src/query/types.dart`): `FilterLines<E>` is `Predicate? Function(EntityFieldsExpr<E> fields)`. A callback may return `null`: it adds no condition.

A nullable field has the same expression type as a non-null one (`fields.notes` is a `FieldExpr<String>`). Nullity is tested with `$isNull`, never with the Dart type.

The compiler checks field names and value types. Renaming or retyping a field in the model breaks every query that uses it at the next build.

### 1.2. Dart Values Inside Expressions

Methods without a suffix take a **Dart value** (`$equal(OrderStatus.pending)`). Methods ending in `Expr` take an **expression** (`$equalExpr(fields.subtotal)`). Values are always sent as bound parameters, never written into the SQL text.

Operators (`+`, `-`, `*`, `/`) take expressions only. Turn a Dart value into an expression with:
- `.toExpression()` on `String`, `int`, `double` and `bool`;
- `Expression.constant<T>(value)` for any other type (`null` gives an SQL NULL);
- `Expression.nullValue<T>()` for an SQL NULL.

Prefer the value forms when they exist (`$plus`, `$times`, `$ifNullThen`...): they bind the value with the column type.

```dart
fields.subtotal * 1.2.toExpression()      // operator: expression needed
fields.subtotal.$times(1.2)               // same, value form
Expression.constant(UtcDateTime.now())    // a constant of another type
```

## 2. Comparisons

Extension `ComparableExprExtension` (`extensions/compare.dart`), on every `ValueExpr<T>`.

### 2.1. With a Value or an Expression

| Value form | Expression form | SQL |
| ---------- | --------------- | --- |
| `$equal(v)` | `$equalExpr(e)` | `=` |
| `$different(v)` | `$differentExpr(e)` | `!=` |
| `$lessThan(v)` | `$lessThanExpr(e)` | `<` |
| `$lessOrEqual(v)` | `$lessOrEqualExpr(e)` | `<=` |
| `$greaterThan(v)` | `$greaterThanExpr(e)` | `>` |
| `$greaterOrEqual(v)` | `$greaterOrEqualExpr(e)` | `>=` |
| `$between(low, high)` | `$betweenExpr(low, high)` | `BETWEEN` |

```dart
fields.status.$equal(OrderStatus.pending)
fields.totalAmount.$between(100.0, 1000.0)
fields.totalAmount.$greaterThanExpr(fields.subtotal)
```

Each method also takes `collate:` (a collation name) for text comparisons: `fields.orderNumber.$lessThan("M", collate: "C")`.

### 2.2. NULL-Safe Equality

`=` and `!=` answer UNKNOWN when one side is NULL, so the row is dropped. `nullSafe: true` on `$equal`, `$different`, `$equalExpr` and `$differentExpr` renders `IS NOT DISTINCT FROM` / `IS DISTINCT FROM`: NULL then compares as a value.

```dart
fields.notes.$different("gift", nullSafe: true)   // keeps the rows where notes IS NULL
fields.shippingAddress.$differentExpr(fields.customer.address, nullSafe: true)
```

### 2.3. Lists

```dart
fields.status.$isInList([OrderStatus.pending, OrderStatus.processing])
fields.status.$isNotInList([OrderStatus.cancelled, OrderStatus.returned])
fields.totalAmount.$isInListExpr([fields.subtotal, fields.taxAmount])
```

- An empty list gives a constant predicate: `$isInList([])` is always false, `$isNotInList([])` is always true. No SQL error.
- One element gives `=` (or `!=`).
- Several Dart values on a plain column usually give `= ANY(?array)`: one bound array, so the SQL text does not depend on the list length. Other cases give `IN (...)`.

### 2.4. Subqueries

`QueryExpr<T>` comes from `oneValue` (see [Subqueries](QUERIES.md#4-subqueries)).

```dart
fields.uuid.$isInSelect(subquery)        // IN (SELECT ...)
fields.uuid.$isNotInSelect(subquery)     // NOT IN (SELECT ...)
fields.totalAmount.$greaterThanAll(subquery)   // > ALL (SELECT ...)
fields.totalAmount.$lessThanAny(subquery)      // < ANY (SELECT ...)
```

Quantified forms: `$lessThanAny/All`, `$lessOrEqualAny/All`, `$greaterThanAny/All`, `$greaterOrEqualAny/All`.

## 3. Combining Predicates

```dart
p1 & p2          // AND
p1 | p2          // OR
p1.$not()        // NOT
Predicate.and([p1, p2, if (cond) p3])   // null entries are ignored
Predicate.or([p1, p2])
Predicate.alwaysTrue
Predicate.alwayFalse                    // spelled this way in the API
```

`Predicate.and([])` and `Predicate.or([])` give `Predicate.alwaysTrue`. Use `Predicate.and` to build optional filters:

```dart
Predicate? orderFilter(
  EntityFieldsExpr<Order> fields, {
  OrderStatus? status,
  double? minAmount,
  String? customerId,
}) => Predicate.and([
  if (status != null) fields.status.$equal(status),
  if (minAmount != null) fields.totalAmount.$greaterOrEqual(minAmount),
  if (customerId != null) fields.customer.$pointToKey(customerId),
]);
```

## 4. NULL Handling

```dart
fields.deliveredAt.$isNull
fields.deliveredAt.$isNotNull
fields.notes.$ifNullThen("")                       // COALESCE(notes, '')
fields.paidAt.$ifNullThenExpr(fields.orderDate)    // COALESCE(paid_at, order_date)
[fields.shippedAt, fields.paidAt, fields.orderDate].$coalesceExpr   // COALESCE of several expressions
["a", null, "b"].$coalesce                         // COALESCE of Dart values
fields.subtotal.$nullIf(0.0)                       // NULLIF(subtotal, 0)
fields.subtotal.$nullIfExpr(fields.taxAmount)
```

Pitfall: `$different(v)` without `nullSafe` drops the NULL rows. Write `fields.notes.$different("x", nullSafe: true)` or `fields.notes.$different("x") | fields.notes.$isNull`.

Pitfall: `SUM`, `MAX`... over zero rows return NULL. Wrap a scalar subquery with `$ifNullThen(0.0)` before writing it into a non-null column.

## 5. Numbers

Extension `NumExprExtension<T extends num>` (`extensions/num.dart`). Both operands of an operator must have the same `T`.

```dart
o.subtotal + o.taxAmount + o.shippingCost    // + - * on ValueExpr<T>
o.totalAmount / o.subtotal                   // always ValueExpr<double> (float division)
o.subtotal.$plus(5.0)                        // value forms: $plus, $minus, $times, $dividedBy
l.quantity.$intDivide(2.toExpression())      // integer division, ValueExpr<int>
o.totalAmount.$negate()
o.totalAmount.$abs
o.taxRate.$power(2.toExpression())           // ValueExpr<num>
o.totalAmount.$round()                       // ValueExpr<int>
o.totalAmount.$roundTo(2.toExpression())     // ValueExpr<double>, 2 decimals
o.totalAmount.$trunc()                       // ValueExpr<int>
o.totalAmount.$truncTo(2.toExpression())     // ValueExpr<double>
```

Comparisons with 0 and 1: `$equalZero()`, `$differentZero()`, `$lessThanZero()`, `$lessOrEqualZero()`, `$greaterThanZero()`, `$greaterOrEqualZero()`, and the same six with `One`.

Mixing `int` and `double`: `$asDouble` and `$asInt` change the **Dart type only**; the SQL is unchanged. `l.quantity.$asDouble * l.unitPrice` is correct because PostgreSQL computes `int * float8` as `float8`. To really convert in SQL, use `$cast<double>()`, `$round()` or `$trunc()`. `o.totalAmount.$asInt` reads a float8 as an `int` and fails when the row is decoded.

## 6. Strings

Extension `StringExprExtension` (`extensions/string.dart`), on `ValueExpr<String>`.

### 6.1. Search

All search methods escape `%` and `_` in the text you give: they match it literally.

```dart
c.name.$startsWith("Du")                          // LIKE 'Du%'
c.email.$endsWith("@example.com", caseSensitive: false)   // ILIKE '%@example.com'
p.description.$contains("organic", caseSensitive: false)  // ILIKE '%organic%'
c.name.$wordSearch("jean dupont", caseSensitive: false)   // ILIKE '%jean%dupont%': every word, in this order
```

These four take `caseSensitive` (default `true`; `false` renders `ILIKE`) and `collation`. `$startsWithExpr`, `$endsWithExpr` and `$containsExpr` take an expression.

Raw patterns (`%` and `_` are wildcards; `escapeLikePattern(text)` escapes user text):

```dart
p.sku.$like("AB_%")
p.sku.$notLike("TEST%")
c.name.$ilike("du%")              // case-insensitive; also $notIlike
o.orderNumber.$matches(r"^ORD-\d+$")                    // POSIX regex ~
o.orderNumber.$notMatches(r"^TEST-", caseSensitive: false)   // !~*
```

Each has an `Expr` variant (`$likeExpr`, `$ilikeExpr`, `$matchesExpr`...).

```dart
c.phone.$isNullOrEmpty   // IS NULL OR = ''
c.name.$isNotEmpty       // at least one character
```

### 6.2. Transformations

```dart
c.email.$toLowerCase              // LOWER
c.name.$toUpperCase               // UPPER
c.name.$capitalize                // INITCAP
c.name.$length                    // ValueExpr<num>
p.sku.$leftChars(3.toExpression())            // first 3 characters
p.sku.$rightChars(4.toExpression())           // last 4 characters
p.sku.$subString(2.toExpression(), 5.toExpression())   // characters 2, 3, 4
c.name.$concat(" <").$concatExpr(c.email).$concat(">")
```

`$subString(from, [to])` works like Dart `String.substring`: `from` counts from 0 and `to` is excluded. Without `to`, it goes to the end. `$concat(text, [others])` and `$concatExpr(expr, [others])` take one or more parts.

### 6.3. Full-Text Search

Extensions in `extensions/full_text.dart`. `config` is a PostgreSQL text search configuration (`"simple"`, `"english"`, `"french"`...). Without it, the database default applies.

```dart
p.description.$toTsVector(config: "english").$matchesQuery("organic -sugar")
p.description.$toTsVector().$matchesTsQuery("organic & !sugar")
p.description.$toTsVector().$rank("organic")      // ValueExpr<double>, for orderBy
```

`$matchesQuery` takes free user input (`WEBSEARCH_TO_TSQUERY`). `$matchesTsQuery` takes the tsquery syntax (`TO_TSQUERY`).

## 7. Dates

Extension `DateTimeExprExtension<T extends DateTimeEx>` (`extensions/date_time.dart`), on `UtcDateTime`, `LocalDateTime` and `DateOnly` expressions. `DatePart` values: `microSecond`, `milliSecond`, `second`, `minute`, `hour`, `day`, `week`, `month`, `year`, `quarter`, `dayOfWeek`, `isoDayOfWeek`, `dayOfYear`, `epoch`.

```dart
o.orderDate.$withoutTime            // midnight of the day
o.orderDate.$trunc(.month)          // DATE_TRUNC
o.orderDate.$firstDayOfWeek         // also $lastDayOfWeek, $firstDayOfMonth, $lastDayOfMonth, $lastDayOfYear
o.orderDate.$firstDayOfYear(iso8601: true)
o.orderDate.$add(7)                          // + 7 days
o.orderDate.$add(1, datePart: .month)        // + 1 month
o.orderDate.$addExpr(delayInDays, datePart: .day)  // + an expression (ValueExpr<num>)
o.orderDate.$extract(.year)                  // ValueExpr<double>; .dayOfWeek: Sunday = 0
```

Differences (all `ValueExpr<num>`):

| Method | Computes |
| ------ | -------- |
| `a.$daysFrom(date)` | whole days of `a - date` (positive when `a` is after `date`) |
| `a.$daysTo(date)` | whole days of `date - a` (the age of `a` when `date` is now) |
| `a.$differenceWith(b, unit: .day)` | the `unit` **component** of `a - b`, not a total |
| `a.$differenceWith(b, unit: .epoch)` | the total number of seconds of `a - b` |

`$differenceWith(b, unit: .hour)` on a 1 day 12:30 difference gives 12, not 36. Use `.epoch` for totals.

```dart
// Orders placed more than 30 days ago
fields.orderDate.$daysTo(UtcDateTime.now()).$greaterThan(30)

// Same filter, able to use an index on order_date
fields.orderDate.$lessThan(
  UtcDateTime(DateTime.timestamp().subtract(const Duration(days: 30))),
)

// Delivery time in hours
o.deliveredAt.$differenceWith(o.orderDate, unit: .epoch) / 3600.toExpression()
```

### 7.1. Date Ranges

`DateRange` and `DateTimeRange` columns (`extensions/range.dart`): `$containsValue(v)`, `$containsRange(r)`, `$isContainedBy(r)`, `$overlaps(r)`, `$isStrictlyLeftOf(r)`, `$isStrictlyRightOf(r)`, `$isAdjacentTo(r)` (each with an `Expr` variant), `$lowerBound`, `$upperBound` (exclusive end) and `$isEmpty`.

## 8. References

A reference field is a `RefFieldExpr<E, PK>`. It is a `ValueExpr<Reference<E>>`: the `String`, `num` and date methods do not apply to it.

### 8.1. Compare to What You Hold

Each `$pointToXxx` predicate renders `column = key`. It renders `IS NULL` when its argument holds no key (`null`, or a reference without primary key).

```dart
fields.customer.$pointToKey(customerId)            // a bare primary key (String here)
fields.customer.$pointToReference(customerRef)     // a Reference<Customer>
fields.customer.$pointToRow(customerDataRow)       // a DataRow<Customer>
fields.customer.$pointToValues(customer)           // a DataRowValues<Customer>
fields.customer.$pointToFieldValue(order.customer) // a FieldValue<Reference<Customer>>
fields.customer.$pointToKey(customerId).$not()     // NOT (customer = key): also drops NULL rows
```

### 8.2. Read the Stored Key

`$keyValue` reads the column as the key it stores (`ValueExpr<PK>`). All key comparisons then apply. Use it for lists, correlations and projections.

```dart
fields.customer.$keyValue.$isInList(customerIds)
line.order.$keyValue.$equalExpr(order.uuid)        // correlation FK = PK
$CustomerStat.project(customer: o.customer.$keyValue, ...)   // a projection takes the key
```

Two reference expressions to the same entity compare directly: `fields.shippingAddress.$equalExpr(fields.customer.address)` (orders shipped to the customer's own address). `$equal(ref)` and `$different(ref, nullSafe: true)` also accept a `Reference<E>`.

### 8.3. Navigate

A reference field also exposes the fields of its target. Navigation adds the join (see [Automatic Joins](QUERIES.md#27-automatic-joins)):

```dart
fields.customer.name.$startsWith("Du")
fields.customer.address.country.$equal("FR")
fields.shippingAddress.country.$ifNullThen("FR").$different("FR")
```

Navigation works in `where`, `having`, `orderBy`, projections and subqueries. It does **not** work inside an UPDATE `set` (a `StateError` at render time): use a subquery there.

## 9. Conditional Values

```dart
// value → value
fields.shippingMethod.$map({
  ShippingMethod.overnight: 1,
  ShippingMethod.express: 2,
}, defaultValue: 3)                                  // ValueExpr<int>

// value → expression
fields.paymentMethod.$mapExpr({
  PaymentMethod.cashOnDelivery: fields.totalAmount.$plus(2.5),
}, defaultValue: fields.totalAmount)

// CASE WHEN on any predicates
Expression.$Iif<String>({
  fields.paidAt.$isNull: "unpaid".toExpression(),
  fields.deliveredAt.$isNull: "paid".toExpression(),
}, otherwise: "delivered".toExpression())

fields.shippingCost.$greatest([5.0])                 // GREATEST; also $least
fields.subtotal.$greatestExpr([fields.taxAmount])    // also $leastExpr
```

Without `defaultValue` / `otherwise`, an unmatched row gives NULL.

## 10. Aggregates

```dart
o.totalAmount.$sum()             // ValueExpr<double> here: same type as the column
o.totalAmount.$avg()             // ValueExpr<double>
o.totalAmount.$stdDev()          // ValueExpr<double>
o.orderDate.$min()               // also $max(); keeps the column type
o.uuid.$count()                  // ValueExpr<int>
o.customer.$count(distinct: true)
o.uuid.$count(filter: o.status.$equal(OrderStatus.cancelled))   // COUNT(...) FILTER (WHERE ...)
(l.quantity.$asDouble * l.unitPrice).$sum()                       // aggregate of a computed value
```

`$sum`, `$avg` and `$stdDev` exist on numbers only. `$min`, `$max` and `$count` exist on any non-aggregated expression. Every aggregate takes `filter:`. `GroupingExpr([dims...])` reads the level of a `GROUPING SETS` row (see [Grouping Sets](QUERIES.md#54-group-by-and-projections)).

## 11. Casts

- `$cast<T>()` renders `CAST(x AS type)`. The SQL type comes from the Dart type `T`: `$cast<double>()`, `$cast<String>()`.
- `$asA<T>()` changes the Dart type only. The SQL is unchanged. Use it when the SQL value already has the right type.

```dart
fields.totalAmount.$cast<String>()              // text
fields.shippingMethod.$map(rates).$cast<double>()   // force a double for arithmetic
```

## 12. Arrays and JSON

Array columns (`ArrayField`), extension `ArrayExprExtension` (`extensions/array.dart`), with a hypothetical `tags` array on `Product`:

```dart
p.tags.$has("organic")                 // 'organic' = ANY(tags)
p.tags.$containsAll(["organic", "local"])   // @>
p.tags.$isContainedBy(allowedTags)     // <@
p.tags.$overlaps(["sale", "new"])      // &&
p.tags.$length                         // CARDINALITY
p.tags.$at(0.toExpression())           // first element (index from 0)
```

JSON columns (`JsonField`, expression `JsonFieldExpr`), extension `JsonExprExtension` (`extensions/json.dart`), with a hypothetical `attributes` JSON field:

```dart
p.attributes.$contains({"color": "red"})      // @>
p.attributes.$hasKey("size")                  // ?; also $hasAnyKey, $hasAllKeys
p.attributes.$getText("color").$equal("red")  // ->> as text
p.attributes.$get("dims").$getText("width")   // -> then ->>
p.attributes.$getPathText(["dims", "width"])  // #>>; also $getPath, $getAt, $getTextAt
p.attributes.$jsonType                        // JSONB_TYPEOF
```

## 13. Sorting

`SortSpec` comes from any expression:

```dart
orderBy: (o) => [
  o.orderDate.$desc,
  o.customer.name.$asc,
  o.paidAt.$sorted(descending: true, nullsFirst: false),
]
```

## 14. Custom SQL Fragments

When the DSL lacks a function, write a template. `_0_`, `_1_`... are replaced by the rendered arguments. An argument is an `Expression` or a `BoundValue(value, adapter)` (sent as a bound parameter). Every argument must appear in the template.

```dart
// ValueExpr from a template; $adapter names the SQL type of the result (null if unknown)
SqlExpr<String>("MD5(_0_)", [c.email], $adapter: DbTypeAdapter.text)

// Predicate from a template
SqlPredicate("_0_ % _1_", [c.name, BoundValue("dupond", DbTypeAdapter.text)])   // pg_trgm similarity

// A function without argument
SqlExpr<String>("gen_random_uuid()", const [], $adapter: null)
```

Never build the template from user input: put user values in `BoundValue` arguments.
