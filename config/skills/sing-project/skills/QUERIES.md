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
final orders = await $Order.query(callContext).load
  .where(where: (fields) =>
    fields.status.$equal(OrderStatus.pending) &           // ✅ OK
    fields.totalAmount.$greaterThan(1000.0)               // ✅ OK
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
$Order.query(callContext).load.where(
  where: (fields) => fields.status.$equal(OrderStatus.pending)
)
```

**2. In UPDATE SET clauses:**
```dart
setter.setExpr(
  fields.lineCount,
  $OrderLine.oneValue(callContext,
    what: (line) => line.uuid.$count(),
    where: (line) => line.order.$equalExpr(fields.uuid),
  )
)
```

**3. In calculations:**
```dart
what: (line) => (line.quantity * line.unitPrice).$sum
```

#### When to Use Values

**1. After calling `.getValue()`:**
```dart
final avgTotal = await $Order.oneValue(callContext,
  what: (fields) => fields.totalAmount.$avg,
  where: (fields) => fields.status.$equal(OrderStatus.completed),
).getValue(); // → Future<double?>

print("Average amount: $avgTotal");
```

**2. In application logic after retrieval:**
```dart
final orders = await $Order.query(callContext).load.listValues();
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
await $Order.query(callContext).update.row(order.$dataRow).execute();
```

#### Example Showing Both Usages

```dart
// 1. Expression in WHERE: comparison with subquery
final bigOrders = await $Order
    .query(callContext)
    .load
    .where(
      where: (fields) => fields.totalAmount.$greaterThanExpr(
        // Expression
        $OrderLine
                .query(callContext)
                .oneValue(
                  what: (line) =>  //
                      (line.quantity.$asDouble * line.unitPrice).$sum,
                  groupBy: (fields) => [fields.order],
                  where: (line) =>
                      line.order.status.$equal(OrderStatus.delivered),
                )
                .$avg *
            1.5.toExpresssion(),
      ),
    )
    .listValues();

// 2. Value after getValue(): usage in code
final avgTotal = await $Order
    .query(callContext)
    .oneValue(
      what: (fields) => fields.totalAmount.$avg,
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
fields.amount.$sum              // Sum
fields.amount.$avg              // Average
fields.amount.$min              // Minimum
fields.amount.$max              // Maximum
fields.uuid.$count()            // Count
fields.uuid.$count(true)        // Distinct count
fields.amount.$stdDev           // Standard deviation
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

In this section, you'll often encounter calls to `listValues()`, `exactlyOne()`, `one()`, etc. See [explanations on the DataLoader class](DATA_CLASSES.md).

### 3.1. LOAD Queries

#### 3.1.1. Basic Load with WHERE

```dart
final orders = await $Order.query(callContext).load
  .where(where: (fields) =>
    fields.status.$equal(OrderStatus.pending) &
    fields.totalAmount.$greaterOrEqual(100.0)
  )
  .listValues();
```

#### 3.1.2. Load by Primary Key

```dart
// Exactly one result (exception if absent)
final order = await $Order.query(callContext).load
  .thisKey(orderId)
  .exactlyOne();

// Zero or one result
final order = await $Order.query(callContext).load
  .thisKey(orderId)
  .one();
```

#### 3.1.3. Load by Reference

```dart
final order = await $Order.query(callContext).load
  .thisRef(orderReference)
  .exactlyOne();
```

### 3.2. INSERT Queries

#### 3.2.1. Inserting a Single Row

```dart
final order = await $Order.query(callContext).insert
  .row(orderDataRow)
  .exactlyOne(); // Returns the inserted DataRowValues

print("Order created: ${order.uuid.value}");
```

#### 3.2.2. Inserting Multiple Rows

```dart
await $OrderLine.query(callContext).insert
  .rows(lineDataRows)
  .execute();
```

**Get the number of inserted rows:**
```dart
final count = await $OrderLine.query(callContext).insert
  .rows(lineDataRows)
  .count();

print("$count rows inserted");
```

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
    order = await $Order.query(callContext).insert
      .row(order.$dataRow)
      .exactlyOne();

    // Link lines to order
    for (final line in orderLines) {
      line.order.primaryKey = order.uuid.value;
    }

    // Insert lines
    await $OrderLine.query(callContext).insert
      .rows(orderLines.map((e) => e.$dataRow))
      .execute();

    // Return order with expectations
    return $Order.query(callContext).load
      .thisRef(order.$asReference)
      .withExpectations(expect);
  });
}
```

### 3.3. UPDATE Queries

#### 3.3.1. Update a Single Row (modified fields only)

```dart
// Load the order
final order = await $Order.query(callContext).load
  .thisKey(orderId)
  .exactlyOne();

// Modify fields
order.status.value = OrderStatus.shipped;
order.shippedAt.setToNow(callContext);

// Save (only modified fields are updated)
await $Order.query(callContext).update
  .row(order.$dataRow)
  .execute();
```

#### 3.3.2. Bulk Update with WHERE

```dart
await $Order.query(callContext).update.where(
  setter: (fields, setter) =>
    setter.setValue(fields.status, OrderStatus.cancelled),
  where: (fields) =>
    fields.status.$equal(OrderStatus.pending) &
    fields.createdAt.$daysFrom(UtcDateTime.now()).$greaterThan(30),
).execute();
```

#### 3.3.3. Update with Expression (calculated value)

**Update counter with subquery:**
```dart
await $Order.query(callContext).update.where(
  setter: (fields, setter) => setter.setExpr(
    fields.lineCount,
    $OrderLine.oneValue(callContext,
      what: (line) => line.uuid.$count(),
      where: (line) => line.order.$equalExpr(fields.uuid),
    ),
  ),
  where: (fields) => fields.uuid.$equal(orderId),
).execute();
```

**Calculation from other fields:**
```dart
await $OrderLine.query(callContext).update.where(
  setter: (fields, setter) => setter.setExpr(
    fields.lineTotal,
    fields.quantity * fields.unitPrice,
  ),
  where: (fields) => fields.order.$equal(orderId),
).execute();
```

#### 3.3.4. setValue vs setExpr

**`setValue(field, value)`** - When you have a **Dart value**
```dart
setter.setValue(fields.status, OrderStatus.shipped)
setter.setValue(fields.shippedAt, UtcDateTime.now())
setter.setValue(fields.customer, customerRef)
```

**`setExpr(field, expr)`** - When you have an **SQL expression**
```dart
// Subquery
setter.setExpr(
  fields.productCount,
  $Product.query(callContext).oneValue(
    what: (p) => p.uuid.$count(),
    where: (p) => p.category.$equalExpr(fields.uuid),
  )
)

// Calculation from other fields
setter.setExpr(
  fields.total,
  fields.subtotal + fields.tax - fields.discount
)

// Conditional expression
setter.setExpr(
  fields.priority,
  fields.urgent.$map({
    true: 1,
    false: fields.importance.$map({
      Importance.high: 2,
      Importance.medium: 3,
      Importance.low: 4,
    })
  })
)
```

### 3.4. DELETE Queries

#### 3.4.1. Delete by Key/Reference

```dart
// By primary key
await $Order.query(callContext).delete
  .thisKey(orderId)
  .execute();

// By reference
await $Order.query(callContext).delete
  .thisRef(orderRef)
  .execute();
```

#### 3.4.2. Bulk Delete with WHERE

```dart
final count = await $Order.query(callContext).delete.where(
  where: (fields) =>
    fields.status.$equal(OrderStatus.cancelled) &
    fields.createdAt.$daysFrom(UtcDateTime.now()).$greaterThan(90)
).count();

print("$count old orders deleted");
```

**Important:** `OnDeleteRule` rules defined in the model apply:
- `cascade`: cascading deletion of children
- `setNull`: foreign keys set to NULL
- `error`: exception if children exist

### 3.5. UPSERT Queries

**Insert or Update based on primary key existence:**

```dart
final order = await $Order.query(callContext).upsert
  .row(orderDataRow)
  .exactlyOne();
```

**Behavior:**
- If primary key exists → **UPDATE**
- If primary key doesn't exist → **INSERT**

**Use case:** Data synchronization where you don't know if the record exists.

### Table Joins

Sing queries automatically perform necessary joins in queries:
```dart
// Orders from Spanish customers delivered abroad
final spanish = await $Order
    .query(callContext)
    .load
    .where(
      where: (fields) =>
          fields.customer.address.country.$equal("ES") &
          (fields.shippingAddress.country.$ifNullThen(
            "ES",
          )).$different("ES"),
    )
    .listValues();

// SELECT T1.*
//   FROM order T1
//   INNER JOIN customer T2 ON (T2.uuid = T1.customer)
//   INNER JOIN address T3 ON (T3.uuid = T2.address)
//   LEFT OUTER JOIN address T4 ON (T4.uuid = T1.shipping_adress)
// WHERE ( T3.country = :Parameter placeholder:)
//   AND ( COALESCE( T4.country) != :Parameter placeholder:)
```
Joins are:
- **inner** (`INNER JOIN`) if the foreign key cannot be null.
- **outer** (`LEFT OUTER JOIN`) otherwise.
  
## 4. Subqueries and Aggregations

### 4.1. EXISTS / NOT EXISTS

#### 4.1.1. Automatically Generated Methods

Sing generates for **each entity**:
- `exists{EntityName}(callContext)` → function returning a Predicate
- `notExists{EntityName}(callContext)` → function returning a Predicate

These methods are in the generated `$Entity` class.

#### 4.1.2. Basic EXISTS

```dart
// Orders having at least one line with quantity > 10
final orders = await $Order.query(callContext).load.where(
  where: (fields) =>
    $OrderLine.existsOrderLine(callContext)(
      where: (line) =>
        line.order.$equalExpr(fields.uuid) &
        line.quantity.$greaterThan(10),
    ),
).listValues();
```

#### 4.1.3. NOT EXISTS

```dart
// Orders without lines
final ordersWithoutLines = await $Order.query(callContext).load.where(
  where: (fields) =>
    $OrderLine.notExistsOrderLine(callContext)(
      where: (line) => line.order.$equalExpr(fields.uuid),
    ),
).listValues();
```

#### 4.1.4. Nested EXISTS

```dart
// Products used in pending orders
final products = await $Product.query(callContext).load.where(
  where: (fields) =>
    $OrderLine.existsOrderLine(callContext)(
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
final products = await $Product.query(callContext).load.where(
  where: (fields) =>
    $OrderLine.existsOrderLine(callContext)(
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

#### 4.2.2. Use as Expression in WHERE

```dart
// Orders where total is greater than sum of lines
final orders = await $Order.query(callContext).load.where(
  where: (fields) =>
    fields.totalAmount.$greaterThanExpr(
      $OrderLine.query(callContext).oneValue(
        what: (line) => (line.quantity * line.unitPrice).$sum,
        where: (line) => line.order.$equalExpr(fields.uuid),
      ),
    ),
).listValues();
```
`$OrderLine.query(callContext).oneValue(...)` has type `ValueExpr<double>` (same type as the `what` return value).

#### 4.2.3. Get Actual Value with getValue()

```dart
// Calculate aggregation
      final totalReceived = await $Order
          .query(callContext)
          .oneValue(
            what: (fields) => (fields.totalAmount).$sum,
            where: (fields) =>
                fields.status.$equal(OrderStatus.delivered) &
                fields.deliveredAt.$withoutTime.$equal(
                  UtcDateTime.now().withoutTime,
                ),
          )
          .getValue(); // → Future<int?>

if (totalReceived != null) {
  print("Total delivered orders today: $totalReceived");
}
```

#### 4.2.4. Common Aggregations

**Sum:**
```dart
what: (line) => line.quantity.$sum
what: (line) => (line.quantity * line.unitPrice).$sum  // Calculate then sum
```

**Average:**
```dart
what: (order) => order.totalAmount.$avg
```

**Min / Max:**
```dart
what: (order) => order.totalAmount.$max
what: (order) => order.orderDate.$min
```

**Count:**
```dart
what: (line) => line.uuid.$count()           // Number of lines
what: (line) => line.product.$count(true)    // Number of distinct products
```

**Standard deviation:**
```dart
what: (order) => order.totalAmount.$stdDev
```

## 5. Advanced Patterns

### 5.1. Arithmetic Expressions in WHERE

#### 5.1.1. Converting Values to Expressions

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

#### 5.1.2. Type Casting for Arithmetic

```dart
where: (dim) =>
  dim.value * dim.unit.$map(dimensionToMm).$cast<double>()
```

**Why `$cast<double>()`?**
- `dim.unit.$map(dimensionToMm)` returns `ValueExpr<num>` (generic type)
- `dim.value` is `ValueExpr<double>`
- The `*` operator is defined for `(double, double)` or `(int, int)` but not `(double, num)`
- The cast forces the `double` type to allow multiplication

#### 5.1.3. Complete Example with Epsilon

```dart
static const epsilon = 1E-8;

where: (dim) =>
  (edMax.toExpresssion() -
    dim.value * dim.unit.$map(dimToMM).$cast<double>())
      .$lessThan(-epsilon)
```

This pattern avoids floating-point comparison issues by using an epsilon.

### 5.2. Conditional Expressions

#### 5.2.1. $Iif - SQL CASE Expression

```dart
List<List> orders = await $Order
    .query(callContext)
    .select(
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
    )
    .execute();
```

#### 5.2.2. $map - Simplified Conditional Mapping

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

#### 5.2.3. Expression Mapping with $mapExpr

```dart
final adjustedPrice = fields.priceCategory.$mapExpr({
  PriceCategory.retail: fields.basePrice * 1.2.toExpresssion(),
  PriceCategory.wholesale: fields.basePrice * 0.9.toExpresssion(),
  PriceCategory.vip: fields.basePrice * 0.8.toExpresssion(),
}, defaultValue: fields.basePrice);
```

### 5.3. Working with References

#### 5.3.1. Comparing References

```dart
// Compare FK with a Reference object
where: (fields) => fields.customer.$samePk(customerRef)

// Compare FK with a primary key value (if PK is String)
where: (fields) => fields.customer.$equal(customerId)

// Compare two reference fields
where: (fields) => fields.assignedTo.$sameReference(fields.createdBy)
```

#### 5.3.2. Navigating References

```dart
// Access fields of referenced entity
where: (fields) =>
  fields.customer.name.$contains('ACME') &
  fields.customer.address.country.$equal('FR')
```
Joins are automatically built.

#### 5.3.3. Updating References

**With setValue (when you have a Reference):**
```dart
await $Order.query(callContext).update.where(
  setter: (fields, setter) =>
    setter.setValue(fields.customer, newCustomerRef),
  where: (fields) => fields.uuid.$equal(orderId),
).execute();
```

**With setExpr (subquery):**
```dart
await $Order.query(callContext).update.where(
  setter: (fields, setter) => setter.setExpr(
    fields.assignedTo,
    $User.query(callContext).oneValue(
      what: (user) => user.uuid,
      where: (user) => user.name.$equal( "DOLL"),
    ),
  ),
  where: (fields) => fields.status.$equal(OrderStatus.pending),
).execute();
```

### 5.4. NULL Value Handling

#### 5.4.1. NULL Tests

```dart
// Orders without delivery date
where: (fields) => fields.deliveredAt.$isNull

// Orders with manager reference
where: (fields) => fields.manager.$isNotNull
```

#### 5.4.2. NULL Replacement (COALESCE)

**With a value:**
```dart
// Use 0 if discount is NULL
fields.discount.$ifNullThen(0.0)

// Calculate total with optional discount
setter.setExpr(
  fields.total,
  fields.subtotal - fields.discount.$ifNullThen(0.0)
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

#### 5.4.3. Nullity in Comparisons

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
$Order.query(callContext).load...

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
      // Load with locking
      final order = await $Order.query(callContext).load
        .thisKey(orderId)
        .exactlyOne();

      // Business validations
      // Note that typed AppError exceptions are sent to client applications
      if (order.status.value != OrderStatus.pending) {
        throw AppError("Only pending orders can be shipped");
      }

      final lineCount = await $OrderLine.query(callContext).load
        .where(where: (line) => line.order.$equal(orderId))
        .count();

      if (lineCount == 0) {
        throw AppError("Cannot ship an order without lines");
      }

      // Update
      order.status.value = OrderStatus.shipped;
      order.shippedAt.setToNow(callContext);

      await $Order.query(callContext).update
        .row(order.$dataRow)
        .execute();

      return $Order.query(callContext).load
        .thisRef(order.$asReference)
        .withExpectations(expect);
    });
  }
}
```

## 9. Summary and Cheat Sheet

### 9.1. Query Anatomy

```dart
await $Entity
  .query(callContext)              // Entry point
  .{operation}                     // load, insert, update, delete, upsert
  .{modifiers}                     // where, thisKey, row, etc.
  .{expected}                      // [fields, resolve, sort](DATA_CLASSES.md)
  .{execution}                     // listValues, execute, count, etc.
```

### 9.2. Main Operations

| Operation | Syntax                                    | Result                   |
| --------- | ----------------------------------------- | ------------------------ |
| LOAD      | `.load.where(...).listValues()`           | `List<DataRowValues<E>>` |
| INSERT    | `.insert.row(dataRow).exactlyOne()`       | `DataRowValues<E>`       |
| UPDATE    | `.update.row(dataRow).execute()`          | `void`                   |
| DELETE    | `.delete.thisKey(pk).execute()`           | `void`                   |
| UPSERT    | `.upsert.row(dataRow).exactlyOne()`       | `DataRowValues<E>`       |
| COUNT     | `.load.where(...).count()`                | `int`                    |
| EXISTS    | `$Entity.existsEntity(ctx)(where: ...)`   | `Predicate`              |
| SCALAR    | `$Entity.oneValue(ctx, what:..., where:)` | `ValueExpr<T>`           |

### 9.3. Expressions vs Values

| Context             | Type            | Example                        |
| ------------------- | --------------- | ------------------------------ |
| Field in WHERE      | `ValueExpr<T>`  | `fields.status`                |
| Comparison method   | `Predicate`     | `.$equal(OrderStatus.pending)` |
| Subquery            | `ValueExpr<T>`  | `$Order.oneValue(ctx, ...)`    |
| After `.getValue()` | `Future<T?>`    | `await expr.getValue()`        |
| DataRowValues field | `FieldValue<T>` | `order.status`                 |
| Field value         | `T`             | `order.status.value`           |

### 9.4. Important Prefixes and Suffixes

- **`$`**: Identifies framework methods/fields (avoids conflicts)
- **`Expr`**: Suffix for variants taking expressions (`$equalExpr`)
- **`toExpresssion()`**: Converts a Dart value to expression
- **`$cast<T>()`**: Forces expression type
- **`.getValue()`**: Executes an expression and returns the value

### 9.5. Security Checklist

- ✅ Use type-safe expressions (never raw SQL)
- ✅ Leverage generated methods (`exists...`, `oneValue`)
- ✅ Validate business logic in services
- ✅ Test after model modification (compiler detects errors)
- ✅ Use `.exactlyOne()` when a result is required
- ✅ Handle NULL values explicitly
- ✅ Document complex business rules

---

**To go further:**
- [DATA_CLASSES.md](DATA_CLASSES.md) - DataRowValues, DataLoader, DataRow
- [SERVICES.md](SERVICES.md) - Define and implement services
- [ACCESS_TOKEN.md](ACCESS_TOKEN.md) - Data access control
- [CONCEPTS_RELATIONSHIPS.md](CONCEPTS_RELATIONSHIPS.md) - Entity relationships
