# Data Encapsulation Classes

## 1. The `DataRowValues` Class

### 1.1. What is the purpose?

This is the most commonly used class for reading/writing data from/to the database. The implementation of this class is quite technical and cryptic. However, at each model rebuild, extensions are generated (e.g., `extension DataRowValues$Order on sing.DataRowValues<Order> { ...}` with its synonym of `Order$Instance` defined at build time) that ensure Dart compiler control of entity field access (does the field exist?) and type-safety (e.g., `orderLine.quantity = "one"` is not allowed as in non-typed languages). Examples with `Order` entity definition as   :
```dart
class OrderEntity extends ModelEntity with UuidPrimaryKeyMixin {

  // Immutable order details
  final orderNumber = StringField(
    maxLength: 20,
    immutable: true,
  ).withLib("Order number");

  final orderDate = DateTimeField.utc().immutable();

  // ...Other declarations
}
```

```dart
final dataValues = ...; // obtains a DataRowValues<Order> instance

// Dart compiler : OK. "orderNumber" is a property of Order$Instance and "QF-1254-5689" is a valid String value.
dataValues.orderNumber.value = "QF-1254-5689";   

// Dart compiler : KO. "orderNumber" is a property of Order$Instance but integer value 123456789 is not a valid String value.
dataValues.orderNumber.value = 123456789;   

// Dart compiler : KO. "orderNum" is NOT a property of Order$Instance .
dataValues.orderNum.value = "QF-1254-5689";   

// Dart compiler : KO. orderDate is a property of Order$Instance but DateTime is not a valid UtcDateTime value.
dataValues.orderDate = DateTime.now();

// Dart compiler : OK. orderDate is a property of Order$Instance and UtcDateTime.now() is a valid UtcDateTime value.
// Local/UTC datetimes are never mixed.
dataValues.orderDate = UtcDateTime.now();
```

**Consequence**:
- after any model modification and rebuild, **the Dart compiler** reports all anomalies (field displayed on a screen but no longer exists, type inconsistency in an assignment, etc.).
- all code manipulating data through typed DataRowValues (e.g., `DataRowValues<Order>` or its equivalent `Order$Instance`) is **secured by the Dart compiler**.
- this is true in service implementations as well as in server or client applications.
- the developer can more easily consider modifying or refactoring their model.

### 1.2. Technical Reference

**Package:** `sing_core`

#### Key Characteristics

##### Generic Type Parameter
- `E extends Entity` - ensures compile-time type safety
- Example: `DataRowValues<Order>` or its synonym `Order$Instance`

##### Internal Structure
- Wraps a `DataRow<E>` instance (stored in `$dataRow`)
- Delegates field access through operator `[]`
- Returns `FieldValue` objects (not raw values)

##### State Access
- `$state` - returns `DataRowState` (initial, inserted, updated, deleted)
- `$asReference` - returns entity reference

##### Field Access
```dart
DataRowValues<Order> order = ...;
FieldValue value = order['fieldName'];  // Base access
```

**Generated extensions** provide direct property access:
```dart
// Generated: extension DataRowValues$Order on DataRowValues<Order>
order.orderNumber.value = "QF-123";  // Type-safe, compiler-checked
```

##### Equality & Hashing
- Based on **primary key fields** only
- If no PK: uses object identity
- Two rows with same PK values are considered equal

##### Value Extraction
- Implements `EntityFieldsValueExtractor<E>`
- `$extract()` - extracts field values following field chains
- Handles null values, missing values, and reference navigation

#### Important Notes for LLM Agents

1. **Never instantiate directly** - obtain instances through Sing-generated code
2. **Type safety** - `DataRowValues<E>` ensures field names and types are validated at compile time
3. **Extensions** - generated at build time provide property-like access (e.g., `order.orderNumber`)
4. **State tracking** - automatically tracks insert/update/delete operations via `$state`
5. **Reference navigation** - supports chained field access across entity references

### 1.3. Common Usage Pattern

## 4. DataLoader Class

### 4.1. Overview
The DataLoader class is central in the Sing framework (like DataRowValues) for everything related to data access, both through [queries](QUERIES.md) and calls to [services](SERVICES.md).

In a client application for example:
```dart
final orders = $Orders.services(dataRegistry).search(status:Search.equal(OrderStatus.pending));
```
or in a server-side service:
```dart
final orders = $Orders.query(callContext).load.where( where: (fields) => fields.status.$equal( OrderStatus.pending));
```
the `orders` variable is of type `DataLoader<Order>`. `DataLoader` encapsulates the **promise** to obtain data but does not encapsulate **any data**. To obtain data and/or have any impact on the data, you must call one of the `DataLoader<E>` methods:
- **listValues({int? limit})**: `Future<List<DataRowValues<E>>>`. Very often used.
- **list({int? limit})**: `Future<List<DataRow<E>>>`. Less frequent.
- **one()**: `Future<DataRowValues<E>?>`
- **exactlyOne()**: `Future<DataRowValues<E>>`. Throws an exception if no or multiple rows returned.
- **execute** and **count**
- **execute()**: Do the job but don't return any value.
- **count()**: Do the job and return affected row count.

Examples (on server side):
```dart
final pendingCount = await $Order.query(callContext).load
  .where(where: (fields) => fields.status.$equal(OrderStatus.pending))
  .count();

// Exécute sans récupérer de données
await $Order.query(callContext).delete
  .where(where: (fields) => fields.status.$equal(OrderStatus.cancelled))
  .execute();
```

Examples (on client side):
```dart
// We are sure that an order with primary key uuid exists.
final order = await $Orders.services(dataRegistry).load.thisKey(uuid).exactlyOne();

// Maybe an order with primary key uuid.
final order = await $Orders.services(dataRegistry).load.thisKey(uuid).one();

// List of pending orders
final pendingOrders = await $Orders.services(dataRegistry).search(status:Search.equal(OrderStatus.pending)).listValues();
```

### 4.2. Façonner les résultats

#### Limiter les champs retournés
```dart
final orders = await $Order.query(callContext).load
  .fields((fields) => [
    fields.orderNumber,
    fields.totalAmount,
    fields.customer.name,  // Navigation dans la référence
  ])
  .listValues();

// Note : les clés primaires sont TOUJOURS retournées même si non demandées
```

#### Eager loading de références
```dart
final orders = await $Order.query(callContext).load
  .resolve((fields) => [
    fields.customer,        // Charge la référence customer
    fields.customer.address // Charge aussi l'adresse du customer
  ])
  .listValues();

// Accès sans requête supplémentaire
for (final order in orders) {
  final customerName = order.customer.dataRowValues?.name.value;
}
```

#### Tri des résultats
```dart
// Tri ascendant
.sort((fields) => [fields.orderDate, fields.orderNumber])

// Tri descendant (préfixe -)
.sort((fields) => [-fields.orderDate])

// Tri mixte
.sort((fields) => [fields.status, -fields.totalAmount])

// Note : avec limit, la clé primaire est ajoutée automatiquement à la fin
```
#### Synthèse

| Method         | Purpose                                                                                                                                                                                                                                                                                                                                                                                                 |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fields(...)`  | Limit the amount of data exchanged between client and server or between server and database by requesting only the necessary data                                                                                                                                                                                                                                                                       |
| `resolve(...)` | Return the requested data (e.g., `orderLines`) but also the data associated with related entities in the same call (and therefore **the same database transaction** for client->server calls)                                                                                                                                                                                                           |
| `sort(...)`    | Sort data before returning it. In [queries](QUERIES.md), data is sorted **by the database**. If the `limit` parameter is provided to the call of `listValues()` or `list()`, the framework **systematically** adds the primary key (if it exists) of the entity **at the end** of the list of sort fields. If the entity does not define a primary key and no sort is requested, an exception is thrown |

### 4.3. Complete example

```dart
final orders = $Order
                   .query(callContext)
                   .load
                   .where( where: (fields) => fields.status.$equal( OrderStatus.pending))
                   .fields( (fields) => [fields.orderNumber, fields.customer.name])
                   .resolve( (fields) => [fields.customer])
                   .sort( (fields) => [-fields.orderData])
                   .listValues(limit:100);
```

### `DataRowValues` and `DataLoader`

The `DataRowValues` and `DataLoader` classes alone ensure a major part of Sing's requirements: guaranteeing controlled access to application data. The impacts of any modification in the data model definitions will be clearly visible (by the compiler) as soon as the model is rebuilt.

#### Important Note
If the `fields(...)` method is used before reading data (`listValue()` or `list()`), the returned data **will not contain** all entity fields but only those explicitly specified (exception: primary keys are **always** returned even if not requested by `fields(...)`). Example:
```dart
final order = await $Orders
               .services(dataRegistry)
               .load
               .thisKey(uuid)
               .fields( (fields) => [fields.orderNumber, fields.custom.name])
               .exactlyOne();
final date = order.orderData.value;            // Fake value
```

## 2. DataRow Class

`DataRow<E>` is an essentially technical class. It encapsulates a record of entity `E`, the value of its fields (`values` property), and its status (`state` property).

| From               | Property/Method | To                 |
| ------------------ | --------------- | ------------------ |
| `DataRow<E>`       | `.values`       | `DataRowValues<E>` |
| `DataRowValues<E>` | `.$dataRow`     | `DataRow<E>`       |

