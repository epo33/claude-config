# Database Queries and Security

## 1. Introduction

### 1.1. Overview

Sing provides a **type-safe** query system with compile-time validation. All queries go through the framework which:
- Validates field names and types
- Prevents SQL injections automatically
- Detects errors during rebuild after model modifications

**Query entry point:**
```dart
final query = $Order.query(callContext);
```

The `CallContext` is **mandatory** for any database operation. It ensures security and enables access control. Queries are therefore only possible on the server side.

### 1.2. Fundamental Principle: Expressions vs Values

**Key concept**: In Sing queries, you manipulate **expressions** (`ValueExpr<T>`), not direct values.

```dart
// ❌ Incorrect: fields.status is a ValueExpr<OrderStatus>, not an OrderStatus
where: (fields) => fields.status == OrderStatus.pending

// ✅ Correct: use expression comparison methods
where: (fields) => fields.status.$equal(OrderStatus.pending)
```

**Why?** Expressions represent SQL operations that will be executed by the database, not in Dart code. This approach **guarantees** type-safety control.

## 2. Expressions and Type Safety

### 2.1. Understanding Expressions

**What is a ValueExpr<T>?**

`ValueExpr<T>` is a typed expression that represents a value of type `T` in an SQL query. The Dart compiler verifies:
- Field name validity
- Type compatibility in comparisons
- Consistency after model modifications

**Example of compiler protection:**
```dart
class OrderEntity extends ModelEntity {
  final orderNumber = StringField(maxLength: 20);
  final orderDate = DateTimeField.utc();
  final status = EnumStringField<OrderStatus>();
  final totalAmount = DoubleField();
}

// The compiler validates everything
final orders = await $Order.query(callContext).load(
  where: (fields) =>
    fields.status.$equal(OrderStatus.pending) &           // ✅ OK
    fields.totalAmount.$greaterThan(1000.0),              // ✅ OK
).listValues();

// Errors detected at compile time
where: (fields) =>
  fields.orderNum.$equal("12345")        // ❌ Error: 'orderNum' doesn't exist
  fields.orderDate.$equal("2024-01-01")  // ❌ Error: String is not UtcDateTime
  fields.status.$equal(123)              // ❌ Error: int is not OrderStatus
```

**After model modification:**
If you rename `orderNumber` to `orderRef`, the compiler will flag **all** obsolete usages in your services and applications.

### 2.2. Expressions vs Values

#### When to Use Expressions

**1. In WHERE clauses:**
```dart
$Order.query(callContext).load(
  where: (fields) => fields.status.$equal(OrderStatus.pending),
)
```

**2. In UPDATE SET clauses:**
```dart
set.setExpr(
  fields.lineCount,
  (order) => $OrderLine.query(callContext).oneValue(
    what: (line) => line.uuid.$count(),
    where: (line) => line.order.$equalExpr(order.uuid),
  ),
)
```

**3. In calculations:**
```dart
what: (line) => (line.quantity.$asDouble * line.unitPrice).$sum()
```

#### When to Use Values

**1. After calling `.getValue()`:**
```dart
final avgTotal = await $Order.query(callContext).oneValue(
  what: (fields) => fields.totalAmount.$avg(),
  where: (fields) => fields.status.$equal(OrderStatus.completed),
).getValue(); // → Future<double?>

print("Average amount: $avgTotal");
```

**2. In application logic after retrieval:**
```dart
final orders = await $Order.query(callContext).load().listValues();
for (final order in orders) {
  final amount = order.totalAmount.value; // Dart value
  if (amount > 1000) {
    print("Large order: ${order.orderNumber.value}");
  }
}
```

**3. To modify DataRowValues:**
```dart
order.status.value = OrderStatus.shipped;  // Dart value assignment
order.shippedAt.setToNow(callContext);
await $Order.query(callContext).update([order.$dataRow]).execute();
```

#### Example Showing Both Usages

```dart
// 1. Expression in WHERE: comparison with subquery
final bigOrders = await $Order
    .query(callContext)
    .load(
      where: (fields) => fields.totalAmount.$greaterThanExpr(
        // Expression
        $OrderLine
                .query(callContext)
                .oneValue(
                  what: (line) =>  //
                      (line.quantity.$asDouble * line.unitPrice).$sum(),
                  groupBy: (fields) => [fields.order],
                  where: (line) =>
                      line.order.status.$equal(OrderStatus.delivered),
                )
                .$avg() *
            1.5.toExpresssion(),
      ),
    )
    .listValues();

// 2. Value after getValue(): usage in code
final avgTotal = await $Order
    .query(callContext)
    .oneValue(
      what: (fields) => fields.totalAmount.$avg(),
      where: (fields) => fields.status.$equal(OrderStatus.delivered),
    )
    .getValue(); // → Future<double?>

if (avgTotal != null && avgTotal > 5000) {
  print("High average cart: $avgTotal");
}
```

### 2.3. Available Operations on Expressions

#### 2.3.1. Common Operations (all types)

**Nullity tests:**
- `$isNull` - tests if NULL
- `$isNotNull` - tests if NOT NULL

**Type conversions:**
- `$cast<T>()` - SQL cast to type T
- `$asA<T>()` - conversion to type T

**Null value handling:**
- `$ifNullThen(value)` - replaces NULL with a value
- `$ifNullThenExpr(expr)` - replaces NULL with an expression

**Conditional mappings:**
- `$map(map, {defaultValue})` - mapping value → value
- `$mapExpr(map, {defaultValue})` - mapping value → expression

**Min/Max of multiple values:**
- `$greatest([values])` - maximum of multiple values
- `$least([values])` - minimum of multiple values

#### 2.3.2. Comparison Operations

**With Dart values:**
```dart
fields.status.$equal(OrderStatus.pending)
fields.status.$different(OrderStatus.cancelled)
fields.amount.$lessThan(100.0)
fields.amount.$lessOrEqual(100.0)
fields.amount.$greaterThan(500.0)
fields.amount.$greaterOrEqual(500.0)
fields.amount.$between(100.0, 1000.0)
fields.status.$isInList([OrderStatus.pending, OrderStatus.processing])
fields.status.$isNotInList([OrderStatus.cancelled, OrderStatus.deleted])
```

**With expressions (Expr suffix):**
```dart
fields.total.$equalExpr(fields.subtotal + fields.tax)
fields.quantity.$greaterThanExpr(fields.minQuantity)
fields.price.$betweenExpr(fields.minPrice, fields.maxPrice)
```

**Special for references:**
```dart
fields.customer.$samePk(customerRef)      // Compare with a Reference object
fields.customer.$differentPk(customerRef)
```

#### 2.3.3. String Operations

**Text search:**
```dart
// Word search (replaces spaces with %)
fields.name.$wordSearch("jean dupont", caseSensitive: false)
// → SQL: LOWER(name) LIKE '%jean%dupont%'

// Starts with
fields.orderNumber.$startsWith("ORD-")

// Ends with
fields.email.$endsWith("@example.com")

// Contains
fields.description.$contains("urgent")

// SQL pattern with wildcards
fields.code.$like("A_B%")  // _ = one character, % = multiple
fields.code.$notLike("TEST%")
```

**Transformations:**
```dart
fields.email.$toLowerCase        // Convert to lowercase
fields.name.$toUpperCase         // Convert to uppercase
fields.title.$capitalize         // Capitalize first letter

fields.name.$length              // Length (returns ValueExpr<num>)

// Substrings
fields.code.$subString(1.toExpresssion(), 3.toExpresssion())   // First 3 characters
fields.code.$leftChars(5.toExpresssion())                      // First 5
fields.code.$rightChars(3.toExpresssion())                     // Last 3

// Concatenation
fields.firstName.$concat(" ").$concatExpr(fields.lastName)
```

**Utilities:**
```dart
fields.description.$isNullOrEmpty   // NULL or empty string
fields.name.$isNotEmpty             // Not empty
```

#### 2.3.4. Numeric Operations

**Arithmetic operators:**
```dart
fields.quantity + fields.bonus              // Addition
fields.total - fields.discount              // Subtraction
fields.quantity * fields.unitPrice          // Multiplication
fields.total / fields.quantity              // Division (returns double)
fields.amount.$negate()                     // Unary minus
fields.total.$intDivide(fields.count)       // Integer division
fields.value.$power(2.toExpresssion())      // Power
fields.delta.$abs                           // Absolute value
```

**Rounding:**
```dart
fields.price.$round()           // Round to integer
fields.price.$round(2)          // Round to 2 decimals
fields.price.$trunc()           // Truncate to integer
fields.price.$asInt             // Conversion to int
fields.count.$asDouble          // Conversion to double
```

**Comparisons with 0 and 1:**
```dart
fields.balance.$equalZero()
fields.balance.$greaterThanZero()
fields.count.$equalOne()
fields.count.$greaterOrEqualOne()
```

**Aggregations:**
```dart
fields.amount.$sum()                    // Sum
fields.amount.$avg()                    // Average
fields.amount.$min()                    // Minimum
fields.amount.$max()                    // Maximum
fields.uuid.$count()                    // Count
fields.uuid.$count(distinct: true)      // Distinct count
fields.amount.$stdDev()                 // Standard deviation
fields.amount.$sum(filter: fields.paid.$equal(true)) // SUM(...) FILTER (WHERE ...)
```

#### 2.3.5. Date Operations

**Truncation:**
```dart
fields.createdAt.$withoutTime              // Truncate to midnight (day)
fields.createdAt.$trunc(.hour)             // Truncate to hour
fields.createdAt.$trunc(.day)              // Truncate to day
fields.createdAt.$trunc(.month)            // Truncate to month
```

**Period boundaries:**
```dart
fields.date.$firstDayOfWeek                // First day of week
fields.date.$lastDayOfWeek                 // Last day of week
fields.date.$firstDayOfMonth               // First day of month
fields.date.$lastDayOfMonth                // Last day of month
fields.date.$firstDayOfYear(iso8601:false) // First day of year
fields.date.$lastDayOfYear                 // Last day of year
```

**Date arithmetic:**
```dart
// Add durations
fields.orderDate.$add(7)                             // +7 days
fields.orderDate.$add(1, datePart: .month)           // +1 month
fields.orderDate.$add(-1, datePart: .year)           // -1 year
fields.startDate.$addExpr(fields.duration)           // Add an expression

// Differences
fields.endDate.$differenceWith(fields.startDate, unit: .day)    // Difference in days
fields.dueDate.$daysFrom(UtcDateTime.now())                     // Days from now
fields.createdAt.$daysTo(UtcDateTime.now())                     // Days until now
```

**Example: orders from the last 30 days:**
```dart
where: (fields) =>
  fields.createdAt.$daysFrom(UtcDateTime.now()).$lessOrEqual(30)
```

#### 2.3.6. Reference Operations

```dart
// Compare two reference fields
fields.assignedTo.$sameReference(fields.createdBy)
fields.customer.$differentReference(fields.supplier)

// Compare foreign key with primary key value
fields.customer.$fkEqual(customerId)
fields.product.$fkEqualExpr(subqueryExpr)
```

#### 2.3.7. Boolean Operations

No specific extensions. Use standard comparisons:
```dart
fields.active.$equal(true)
fields.deleted.$equal(false)
```

Convert a bool value to expression:
```dart
true.toExpresssion()
```

### 2.4. Predicates and Logical Operators

**Combining predicates:**
```dart
// AND operator (&)
predicate1 & predicate2

// OR operator (|)
predicate1 | predicate2

// NOT operator
predicate.$not()
```

**Building complex predicates:**
```dart
// Combine with AND (ignores null, allows `if (...) predicate`)
Predicate.and([pred1, pred2, pred3])

// Equivalent if no predicate is null:
pred1 & pred2 & pred3

// Combine with OR (ignores null, allows `if (...) predicate`)
Predicate.or([pred1, pred2, pred3])

// Equivalent if no predicate is null:
pred1 | pred2 | pred3

// Constant predicates
Predicate.alwaysTrue
Predicate.alwayFalse
```

**Example: optional filters:**
```dart
Predicate buildSearchPredicate(
  EntityFieldsExpr<Order> fields,
  OrderFilters filters,
) {
  return Predicate.and([
    // Always active filter
    fields.deleted.$equal(false),

    // Conditional filters
    if (filters.status != null)
      fields.status.$equal(filters.status!),

    if (filters.minAmount != null)
      fields.totalAmount.$greaterOrEqual(filters.minAmount!),

    if (filters.customerRef != null)
      fields.customer.$samePk(filters.customerRef!),

    if (filters.hasLines == true)
      $OrderLine.existsOrderLine(callContext)(
        where: (line) => line.order.$equalExpr(fields.uuid),
      )
    else if (filters.hasLines == false)
      $OrderLine.notExistsOrderLine(callContext)(
        where: (line) => line.order.$equalExpr(fields.uuid),
      ),
  ]);
}
```

**Example: text search with OR:**
```dart
where: (fields) =>
  fields.name.$wordSearch(searchText, caseSensitive: false) |
  fields.orderNumber.$equal(searchText.toUpperCase()) |
  fields.customerRef.$contains(searchText)
```

### 2.5. Converting Values to Expressions

To use a Dart value in an expression calculation, convert it with `.toExpresssion()`:

```dart
// Available for: String, int, double, bool
final maxDiameter = 25.5; // Dart double

where: (dim) =>
  (maxDiameter.toExpresssion() - dim.value * dim.unit.$map(toMmFactor))
    .$lessThan(0.0)
```

## 3. Query Operations

`$Order.query(callContext)` returns a `Query<Order, String>` (entity type, primary key type). Its verbs take everything they need as named parameters and return their result at once: a `DataLoader<E>` for rows, a `Future<int>` for counts, a `Predicate` or a `ValueExpr` for subqueries. Anything that produces a handle reused later (join, group, projection, CTE, compound) goes through the engine builder opened by `query.select()` (see section 5).

You'll often encounter calls to `listValues()`, `exactlyOne()`, `one()`, `execute()`, `count()` on the returned `DataLoader`. See [explanations on the DataLoader class](DATA_CLASSES.md). Write verbs also return a `DataLoader<E>`: `execute()` or `count()` runs the statement, `listValues()`/`exactlyOne()` runs it and hands back the written rows as the database stored them.

### 3.1. LOAD Queries

#### 3.1.1. Basic Load with WHERE

```dart
final orders = await $Order.query(callContext).load(
  where: (fields) =>
      fields.status.$equal(OrderStatus.pending) &
      fields.totalAmount.$greaterOrEqual(100.0),
).listValues();
```

`load` also takes `orderBy`, `limit` and `offset`. The expectations of the loader (`fields`, `resolve`, `sort`, `limit` of `listValues`) append their own sorts and override the pagination:
```dart
final latest = await $Order.query(callContext).load(
  where: (fields) => fields.status.$equal(OrderStatus.pending),
  orderBy: (fields) => [fields.orderDate.$desc, fields.orderNumber.$asc],
  limit: 20,
).listValues();
```
`$asc`, `$desc` and `$sorted(descending:, nullsFirst:)` build a `SortSpec` from any expression.

#### 3.1.2. Load by Primary Key

```dart
// Exactly one result (exception if absent)
final order = await $Order.query(callContext).loadKey(orderId).exactlyOne();

// Zero or one result
final order = await $Order.query(callContext).loadKey(orderId).one();

// Several keys
final orders = await $Order.query(callContext).loadKeys(orderIds).listValues();
```

#### 3.1.3. Load by Reference

```dart
final order = await $Order.query(callContext).loadRef(orderReference).exactlyOne();
final orders = await $Order.query(callContext).loadRefs(references).listValues();
```

#### 3.1.4. Count

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
`load(...).count()` gives the same `COUNT(*)`.

#### 3.1.5. Raw Column Values

`values` reads columns without building rows: the result is a `List<List>`, one inner list per row, values in column order as the driver decodes them.
```dart
final List<List> rows = await $Order.query(callContext).values(
  columns: (fields) => [fields.orderNumber, fields.totalAmount],
  where: (fields) => fields.status.$equal(OrderStatus.shipped),
);
```
`values` also takes `groupBy` and `having` for aggregated columns:
```dart
final totals = await $Order.query(callContext).values(
  columns: (fields) => [fields.customer, fields.totalAmount.$sum()],
  groupBy: (fields) => [fields.customer],
  having: (fields) => fields.totalAmount.$sum().$greaterThan(1000.0),
);
```

### 3.2. INSERT Queries

#### 3.2.1. Inserting a Single Row

```dart
final order = await $Order.query(callContext).insert([orderDataRow]).exactlyOne();
// Returns the inserted DataRowValues, as the database stored it (defaults applied)

print("Order created: ${order.uuid.value}");
```

#### 3.2.2. Inserting Multiple Rows

```dart
await $OrderLine.query(callContext).insert(lineDataRows).execute();
```

**Get the number of inserted rows:**
```dart
final count = await $OrderLine.query(callContext).insert(lineDataRows).count();

print("$count rows inserted");
```
`count()` runs the insert without reading the rows back; `listValues()` reads them back through `RETURNING`.

#### 3.2.3. Complete Example: Creating Order with Lines

```dart
DataLoader<Order> addOrder({
  required CallContext callContext,
  required Order$Instance order,
  required Iterable<OrderLine$Instance> orderLines,
}) {
  return DataLoader<Order>.defered($Order.ofContext(callContext), (expect) async {
    // Business validation
    if (orderLines.isEmpty) {
      throw AppError("An order must have at least one line");
    }

    // Insert order
    order = await $Order.query(callContext).insert([order.$dataRow]).exactlyOne();

    // Link lines to order
    for (final line in orderLines) {
      line.order.primaryKey = order.uuid.value;
    }

    // Insert lines
    await $OrderLine
        .query(callContext)
        .insert(orderLines.map((e) => e.$dataRow))
        .execute();

    // Return order with expectations
    return $Order
        .query(callContext)
        .loadRef(order.$asReference)
        .withExpectations(expect);
  });
}
```

#### 3.2.4. INSERT from a SELECT

`insertSelect` writes the rows of a select shaped as the target entity: a projection built with the generated `$Target.project(...)` (every field) or `$Target.partialProject(...)` (some fields, the others left to the database default), or a plain select of the entity's own rows. See section 5 for the builder.
```dart
// Copy delivered orders into an OrderArchive entity sharing the same field names
await $OrderArchive.query(callContext).insertSelect(
  ($Order.query(callContext).select()
        ..where((o) => o.status.$equal(OrderStatus.delivered)))
      .projectPartial(
        (o) => $OrderArchive.partialProject(
          uuid: o.uuid,
          orderNumber: o.orderNumber,
          totalAmount: o.totalAmount,
        ),
      ),
).execute();
```
`insertSelect` is refused on an entity with change listeners unless `ignoreListeners: true`, and on an entity stored over several tables (inheritance).

### 3.3. UPDATE Queries

#### 3.3.1. Update a Single Row (modified fields only)

```dart
// Load the order
final order = await $Order.query(callContext).loadKey(orderId).exactlyOne();

// Modify fields
order.status.value = OrderStatus.shipped;
order.shippedAt.setToNow(callContext);

// Save (only modified fields are updated, the row located by its primary key)
await $Order.query(callContext).update([order.$dataRow]).execute();
```

`update` takes several rows. With `where`, each row is located by a predicate built from its values rather than by its primary key:
```dart
await $Order.query(callContext).update(
  rows,
  where: (row, fields) =>
      fields.orderNumber.$equal(Order$Instance(row).orderNumber.value),
).execute();
```

#### 3.3.2. Bulk Update with WHERE

`updateWhere` sets columns on every row a predicate selects, without loading them. The `set` callback receives a `FieldSetter` and the **fields** of the entity (`Field` objects, not expressions):
```dart
await $Order.query(callContext).updateWhere(
  set: (set, fields) => set.setValue(fields.status, OrderStatus.cancelled),
  where: (fields) =>
      fields.status.$equal(OrderStatus.pending) &
      fields.orderDate.$daysFrom(UtcDateTime.now()).$greaterThan(30),
).execute();
```
`updateWhere` is refused on an entity with change listeners unless `ignoreListeners: true` (the listeners never see the rows).

#### 3.3.3. Update with Expression (calculated value)

`setExpr` takes a callback receiving the **expressions** of the entity, so the assigned value may read the row being updated.

**Update counter with subquery:**
```dart
await $Order.query(callContext).updateWhere(
  set: (set, fields) => set.setExpr(
    fields.lineCount,
    (order) => $OrderLine.query(callContext).oneValue(
      what: (line) => line.uuid.$count(),
      where: (line) => line.order.$equalExpr(order.uuid),
    ),
  ),
  where: (fields) => fields.uuid.$equal(orderId),
).execute();
```

**Calculation from other fields:**
```dart
await $OrderLine.query(callContext).updateWhere(
  set: (set, fields) => set.setExpr(
    fields.lineTotal,
    (line) => line.quantity.$asDouble * line.unitPrice,
  ),
  where: (fields) => fields.order.$equal(orderId),
).execute();
```

#### 3.3.4. FieldSetter Methods

- **`setValue(field, value)`**: a **Dart value** (or `null`)
```dart
set.setValue(fields.status, OrderStatus.shipped)
set.setValue(fields.shippedAt, UtcDateTime.now())
set.setValue(fields.customer, customerRef)   // a Reference<Customer>
```
- **`setExpr(field, (fields) => expr)`**: an **SQL expression** over the row
```dart
// Subquery
set.setExpr(
  fields.productCount,
  (category) => $Product.query(callContext).oneValue(
    what: (p) => p.uuid.$count(),
    where: (p) => p.category.$equalExpr(category.uuid),
  ),
)

// Calculation from other fields
set.setExpr(fields.total, (o) => o.subtotal + o.tax - o.discount)

// Conditional expression
set.setExpr(
  fields.priority,
  (o) => o.urgent.$map({true: 1, false: 4}),
)
```
- **`setNull(field)`**: `NULL`
- **`increment(field, n)`**: `field = field + n`
```dart
set.increment(fields.retryCount, 1)
```

#### 3.3.5. UPDATE from a SELECT

`updateSelect` assigns columns from a select correlated to the row being updated: the `source` callback receives the order, whose `subquery<S>(def)` opens a select able to reference `order.fields`. The select must yield one row per updated row.
```dart
// Fill the missing shipping address from the customer's address
await $Order.query(callContext).updateSelect(
  source: (order) =>
      (order.subquery<Customer>($Customer.ofContext(callContext))
            ..where((c) => c.uuid.$equalExpr(order.fields.customer)))
          .projectPartial((c) => $Order.partialProject(shippingAddress: c.address)),
  where: (o) => o.shippingAddress.$isNull,
).execute();
```
Same restrictions as `insertSelect`: no change listeners (unless `ignoreListeners: true`), single storage table.

### 3.4. DELETE Queries

#### 3.4.1. Delete by Key/Reference

```dart
// By primary key
await $Order.query(callContext).deleteKey(orderId).execute();
await $Order.query(callContext).deleteKeys(orderIds).execute();

// By reference
await $Order.query(callContext).deleteRef(orderRef).execute();
await $Order.query(callContext).deleteRefs(orderRefs).execute();
```

#### 3.4.2. Bulk Delete with WHERE

```dart
final count = await $Order.query(callContext).delete(
  where: (fields) =>
      fields.status.$equal(OrderStatus.cancelled) &
      fields.orderDate.$daysFrom(UtcDateTime.now()).$greaterThan(90),
).count();

print("$count old orders deleted");
```
`count()` deletes without reading the rows unless a change listener needs them; `listValues()` hands the deleted rows back. `delete(where:)` is refused on an entity with change listeners unless `ignoreListeners: true`; `deleteKey(s)`/`deleteRef(s)` always run the listeners.

**Important:** `OnDeleteRule` rules defined in the model apply:
- `cascade`: cascading deletion of children
- `setNull`: foreign keys set to NULL
- `error`: exception if children exist

### 3.5. UPSERT Queries

**Insert or Update based on primary key existence:**

```dart
final order = await $Order.query(callContext).upsert([orderDataRow]).exactlyOne();
```

**Behavior:**
- If primary key exists → **UPDATE** (`INSERT ... ON CONFLICT DO UPDATE`)
- If primary key doesn't exist → **INSERT**

**Use case:** Data synchronization where you don't know if the record exists.

**Upsert on a predicate** (`on`): the stored row is the one matching a predicate built from the row's values, instead of the primary key. On a single table this is a `MERGE` (PostgreSQL 15+); the predicate must match at most one row.
```dart
await $Order.query(callContext).upsert(
  rows,
  on: (row, stored) =>
      stored.orderNumber.$equal(Order$Instance(row).orderNumber.value),
).execute();
```
On an entity stored over several tables (inheritance), the stored row is looked up first, then updated or inserted, with no lock against a concurrent insert.

### 3.6. Automatic Joins

Navigating a reference in a predicate or an expression makes the join for you:
```dart
// Orders from Spanish customers delivered abroad
final spanish = await $Order.query(callContext).load(
  where: (fields) =>
      fields.customer.address.country.$equal("ES") &
      fields.shippingAddress.country.$ifNullThen("ES").$different("ES"),
).listValues();

// SELECT T1.*
//   FROM order T1
//   INNER JOIN customer T2 ON (T2.uuid = T1.customer)
//   INNER JOIN address T3 ON (T3.uuid = T2.address)
//   LEFT OUTER JOIN address T4 ON (T4.uuid = T1.shipping_adress)
// WHERE ( T3.country = ?p1)
//   AND ( COALESCE( T4.country, ?p2) != ?p3)
```
Joins are:
- **inner** (`INNER JOIN`) if the foreign key cannot be null.
- **outer** (`LEFT OUTER JOIN`) otherwise.

A join in the other direction (children of a row, with a predicate of your own) is an explicit `join` on the builder (see 5.2).

## 4. Subqueries and Aggregations

### 4.1. EXISTS / NOT EXISTS

#### 4.1.1. Automatically Generated Methods

Sing generates for **each entity**:
- `exists{EntityName}(callContext)` → function returning a Predicate
- `notExists{EntityName}(callContext)` → function returning a Predicate
- `valueFrom{EntityName}<T>(callContext, what:, where:, groupBy:, having:)` → `QueryExpr<T>`, same as `query(callContext).oneValue(...)`

These methods are in the generated `$Entity` class and shortcut `$Entity.query(callContext).exists(where:)`, `.notExists(where:)` and `.oneValue(...)`. The subquery is correlated to the select it renders in: its `where` may reference the fields of the outer query.

#### 4.1.2. Basic EXISTS

```dart
// Orders having at least one line with quantity > 10
final orders = await $Order.query(callContext).load(
  where: (fields) => $OrderLine.existsOrderLine(callContext)(
    where: (line) =>
        line.order.$equalExpr(fields.uuid) & line.quantity.$greaterThan(10),
  ),
).listValues();
```

#### 4.1.3. NOT EXISTS

```dart
// Orders without lines
final ordersWithoutLines = await $Order.query(callContext).load(
  where: (fields) => $OrderLine.notExistsOrderLine(callContext)(
    where: (line) => line.order.$equalExpr(fields.uuid),
  ),
).listValues();
```

#### 4.1.4. Nested EXISTS

```dart
// Products used in pending orders
final products = await $Product.query(callContext).load(
  where: (fields) => $OrderLine.existsOrderLine(callContext)(
    where: (line) =>
        line.product.$equalExpr(fields.uuid) &
        $Order.existsOrder(callContext)(
          where: (order) =>
              order.uuid.$equalExpr(line.order) &
              order.status.$equal(OrderStatus.pending),
        ),
  ),
).listValues();
```

**Note**: the same query could be written as:
```dart
// Products used in pending orders
final products = await $Product.query(callContext).load(
  where: (fields) => $OrderLine.existsOrderLine(callContext)(
    where: (line) =>
        line.product.$equalExpr(fields.uuid) &
        line.order.status.$equal(OrderStatus.pending),
  ),
).listValues();
```

#### 4.1.5. EXISTS Negation

```dart
// Two equivalent ways:

// 1. With NOT EXISTS
$OrderLine.notExistsOrderLine(callContext)(
  where: (line) => line.order.$equalExpr(fields.uuid),
)

// 2. With predicate negation
$OrderLine.existsOrderLine(callContext)(
  where: (line) => line.order.$equalExpr(fields.uuid),
).$not()
```

### 4.2. oneValue - Scalar Subqueries

#### 4.2.1. Use as Expression in WHERE

```dart
// Orders where total is greater than sum of lines
final orders = await $Order.query(callContext).load(
  where: (fields) => fields.totalAmount.$greaterThanExpr(
    $OrderLine.query(callContext).oneValue(
      what: (line) => (line.quantity.$asDouble * line.unitPrice).$sum(),
      where: (line) => line.order.$equalExpr(fields.uuid),
    ),
  ),
).listValues();
```
`$OrderLine.query(callContext).oneValue(...)` has type `QueryExpr<double>`, a `ValueExpr<double>` (same type as the `what` return value). It also fits `IN`: `fields.uuid.$isInSelect(subquery)`.

#### 4.2.2. Get Actual Value with getValue()

```dart
// Calculate aggregation
final totalReceived = await $Order
    .query(callContext)
    .oneValue(
      what: (fields) => fields.totalAmount.$sum(),
      where: (fields) =>
          fields.status.$equal(OrderStatus.delivered) &
          fields.deliveredAt.$withoutTime.$equal(UtcDateTime.now().withoutTime),
    )
    .getValue(); // → Future<double?>

if (totalReceived != null) {
  print("Total delivered orders today: $totalReceived");
}
```
`getValue()` runs the subquery on its own and returns `null` unless it yields exactly one value of the expected type.

#### 4.2.3. oneValue with GROUP BY / HAVING

`oneValue` takes `groupBy` and `having`; the result is then one value per group, to be consumed by `IN` or an aggregate of the outer query:
```dart
// Customers with more than 5 orders
final busy = $Order.query(callContext).oneValue(
  what: (o) => o.customer,
  groupBy: (o) => [o.customer],
  having: (o) => o.uuid.$count().$greaterThan(5),
);
final customers = await $Customer.query(callContext).load(
  where: (c) => c.uuid.$isInSelect(busy),
).listValues();
```

#### 4.2.4. Common Aggregations

Aggregates are **methods**, each taking an optional `filter:` predicate (`FILTER (WHERE ...)`).

**Sum:**
```dart
what: (line) => line.quantity.$sum()
what: (line) => (line.quantity.$asDouble * line.unitPrice).$sum()  // Calculate then sum
```

**Average:**
```dart
what: (order) => order.totalAmount.$avg()
```

**Min / Max:**
```dart
what: (order) => order.totalAmount.$max()
what: (order) => order.orderDate.$min()
```

**Count:**
```dart
what: (line) => line.uuid.$count()                  // Number of lines
what: (line) => line.product.$count(distinct: true) // Number of distinct products
what: (line) => line.uuid.$count(filter: line.quantity.$greaterThan(10))
```

**Standard deviation:**
```dart
what: (order) => order.totalAmount.$stdDev()
```

## 5. Engine Builder (select)

`query.select()` returns a `TupleSelect<E>`: the select of the entity's rows, ready to run, on which joins, filters, ordering, grouping, projections, CTEs and compounds accumulate. The façade verbs of section 3 are built on it; use it directly when a verb is not enough. Mutators (`where`, `orderBy`, `distinct`, `distinctOn`, `limit`, `offset`, `having`) return `void`: chain them with the cascade operator `..`. Transitions that produce another object (`groupBy`, `groupingSets`, `project`, `projectPartial`, `asCte`, `union`...) return it.

### 5.1. Filters, Sorts, Fetch

```dart
final select = $Order.query(callContext).select()
  ..where((o) => o.status.$equal(OrderStatus.pending))
  ..where((o) => o.totalAmount.$greaterThan(100.0))   // AND
  ..orderBy((o) => [o.orderDate.$desc])
  ..limit(20);

final orders = await select.fetch(callContext).listValues();  // DataLoader<Order>
final count = await select.count(callContext);               // COUNT(*)
final rows = await select.values(callContext, (o) => [o.orderNumber, o.totalAmount]);
print(select.toSql());                                        // the SQL text
```
`fetch(callContext)` returns the same `DataLoader<E>` as `load`; the loader's `fields`, `resolve`, `sort` and `limit` apply on top. `distinct()` and `distinctOn((o) => [...])` are available (the `ORDER BY` must start with the `DISTINCT ON` expressions).

### 5.2. Explicit Joins

`join<J>(def, on:, outer:)` joins another entity and returns its fields, usable in every later clause of the select:
```dart
final orders = $Order.query(callContext).select();
final lines = orders.join<OrderLine>(
  $OrderLine.ofContext(callContext),
  on: (line) => line.order.$fkEqualExpr(orders.fields.uuid),
  outer: true,
);
orders..where((o) => lines.quantity.$greaterThan(10));
```
`select.fields` are the expressions of the root entity; `$fkEqualExpr` compares a reference field to a primary key expression. Reference navigation (`o.customer.name`) still joins automatically.

### 5.3. GROUP BY and Projections

`groupBy` moves to a `GroupedSelect`, on which only `having` and the subquery forms remain; its rows are fetched through a **projection** into the shape of a tuple. A tuple is a `ModelTuple` of the model, a virtual entity with fields and no table:
```dart
// model
class CustomerStatTuple extends ModelTuple {
  CustomerStatTuple();

  final customer = ReferenceTo<CustomerEntity>();

  final orderCount = IntField();

  final total = DoubleField();
}
```
Sing generates `$CustomerStat.project(...)` (every field required, nullable ones optional) and `$CustomerStat.partialProject(...)` (every field optional) with one `ValueExpr` parameter per field. A projected reference takes the primary key expression of its target.
```dart
DataLoader<CustomerStat> customerStats({required CallContext callContext}) {
  final orders = $Order.query(callContext).select();
  final grouped = orders.groupBy((o) => [o.customer])
    ..having((o) => o.uuid.$count().$greaterThan(1));
  return grouped
      .project(
        (o) => $CustomerStat.project(
          customer: o.customer,
          orderCount: o.uuid.$count(),
          total: o.totalAmount.$sum(),
        ),
      )
      .fetch(callContext);
}
```
`project` returns a `ProjectedSelect<E, P>`: `fetch(callContext)` gives a `DataLoader<P>` (rows of the tuple, references resolvable), `count(callContext)` the number of groups. `project` also works on an ungrouped select to fetch computed columns; `projectPartial` (some fields only) feeds `insertSelect`/`updateSelect` and nothing else.

**Grouping sets** (`GROUP BY GROUPING SETS`): one aggregation level per set, the empty set being the grand total. `GroupingExpr([dims...])` tells the levels apart (bit set when the dimension is aggregated at that row):
```dart
final levels = orders.groupingSets((o) => [
  [o.customer, o.status],
  [o.customer],
  [],
]);
```
A select grouped by sets takes no further `groupBy`.

### 5.4. Subqueries in the Builder

`subquery<S>(def)` opens a select correlated to the current one; end it with `exists()`, `notExists()` or `oneValue((s) => expr)`:
```dart
final orders = $Order.query(callContext).select();
final withBigLine = orders
    .subquery<OrderLine>($OrderLine.ofContext(callContext))
  ..where((line) => line.order.$equalExpr(orders.fields.uuid))
  ..where((line) => line.quantity.$greaterThan(10));
orders..where((_) => withBigLine.exists());
```
The generated `existsX`/`notExistsX`/`valueFromX` of section 4 are usable inside `where` as well.

### 5.5. Common Table Expressions

`asCte(name:)` freezes any fixed-shape select (entity select or full projection) as a `CteSource<P>`; `TupleSelect<P>.onCte(cte)` selects from it and `joinCte<P>(cte, on:)` joins it. One source declares once per statement however many times it is used.
```dart
// The ProjectedSelect of 5.3, before fetch
final stats = customerStatsSelect(callContext).asCte(name: "stats");

// Select on the CTE
final big = TupleSelect<CustomerStat>.onCte(stats)
  ..where((s) => s.total.$greaterThan(10000.0));
final rows = await big.fetch(callContext).listValues();

// Join the CTE
final customers = $Customer.query(callContext).select();
final joined = customers.joinCte<CustomerStat>(
  stats,
  on: (s) => s.customer.$fkEqualExpr(customers.fields.uuid),
);
customers..where((_) => joined.orderCount.$greaterThan(3));
```
`RecursiveCteSource<P>(roots:, recurse: (self) => ..., all: true)` builds a `WITH RECURSIVE`: `roots` and the select `recurse` builds on `self` share the shape `P`; the recursive branch may neither group nor aggregate.

### 5.6. Compounds (UNION, INTERSECT, EXCEPT)

Two selects of the same shape combine with `union`, `intersect`, `except` (`all: true` for the `ALL` variants). The `CompoundSelect<P>` takes `orderBy`, `limit`, `offset` on the shape's fields and runs with `fetch(callContext)` or `count(callContext)`.
```dart
final pending = $Order.query(callContext).select()
  ..where((o) => o.status.$equal(OrderStatus.pending));
final unpaid = $Order.query(callContext).select()
  ..where((o) => o.paidAt.$isNull);
final orders = await (pending.union(unpaid)
      ..orderBy((o) => [o.orderDate.$desc]))
    .fetch(callContext)
    .listValues();
```

### 5.7. Engine Write Orders (advanced)

The façade verbs run engine orders you may use directly on a `ServerEntityDef` (`$Order.ofContext(callContext)`): `InsertRows`, `InsertSelect`, `UpdateRow`, `UpdateWhere`, `UpdateSelect`, `UpsertRow` (`ON CONFLICT`), `DeleteWhere`, `MergeRows` (`MERGE`, PostgreSQL 15+). Each has `execute(callContext)` (row count), `returning(fields)` then `fetch(callContext)` (a `DataPacket<E>` of the returned rows) and `toSql()`. **They bypass** change listeners, access tokens, mandatory field checks and the multi-table dispatch of inherited entities: prefer the façade unless you need a branch it does not expose.

```dart
final def = $Order.ofContext(callContext);
final merge = MergeRows<Order>.rows(def, rows)
  ..on((stored, incoming) => stored.orderNumber.$equalExpr(incoming.orderNumber))
  ..whenMatchedRewrite()
  ..whenNotMatchedInsert();
final written = await merge.execute(callContext);
```
`MergeRows` branches: `whenMatchedUpdate`, `whenMatchedRewrite`, `whenMatchedDelete`, `whenMatchedDoNothing`, `whenNotMatchedInsert`, `whenNotMatchedDoNothing`, `whenNotMatchedBySourceDelete`/`Update` (PostgreSQL 17); `onPrimaryKey()` is the usual upsert join; `MergeRows.select(def, (order) => ...)` takes a select source opened through `order.subquery`. `UpdateWhere` and `UpsertRow.doUpdateOnConflict` take a `ColumnSetter` (`setValue`, `setExpr`, `setNull`, `increment`), the engine counterpart of the façade's `FieldSetter`.

## 6. Advanced Patterns

### 6.1. Arithmetic Expressions in WHERE

#### 6.1.1. Converting Values to Expressions

```dart
final maxExternalDiameter = 25.5; // Dart value

where: (dim) =>
  (maxExternalDiameter.toExpresssion() -
    dim.value * dim.unit.$map(dimensionToMm).$cast<double>())
      .$lessThan(-epsilon)
```

**Why `toExpresssion()`?**
- `maxExternalDiameter` is a Dart `double`
- Fields (`dim.value`) are `ValueExpr<double>`
- Arithmetic operators require `ValueExpr op ValueExpr`
- `.toExpresssion()` converts the Dart value to an expression

#### 6.1.2. Type Casting for Arithmetic

```dart
where: (dim) =>
  dim.value * dim.unit.$map(dimensionToMm).$cast<double>()
```

**Why `$cast<double>()`?**
- `dim.unit.$map(dimensionToMm)` returns `ValueExpr<num>` (generic type)
- `dim.value` is `ValueExpr<double>`
- The `*` operator is defined for `(double, double)` or `(int, int)` but not `(double, num)`
- The cast forces the `double` type to allow multiplication

#### 6.1.3. Complete Example with Epsilon

```dart
static const epsilon = 1E-8;

where: (dim) =>
  (edMax.toExpresssion() -
    dim.value * dim.unit.$map(dimToMM).$cast<double>())
      .$lessThan(-epsilon)
```

This pattern avoids floating-point comparison issues by using an epsilon.

### 6.2. Conditional Expressions

#### 6.2.1. $Iif - SQL CASE Expression

```dart
List<List> orders = await $Order
    .query(callContext)
    .values(
      columns: (fields) => [
        fields.orderNumber,
        Expression.$Iif<String>({
          fields.status.$equal(OrderStatus.pending): 'Pending'
              .toExpresssion(),
          fields.status.$equal(OrderStatus.processing): 'Processing'
              .toExpresssion(),
          fields.status.$equal(OrderStatus.shipped): 'Shipped'
              .toExpresssion(),
        }, otherwise: 'Other'.toExpresssion()),
      ],
    );
```

#### 6.2.2. $map - Simplified Conditional Mapping

```dart
// Simple value → value mapping
final priority = fields.status.$map({
  OrderStatus.urgent: 1,
  OrderStatus.high: 2,
  OrderStatus.normal: 3,
  OrderStatus.low: 4,
}, defaultValue: 99);

// Use in WHERE
where: (fields) =>
  fields.status.$map({
    OrderStatus.urgent: 1,
    OrderStatus.high: 2,
    OrderStatus.normal: 3,
  }, defaultValue: 4).$lessOrEqual(2)
```

**$map vs $Iif:**
- `$map`: simple mapping, more concise
- `$Iif`: more flexible, allows complex expressions as values

#### 6.2.3. Expression Mapping with $mapExpr

```dart
final adjustedPrice = fields.priceCategory.$mapExpr({
  PriceCategory.retail: fields.basePrice * 1.2.toExpresssion(),
  PriceCategory.wholesale: fields.basePrice * 0.9.toExpresssion(),
  PriceCategory.vip: fields.basePrice * 0.8.toExpresssion(),
}, defaultValue: fields.basePrice);
```

### 6.3. Working with References

#### 6.3.1. Comparing References

```dart
// Compare FK with a Reference object
where: (fields) => fields.customer.$samePk(customerRef)

// Compare FK with a primary key value (if PK is String)
where: (fields) => fields.customer.$equal(customerId)

// Compare two reference fields
where: (fields) => fields.assignedTo.$sameReference(fields.createdBy)
```

#### 6.3.2. Navigating References

```dart
// Access fields of referenced entity
where: (fields) =>
  fields.customer.name.$contains('ACME') &
  fields.customer.address.country.$equal('FR')
```
Joins are automatically built.

#### 6.3.3. Updating References

**With setValue (when you have a Reference):**
```dart
await $Order.query(callContext).updateWhere(
  set: (set, fields) => set.setValue(fields.customer, newCustomerRef),
  where: (fields) => fields.uuid.$equal(orderId),
).execute();
```

**With setExpr (subquery):**
```dart
await $Order.query(callContext).updateWhere(
  set: (set, fields) => set.setExpr(
    fields.assignedTo,
    (_) => $User.query(callContext).oneValue(
      what: (user) => user.uuid,
      where: (user) => user.name.$equal("DOLL"),
    ),
  ),
  where: (fields) => fields.status.$equal(OrderStatus.pending),
).execute();
```

### 6.4. NULL Value Handling

#### 6.4.1. NULL Tests

```dart
// Orders without delivery date
where: (fields) => fields.deliveredAt.$isNull

// Orders with manager reference
where: (fields) => fields.manager.$isNotNull
```

#### 6.4.2. NULL Replacement (COALESCE)

**With a value:**
```dart
// Use 0 if discount is NULL
fields.discount.$ifNullThen(0.0)

// Calculate total with optional discount
set.setExpr(
  fields.total,
  (o) => o.subtotal - o.discount.$ifNullThen(0.0),
)
```

**With an expression:**
```dart
// Use defaultLabel if label is NULL
fields.label.$ifNullThenExpr(fields.defaultLabel)

// Cascade of multiple fields
fields.phone.$ifNullThenExpr(
  fields.mobilePhone.$ifNullThenExpr(
    fields.officePhone
  )
)
```

#### 6.4.3. Nullity in Comparisons

```dart
// NULL vs non-NULL references
fields.manager.$isNull                    // Manager is NULL
fields.assignedTo.$differentPk(userRef)   // Handles NULL automatically

// Warning: $different does NOT match NULL
fields.status.$different(OrderStatus.cancelled)  // Excludes NULL
// To include NULL:
fields.status.$different(OrderStatus.cancelled) | fields.status.$isNull
```

## 7. Security Best Practices

### 7.1. Always Use CallContext

```dart
// ✅ Correct
$Order.query(callContext).load(...)

// ❌ Never raw SQL
// Doesn't exist in Sing - by design!
```

The `CallContext`:
- Encapsulates a transaction (a database transaction). For sub-transactions => callContext.subTransaction
- Identifies the user
- Applies access controls
- Prevents SQL injections (raw values are **always** passed with parameters, **never** injected into SQL order)
- Traces operations (debugging)

### 7.2. Leverage Type-Safe Expressions

**The compiler is your ally:**
```dart
// The compiler detects
fields.orderNum.$equal("12345")     // ❌ Field doesn't exist
fields.orderDate.$equal("2024")     // ❌ Incorrect type
fields.status.$equal(123)           // ❌ Incompatible type
```

**After model modification:**
- All obsolete usages are flagged
- Refactoring is safe
- No silent regression

### 7.3. Use Generated Code

```dart
// ✅ Use generated methods
$OrderLine.existsOrderLine(callContext)

// ✅ Trust the type system
final orders: List<Order$Instance> = ...
for (final order in orders) {
  // Compiler knows all fields
  order.status.value = OrderStatus.shipped;
}
```

### 7.4. Business Validation in Services

```dart
mixin OrderServices on EntityServerServices<Order, String> {
  DataLoader<Order> validateAndShip({
    required CallContext callContext,
    required String orderId,
  }) {
    // Need to perform async operations before returning a DataLoader => use DataLoader.defered
    return DataLoader.defered($Order.ofContext(callContext), (expect) async {
      final order = await $Order.query(callContext).loadKey(orderId).exactlyOne();

      // Business validations
      // Note that typed AppError exceptions are sent to client applications
      if (order.status.value != OrderStatus.pending) {
        throw AppError("Only pending orders can be shipped");
      }

      final lineCount = await $OrderLine.query(callContext).count(
        where: (line) => line.order.$equal(orderId),
      );

      if (lineCount == 0) {
        throw AppError("Cannot ship an order without lines");
      }

      // Update
      order.status.value = OrderStatus.shipped;
      order.shippedAt.setToNow(callContext);

      await $Order.query(callContext).update([order.$dataRow]).execute();

      return $Order
          .query(callContext)
          .loadRef(order.$asReference)
          .withExpectations(expect);
    });
  }
}
```

## 8. Summary and Cheat Sheet

### 8.1. Query Anatomy

```dart
await $Entity
  .query(callContext)              // Entry point: Query<E, PK>
  .{verb}(...)                     // load(where:), loadKey(pk), insert(rows), updateWhere(set:, where:), delete(where:), ...
  .{expected}                      // [fields, resolve, sort](DATA_CLASSES.md)
  .{execution}                     // listValues, exactlyOne, execute, count, etc.

$Entity.query(callContext).select() // Engine builder: TupleSelect<E>
  ..where(...)..orderBy(...)        // then join, groupBy, project, asCte, union...
  .fetch(callContext)               // DataLoader<E>
```

### 8.2. Main Operations

| Operation      | Syntax                                                  | Result                   |
| -------------- | ------------------------------------------------------- | ------------------------ |
| LOAD           | `.load(where: ...).listValues()`                        | `List<DataRowValues<E>>` |
| LOAD by key    | `.loadKey(pk).exactlyOne()` / `.loadRef(ref).one()`     | `DataRowValues<E>`       |
| COUNT          | `.count(where: ...)`                                    | `int`                    |
| RAW COLUMNS    | `.values(columns: ..., where: ...)`                     | `List<List>`             |
| INSERT         | `.insert([dataRow]).exactlyOne()`                       | `DataRowValues<E>`       |
| INSERT SELECT  | `.insertSelect(select.projectPartial(...)).execute()`   | `void`                   |
| UPDATE rows    | `.update([dataRow]).execute()`                          | `void`                   |
| UPDATE where   | `.updateWhere(set: (set, f) => ..., where: ...).count()`| `int`                    |
| UPDATE SELECT  | `.updateSelect(source: (order) => ..., where: ...)`     | `DataLoader<E>`          |
| DELETE         | `.deleteKey(pk).execute()` / `.delete(where: ...).count()` | `void` / `int`        |
| UPSERT         | `.upsert([dataRow]).exactlyOne()`                       | `DataRowValues<E>`       |
| UPSERT on      | `.upsert(rows, on: (row, stored) => ...).execute()`     | `void`                   |
| EXISTS         | `$Entity.existsEntity(ctx)(where: ...)`                 | `Predicate`              |
| SCALAR         | `.oneValue(what: ..., where: ...)`                      | `QueryExpr<T>`           |
| BUILDER        | `.select()..where(...)` then `.fetch(ctx)`              | `TupleSelect<E>`         |
| GROUP          | `.select().groupBy(...).project((f) => $T.project(...))`| `ProjectedSelect<E, T>`  |

### 8.3. Expressions vs Values

| Context             | Type            | Example                                  |
| ------------------- | --------------- | ---------------------------------------- |
| Field in WHERE      | `ValueExpr<T>`  | `fields.status`                          |
| Comparison method   | `Predicate`     | `.$equal(OrderStatus.pending)`           |
| Subquery            | `QueryExpr<T>`  | `$Order.query(ctx).oneValue(...)`        |
| After `.getValue()` | `Future<T?>`    | `await expr.getValue()`                  |
| Field in `set:`     | `Field<T>`      | `fields.status` (of `updateWhere`)       |
| DataRowValues field | `FieldValue<T>` | `order.status`                           |
| Field value         | `T`             | `order.status.value`                     |

### 8.4. Important Prefixes and Suffixes

- **`$`**: Identifies framework methods/fields (avoids conflicts)
- **`Expr`**: Suffix for variants taking expressions (`$equalExpr`)
- **`toExpresssion()`**: Converts a Dart value to expression
- **`$cast<T>()`**: Forces expression type
- **`.getValue()`**: Executes a scalar subquery and returns the value
- **`$asc` / `$desc`**: Turn an expression into a `SortSpec` (`orderBy`)
- **`..`**: Cascade on the builder mutators (`where`, `orderBy`, `limit`, `having` return `void`)

### 8.5. Security Checklist

- ✅ Use type-safe expressions (never raw SQL)
- ✅ Leverage generated methods (`exists...`, `valueFrom...`, `$X.project`)
- ✅ Validate business logic in services
- ✅ Test after model modification (compiler detects errors)
- ✅ Use `.exactlyOne()` when a result is required
- ✅ Handle NULL values explicitly
- ✅ Prefer the façade verbs to the engine write orders (listeners, access tokens, mandatory fields)
- ✅ Document complex business rules

---

**To go further:**
- [DATA_CLASSES.md](DATA_CLASSES.md) - DataRowValues, DataLoader, DataRow
- [SERVICES.md](SERVICES.md) - Define and implement services
- [ACCESS_TOKEN.md](ACCESS_TOKEN.md) - Data access control
- [CONCEPTS_RELATIONSHIPS.md](CONCEPTS_RELATIONSHIPS.md) - Entity relationships
