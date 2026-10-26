# Data Exchange Between Client and Server

## 1. Principle

A Sing client and a Sing server exchange JSON. JSON only knows strings, numbers, booleans, `null`, objects and arrays ([RFC 8259](https://datatracker.ietf.org/doc/html/rfc8259)). Every other Dart type crosses the wire through a **JSON type adapter** that both sides share. The builder generates the adapters of the model types. Application code never writes JSON by hand for service parameters and results.

When the receiver does not know the exact type in advance, the JSON carries a type marker: `$kind` for search criteria ([§6](#6-search-criteria)), `$entity` for rows and references ([§5](#5-wire-form-of-rows)). Model identifiers cannot contain `$`, so these keys never collide with a field name.

## 2. Types That Can Travel

A service parameter, a service result, a property of a `@serializable` class and a typed `JsonField<T>` can use:

| Kind | Types |
| ---- | ----- |
| Scalars | `String`, `int`, `double`, `bool`, `DateTime`, `UtcDateTime`, `LocalDateTime`, `DateOnly`, `TimeOnly`, `Duration`, `Decimal`, `DateRange`, `DateTimeRange`, `Uint8List` |
| Enums | any enum the model reaches: field type, service signature, `@serializable` class property ([§3.3](#33-enums)) |
| Model data | `Reference<X>`, `DataRow<X>`, `X$Instance` (`DataRowValues<X>`), `DataPacket<X>`, `DataLoader<X>` (result), `Expect<X>`, `X$Search` |
| Analysis | `CubeDefinition`, `CubeResult` |
| Classes | classes annotated `@serializable` ([§4](#4-serializable-classes-dtos)) |
| Containers | `List<T>`, `Iterable<T>`, `Set<T>`, `Map<String, T>` of any type above |

Each type is served by a `JsonTypeAdapter<T>` (`sing_core/lib/src/types/json_type_adapter.dart`) with `toJson(T)`, `fromJson(JsonReader)` and `jsonSchema` (for OpenAPI). `JsonTypeAdapters.typed<T>()` returns the registered adapter of `T` and throws when none is registered. Generated model layers register theirs through `ModelLayer.jsonAdapters` when the `DataRegistry` is built.

## 3. Scalar Forms

### 3.1. Dates, Times and Durations

| Type | JSON |
| ---- | ---- |
| `DateTime`, `UtcDateTime`, `LocalDateTime`, `DateOnly` | ISO-8601 string |
| `TimeOnly` | integer, microseconds since midnight |
| `Duration` | integer, microseconds |
| `DateRange`, `DateTimeRange` | object with the bounds, or `{"empty": true}` |

### 3.2. Numbers and Binary

| Type | JSON |
| ---- | ---- |
| `Decimal` | string (exact value) |
| `Uint8List` | base64 string |

### 3.3. Enums

An enum value travels as its `name`. This is also true for a `DbEnum`: its `key` is used in the database only. The builder registers a `JsonEnumAdapter<E>` for every enum it reaches. An enum reached by nothing else can be registered with `@serializable` on the enum:

```dart
@serializable
enum QuoteBasis { flat, weighted, negotiated }
```

## 4. Serializable Classes (DTOs)

`@serializable` (or `@Serializable()`) on a class lets it travel. The class must be declared in the `lib/` of the model package or of the `common` package (`commonPackagePath`). Put it in `common` when the client uses it. Example from `example/common/lib/src/dto/shipping_quote.dart`:

```dart
@serializable
class ShippingQuote {
  const ShippingQuote({
    required this.carrier,
    required this.amount,
    required this.basis,
    required this.options,
    this.comment,
  });

  final String carrier;
  final Decimal amount;
  final QuoteBasis basis;
  final List<String> options;
  final String? comment;
}
```

The builder writes the JSON form from the fields when the class follows these rules:

- the class is not abstract and no other class extends it;
- it has an unnamed, non-factory constructor with **named** parameters only;
- every public instance field is `final` and filled by a constructor parameter of the same name;
- every field type can travel ([§2](#2-types-that-can-travel)), including model types (`Order$Instance`, `Order$Search`) and other `@serializable` classes.

A field is optional on the wire when its constructor parameter is nullable.

A class can state its own form instead, with **both** a `fromJson` factory and a `toJson` method:

```dart
@serializable
class TrackingCode {
  const TrackingCode(this.value);

  factory TrackingCode.fromJson(JsonReader json) => TrackingCode(json.asString);

  final String value;

  Object toJson() => value;
}
```

The factory takes a `JsonReader`. It reaches the data registry through `json.dataRegistry` when it needs it.

A class that breaks a rule, or declares only one of `fromJson` and `toJson`, is **skipped with a warning**: it is not registered, and a service using it fails at run time. Read the `sing_emit` warnings after each build.

`@serializable` on a superclass does not register its subclasses.

## 5. Wire Form of Rows

### 5.1. `DataRow`

A row travels as an object with its field values, each written by the adapter of its field, plus metadata keys:

| Key | Content |
| --- | ------- |
| `$entity` | the `tupleKey` of its entity (its path, `orders/orders`) or tuple ([Tuples](DATA_MODEL.md#8-tuples)) |
| `$state` | the row state name (`initial`, `inserted`, `updated`, `deleted`) |
| `$updated` | the names of the fields the row means to write, when some are updated |
| `$rowVersion` | the [row version](DATA_CLASSES.md#4-row-version) read with the row, when known |
| `$checkRowVersion` | `true` when the next update must check the version |

```json
{"$entity": "orders/orders", "$state": "updated", "$rowVersion": 3,
 "uuid": "…", "status": "shipped", "$updated": ["status"]}
```

- Fields without a value, server-only fields and fields without a column (`@SearchOnlyField`, own key references) are not written.
- On reading, `$updated` cannot mark a primary key or an immutable field as updated.

### 5.2. `Reference`

```json
{"$entity": "orders/customers", "primaryKey": "…"}
```

A row not inserted yet has no key. Its reference carries a `uuid` instead, which the packet uses to match it.

### 5.3. `DataPacket`

A `DataPacket` (the result of a `DataLoader`) travels as:

```json
{"$entity": "orders/orders", "resultRows": 2, "paginated": true,
 "dataRows": [ … ], "maskedRefs": [ … ]}
```

- `dataRows` holds the `resultRows` result rows first, then the rows reached through references.
- `paginated` is written only when `true`. `maskedRefs` (references the caller may not read) only when not empty.
- `$entity` is absent for a packet typed `DataPacket<Entity>`.

## 6. Search Criteria

Every `SearchOn` criterion travels as an object with a `$kind` key (`SearchOn.kindKey`) naming its class, next to its own state. This long form is the only accepted one.

```json
{"$kind": "string", "text": "lyo", "type": "contains", "caseSensitive": true}
{"$kind": "int", "value": 10, "other": 20, "type": "between"}
{"$kind": "all", "conditions": [{"$kind": "equal", "value": 1}, {"$kind": "null", "notNull": true}]}
```

`SearchOnField.fromJson<V>(json)` rebuilds a criterion from `$kind`, `V` being the field value type. A generated `X$Search` writes its non-empty criteria and its `@SearchOnlyField` values, and refuses an unknown key on reading (`SearchOnEntity.checkedMap`). Criteria themselves are described in [Searches](SEARCHES.md).
