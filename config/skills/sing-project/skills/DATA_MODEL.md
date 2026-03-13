# Building the Data Model

The data model is defined by:
- Namespace definitions
- Entity definitions

From these definitions, the Sing code generation process (sing_builder) produces code that can be used:
- In specific service implementations
- In server applications
- In client applications

To launch the build, use the command `dart run model/build/sing_build.dart`.

## 1. Define a Namespace

1. Choose a name for the namespace (e.g., `Orders`). [See naming conventions](PROJECT_STRUCTURE.md) to determine a functional name and rules to follow.
2. Determine the parent namespace. Use the root namespace if not specified.
3. In the parent namespace directory, add a subdirectory with the chosen name (e.g., `orders`, snake_case).
4. In the newly created directory, create a Dart file with the chosen name (e.g., `orders.dart`, snake_case).
5. Add code:
```dart
import 'package:sing_model/sing_model.dart';

class OrdersNameSpace extends ModelNameSpace {}
```
6. Modify the class defining the parent namespace:
```dart
final orders = Orders();
```
7. In the definition file of the parent namespace class, add:
```dart
import 'orders/orders.dart';
export 'orders/orders.dart';   // Chaining exports
```

**Important**: Do not confuse the namespace (e.g., `Orders`) with the namespace definition (e.g., `OrdersNameSpace`).

**Next step**: Define sub-namespaces or entities in this namespace.

## 2. Add an Entity to the Model

1. Choose a name for the entity (e.g., `Order`). [See naming conventions](PROJECT_STRUCTURE.md) to determine a functional name and rules to follow.
2. Determine the parent namespace. Use the root namespace if not specified.
3. In the parent namespace directory, add a file with the chosen name (e.g., `order.dart`, snake_case).
4. Add code:
```dart
import 'package:sing_model/sing_model.dart';

class OrderEntity extends ModelEntity {}
```
5. Modify the class defining the parent namespace:
```dart
final orders = Order();  // Note: the field name uses the plural form of the entity name
```
6. In the definition file of the parent namespace class, add:
```dart
import 'order.dart';
export 'order.dart';   // Chaining exports
```

**Next step**: Define decorators to add to the entity definition and the entity fields.

**Important**: Do not confuse the **entity** (e.g., `Order`) with the entity definition (e.g., `OrderEntity`). The entity is used in service code and applications. The entity definition is only used by `sing_builder` to generate the necessary code.

## 3. Entity Decorators

Decorators control code generation and behavior:

### 3.1. CRUD Services

**WARNING**: To benefit from the standard CRUD services implementation, an entity must be **referenceable**, i.e., define a primary key composed of a single field.

#### 3.1.1. @StdEntityServices()
Generates all standard CRUD services. Parameters of the `StdEntityServices()` constructor allow fine-grained control.
```dart
@StdEntityServices( delete:false)
class OrderEntity extends ModelEntity {
    // Generates: load, insert, update, upsert and delete services
}
```

#### 3.1.2. @LoadServices()
Simpler alternative to @StdEntityServices for read-only:
```dart
@LoadServices()
class ProductEntity extends ModelEntity {
  // Generates: loadThisKey(primaryKey), loadThoseKeys([primaryKey1, primaryKey2, ...]),
  // loadThisRef(reference), loadThoseRefs([reference1, reference2, ...])
}
```

#### 3.1.3. @InsertServices()
Adds `insertThis(row)`, `insertThose([rows])` to the entity services.

#### 3.1.4. @UpdateServices()
Adds `updateThis(row)`, `updateThose([rows])` to the entity services.

#### 3.1.5. @UpsertServices()
Adds `upsertThis(row)`, `upsertThose([rows])` to the entity services (update if exists, insert otherwise).

#### 3.1.6. @DeleteServices()
Adds `deleteThisKey(primary key value)`, `deleteThoseKeys([primary key values])`, `deleteThisRef(reference)`, `deleteThoseRefs([references])` to the entity services.

### 3.2. @Searchable()
Generates search/filter capabilities:
```dart
@Searchable()
class OrderEntity extends ModelEntity {
  // Generates: Order$Search filter class and $Order.services(...).search service
}
```

Result: `Order$Search` class defined with optional fields for all entity fields (unless optedout in field definition with `@AutoSearch.no` decorator). This class can be used in the auto-generated `search` service.

### 3.3. @Implementor(SomeServiceMixin)
Includes custom service in the entity's services:
```dart
@Implementor(OrderServices)
class OrderEntity extends ModelEntity {
  // Custom OrderServices mixin will be included in Order$Services
}
```

[Details on service implementation](SERVICES.md)

### 3.4. @AccessToken.authenticated
Require authentication for all operations:
```dart
@StdEntityServices()
@AccessToken.authenticated
class OrderEntity extends ModelEntity {
  // Only authenticated users can CRUD this entity
}
```
Alternative for specific fields:
```dart
class OrderEntity extends ModelEntity {
  @AccessToken.authenticated
  final sensitiveInfo = StringField();
}
```

[Details on access control](ACCESS_TOKEN.md)

### 3.5. @DbName(...)
Allows you to specify the entity's storage table name
```dart
@DbName("app_users")
class UserEntity extends ModelEntity {
}
```

Effect: `User` data rows will be stored in a database table named `app_users`. Without this decorator, they will be stored in the `user` table (or `user_`, depending on the database engine).

This decorator can also be used on a namespace definition class (to create a schema in the database) or on a field in an entity definition (to force the column name).

### 3.6. @serverSideOnly
Entity is not defined nor visible on client applications.
```dart
@StdEntityServices()
@serverSideOnly
class GrantEntity extends ModelEntity {
  // Only server application can see or use this entity
}
```

Alternative for specific fields:
```dart
class UserLoginEntity extends ModelEntity {
  @serverSideOnly
  final password = StringField(maxLength: 1024).nullable();
}
```

Effects:
  - Field `password` does not exist on client applications.
  - Field `password` is never serialized in JSON data.

### 3.7. @Migrations()
Links a migration class to manage schema evolution for this entity.
```dart
@StdEntityServices()
@Migrations(OrderMigrations)
class OrderEntity extends ModelEntity {
  // OrderMigrations class will handle schema changes for this entity
}
```

See [Migrations](MIGRATIONS.md) for complete documentation on schema evolution and migration strategies.

## 4. Entity Example: Order Entity

```dart
// model/lib/model/orders/order.dart
import 'package:sing_model/sing_model.dart';
import 'package:common/enums.dart';
import '../product/product.dart';

@StdEntityServices()
@Searchable()
@Implementor(OrderServices)
@Documentation(lib: "Customer order with line items")
class OrderEntity extends ModelEntity with UuidPrimaryKeyMixin {

  // Immutable order details
  final orderNumber = StringField(
    maxLength: 20,
    immutable: true,
  ).withLib("Order number");

  final orderDate = DateTimeField.utc().immutable();

  // Customer information
  final customerName = StringField(maxLength: 100)
    .withLib("Customer name");
  final customerEmail = StringField(maxLength: 100)
    .withLib("Customer email");
  final customerPhone = StringField(maxLength: 20).nullable()
    .withLib("Customer phone");

  // Addresses
  final shippingAddress = StringField(maxLength: 500)
    .withLib("Shipping address");
  final billingAddress = StringField(maxLength: 500).nullable()
    .withLib("Billing address");

  // Shipping and payment
  final shippingMethod = EnumStringField<ShippingMethod>()
    .withLib("Shipping method");
  final paymentMethod = EnumStringField<PaymentMethod>()
    .withLib("Payment method");

  // Financial
  final subtotal = DoubleField().withLib("Subtotal");
  final taxRate = DoubleField().withLib("Tax rate (%)");
  final taxAmount = DoubleField().withLib("Tax amount");
  final shippingCost = DoubleField().withLib("Shipping cost");
  final totalAmount = DoubleField().withLib("Total amount");

  // Status and tracking
  final status = EnumStringField<OrderStatus>(
    defaultValue: OrderStatus.pending,
  ).withLib("Order status");

  final paidAt = DateTimeField.utc().nullable()
    .withLib("Payment date");
  final shippedAt = DateTimeField.utc().nullable()
    .withLib("Shipment date");
  final deliveredAt = DateTimeField.utc().nullable()
    .withLib("Delivery date");

  // Define indices
  @override
  Iterable<ModelIndex> get indices => [
    ModelIndex([orderNumber], unique: true),
    ModelIndex([customerEmail]),
    ModelIndex([status]),
  ];
}
```

## 5. Common Patterns and Anti-Patterns

### ✅ Good: Meaningful Field Names
```dart
final customerEmail = StringField();  // Clear intent
final price = DoubleField();           // Self-documenting
final isActive = BoolField();          // Clear boolean
```

### ❌ Bad: Unclear or Generic Names
```dart
final data = StringField();            // What data?
final value = DoubleField();           // Which value?
final f1 = StringField();              // Single letter names
```

### ✅ Good: Use Enums for Status Fields
```dart
final status = EnumStringField<OrderStatus>();
```

### ❌ Bad: String-Based Status
```dart
final status = StringField();  // Allows "pneding", "PENDING", etc.
```

### ✅ Good: Use Reusable Mixins
```dart
class OrderEntity extends ModelEntity with UuidPrimaryKeyMixin, TimestampsMixin {
  // Consistent field names across entities
}
```

### ❌ Bad: Repeating Field Definitions
```dart
class OrderEntity extends ModelEntity {
  final uuid = UuidField();
  final createdAt = DateTimeField.utc().immutable();
  final updatedAt = DateTimeField.utc();
  // ... repeated in 20 entities
}
```

### ✅ Good: Immutable Audit Fields
```dart
final createdAt = DateTimeField.utc().immutable();
final createdBy = ReferenceTo<UserEntity>().immutable();
```

### ❌ Bad: Updatable Audit Fields
```dart
final createdAt = DateTimeField.utc();  // Can be changed!
```

### ✅ Good: Set Bounds on Numeric Fields
```dart
final quantity = IntField(lowBound: 1, highBound: 10000);
final price = DoubleField();  // Implicit bounds by validation
```

### ❌ Bad: Unbounded Fields
```dart
final age = IntField();  // Can be negative?
final discount = DoubleField();  // Can be >100%?
```

## 6. Defining Entity Fields

Entity fields are declared as fields of the entity definition class whose type is derived from `FieldDef` (defined in the `sing_core` package).

Sing provides typed field definitions that:
- Generate correct database columns
- Provide compile-time validation
- Enable type-safe queries

### Sing Fields Types

The field type constructors define numerous optional parameters allowing behavior specialization (min/max length for strings, bounds for numbers, ...).

Unless otherwise specified (`field.nullable()`), all fields defined in an entity do not accept `null` values.

#### String
```dart
final name = StringField(maxLength: 100);                 // NOT NULL constraint
final surname = StringField(maxLength: 100).nullable();   // Allow NULL value
```

#### Integer
```dart
final quantity = IntField();
```

Database: (u)int 8, 16, 32, 64. Depends on lowBound and highBound properties. Int64 if bounds are unknown.

#### Double / Decimal
```dart
final price = DoubleField();
final taxRate = DoubleField();
```

Database: `REAL` or `DECIMAL` or `FLOAT8` depending on database engine

#### Boolean
```dart
final isActive = BoolField();
```

Database: `BOOLEAN` for databases that support it, short integer otherwise (values false=0, true=1).

#### DateTime
```dart
// UTC timezone
final createdAt = DateTimeField.utc();

// Local timezone : stored "as this" with no timezone conversion (e.g., birth date, meeting date with well known site giving timezone)
final localTime = DateTimeField.local();

// Date without time : always "local" (no timezone conversion)
final scheduledAt = DateTimeField.dateOnly();
```

Database: `TIMESTAMP` or `TIMESTAMPTZ`

#### UUID
```dart
final id = UuidField();
```

Database: `VARCHAR(64)` allowing to store unique string key values (not auto allocated).

#### Enum
```dart
final status = EnumStringField<OrderStatus>();    // name of enum value is used as database value
final priority = EnumIntField<PriorityLevel>();   // index of enum value is used as database value
```

Database: `VARCHAR(...)` or `INTEGER`. 

Define enums as regular Dart enums:
```dart
enum OrderStatus {
  pending,
  processing,
  shipped,
  delivered,
  cancelled,
}
```

It is strongly recommended to define the enums used in the model's entity definitions in the project's `common` package (`common/lib/src/enums`) and to export (directly or indirectly) all enums in `common/lib/common.dart`.

#### Binary
```dart
final signature = BinaryField();
```

Database: `BLOB`

#### Memo
```dart
@AutoSearch.no                 // Do not allow searches on comment fields
final comments = MemoField();
```

Database: `CLOB`

#### Duration
```dart
final processingTime = DurationField(
  storeAs: StoreDuration.asMinutes,  // or asSeconds, asHours, asDays
);
```

#### References
Used to define links (or reference or foreign key) between entities. 
```dart
final order = ReferenceTo<OrderEntity>();
final product = ReferenceTo<ProductEntity>();
```
Generates:
- FK column in database
- Type-safe reference in Dart
- On delete rules ( `onDelete` parameter of `ReferenceTo`'s constructor)

See [Relationships](CONCEPTS_RELATIONSHIPS.md) for full details.


### Field Modifiers

#### Nullable
```dart
final phone = StringField().nullable();
final middleName = StringField().nullable();
```

#### Immutable
```dart
final createdAt = DateTimeField.utc().immutable();  // Typically immutable
```

Implications:
- Cannot be updated after insertion
- Useful for audit fields, natural keys

#### @SearchOnlyField
```dart
@SearchOnlyField
final toForeignCountry = BoolField().nullable; 
```

Implications:
- `toForeignCountry` **ne définit pas** de colonne dans la table
- uniquement utilisable dans [les recheches étendues].(SEARCHES.md)

#### Default Values
```dart
final isActive = BoolField(defaultValue: true);
final quantity = IntField(defaultValue: 0);
```

Effects:
- Database assigns on insert if not provided
- Client-side validation uses defaults

### Field Naming and SQL Mapping

By default, Sing maps field names to database columns:

```dart
final customerName → customer_name (in database)
final totalAmount → total_amount
final sku → sku
```
If a field is identified with a reserved database identifier (e.g., `where`), the column will be "escaped" (i.e., `where` becomes `where_`).

### Common Field Mixins

It is convenient to define mixins that define one or more common fields in the model.

For example, if many entities in the model use UuidField as primary key

```dart
mixin UuidPrimaryKeyMixin on ModelEntity {
  final uuid = UuidField(autoAllocate: true).primaryKey().immutable();
}
```

used as
```dart
class OrderEntity extends ModelEntity with UuidPrimaryKeyMixin {
}
```

Other examples :
```dart
mixin TimestampsMixin on ModelEntity {
  final createdAt = DateTimeField.utc().immutable();

  final updatedAt = DateTimeField.utc();
}

mixin CommentFieldMixin on ModelEntity {
  @AutoSearch.no  // comment field will not be in (possibly) auto generated search service
  final comment = StringField(maxLength: 1024).nullable();
}
```

