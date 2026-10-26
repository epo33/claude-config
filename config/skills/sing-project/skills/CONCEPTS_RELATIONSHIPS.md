# Relationships Between Entities

This document explains how to link entities with references (foreign keys), how to read and write a reference at runtime, and how to load the rows it points to.

Related documents: [field declarations](FIELD_TYPES.md#29-references), [searches through references](SEARCHES.md#5-searching-through-references), [reference predicates in queries](QUERY_EXPRESSIONS.md#8-references), [DataRow, DataPacket and FieldValue](DATA_CLASSES.md).

Sources: `sing_model/lib/src/reference.dart` (`ReferenceTo`), `sing_core/lib/src/std/field_def/reference.dart` (`ReferenceField`), `sing_core/lib/src/data_row/reference.dart` (`Reference`), `sing_core/lib/src/data_row/reference_value.dart` and `intfs.dart` (`FieldValueRef`), `sing_server/lib/src/entity.dart` (foreign keys and indexes of a table).

## 1. Declaring a Reference

### 1.1. `ReferenceTo<E>` in the Model

A reference is a field of type `ReferenceTo<XxxEntity>` in the model class. It points to one row of the target entity. From `example/model/lib/model/orders/order_line.dart`:

```dart
@LoadServices()
@Searchable()
class OrderLineEntity extends ModelEntity with UuidPrimaryKeyMixin {
  OrderLineEntity();

  final order = ReferenceTo<OrderEntity>(onDelete: .cascade);

  final product = ReferenceTo<ProductEntity>(onDelete: .error);

  final quantity = IntField(lowBound: 1);

  final lineIndex = IntField().immutable();

  final unitPrice = DoubleField();
}
```

Constructor parameters of `ReferenceTo<E>`:

| Parameter           | Default  | Effect                                                                                                         |
| ------------------- | -------- | -------------------------------------------------------------------------------------------------------------- |
| `onDelete`          | `.error` | `ON DELETE` rule of the foreign key (section 1.3).                                                             |
| `declareForeignKey` | `true`   | `false`: the column exists but no foreign key constraint is created.                                           |
| `autoIndex`         | `true`   | `false`: no automatic index on the column (section 1.2).                                                       |
| `deferred`          | `false`  | Stored in the model, but has no effect: every foreign key is created `DEFERRABLE INITIALLY DEFERRED`.          |
| `accessToken`       | none     | Token required to read the field.                                                                              |

Modifiers (each returns a new field): `.nullable()`, `.immutable()`, `.primaryKey()`, `.readOnly()`, `.withDbName("...")`, `.autoIndexed(false)`, and the generic `.withLib("...")`, `.withDescr("...")`, `.serverOnly()`.

`ReferenceTo<E>.ownKey()` is a special form (section 2.5).

**The target must have a single-field primary key.** A reference to an entity with a composite primary key fails with "Entity X define a composed primary key. It can't be referenced." An entity without primary key cannot be referenced either.

### 1.2. What the Database Gets

For `OrderLine.order`, the `order_line` table gets:

- a column `order`, of the type of the primary key of `Order` (a `uuid` column here), `NOT NULL` unless the field is `.nullable()`;
- a foreign key to the `order` table with the `ON DELETE` rule of `onDelete`. It is always `DEFERRABLE INITIALLY DEFERRED`: the check runs at commit, so the insert order of rows inside one transaction does not matter;
- an index on the column.

No foreign key is created when `declareForeignKey: false`, or when the target is a `@ViewEntity()`.

The automatic index is skipped when:

- `autoIndex: false`;
- the reference field is part of the primary key;
- an index declared in `getIndicies()` already starts with this column.

```dart
@override
Iterable<ModelIndex> getIndicies() => [
  // Unique: one line per product in an order.
  // This index starts with `order`: no extra index on `order`.
  // `product` still gets its automatic index.
  ModelIndex([order, product], unique: true),
];
```

The method name is `getIndicies()` (with this spelling), declared on `ModelEntity`.

### 1.3. Delete Rules

`onDelete` takes a `ReferentialAction` (`sing_core/lib/src/db/db_table.dart`):

| Value        | SQL           | Deleting the target row...                                    | Use for                                         |
| ------------ | ------------- | ------------------------------------------------------------- | ----------------------------------------------- |
| `.error`     | `RESTRICT`    | fails while a row points to it. Default value.                | Shared data: `OrderLine.product`, `Order.customer`. |
| `.cascade`   | `CASCADE`     | also deletes the rows that point to it.                       | Rows that only exist inside their parent: `OrderLine.order`. |
| `.setToNull` | `SET NULL`    | sets the reference to `NULL`.                                 | Optional links. The field **must** be `.nullable()`. |
| `.setDefault`| `SET DEFAULT` | sets the column default value.                                | Rare.                                           |

The builder does not check that a `.setToNull` reference is nullable. If it is not, the delete fails at runtime on the `NOT NULL` constraint.

Choose the rule from the meaning of the link: `cascade` on a reference to a shared entity (for example `OrderLine.product`) deletes data you want to keep.

### 1.4. What the Generated Code Gets

For `OrderLine.order` (target `Order`, primary key `String`):

| Generated member                                      | Type                                   | Use                                                         |
| ----------------------------------------------------- | -------------------------------------- | ----------------------------------------------------------- |
| `OrderLine$Instance.order` (on `DataRowValues`)       | `FieldValueRef<Order, String>`         | Read or write the reference of a row (section 3.2).          |
| `fields.order` in `fields`/`resolve`/`sort` builders  | `EntityFieldsChainView<Order>`         | Navigate: `fields.order.customer.name` (section 5).          |
| `fieldList.order` (`EntityFieldsList`)                | `ReferenceField<Order, String>`        | The field definition, a `ScalarField<Reference<Order>>`.     |
| `fields.order` in a query `where:`                    | `RefFieldExpr<Order, String>`          | `$pointToKey`, `$keyValue`... ([queries](QUERY_EXPRESSIONS.md#8-references)). |
| `Order$ReferenceExtension.primaryKey`                 | `String`                               | Typed key of a `Reference<Order>`.                           |
| `OrderLine$Search.order` / `refToOrder`               | `Order$Search` / `SearchOnField<String>` | Search on the target fields / on the key value.            |
| `Order$Search.whereOrderLineOrder`                    | `SearchOnForeignField<E, OrderLine>`   | Reverse criterion on the children (section 4.1).             |

## 2. Relationship Patterns

### 2.1. One-to-Many

The "many" side holds the reference. The "one" side has **no** collection field: there is no `Order.lines`. You reach the children with a search or a query (section 4).

```dart
class OrderLineEntity extends ModelEntity with UuidPrimaryKeyMixin {
  final order = ReferenceTo<OrderEntity>(onDelete: .cascade).immutable();
  final product = ReferenceTo<ProductEntity>(onDelete: .error);
  // ...
}
```

Make the parent reference `.immutable()` when a child never moves to another parent. An immutable field accepts one assignment; a second assignment with a different value throws.

### 2.2. Many-to-Many

Use an association entity with two references. Put the link attributes on it.

```dart
// Plausible OrderHub extension: products in categories.
@StdEntityServices()
@Searchable()
class ProductCategoryEntity extends ModelEntity with UuidPrimaryKeyMixin {
  ProductCategoryEntity();

  final product = ReferenceTo<ProductEntity>(onDelete: .cascade);

  final category = ReferenceTo<CategoryEntity>(onDelete: .cascade);

  final displayOrder = IntField();

  @override
  Iterable<ModelIndex> getIndicies() => [
    ModelIndex([product, category], unique: true),
  ];
}
```

Without the unique index, the same pair can be stored twice.

Alternative: make the two references the composite primary key (`.primaryKey()` on both, no `UuidPrimaryKeyMixin`). The association then has no extra index to declare, but **it cannot be the target of a reference** (composite key).

Reading the categories of a product, client side:

```dart
final links = await $ProductCategory
    .services(dataRegistry)
    .search(refToProduct: Search.equal(productUuid))
    .resolve((fields) => [fields.category])
    .listValues();
final categoryNames = [
  for (final link in links) link.category.dataRowValues.name.value,
];
```

### 2.3. Self-Reference (Hierarchy)

A reference to the entity itself is usually `.nullable()`: a root row has no parent.

```dart
// Plausible OrderHub extension.
class CategoryEntity extends ModelEntity with UuidPrimaryKeyMixin {
  final name = StringField(maxLength: 100);

  final parent = ReferenceTo<CategoryEntity>(onDelete: .setToNull).nullable();
}
```

Direct children: `search(refToParent: Search.equal(categoryUuid))`. Roots: `search(refToParent: Search.isNull())`. For a whole subtree, do not loop over client calls: write a server service with a recursive CTE (`RecursiveCteSource`, see [queries](QUERIES.md)).

### 2.4. Mutual References

Entity A may reference B while B references A. Foreign keys are checked at commit, so both rows can be inserted in the same transaction in any order. At least one side should be `.nullable()` so that a row can exist before its partner.

### 2.5. Reference as Primary Key (One-to-One)

A reference marked `.primaryKey()` makes the row an extension of its target: at most one row per target.

```dart
// Plausible OrderHub extension: one preference row per customer.
@StdEntityServices()
@Searchable()
class CustomerPreferencesEntity extends ModelEntity {
  final customer = ReferenceTo<CustomerEntity>(onDelete: .cascade).primaryKey();

  final newsletter = BoolField();
}
```

The primary key value is then itself a `Reference<Customer>`. Another entity can reference `CustomerPreferences`; its `refTo` search parameter is then typed `SearchOnField<Reference<Customer>>` (see [searches](SEARCHES.md)).

### 2.6. Own-Key Reference: `ReferenceTo<E>.ownKey()`

An own-key reference points to the row of `E` whose primary key **equals the primary key of the current row**. It has no column and no foreign key. Typical use: a computed `@ViewEntity()` keyed by the same uuid. From `example/model/lib/model/orders/order.dart`:

```dart
// In OrderEntity: OrderSummary is a view keyed by the order uuid.
final summary = ReferenceTo<OrderSummaryEntity>.ownKey();
```

At runtime:

- `order.summary.primaryKey` is `order.uuid.value`;
- assigning it throws a `StateError`;
- it is not sent in JSON and not stored;
- it is resolved like any reference: `.resolve((fields) => [fields.summary])` then `order.summary.dataRowValues.lineCount.value`.

See [VIEW_ENTITIES.md](VIEW_ENTITIES.md) for the view side.

## 3. References at Runtime

### 3.1. `Reference<E>`

`Reference<E>` (`sing_core/lib/src/data_row/reference.dart`) identifies one row of `E`:

| Member                 | Meaning                                                                    |
| ---------------------- | -------------------------------------------------------------------------- |
| `entity`               | The `EntityDef` of the target.                                             |
| `pkValue`              | The primary key value, `dynamic`. `null` for a null reference.             |
| `primaryKey`           | Generated extension (`Customer$ReferenceExtension`): typed `pkValue`.      |
| `isNull`               | `pkValue == null`.                                                         |
| `toJson()` / `Reference.fromJson(dataRegistry, json)` | Wire form: `{"$entity": ..., "primaryKey": ...}`. |

Getting a reference:

```dart
// From a key
final ref = $Customer.of(dataRegistry).reference(primaryKey: customerUuid);

// From a row
final ref = customer.$asReference;        // DataRowValues<Customer>
final ref = customerRow.asReference;      // DataRow<Customer>

// From a reference field
final ref = order.customer.value;         // Reference<Customer>
```

Two references are equal when they target the same root entity (ancestors included) and hold the same key. A reference built from a row that has no key yet carries a correlation uuid instead of a key; it is equal only to itself.

### 3.2. Reading and Writing a Reference Field

`order.customer` is a `FieldValueRef<Customer, String>`, a `FieldValue<Reference<Customer>>` with extra members:

```dart
// Read
final customerUuid = order.customer.primaryKey;      // String?
final customerRef = order.customer.value;           // Reference<Customer>
final noAddress = order.shippingAddress.isNull;     // true when no target

// Write: the most common form
line.order.primaryKey = order.uuid.value;

// Write: from a reference or a row
order.customer.value = customer.$asReference;
order.shippingAddress.primaryKey = null;            // nullable reference only
```

Writing marks the field as updated, like any field (see [DATA_CLASSES.md](DATA_CLASSES.md)).

The example service `OrderServices.addOrder` (`example/model/lib/model/orders/order.services.dart`) uses this to attach lines to a new order before inserting them:

```dart
order = await $Order.query(callContext).insertRow(order.$dataRow).exactlyOne();
for (final line in orderLines) {
  line.order.primaryKey = order.uuid.value;
}
await $OrderLine.query(callContext)
    .insertRows(orderLines.map((line) => line.$dataRow))
    .execute();
```

With `UuidField(autoAllocate: true)`, the uuid exists as soon as the row is created. You can link children to a parent before inserting the parent.

### 3.3. Loading the Referenced Row: `resolve`

A reference field holds only the key. To read fields of the target, ask the `DataLoader` to **resolve** the reference. The target rows come in the same `DataPacket`, in the same call.

```dart
final orders = await $Order
    .services(dataRegistry)
    .search(status: Search.equal(OrderStatus.pending))
    .resolve((fields) => [
      fields.customer,              // loads the customer
      fields.customer.address,      // and the customer's address
    ])
    .listValues();

for (final order in orders) {
  final customer = order.customer.dataRowValues;    // DataRowValues<Customer>
  final city = customer.address.dataRowValues.city.value;
}
```

Members of `FieldValueRef` for resolved rows:

| Member                        | Behavior                                                                                       |
| ----------------------------- | ---------------------------------------------------------------------------------------------- |
| `hasDataRow`                  | `true` when the target row is in the packet.                                                   |
| `dataRowValues` / `dataRow`   | The target row. **Throws** `"Field 'x' has not been resolved."` when `hasDataRow` is false.    |
| `isMasked`                    | `true` when the server did not load the target on purpose (see below).                         |
| `setDataRow(row)` / `setDataValues(values)` | Points the reference to `row` and adds `row` to the packet. Throws when the current row is not in a `DataPacket` (a row from `createDataRow()` is not). |

Rules:

- A null reference has no row: test `isNull` before `dataRowValues` on a nullable reference.
- A chain in `fields(...)` or `sort(...)` resolves its references automatically: `.fields((f) => [f.orderNumber, f.customer.name])` loads the customer with only its `name` (and its key).
- Resolution is also available in server queries: `$Order.query(callContext).load(...).resolve(...)`.

**Masked references.** The server does not resolve a reference when the current account lacks the read token of the target entity, or when a mixin filter of the target excludes the row. The reference keeps its key, `hasDataRow` is false and `isMasked` is true. UI code should show "not available" for a masked reference, not an error.

### 3.4. Loading a Target Later

When the reference was not resolved, load the target by its key or reference:

```dart
// Client
final customer = await $Customer
    .services(dataRegistry)
    .loadThisRef(ref: order.customer.value)
    .exactlyOne();

// Server
final customer = await $Customer
    .query(callContext)
    .loadKey(order.customer.primaryKey!)
    .exactlyOne();
```

To add targets to an existing packet on the server, use `$Customer.query(callContext).resolveReferences(dataPacket, references, Expect())`: it loads only the rows the packet does not hold yet, and marks the excluded ones as masked.

## 4. Finding Children (Reverse Lookups)

### 4.1. With Searches (Client or Server)

Full details: [searches through references](SEARCHES.md#5-searching-through-references).

```dart
// Lines of one order: criterion on the key value
final lines = await $OrderLine
    .services(dataRegistry)
    .search(refToOrder: Search.equal(orderUuid))
    .listValues();

// Lines of pending orders: criterion on the fields of the target
final lines = await $OrderLine
    .services(dataRegistry)
    .search(order: Order$Search(status: Search.equal(OrderStatus.pending)))
    .listValues();

// Orders with at least one line of more than 5 units: reverse criterion
final orders = await $Order
    .services(dataRegistry)
    .search(
      whereOrderLineOrder: $Order.whereOrderLineOrder(
        OrderLine$Search(quantity: SearchOnInt(value: 5, type: .greaterThan)),
      ),
    )
    .listValues();
```

`$Order.whereOrderLineOrder(filters)` is a generated helper that builds the `SearchOnForeignField(fieldName: "order", filters: ...)`. Pass `none: true` to `SearchOnForeignField` to keep the orders that **no** matching line points to.

A reverse criterion `where<Entity><Field>` is generated on the target for each reference of a `@Searchable()` entity. Annotate the reference with `@NoReverseSearch()` to skip it.

### 4.2. With Queries (Server)

```dart
final lines = await $OrderLine
    .query(callContext)
    .load(where: (fields) => fields.order.$pointToKey(orderUuid))
    .listValues();
```

Compare a reference with `$pointToKey(key)`, `$pointToReference(ref)`, `$pointToRow(row)`, `$pointToValues(values)` or `$pointToFieldValue(fieldValue)`. Read the stored key with `$keyValue`. Details: [reference operations](QUERY_EXPRESSIONS.md#8-references).

## 5. Navigating Through References

A builder parameter (`fields`) exposes each reference as an `EntityFieldsChainView<Target>`. You can chain fields across references in every builder:

| Builder                  | Example                                            | Effect                                               |
| ------------------------ | -------------------------------------------------- | ---------------------------------------------------- |
| query `where:`           | `fields.customer.address.country.$equal("FR")`     | The server adds the joins.                           |
| `fields(...)`            | `[fields.orderNumber, fields.customer.name]`       | Reads only these fields; resolves `customer`.        |
| `resolve(...)`           | `[fields.customer.address]`                        | Resolves `customer`, then its `address`.             |
| `sort(...)`              | `[fields.customer.name, -fields.orderDate]`        | Sorts on the target field; resolves `customer`.      |
| search                   | `customer: Customer$Search(name: ...)`             | Criterion on the target fields.                      |

On a row, follow resolved references explicitly: `order.customer.dataRowValues.address.dataRowValues.city.value`.

## 6. Checklist

- Every `ReferenceTo` targets an entity with a single-field primary key.
- `onDelete` matches the meaning: `cascade` for owned children, `error` for shared data, `setToNull` only on a `.nullable()` field.
- Association entities have a unique index on their pair of references (or a composite primary key).
- Parent references that never change are `.immutable()`.
- Code that reads `xxx.dataRowValues` requests the reference in `resolve(...)` (or in a `fields(...)` chain) and handles `isNull` and `isMasked`.
- New rows get their references with `primaryKey = ...` or `value = ...`; `setDataRow` only works on rows held in a `DataPacket`.
