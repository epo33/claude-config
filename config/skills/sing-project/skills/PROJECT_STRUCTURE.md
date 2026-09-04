# Project Structure & Naming Conventions

This document explains the directory and file organization conventions for Sing projects, helping LLM agents navigate and understand the codebase structure. In all examples, {project_key} is a short string associated to the project used as prefix in names.

## 1. Overview

A Sing project follows a multi-package structure where the **model** is the source of truth, and generated code is organized systematically:

```
project_root/
├── model/                           # Model definitions (developer-written),
│   ├── build/
│   │   ├── sing_build.dart          # `dart run build/sing_build.dart`: rebuilds the generated code
│   │   └── sing_init.dart           # Re-runs the package initialization
│   ├── lib/                         # Library code
│   │   ├── model/                   # Model definitions (developer-written)
│   │   │   └── model.dart           # `createXxxModel()` returning the `Model`, root namespace class
│   │   ├── sing/                    # Auto-generated server code (DO NOT CHANGE)
│   │   ├── server.dart              # `export 'sing/server.dart';`
│   │   └── model.dart               # Exports sing_model, sing_server, model definitions, common package
├── common/                          # Shared code and types (developer + generated), 
├── model_sing_client/               # Client SDK (auto-generated, path set by `Model.clientPackagePath`)
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
├── build/
│   ├── sing_build.dart              # Code generation script
│   └── sing_init.dart               # Package initialization script
├── lib/
│   ├── model/                       # ← Developer-written model definitions
│   │   ├── model.dart                       # `createXxxModel()` and the root namespace class. Sub structure exports
│   │   ├── entity_a.dart                    # Entity definition at root level
│   │   ├── [sub_namespace1]/                # Sub-namespace (can contain entities and/or sub-namespaces)
│   │   │   ├── sub_namespace1.dart          # Namespace definition. Sub structure exports
│   │   │   ├── entity_b.dart                # Entity definition at sub-namespace level
│   │   │   ├── entity_c.dart                # Another entity at same level
│   │   │   └── [sub_sub_namespace1]/        # Nested sub-namespace (recursive nesting allowed)
│   │   │       ├── sub_sub_namespace.dart   # Namespace definition. Sub structure exports
│   │   │       ├── entity_d.dart            # Entity at nested level
│   │   └── [sub_namespace2]/                # Another sub-namespace at root level
│   │       ├── sub_namespace2.dart          # Namespace definition. Sub structure exports
│   │       ├── entity_e.dart
│   │       └── [sub_sub_namespace2]/
│   │           ├── sub_sub_namespace2.dart  # Namespace definition. Sub structure exports
│   │           └── entity_f.dart
│   ├── sing/                        # ← Auto-generated server code (DO NOT CHANGE)
│   ├── server.dart                  # `export 'sing/server.dart';`
│   └── model.dart                   # Exports framework, model definitions and common package
├── test/                            # Unit tests for model/services
└── pubspec.yaml                     # Project pubspec
```

**Key Points About Namespace Structure**:
- **One root namespace**: There is exactly one root namespace, declared in `model/lib/model/model.dart` (e.g. `OrderHubNameSpace` in `example/model/lib/model/model.dart`) and passed to `Model(rootNameSpace:)`; its sub-namespaces are directories of `model/lib/model/`
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

### 2.3. Version Files

[Migration steps](MIGRATIONS.md) belong to the model versions: subclasses of `MajorVersion` (with a default constructor) listed in `Model(majorVersions:)`, each holding its `MinorVersion`s, `PatchVersion`s and `BeforeMigrationStep` / `AfterMigrationStep`s. The framework does not impose their file location; the convention is one file per major version under `model/lib/model/versions/` (e.g. `v1.dart` for `class V1 extends MajorVersion`).

**When to add a step**:
- Renaming fields or entities with data to keep
- Data type conversions
- Seed data, schema changes beyond what the DDL orders derive from the model

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
- `common/lib/src/sing/` contains auto-generated shared types: `common.dart` (entity interfaces with their `tupleKey`, `DataRowValues$Xxx` extensions), `searches.dart` (`Xxx$Search` classes), `consts.dart`, `registry.dart` (`XxxRegistry<E>` model interface) and `sing.dart` (export file)
- `common/lib/src/sing/` always contains a `sing.dart` file (created by the package initialization)
- Entity **interfaces** are shared (not implementations)
- Client and server both depend on this for common types definitions (enum, extensions, etc)

---

## 4. Server Package Structure

Server implementation (registry creation, migration call, HTTP server). `example/orderhub_server/bin/orderhub_server.dart` shows the minimum: `createDataRegistry` building `OrderHubServerRegistry(dataControler: PgDataControler(...))` and `migrateDatabase` (see [APP_SERVER.md](APP_SERVER.md)). A suggested layout for a larger server:

```
{project}_server/
├── bin/
│   └── {project}_server.dart        # Entry point
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

## 5. File Naming Pattern Reference

| File Type               | Location                | Pattern                         | Example                 |
| ----------------------- | ----------------------- | ------------------------------- | ----------------------- |
| **Entity Definition**   | `model/lib/model/[ns]/` | `{entity_name}.dart`            | `order.dart`            |
| **Entity Class**        | `{entity_name}.dart`    | `{EntityName}Entity`            | `OrderEntity`           |
| **Custom Services**     | `model/lib/model/[ns]/` | `{entity_name}.services.dart`   | `order.services.dart`   |
| **Service Mixin**       | `.services.dart`        | `{EntityName}Services`          | `OrderServices`         |
| **Model Versions**      | `model/lib/model/versions/` | `v{n}.dart` (convention)    | `v1.dart`               |
| **Version Class**       | `v{n}.dart`             | `V{n} extends MajorVersion`     | `V1`                    |
| **Generated Entity**    | `model/lib/sing/[root]/[ns]/` | `{entity_name}.dart` (`$Order`, `_Order$Impl`, `Order$Services`) | `order_hub/orders/order.dart` |
| **Generated Namespace** | `model/lib/sing/[root]/` | `{namespace_name}.dart`        | `order_hub/orders.dart` |
| **Generated Registry**  | `model/lib/sing/`       | `server.dart` (`OrderHub$Layer`, `OrderHubServerRegistry`) | `server.dart` |
| **Generated Searches**  | `model/lib/sing/`, `common/lib/src/sing/` | `server_searches.dart`, `searches.dart` | `Order$Search` |
| **Generated Interface** | `common/lib/src/sing/`  | `common.dart` (`Order`, `Order$Instance`, `DataRowValues$Order`) | `common.dart` |

---

## 6. Recognizing Auto-Generated Files

### 6.1. Red Flags: Don't Edit These

Files in `model/lib/sing/`, `common/lib/src/sing/` and `model_sing_client/lib/src/` are **always** auto-generated (header `// Generated by SING. DO NOT MODIFY`). Never modify:
- `model/lib/sing/server.dart`, `server_common.dart`, `server_exports.dart`, `server_init.dart`, `server_mixins.dart`, `server_searches.dart`, `server_tokens.dart` and the namespace directories
- `common/lib/src/sing/common.dart`, `consts.dart`, `registry.dart`, `searches.dart`, `sing.dart`
- `model_sing_client/lib/src/client.dart`, `client_common.dart`, `client_ent.dart`, `client_exports.dart`, `client_init.dart`, `client_mixins.dart`, `client_searches.dart`, `client_svc.dart`, `client_tokens.dart` and the namespace directories

If you need to change these, **modify the model and regenerate** (from `model/`):
```bash
dart run build/sing_build.dart
```

### 6.2. Green Flags: Safe to Edit

These files are developer-written:
- `model/lib/model/**/*.dart` (all entity and namespace definitions)
- `model/lib/model/**/*.services.dart` (custom services)
- `model/lib/model/versions/*.dart` (model versions and migration steps)

---

## 7. Package Initialization Pattern

### 7.1. New Project Setup

When creating a new Sing project `myapp` (details in [INIT_PROJECT.md](INIT_PROJECT.md)):

```bash
# 1. Create the model package
cd myapp
dart create model
# add sing_builder (path dependency on the Sing sources) to model/pubspec.yaml dev_dependencies

# 2. Initialize model, common and model_sing_client packages
cd model
dart run sing_builder:init PATH_TO_SING
# model/pubspec.yaml: path dependencies on sing_model, sing_server, ../common
# common/pubspec.yaml: path dependency on sing_core
# model_sing_client/pubspec.yaml: path dependency on sing_client

# 3. Create the server package
cd ..
dart create myapp_server
# myapp_server/pubspec.yaml
dependencies:
  model:
    path: ../model
  sing_server:
    path: PATH_TO_SING/sing_server
  sing_postgresql:
    path: PATH_TO_SING/sing_postgresql
```

### 7.2. Typical Namespace Creation

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

# 5. Regenerate (from model/)
dart run build/sing_build.dart

# Generated code appears in:
# - model/lib/sing/{root}/orders/order.dart ($Order, _Order$Impl, Order$Services)
# - model/lib/sing/{root}/orders.dart (Orders namespace)
# - model/lib/sing/server_searches.dart, common/lib/src/sing/searches.dart (Order$Search)
# - common/lib/src/sing/common.dart (Order interface, Order$Instance, DataRowValues$Order)
# - model_sing_client/lib/src/{root}/orders/... (client side)
```

---

## 8. Locating Code in a Project

### 8.1. "Where is the X entity defined?"

```
Entity Definition → model/lib/model/{namespace}/{entity_name}.dart
Generated Server Code → model/lib/sing/{root}/{namespace}/{entity_name}.dart
Shared Interface → common/lib/src/sing/common.dart (class {EntityName}, static tupleKey)
```

### 8.2. "Where are the custom services for Order?"

```
Custom Logic → model/lib/model/orders/order.services.dart
Generated Services → model/lib/sing/{root}/orders/order.dart, class Order$Services (READ-ONLY)
```

### 8.3. "Where are migrations defined?"

```
Version tree and steps → MajorVersion subclasses listed in Model(majorVersions:) (model/lib/model/versions/ by convention)
DDL orders → computed at run time by migrateDatabase from the model and the database (no generated file)
```

### 8.4. "Where do I handle HTTP requests?"

```
Entry point → {project}_server/bin/{project}_server.dart
Sing services → dataRegistry.processRequest(request:, sessionManager:) mounted on a route (see APP_SERVER.md)
```

---

## 9. Best Practices

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
- Example: `example/model/lib/model/`
- Generated: `example/model/lib/sing/`, `example/common/lib/src/sing/`, `example/model_sing_client/lib/src/`
- Server application: `example/orderhub_server/bin/orderhub_server.dart`

