# Project Structure & Naming Conventions

This document explains the directory and file organization conventions for Sing projects, helping LLM agents navigate and understand the codebase structure. In all examples, {project_key} is a short string associated to the project used as prefix in names.

## 1. Overview

A Sing project follows a multi-package structure where the **model** is the source of truth, and generated code is organized systematically:

```
project_root/
├── model/                           # Model definitions (developer-written),
│   ├── lib/                         # Library code
│   │   ├── model/                   # Model definitions (developer-written)
│   │   │   └── model.dart           # Main export file. MUST export `../sing/sing.dart`
│   │   └── sing/                    # Auto-generated server code (DO NOT CHANGE)
├── common/                          # Shared code and types (developer + generated), 
├── {project}_sing_client/           # Client SDK (auto-generated). 
|
|                   # Developper code
|
├── {project}_server/                # Server implementation (developer + HTTP handlers). Dart package
├── {project}_client1                # Flutter app (developer-written, optional)
├── ...                
└── {project}_client_n               # Flutter app (developer-written, optional)
```

**Key Principle**: The `model/` package is where developers define the source of truth. Everything else is either auto-generated or depends on the model.

---

**Naming Rules**:

Entities are what your domain is for. Entities names follow **Functional Naming Rules** (Business Domain):
   - Entity names represent actual business concepts: `Order`, `Customer`, `Product`, `Invoice`
   - It should be in singular form.
   - NOT generic placeholders: ❌ `Entity1`, ❌ `DataObject`, ❌ `Record`
   - NOT abbreviated: ❌ `Ord`, ❌ `Cust` (use full meaningful names)
   - Should be immediately understandable to domain stakeholders
   - Examples: `Order` (sales domain), `Customer` (CRM domain), `Product` (catalog domain)

Namespaces are used to organize entities into logical groups, especially in domains where entities number in the dozens or hundreds. Namespaces "contain" entities and/or sub-namespaces (recursively). A namespace could define a schema in the database, but this requires a decorator on its model class (`@DbName`).
Namespaces are named:
- using the plural form of the primary entity name when such an entity exists (e.g., "Customers" for a namespace containing the entities "Customer", "Address", "Reminder", etc.)
- using a generic term (e.g., "System") when they group functionally related entities but without an obvious "master" entity (e.g. entities "User", "Session", "Log", etc).

**Important** : entities and namespaces names **MUST** be unique across the model. It is forbidden to define two entities or namespaces with the same name. It is forbidden to define an entity and a namespace with the same name.

---

## 2. Model Package Structure

The `model` package contains entity definitions and is the most important for understanding the data structure.

### 2.1. Directory Organization

```
model/
├── lib/
│   ├── model/                       # ← Developer-written model definitions
│   │   │
│   │   └── [root_namespace]/                    # Root namespace (unique, top-level)
│   │       ├── root_namespace.dart              # Namespace definition. Sub structure exports
│   │       ├── entity_a.dart                    # Entity definition at root level
│   │       ├── [sub_namespace1]/                # Sub-namespace (can contain entities and/or sub-namespaces)
│   │       │   ├── sub_namespace1.dart          # Namespace definition. Sub structure exports
│   │       │   ├── entity_b.dart                # Entity definition at sub-namespace level
│   │       │   ├── entity_c.dart                # Another entity at same level
│   │       │   └── [sub_sub_namespace1]/        # Nested sub-namespace (recursive nesting allowed)
│   │       │       ├── sub_sub_namespace.dart   # Namespace definition. Sub structure exports
│   │       │       ├── entity_d.dart            # Entity at nested level
│   │       └── [sub_namespace2]/                # Another sub-namespace at root level
│   │           ├── sub_namespace2.dart          # Namespace definition. Sub structure exports
│   │           ├── entity_e.dart
│   │           └── [sub_sub_namespace2]/
│   │               ├── sub_sub_namespace2.dart  # Namespace definition. Sub structure exports
│   │               └── entity_f.dart
│   └── sing/                        # ← Auto-generated server code (DO NOT CHANGE)
├── test/                            # Unit tests for model/services
├── pubspec.yaml                     # Project pubspec
└── build/                           # Build artifacts (ignore)
```

**Key Points About Namespace Structure**:
- **One root namespace**: There is exactly one root namespace under `model/lib/model/`
- **Sub-namespaces**: Multiple sub-namespaces can be nested within the root namespace
- **Recursive nesting**: Sub-namespaces can contain sub-sub-namespaces indefinitely
- **Entities at any level**: Entities can exist at any nesting level (root, sub, or deeper)
- **Mixed content**: A namespace can contain both entities AND sub-namespaces at the same level
- **Namespace**: file name as `{namespace_name}.dart` (snake_case), in a directory with then same name (without extension) in its namespace's directory. Root namespace : parent directory is model/lib/model. Contain namespace definition (entities and sub-namespace contained).
- **Entity File**: file name as `{entity_name}.dart` (snake_case), in its namespace's directory. Contain entity model definition.

```dart
// model/lib/model/orders/order.dart
class OrderEntity extends ModelEntity {
  final uuid = UuidField(autoAllocate: true).primaryKey()
  final customerName = StringField(maxLength: 100);
  final totalAmount = DoubleField();
}
```

**Mapping Example for entities**:
```
Functional Name  │ Model Class Name  │ File Name
─────────────────┼───────────────────┼──────────────
Order            │ OrderEntity       │ order.dart
Customer         │ CustomerEntity    │ customer.dart
Product          │ ProductEntity     │ product.dart
InvoiceLine      │ InvoiceLineEntity │ invoice_line.dart
```
The `Entity` suffix on entity definition classes is **mandatory**: this is the **definition** of the entity, not the entity itself as it will be accessible in your application code. `sing_builder` enforces this rule and stops code generation if this convention is not followed.

**Mapping Example for namespaces**:
```
Functional Name  │ Model Class Name  │ File Name      │ Directory Name
─────────────────┼───────────────────┼────────────────┼────────────────
Orders           │ OrdersNameSpace   │ orders.dart    │ orders
System           │ SystemNameSpace   │ system.dart    │ system
```
The `NameSpace` suffix on namespace definition classes is **mandatory**: this is the **definition** for the same reason as the entity convention. `sing_builder` enforces this rule and stops code generation if this convention is not followed.

**Why This Matters**:
- **Functional naming** ensures domain clarity: agents and developers immediately understand what the entity represents
- **Technical naming** ensures consistency: Dart style guide compliance and predictable file locations
- Together, they enable navigation patterns: knowing entity means you know file location (`Order` → look in `order.dart`)

### 2.2. Custom Service Files

Sing allows you to define the most common services (search, CRUD) without writing custom logic. However, it is essential to be able to define services distinct from these standard services.

**Pattern**: The convention is to place specialized service definitions in a file named:
- `{entity_name}.services.dart` (snake_case with `.services` suffix) for specialized services defined on an entity.
- `{namespace_name}.services.dart` (snake_case with `.services` suffix) for specialized services defined on a namespace.

The file is placed in the same directory as the entity or namespace definition.

**When to create**:
- Adding business logic beyond standard CRUD
- Custom operations (batch updates, complex workflows)
- Domain-specific methods

**Naming Rules**:
- File suffix: `.services.dart`
- Mixin name:
  - `{EntityName}Services` (no "Mixin" suffix) for services on an entity.
  - `{NameSpaceName}Services` (no "Mixin" suffix) for services on a mixin.
- Referenced in entity or namespace model : `@Implementor(OrderServices)`.

For more details, [see the implementation details of services](SERVICES.md).

### 2.3. Migration Files

If [migration steps](MIGRATIONS.md) are necessary for an entity or namespace, they are defined in a file named:

**Pattern**:
- `{entity_name}.migrations.dart` (snake_case with `.migrations` suffix) for migration steps defined on an entity.
- `{namespace_name}.migrations.dart` (snake_case with `.migrations` suffix) for migration steps defined on a namespace.

The file is placed in the same directory as the entity or namespace definition.

**When to create**:
- Renaming fields or entities
- Data type conversions
- Schema changes beyond simple column additions

---

## 3. Common Package Structure

Shared types between server and client.

```
common/
├── lib/
│   ├── common.dart                  # Main export file for the common package. MUST export `src/sing/sing.dart`
│   └── src/
│       ├── sing/                    # ← Auto-generated shared code. DO NOT EDIT
│       └── [developer-written utilities] # Constants, extensions, etc.
│
└── pubspec.yaml
```

**Key Points**:
- `common/lib/src/sing/` contains auto-generated shared types
- `common/lib/src/sing/` alaways contains a sing.dart file (generated at first build)
- Entity **interfaces** are shared (not implementations)
- Client and server both depend on this for common types definitions (enum, extensions, etc)

---

## 4. Server Package Structure

Server implementation (business logic, HTTP handlers, migrations).

```
{project}_server/
├── lib/
│   ├── processes/                   # Process initialization
│   │   ├── main.dart                # Entry point
│   │   ├── http_server.dart         # HTTP server setup
│   │   └── worker.dart              # Background worker (optional)
│   │
│   ├── handlers/                    # HTTP request handlers
│   │   ├── order_handlers.dart      # /api/orders/* endpoints
│   │   ├── product_handlers.dart    # /api/products/* endpoints
│   │   └── ...
│   │
│   └── services/                    # Business logic (beyond CRUD)
│       ├── order_processing.dart
│       ├── payment_service.dart
│       └── ...
│
├── test/                            # Integration tests
└── pubspec.yaml
```

**Key Points**:
- `processes/main.dart`: Server startup and initialization
- `handlers/`: HTTP endpoint routing
- `services/`: Domain logic (orchestration, payments, etc.)
- **Do not edit** `model/lib/sing/` — regenerate instead

---

## File Naming Pattern Reference

| File Type               | Location                | Pattern                         | Example                 |
| ----------------------- | ----------------------- | ------------------------------- | ----------------------- |
| **Entity Definition**   | `model/lib/model/[ns]/` | `{entity_name}.dart`            | `order.dart`            |
| **Entity Class**        | `{entity_name}.dart`    | `{EntityName}Entity`            | `OrderEntity`           |
| **Custom Services**     | `model/lib/model/[ns]/` | `{entity_name}.services.dart`   | `order.services.dart`   |
| **Service Mixin**       | `.services.dart`        | `{EntityName}Services`          | `OrderServices`         |
| **Migrations**          | `model/lib/model/[ns]/` | `{entity_name}.migrations.dart` | `order.migrations.dart` |
| **Migration Class**     | `.migrations.dart`      | `{EntityName}Migrations`        | `OrderMigrations`       |
| **Listeners**           | `model/lib/model/[ns]/` | `{entity_name}.listeners.dart`  | `order.listeners.dart`  |
| **Listener Mixin**      | `.listeners.dart`       | `{EntityName}Listeners`         | `OrderListeners`        |
| **Faker**               | `model/lib/model/[ns]/` | `{entity_name}.faker.dart`      | `order.faker.dart`      |
| **Faker Class**         | `.faker.dart`           | `{EntityName}Faker`             | `OrderFaker`            |
| **Generated EntityDef** | `model/lib/sing/[ns]/`  | `{entity_name}_def.dart`        | `order_def.dart`        |
| **Generated Services**  | `model/lib/sing/[ns]/`  | `{entity_name}_services.dart`   | `order_services.dart`   |
| **Generated Search**    | `model/lib/sing/[ns]/`  | `{entity_name}_search.dart`     | `order_search.dart`     |

---

## Recognizing Auto-Generated Files

### Red Flags: Don't Edit These

Files in `model/lib/sing/` are **always** auto-generated. Never modify:
- `*_def.dart`
- `*_services.dart`
- `*_search.dart`
- `*_tokens.dart`
- `server_registry.dart`
- `server_migrations.dart`
- `server_json.dart`
- `server_init.dart`

If you need to change these, **modify the model and regenerate**:
```bash
dart run sing_builder generate
```

### Green Flags: Safe to Edit

These files are developer-written:
- `model/lib/model/**/*.dart` (all entity definitions)
- `model/lib/model/**/*.services.dart` (custom services)
- `model/lib/model/**/*.migrations.dart` (custom migrations)
- `model/lib/model/**/*.listeners.dart` (event listeners)
- `model/lib/model/**/*.faker.dart` (test data)

---

## Package Initialization Pattern

### New Project Setup

When creating a new Sing project `myapp`:

```bash
# 1. Create model package
mkdir -p myapp/model/lib/model
cd myapp/model
dart pub init

# 2. Create common package
mkdir -p ../common/lib/src/sing
cd ../common
dart pub init

# 3. Create server package
mkdir -p ../myapp_server/lib/processes
cd ../myapp_server
dart pub init

# 4. Add dependencies (in each pubspec.yaml)
# model/pubspec.yaml
dependencies:
  sing_model: ^0.0.1
  sing_server: ^0.0.1

# common/pubspec.yaml
dependencies:
  sing_core: ^0.0.1

# myapp_server/pubspec.yaml
dependencies:
  myapp_model:
    path: ../model
  myapp_common:
    path: ../common
  sing_server: ^0.0.1
  shelf: ^1.0.0
```

### Typical Namespace Creation

When adding a new domain (e.g., `Orders`):

```bash
# 1. Create namespace directory
mkdir -p model/lib/model/orders

# 2. Create entity file
touch model/lib/model/orders/order.dart

# 3. Add decorators and definition
# @StdEntityServices()
# @Searchable()
# class OrderEntity extends ModelEntity { ... }

# 4. Create services file (if custom logic needed)
touch model/lib/model/orders/order.services.dart

# 5. Regenerate
dart run sing_builder generate

# Generated files appear in:
# - model/lib/sing/orders/order_def.dart
# - model/lib/sing/orders/order_services.dart
# - model/lib/sing/orders/order_search.dart
# - common/lib/src/sing/orders/order.dart (interface)
```

---

## Locating Code in a Project

### "Where is the X entity defined?"

```
Entity Definition → model/lib/model/{namespace}/{entity_name}.dart
Generated Server Code → model/lib/sing/{namespace}/{entity_name}_*.dart
Shared Interface → common/lib/src/sing/{namespace}/{entity_name}.dart
```

### "Where are the custom services for Order?"

```
Custom Logic → model/lib/model/orders/order.services.dart
Generated Services → model/lib/sing/orders/order_services.dart (READ-ONLY)
```

### "Where are migrations defined?"

```
Custom Steps → model/lib/model/{namespace}/{entity_name}.migrations.dart
Generated DDL → model/lib/sing/server_migrations.dart (READ-ONLY)
```

### "Where do I handle HTTP requests?"

```
Routing → {project}_server/lib/processes/main.dart
Handlers → {project}_server/lib/handlers/*.dart
```

---

## Best Practices

### ✅ Good: Follow Naming Conventions

```
model/lib/model/
├── orders/
│   ├── order.dart                   # Entity definition
│   ├── order.services.dart          # Custom business logic
│   └── order_line.dart              # Related entity
└── products/
    ├── product.dart
    └── promotion.dart
```

### ❌ Bad: Inconsistent Naming

```
model/lib/model/
├── Orders.dart                      # ❌ PascalCase filename
├── OrderServices.dart               # ❌ Missing .services suffix
├── product/Product.dart             # ❌ PascalCase filename
└── promo.dart                       # ❌ Abbreviations unclear
```

### ✅ Good: Logical Namespace Organization

```
model/lib/model/
├── orders/              # All order-related entities
│   ├── order.dart
│   ├── order_line.dart
│   └── order.services.dart
├── products/            # All product-related
│   ├── product.dart
│   └── promotion.dart
└── customers/           # Customer domain
    └── customer.dart
```

### ❌ Bad: Unorganized Structure

```
model/lib/model/
├── order.dart
├── order_line.dart
├── product.dart
├── promotion.dart
├── customer.dart
├── invoice.dart         # ← Hard to find related files
└── payment.dart
```

### ✅ Good: Separate Custom Logic

```
# model/lib/model/orders/order.services.dart
mixin OrderServices on EntityServerServices<Order, String> {
  // Custom business logic here
}

# model/lib/model/orders/order.dart
@StdEntityServices()
@Implementor(OrderServices)  # Link to custom logic
class OrderEntity extends ModelEntity { ... }
```

### ❌ Bad: Mixing Concerns

```dart
// ❌ Don't put custom logic in entity definition
class OrderEntity extends ModelEntity {
  // ... field definitions ...

  // ❌ Business logic doesn't belong here
  Future<Order> complexProcessing() { ... }
}
```

---

**Related Code**:
- Example: `example/orderhub/model/lib/model/`
- Generated: `example/orderhub/model/lib/sing/`

