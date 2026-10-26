# Building the Data Model

## 1. Overview

A Sing model is plain Dart code in the `model` package (`model/lib/model/`). It uses the classes of `sing_model`:

| Class | Role |
| ----- | ---- |
| `Model` | the model itself, built by one top-level function |
| `ModelNameSpace` | a namespace: a database schema and a node of the service tree |
| `ModelEntity` | an entity stored in a table |
| `ModelAncestorEntity<T>` / `ModelDescendantEntity<T>` | polymorphic entities ([§7](#7-polymorphic-entities-ancestor-and-descendants)) |
| `ModelTuple` | a row shape without table ([§8](#8-tuples)) |

Fields are described in [Entity Fields](FIELD_TYPES.md).

`sing_builder` reads this code with the Dart analyzer and generates the server, common and client code. Run it from the model package:

```bash
dart run sing_builder:sing_emit
```

The builder never runs the model. It reads declarations, so their **shape** matters: each section below says which forms it accepts. The generated server code does instantiate the model at run time, to read the field parameters and the indexes.

A definition class is not the entity used by application code. `OrderEntity` is the definition. The builder generates `Order` (interface), `$Order`, `Order$Instance`, `Order$Search`, `Order$Services`... The generated name is the class name without its `Entity`, `Tuple`, `NameSpace` or `Mixin` suffix. See [Generated code](GENERATED_CODE.md).

## 2. The Model Entry Point

The model package declares **exactly one** top-level function in `lib/` that returns a `Model` and builds it in place. From `example/model/lib/model/model.dart`:

```dart
Model createOrderHubModel() => Model(
  modelName: "OrderHub",
  rootNameSpace: OrderHubNameSpace(),
  clientPackagePath: "../model_sing_client",
  commonPackagePath: "../common",
);
```

Parameters of `Model` (`sing_model/lib/src/model.dart`):

| Parameter | Role |
| --------- | ---- |
| `modelName` | required, written as a string literal. First letter is upper-cased. Prefix of generated classes (`OrderHubServerRegistry`...). |
| `rootNameSpace` | instance of the root namespace class |
| `commonPackagePath` | path of the `common` package, relative to the model package |
| `clientPackagePath` | path of the generated client package, relative to the model package |
| `packageName` | Dart package name used in imports. Default: the package declaring the function. |
| `singSubDir` | folder under `lib/` for generated files. Default `sing` (`lib/sing/`). |
| `aliases` | `Alias(glob:, package:, alias:)` list: import prefix used in generated code for matching packages. `core`, `http`, `meta` and `impl` are reserved. An alias cannot start with `_`. |
| `subModels` | models mounted by this one ([Submodels](SUBMODELS.md)) |
| `isSubModel` | `true` for a model meant to be mounted by another |
| `majorVersions` | model versions and their migration steps, as a list of constructor calls `[OrderHubV0()]` ([Migrations](MIGRATIONS.md#2-model-versions)) |
| `strictAccessTokens` | when `true`, the build fails for any concrete entity publishing services with no `@TokenContext` above it and no explicit `@AccessToken` |

`serverHttpResponseType` and `clientHttpResponseType` exist on the class but the builder does not read them.

## 3. Namespaces

A namespace groups entities and sub-namespaces. Each entity or namespace is mounted by a property of its parent namespace.

1. Create a folder named after the namespace in snake_case (`orders/`) in the parent folder.
2. Create `orders/orders.dart` with the definition class. Its name ends with `NameSpace`.
3. Mount it in the parent with a `final` property.
4. Chain the exports so that `package:model/model.dart` reaches every definition.

From `example/model/lib/model/orders/orders.dart`:

```dart
import "package:model/model.dart";

export "address.dart";
export "customer.dart";
export "order.dart";
export "order_line.dart";

class OrdersNameSpace extends ModelNameSpace {
  OrdersNameSpace();

  final addresses = AddressEntity();

  final customers = CustomerEntity();

  final orders = OrderEntity();

  final orderLines = OrderLineEntity();
}
```

And in the root namespace:

```dart
@AccessToken.authentified
@openApi
class OrderHubNameSpace extends ModelNameSpace {
  OrderHubNameSpace();

  final orders = OrdersNameSpace();

  final products = ProductsNameSpace();
}
```

Rules:

- The property name is the path segment: `orders` mounts `OrdersNameSpace` at `/orders`. Use the plural of the main entity for an entity property (`orderLines = OrderLineEntity()`).
- A model holds **one** instance of each entity class. Mounting the same class twice is refused.
- A namespace that mounts itself, directly or not, is refused.
- A namespace that nothing mounts, or a concrete entity that no namespace mounts, produces a warning: it is not in the model tree.
- Names of entities and namespaces must be unique in the model ([naming conventions](PROJECT_STRUCTURE.md)).

Namespace annotations:

| Annotation | Effect |
| ---------- | ------ |
| `@DbName("sales")` | database schema of the tables below it. Without it, the schema of the nearest parent namespace with `@DbName` is used, else `public`. |
| `@Implementor(XServices)` | services attached to the namespace ([Services](SERVICES.md)) |
| `@AccessToken.xxx`, `@TokenContext(...)` | access control of the services below ([Access tokens](ACCESS_CONTROL.md)) |
| `@openApi` / `@OpenApi(false)` | publishes (or hides) the services below in the OpenAPI description |
| `@Documentation(lib: ..., description: ...)` | label and description |

`@serverSideOnly` on the **property** that mounts a namespace keeps the namespace and its content off the clients.

## 4. Entities

### 4.1. Declaring an Entity

1. Create `order.dart` (snake_case) in the namespace folder.
2. Declare a class whose name ends with `Entity` and extends `ModelEntity`.
3. Mount it in the namespace and export the file ([§3](#3-namespaces)).

From `example/model/lib/model/orders/order.dart` (shortened):

```dart
import "package:model/model.dart";

export "order.services.dart";

@Implementor(OrderServices)
@LoadServices()
@Searchable()
class OrderEntity extends ModelEntity with UuidPrimaryKeyMixin {
  OrderEntity();

  final orderNumber = StringField(maxLength: 50).immutable();

  final orderDate = DateTimeField.utc().immutable();

  final customer = ReferenceTo<CustomerEntity>(
    onDelete: ReferentialAction.error,
  );

  final shippingAddress = ReferenceTo<AddressEntity>(
    onDelete: ReferentialAction.error,
  ).nullable();

  final status = EnumField<OrderStatus>(defaultValue: .pending);

  final totalAmount = DoubleField();

  final notes = StringField(maxLength: 1000).nullable();

  final paidAt = DateTimeField.utc().nullable();

  @SearchOnlyField()
  final test = BoolField();
}
```

The fields of an entity are its own `final` fields, then those of its mixins, then those of its model superclasses.

### 4.2. Primary Key

Mark the key field with `.primaryKey()`. Most entities get it from a mixin:

```dart
mixin UuidPrimaryKeyMixin on ModelEntity {
  final uuid = UuidField(autoAllocate: true).primaryKey().immutable();
}
```

- An entity with **one** primary key field is *referenceable*: it can be the target of a `ReferenceTo`, and it can use the standard CRUD services. The key type is the value type of this field (`String` for a `UuidField`).
- Several `.primaryKey()` fields give a composite key. Such an entity cannot be referenced and has no row version.
- A `ReferenceTo` can be the key (`ReferenceTo<OrderEntity>(onDelete: .cascade).primaryKey()`): the key type is then the key type of the target.

### 4.3. Entity Annotations

| Annotation | Effect |
| ---------- | ------ |
| `@StdEntityServices(...)` | load, insert, update, upsert and delete services ([§4.4](#44-standard-crud-services)) |
| `@LoadServices()`, `@InsertServices()`, `@UpdateServices()`, `@UpsertServices()`, `@DeleteServices()` | one group of standard services each |
| `@Implementor(XServices, serverSideOnly:, accessToken:)` | adds the services of a hand-written mixin ([Services](SERVICES.md)). Several `@Implementor` can be stacked. |
| `@Searchable()` | generates `X$Search` and the `search` service. `@Searchable(searchable: false)` opts a descendant out. ([Searches](SEARCHES.md#1-declaring-a-searchable-entity)) |
| `@ViewEntity()` | the entity has no table ([§6](#6-views)) |
| `@AccessToken.xxx` | token required by the services of the entity (`AccessToken.authentified`, `AccessToken.me`, ... or a `const AccessToken("/my/path")`). See [Access tokens](ACCESS_CONTROL.md#2-tokens-on-services). |
| `@TokenContext(...)` / `@TokenContext.generic()` | token context of the entity: standard services take their `read`/`write` token from it ([Access tokens](ACCESS_CONTROL.md#3-token-contexts)) |
| `@openApi` / `@OpenApi(false)` | publishes or hides its services in the OpenAPI description |
| `@Documentation(lib: ..., description: ...)` | label and description of the entity |
| `@InNameSpace(XNameSpace)` | namespace of an entity that no namespace mounts, such as a generic base ([§5.4](#54-generic-entities)) |
| an `EntityControler` subclass used as annotation | change listeners run by the server on writes ([Entity change listeners](SERVICES.md#7-entity-change-listeners)) |

Annotations are also read on the superclasses and mixins of the entity. The one written on the class itself wins.

Keep an entity off the clients with `@serverSideOnly` on the **namespace property** that mounts it:

```dart
class OrdersNameSpace extends ModelNameSpace {
  @serverSideOnly
  final paymentLogs = PaymentLogEntity();
}
```

`@DbName` on an entity class is not read: the table name always comes from the class name ([§10](#10-database-names)). Schema migrations are not declared on entities: see [Migrations](MIGRATIONS.md).

### 4.4. Standard CRUD Services

The entity must be referenceable ([§4.2](#42-primary-key)). Signatures and usage: [Services](SERVICES.md#3-standard-crud-services).

| Annotation | Services | Parameters |
| ---------- | -------- | ---------- |
| `@LoadServices()` | `loadThisKey`, `loadThoseKeys`, `loadThisRef`, `loadThoseRefs` | `key`, `keys`, `ref`, `refs` |
| `@InsertServices()` | `insertThis`, `insertThose` | `data` (a `DataRow` or a list of them) |
| `@UpdateServices()` | `updateThis`, `updateThose` | `data` |
| `@UpsertServices()` | `upsertThis`, `upsertThose` | `data` |
| `@DeleteServices()` | `deleteThisKey`, `deleteThoseKeys`, `deleteThisRef`, `deleteThoseRefs` | `key`, `keys`, `ref`, `refs` |

All of them take `callContext` and return a `DataLoader<X>`. Insert, update and upsert drop the values of `.readOnly()` fields sent by the caller.

`@StdEntityServices` combines the five groups. Each group can be turned off, and tokens can be set:

```dart
@StdEntityServices(delete: false, writeToken: AccessToken.maintenance)
class ProductEntity extends ModelEntity with UuidPrimaryKeyMixin {
  ProductEntity();
}
```

| Parameter | Default | Effect |
| --------- | ------- | ------ |
| `load`, `insert`, `update`, `upsert`, `delete` | `true` | generates the group |
| `accessToken` | none | token of every service |
| `readToken` | `accessToken` | token of the load services |
| `writeToken` | `accessToken` | token of the other services |
| `serverSideOnly` | `false` | the services exist on the server only |

Without tokens, each service is guarded by the token context of the entity, for the verb `read` (load) or `write` (others). See [Access tokens](ACCESS_CONTROL.md#24-standard-services).

### 4.5. Indexes

Override `getIndicies()` (this exact spelling) and return `ModelIndex` objects built on the field instances of the entity:

```dart
class OrderLineEntity extends ModelEntity with UuidPrimaryKeyMixin {
  OrderLineEntity();

  final order = ReferenceTo<OrderEntity>(onDelete: .cascade);

  final lineIndex = IntField().immutable();

  @override
  Iterable<ModelIndex> getIndicies() => [
    ModelIndex([order, lineIndex], unique: true),
  ];
}
```

- `ModelIndex(fields, {unique = false, nullsDistinct = true})`.
- `nullsDistinct: false` on a unique index makes `NULL` values equal (PostgreSQL `NULLS NOT DISTINCT`).
- A `StringField` with a `collation` is indexed with that collation.
- A `ReferenceTo` is already indexed (`autoIndex: true`). Do not add a single-field index on it.
- This method is run by the generated code, not read by the builder: any Dart code works.

### 4.6. Field Links

`getLinks()` declares links between two fields of the entity. Sing stores the link in `FieldProps.linkedFieldName` and gives it no meaning: the application decides.

```dart
@override
Iterable<FieldLink> getLinks() => [
  shippingAddress.linkedWith(billingAddress, requireOne: true),
];
```

`requireOne: true` records that at least one of the two fields must be non-null. Sing does not enforce it.

## 5. Sharing Fields

### 5.1. Mixins

A mixin `on ModelEntity` declares fields shared by several entities. From `example/model/lib/model/model_tools/common_fields.dart`:

```dart
mixin TimestampsMixin on ModelEntity {
  final createdAt = DateTimeField.utc().immutable();

  final updatedAt = DateTimeField.utc();
}

mixin CommentFieldMixin on ModelEntity {
  @AutoSearch.no
  final comment = StringField(maxLength: 1024).nullable();
}
```

```dart
class ProductEntity extends ModelEntity
    with UuidPrimaryKeyMixin, TimestampsMixin {
  ProductEntity();
}
```

The fields are copied into each entity. Annotations written on the mixin (such as `@Searchable()`) apply to the entities using it.

### 5.2. Entity Mixins With an Interface

Add `@EntityMixin()` to the mixin when generic code must handle every entity that uses it. The builder generates an interface named after the mixin without its `Mixin` suffix, and every entity using the mixin implements it.

```dart
@EntityMixin()
mixin TimestampsMixin on ModelEntity {
  final createdAt = DateTimeField.utc().immutable();

  final updatedAt = DateTimeField.utc();
}
// Generated: abstract interface class Timestamps, implemented by Product.
```

A mixin can be generic, for example to hold a reference to the entity that uses it: `mixin HistoryMixin<T extends ModelEntity> on ModelEntity { final target = ReferenceTo<T>(); }`. Each entity closes `T` with its own target.

### 5.3. Abstract Base and Plain Inheritance

An abstract class extending `ModelEntity` holds fields shared by its subclasses. It has no table and is not mounted. The builder generates an interface for it, implemented by each concrete subclass. Example from `example/foundation`, where the base lives in another package:

```dart
abstract class AuditTraceEntity extends ModelEntity {
  final uuid = UuidField(autoAllocate: true).primaryKey().immutable();

  final occurredAt = DateTimeField.utc().immutable();

  final actor = StringField(maxLength: 100).nullable();
}

@Implementor(OrderStatusTraceServices)
class OrderAuditTraceEntity extends AuditTraceEntity {
  final orderNumber = StringField(maxLength: 50);

  final newStatus = EnumField<OrderStatus>();
}
```

A concrete entity can also extend another concrete entity (`class ExpressOrderEntity extends OrderEntity`). Both are mounted and **each has its own table** with all its fields. The generated interface of the subclass implements the one of the superclass. Use [§7](#7-polymorphic-entities-ancestor-and-descendants) when rows of the subclass must also be rows of the superclass.

### 5.4. Generic Entities

An entity class with type parameters is abstract: no table. Concrete subclasses close the parameters. `@InNameSpace` gives the generic base a place in the tree, and `@TokenContext.generic()` makes each subclass use the token context of the entity its parameter names:

```dart
@Searchable()
@LoadServices()
@InNameSpace(OrdersNameSpace)
@TokenContext.generic()
class ChangeLogEntity<R extends ModelEntity> extends ModelEntity
    with UuidPrimaryKeyMixin {
  ChangeLogEntity();

  final at = DateTimeField.utc();

  final target = ReferenceTo<R>(onDelete: ReferentialAction.cascade);
}

@StdEntityServices()
class OrderChangeLogEntity extends ChangeLogEntity<OrderEntity> {
  OrderChangeLogEntity();
}
```

Mount only the concrete subclasses (`final orderChangeLogs = OrderChangeLogEntity();`).

## 6. Views

### 6.1. `@ViewEntity`

A view entity has fields but no table. Its rows are computed by its services. From `example/model/lib/model/orders/order_summary.dart`:

```dart
@ViewEntity()
@Implementor(OrderSummaryServices)
class OrderSummaryEntity extends ModelEntity {
  OrderSummaryEntity();

  final order = UuidField(autoAllocate: false).primaryKey();

  final lineCount = IntField();
}
```

The service mixin overrides one or both hooks of `EntityServerServices`:

| Hook | Needed for |
| ---- | ---------- |
| `CteSource<E>? $viewSource(CallContext)` | querying the view (filter, sort): the rows as a SQL source |
| `DataLoader<E> $resolveViewKeys(CallContext, Iterable<PK> keys)` | resolving references to view rows by key |

```dart
mixin OrderSummaryServices on EntityServerServices<OrderSummary, String> {
  @override
  CteSource<OrderSummary> $viewSource(CallContext callContext) =>
      TupleSelect<OrderLine>($OrderLine.of(callContext.dataRegistry))
          .groupBy((fields) => [fields.order])
          .project(
            (fields) => $OrderSummary.project(
              order: fields.order.$keyValue,
              lineCount: fields.uuid.$count(),
            ),
          )
          .asCte();
}
```

Without `$viewSource`, a query on the view throws. Without `$resolveViewKeys`, resolving a reference to it throws. See [Queries: GROUP BY and projections](QUERIES.md#54-group-by-and-projections) and [Common table expressions](QUERIES.md#55-common-table-expressions).

A view has no row version. A view holding a `ReferenceTo` is allowed.

Full guide (hooks, queries on a view, services returning view rows): [VIEW_ENTITIES.md](VIEW_ENTITIES.md).

### 6.2. Own Key References to a View

`ReferenceTo<V>.ownKey()` on an entity points at the view row whose key equals the primary key of the holding row. It has no column. From `OrderEntity`:

```dart
final summary = ReferenceTo<OrderSummaryEntity>.ownKey();
```

The builder refuses it when:

- the target is not a `@ViewEntity`;
- the key of the view and the key of the holder hold different types (`String` and `String` here);
- the field is itself the primary key.

The field is read-only and immutable. The row is resolved through `$resolveViewKeys`.

## 7. Polymorphic Entities: Ancestor and Descendants

Use this when several entity kinds share an identity and a base table, and a query on the ancestor must return all kinds.

- The ancestor extends `ModelAncestorEntity<T>` and answers `selectorField` with one of its fields. The selector field stores the kind of each row.
- Each descendant extends `ModelDescendantEntity<T>` and calls `super` with `ancestorEntity: XEntity()` (an instance creation), its `selectorValue` (a constant) and `shareStorage`.

```dart
@StdEntityServices()
@Searchable()
class PaymentEntity extends ModelAncestorEntity<String>
    with UuidPrimaryKeyMixin {
  PaymentEntity();

  final kind = StringField(maxLength: 20);

  final amount = DecimalField(precision: 10, scale: 2);

  @override
  ScalarField<String> get selectorField => kind;
}

abstract class PaymentDescendant extends ModelDescendantEntity<String> {
  PaymentDescendant({required String kind, super.shareStorage})
    : super(ancestorEntity: PaymentEntity(), selectorValue: kind);
}

@StdEntityServices()
class CardPaymentEntity extends PaymentDescendant {
  CardPaymentEntity() : super(kind: "card", shareStorage: true);

  final cardLast4 = StringField(maxLength: 4).nullable();
}

@StdEntityServices()
class BankTransferEntity extends PaymentDescendant {
  BankTransferEntity() : super(kind: "transfer");

  final iban = StringField(maxLength: 34);
}
```

The full working example is `coverage/coverage_model/lib/model/pets/animal.dart`.

| `shareStorage` | Storage of the descendant |
| -------------- | ------------------------- |
| `true` | its fields are columns of the ancestor table. Rows of other kinds leave them empty, so declare them nullable. |
| `false` (default) | its own table holds its own fields, joined to the ancestor table by the key |

Rules:

- `selectorField` must be a getter written `get selectorField => kind;`, naming a field of the ancestor.
- An abstract class between the descendant and `ModelDescendantEntity` can name the ancestor once, as `PaymentDescendant` does. The builder follows the constructor chain until a `super` call passes `ancestorEntity`. A chain that never names it is refused.
- Mount the ancestor and every descendant in a namespace.
- There are two levels only: Dart single inheritance prevents a class from being both an ancestor and a descendant.
- The generated interface of a descendant implements the ancestor's (`CardPayment implements Entity, Payment`). Its search class extends the ancestor's ([Searches](SEARCHES.md#23-entity-inheritance)).
- The descendant uses the key of the ancestor. Do not declare another primary key.

## 8. Tuples

A tuple describes a typed row shape with no table, no services and no search. It is the row type of a projection or of a service returning computed rows (`DataLoader<CustomerStat>`).

```dart
class CustomerStatTuple extends ModelTuple {
  CustomerStatTuple();

  @override
  String get tupleKey => "orders.customerStat";

  final customer = ReferenceTo<CustomerEntity>();

  final orderCount = IntField();

  final totalSpent = DoubleField();
}
```

- `tupleKey` must be a getter returning a constant string. The builder refuses anything else.
- The key must be unique across the model and its sub-models, and differ from every entity path. A clash is refused when the `DataRegistry` is built.
- Mount the tuple in a namespace like an entity (`final customerStats = CustomerStatTuple();`).
- Every generated interface exposes `static const String tupleKey`: the declared key for a tuple (`CustomerStat.tupleKey == "orders.customerStat"`), the path for an entity (`Order.tupleKey == "orders/orders"`). `DataRegistry.tupleDefByKey` resolves both. A row carries this key on the wire under `$entity` ([Data exchange](AUTO_JSON.md#5-wire-form-of-rows)).

See [Queries: GROUP BY and projections](QUERIES.md#54-group-by-and-projections).

## 9. Row Version Column

Sing adds a column `_version INT4 NOT NULL DEFAULT 0` to the table of every **versioned** entity. Sing bumps it on each write. It is **not a field**: it is absent from `fields`, the model definition, searches and OpenAPI.

An entity is versioned when it is stored in its own table and has a single-field primary key. Views, abstract entities and entities with a composite key are not versioned. In a polymorphic family, the column lives in the ancestor table only. A `shareStorage` descendant reads and bumps it there. A descendant with its own table reaches it through the join (`ServerEntityDef.rowVersionStorage`, `isVersioned`, `carriesRowVersion`).

A field whose column would be named `_version` is refused when the table is built. The version travels as row metadata: see [DataRow row version](DATA_CLASSES.md#4-row-version) and [optimistic locking](QUERIES.md#38-optimistic-locking-row-version).

## 10. Database Names

| Object | Name |
| ------ | ---- |
| Schema | `@DbName` of the nearest namespace carrying one, else `public` |
| Table | the generated entity name in snake_case: `OrderLineEntity` -> `order_line` |
| Column | the field name in snake_case, or `@DbName` / `.withDbName()` |
| Enum table | `enum_<ident>` ([Enums](FIELD_TYPES.md#26-enums)) |

A name that is a reserved SQL word gets a trailing `_`: `OrderEntity` -> table `order_`. A `shareStorage` descendant uses the table of its ancestor.

Renaming an entity class or a field renames the table or column. Plan it as a migration ([Migrations](MIGRATIONS.md), [renaming an entity](SERVICES.md#92-entity-renamed)).

## 11. Common Mistakes

| Mistake | Fix |
| ------- | --- |
| `StringField()` | `maxLength` is required: `StringField(maxLength: 100)` |
| `get indices => [...]` | the method is `getIndicies()` |
| `EnumField<MyEnum>` on a plain enum | make the enum a `DbEnum` ([§2.6 of Entity Fields](FIELD_TYPES.md#26-enums)) |
| `@DbName("orders")` on an entity class | not read; put `@DbName` on the namespace (schema) or the field (column) |
| `@serverSideOnly` on an entity class | put it on the namespace property that mounts the entity |
| `@AccessToken.xxx` on a field | use the `accessToken:` constructor parameter |
| `ReferenceTo<X>().autoIndexed(false)` | `ReferenceTo<X>(autoIndex: false)` |
| `final email = sharedEmailField;` | write the constructor in place, or call a one-expression factory ([§5 of Entity Fields](FIELD_TYPES.md#5-how-a-field-may-be-written)) |
| `ReferenceTo<Customer>()` | name the definition class: `ReferenceTo<CustomerEntity>()` |
| `final status = StringField(maxLength: 20);` for a closed set of values | `EnumField<OrderStatus>()` |
| `createdAt` without `.immutable()` | audit and natural-key fields should be `.immutable()` |
| a long text in `StringField` | values longer than `maxLength` are silently truncated; use `MemoField` or `truncateIfTooLong: false` |
| `IntField()` for a quantity | state the bounds: `IntField(lowBound: 1)` |
| `@StdEntityServices()` on an entity without primary key | add a single-field primary key ([§4.2](#42-primary-key)) |
