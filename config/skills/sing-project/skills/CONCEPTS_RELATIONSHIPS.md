# Relationships Between Entities

This document explains how to model relationships (one-to-many, many-to-many, and reverse lookups) in Sing.

## 1. Relationship Types in Sing

Sing supports three relationship patterns:

| Pattern                | Implementation       | Use Case           |
| ---------------------- | -------------------- | ------------------ |
| **One-to-Many (1:N)**  | FK from "many" side  | Order → OrderLines |
| **Many-to-Many (N:N)** | Association entity   | Product ↔ Category |
| **Hierarchical**       | FK to self or parent | Employee → Manager |

## 2. One-to-Many Relationships (1:N)

The most common pattern in Sing.

### 2.1. Basic Pattern

**Parent Entity** (has many):
```dart
class OrderEntity extends ModelEntity with UuidPrimaryKeyMixin {
  final customerName = StringField(maxLength: 100);
  final totalAmount = DoubleField();
}
```

**Child Entity** (belongs to one parent):
```dart
class OrderLineEntity extends ModelEntity with UuidPrimaryKeyMixin {
  // Foreign Key to parent Order
  final order = ReferenceTo<OrderEntity>();

  // Other fields
  final product = ReferenceTo<ProductEntity>();
  final quantity = IntField(lowBound: 1);
  final linePrice = DoubleField();
}
```

**Result**:
- `order` field generates FK column in database (unless `declareForeignKey:false` in constructor call)
- `order` column in `order_line` table is automatically indexed (unless `autoIndex:false` in constructor call)
- `OrderLine` always has a parent `Order`
- Type-safe reference: `orderLine.order.value` returns `String` (UUID)
- Error raised if parent record is deleted (unless `onDelete` is specified in constructor call)

### 2.2. Cascade Rules

Control what happens when the parent is deleted:

#### 2.2.1. Cascade Delete
```dart
final order = ReferenceTo<OrderEntity>( onDelete: OnDeleteRule.cascade);
```

Behavior:
- Deleting an Order automatically deletes all OrderLines
- Database enforces via FK constraint
- Useful for: Child entities that don't exist independently

**When to use**: OrderLine (can't exist without Order)

#### 2.2.2. Error on Delete
```dart
final product = ReferenceTo<ProductEntity>(
  onDelete: OnDeleteRule.error,  // Default value
);
```

Behavior:
- Deleting a Product fails if any OrderLine references it
- Prevents orphaned references
- Useful for: Entities that should be preserved

**When to use**: Product (should not be deleted if ordered)

#### 2.2.3. Set Null on Delete (Soft Delete)
```dart
final promotion = ReferenceTo<PromotionEntity>(
  onDelete: OnDeleteRule.setNull,
);
```

Behavior:
- Deleting a Promotion sets FK to NULL in referencing records
- Useful for: Optional relationships that can be orphaned
- Requires field to be `.nullable()`

**When to use**: Optional related entities

### 2.3. Complete Example: Order with Line Items

```dart
// model/lib/model/orders/order.dart
@StdEntityServices()
@Searchable()
@Implementor(OrderServices)
class OrderEntity extends ModelEntity with UuidPrimaryKeyMixin {
  final customerName = StringField(maxLength: 100);
  final orderDate = DateTimeField.utc().immutable();
  final totalAmount = DoubleField();
  final status = EnumStringField<OrderStatus>();
}

// model/lib/model/orders/order_line.dart
@StdEntityServices()
@Searchable()
class OrderLineEntity extends ModelEntity with UuidPrimaryKeyMixin {
  // FK to Order - cascade delete if order deleted
  final order = ReferenceTo<OrderEntity>(
    onDelete: OnDeleteRule.cascade,
  ).withLib("Parent order");

  // FK to Product - error if product deleted
  final product = ReferenceTo<ProductEntity>(
    onDelete: OnDeleteRule.error,
  ).withLib("Product ordered");

  // Line details
  final quantity = IntField(lowBound: 1);
  final unitPrice = DoubleField();
  final lineTotal = DoubleField();

  // Optional discount
  final discountApplied = ReferenceTo<PromotionEntity>(
    onDelete: OnDeleteRule.setNull,
  ).nullable().withLib("Discount applied");

  // Ensure valid references
  @override
  Iterable<ModelIndex> get indices => [
    ModelIndex([order, product], unique: true),  // One line per product per order (Sing dont add an another index on order column but index product column)
  ];
}
```

## 3. Many-to-Many Relationships (N:N)

Use an **association entity** to connect two entities with optional attributes.

### 3.1. Pattern: Product ↔ Category

**Scenario**: Products can have multiple Categories, Categories contain multiple Products.

**Option 1: Simple Association (No Extra Attributes)**

```dart
// model/lib/model/categories/product_category.dart
class ProductCategoryEntity extends ModelEntity with UuidPrimaryKeyMixin {
  // Foreign keys
  final product = ReferenceTo<ProductEntity>(
    onDelete: OnDeleteRule.cascade,
  ).primaryKey();

  final category = ReferenceTo<CategoryEntity>(
    onDelete: OnDeleteRule.cascade,
  ).primaryKey();

}
```

**Accessing the relationship**:
```dart
// Get all categories for a product in a client application
final productCategories = await $ProductCategory.services(dataRegistry)
    .search( refProduct: Search.equal(productUuid) )
    .resolve( (fields) =>[ fields.category])
    .listValues();

// Get category names
final categoryNames = productCategories
    .map((pc) => pc.category.dataValues.name)
    .toList();
```

### 3.2. Option 2: Association with Attributes

**Scenario**: Product ↔ Warehouse with quantity in stock.

```dart
// model/lib/model/inventory/product_warehouse.dart
@StdEntityServices()
@Searchable()
class ProductWarehouseEntity extends ModelEntity with UuidPrimaryKeyMixin {
  // Foreign keys
  final product = ReferenceTo<ProductEntity>(
    onDelete: OnDeleteRule.cascade,
  );

  final warehouse = ReferenceTo<WarehouseEntity>(
    onDelete: OnDeleteRule.cascade,
  );

  // Association attributes
  final quantityInStock = IntField(lowBound: 0);
  final lastStockCheckDate = DateTimeField.utc().nullable();
  final minStockLevel = IntField(lowBound: 0);
  final maxStockLevel = IntField(lowBound: 0);
  final location = StringField(maxLength: 50).nullable();

  // Constraints
  @override
  Iterable<ModelIndex> get indices => [
    ModelIndex([product, warehouse], unique: true),
    ModelIndex([warehouse]),  // Find all products in warehouse
  ];
}
```

## 4. Reverse Lookups (Finding Children)

By default, child entities have FK to parent. How do you query the parent's children?

### 4.1. Reverse Relationship Pattern

#### 4.1.1. Problem
```dart
// Child entity has: final order = ReferenceTo<OrderEntity>();
// But Order entity has no link back to OrderLines!

// How to find all OrderLines for an Order?
```

#### 4.1.2. Solution: SearchOnForeignField

Sing generates helper methods for reverse lookups:

```dart
// In $Order class (generated):
static SearchOnForeignField<Order, OrderLine>
whereOrderLineOrder(OrderLine$Search filters) =>
    SearchOnForeignField<Order, OrderLine>(
      fieldName: r'order',
      filters: filters,
    );
```

**Usage**: Find Order's children
```dart
// Get all lines for an order
final lines = await $OrderLine.services(registry)
    .search(
      where: (f) => f.order.$equal(orderId),
    )
    .toList();

// Or with additional filters
final lines = await $OrderLine.services(registry)
    .loadSearch(
      where: (f) => f.order.$equal(orderId)
          .$and(f.quantity.$gt(5)),
    )
    .toList();
```

### 4.2. Hierarchical Relationships (Self-References)

**Scenario**: Employee → Manager (Manager is also an Employee)

```dart
// model/lib/model/employees/employee.dart
@StdEntityServices()
@Searchable()
class EmployeeEntity extends ModelEntity with UuidPrimaryKeyMixin {
  final name = StringField(maxLength: 100);
  final email = StringField(maxLength: 100);

  // Manager is optional (CEO has no manager)
  final manager = ReferenceTo<EmployeeEntity>(
    onDelete: OnDeleteRule.setNull,
  ).nullable().withLib("Direct manager");

  // Department (non-hierarchical)
  final department = ReferenceTo<DepartmentEntity>(
    onDelete: OnDeleteRule.error,
  );
}
```

**Finding direct reports**:
```dart
// All employees reporting to managerId
final directReports = await $Employee.services(registry)
    .loadSearch(
      where: (f) => f.manager.$equal(managerId),
    )
    .toList();

// All employees in manager's chain
Future<List<Employee>> getSubordinates(String managerId) async {
  final direct = await $Employee.services(registry)
      .loadSearch(
        where: (f) => f.manager.$equal(managerId),
      )
      .toList();

  final subordinates = <Employee>[...direct];
  for (final emp in direct) {
    subordinates.addAll(
      await getSubordinates(emp.uuid.value),
    );
  }
  return subordinates;
}
```

## 5. Circular References and Avoiding Deadlocks

**Problem**: Entity A references B, Entity B references A.

```dart
// BAD: Creates circular dependency
class PersonEntity extends ModelEntity {
  final spouse = ReferenceTo<PersonEntity>().nullable();
  final children = ReferenceTo<PersonEntity>().nullable();  // ❌
}
```

**Solution**: Use association entity for true N:N

```dart
// GOOD: Clear association entity
@StdEntityServices()
class PersonFamilyRelationEntity extends ModelEntity with UuidPrimaryKeyMixin {
  final person1 = ReferenceTo<PersonEntity>(onDelete: OnDeleteRule.cascade);
  final person2 = ReferenceTo<PersonEntity>(onDelete: OnDeleteRule.cascade);
  final relationType = EnumStringField<FamilyRelationType>();

  @override
  Iterable<ModelIndex> get indices => [
    ModelIndex([person1, person2], unique: true),
    ModelIndex([person2, person1], unique: true),  // Both directions
  ];
}

enum FamilyRelationType {
  spouse,
  child,
  parent,
  sibling,
}
```

**Query**:
```dart
// Find all family relations for a person
final relations = await $PersonFamilyRelation.services(registry)
    .loadSearch(
      where: (f) => f.person1.$equal(personId)
          .$or(f.person2.$equal(personId)),
    )
    .toList();
```

## 6. Best Practices

### 6.1. ✅ Good: Clear FK Semantics

```dart
class OrderLineEntity extends ModelEntity {
  // Clear that this line belongs to exactly one order
  final order = ReferenceTo<OrderEntity>(
    onDelete: OnDeleteRule.cascade,
  );

  // Clear that product is external reference
  final product = ReferenceTo<ProductEntity>(
    onDelete: OnDeleteRule.error,
  );
}
```

### 6.2. ❌ Bad: Ambiguous References

```dart
class OrderLineEntity extends ModelEntity {
  final ref1 = ReferenceTo<EntityA>();  // What is this?
  final ref2 = ReferenceTo<EntityB>();  // Unclear purpose
}
```

### 6.3. ✅ Good: Unique Constraints on Association Entities

```dart
class ProductCategoryEntity extends ModelEntity {
  final product = ReferenceTo<ProductEntity>();
  final category = ReferenceTo<CategoryEntity>();

  @override
  Iterable<ModelIndex> get indices => [
    ModelIndex([product, category], unique: true),  // One per pair
  ];
}
```

### 6.4. ❌ Bad: Duplicate Associations

```dart
// Without unique constraint, same product-category could appear multiple times
class ProductCategoryEntity extends ModelEntity {
  final product = ReferenceTo<ProductEntity>();
  final category = ReferenceTo<CategoryEntity>();
  // No unique constraint!
}
```

### 6.5. ✅ Good: Immutable FKs

```dart
class OrderLineEntity extends ModelEntity {
  // These should never change
  final order = ReferenceTo<OrderEntity>(immutable: true);
  final product = ReferenceTo<ProductEntity>(immutable: true);
}
```

### 6.6. ❌ Bad: Mutable FKs

```dart
final order = ReferenceTo<OrderEntity>();  // Can be changed!
```

### 6.7. ✅ Good: Proper Cascade Rules

```dart
// Child-only entities: cascade
final order = ReferenceTo<OrderEntity>(onDelete: OnDeleteRule.cascade);

// Shared entities: error
final product = ReferenceTo<ProductEntity>(onDelete: OnDeleteRule.error);

// Optional references: setNull
final promotion = ReferenceTo<PromotionEntity>(onDelete: OnDeleteRule.setNull);
```

### 6.8. ❌ Bad: Wrong Cascade Rules

```dart
// CASCADE when product should be protected
final product = ReferenceTo<ProductEntity>(
  onDelete: OnDeleteRule.cascade,  // ❌ Oops! Deletes product
);
```

## 7. Example: Complete E-commerce Model

```dart
// Orders with items
@StdEntityServices()
class OrderEntity extends ModelEntity with UuidPrimaryKeyMixin {
  final customerName = StringField(maxLength: 100);
  final orderDate = DateTimeField.utc().immutable();
  final status = EnumStringField<OrderStatus>();
}

@StdEntityServices()
class OrderLineEntity extends ModelEntity with UuidPrimaryKeyMixin {
  final order = ReferenceTo<OrderEntity>(onDelete: OnDeleteRule.cascade);
  final product = ReferenceTo<ProductEntity>(onDelete: OnDeleteRule.error);
  final quantity = IntField(lowBound: 1);

  @override
  Iterable<ModelIndex> get indices => [
    ModelIndex([order, product], unique: true),
  ];
}

// Products in categories
@StdEntityServices()
class ProductEntity extends ModelEntity with UuidPrimaryKeyMixin {
  final name = StringField(maxLength: 100);
  final price = DoubleField();
}

@StdEntityServices()
class CategoryEntity extends ModelEntity with UuidPrimaryKeyMixin {
  final name = StringField(maxLength: 50);
}

@StdEntityServices()
class ProductCategoryEntity extends ModelEntity with UuidPrimaryKeyMixin {
  final product = ReferenceTo<ProductEntity>(onDelete: OnDeleteRule.cascade);
  final category = ReferenceTo<CategoryEntity>(onDelete: OnDeleteRule.cascade);

  @override
  Iterable<ModelIndex> get indices => [
    ModelIndex([product, category], unique: true),
  ];
}
```

