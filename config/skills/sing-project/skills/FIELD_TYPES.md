# Entity Fields

A field is a `final` instance property of an entity, tuple or entity mixin definition. Its value is a field object from `sing_core` (`sing_core/lib/src/std/field_def/`), re-exported by `sing_model`. For where fields live in the model, see [Building the Data Model](DATA_MODEL.md).

```dart
final orderNumber = StringField(maxLength: 50).immutable();
```

## 1. Rules That Apply to Every Field

- A field is **not null** by default. Add `.nullable()` to accept `null`.
- The property name is the field name. It must not contain `$`.
- The column name is the field name in snake_case (`totalAmount` -> `total_amount`). A name that is a reserved SQL word gets a trailing `_` (`where` -> `where_`). `@DbName("...")` or `.withDbName("...")` forces the column name.
- `_version` is reserved for the [row version column](DATA_MODEL.md#9-row-version-column). A field stored in a column named `_version` is refused when the table is built.
- Constructor arguments are read from the live object at run time: any Dart expression works (`maxLength: kNameLength`). Only the **shape** of the declaration is constrained (see [§5](#5-how-a-field-may-be-written)).
- Every field constructor accepts `accessToken:` (except the `DateTimeField` factories): a user without this token does not see the field.

## 2. Field Types

Column types are the PostgreSQL types emitted by `sing_server/lib/src/db/sql_provider.dart`.

| Field | Dart value | Column | Main parameters |
| ----- | ---------- | ------ | --------------- |
| `StringField` | `String` | `VARCHAR(maxLength)` | `maxLength` (required), `minLength`, `truncateIfTooLong`, `trim`, `singleLine`, `charCase`, `padding`, `padWith`, `regExp`, `collation`, `defaultValue` |
| `MemoField` | `String` | `TEXT` | `defaultValue` |
| `IntField` | `int` | `INT2` / `INT4` / `INT8` | `lowBound`, `highBound`, `width`, `defaultValue` |
| `OidField` | `int` | `SERIAL` / `BIGSERIAL` | `autoIncrement` (default `true`), `lowBound`, `highBound` |
| `DoubleField` | `double` | `FLOAT8` (`FLOAT4` with `singlePrecision: true`) | `lowBound`, `highBound`, `decimals`, `singlePrecision`, `defaultValue` |
| `DecimalField` | `Decimal` | `NUMERIC(precision,scale)` or `NUMERIC` | `precision`, `scale`, `defaultValue` |
| `BoolField` | `bool` | `BOOLEAN` | `defaultValue` |
| `DateTimeField.utc()` | `UtcDateTime` | `TIMESTAMPTZ` | `defaultValue` |
| `DateTimeField.local()` | `LocalDateTime` | `TIMESTAMP` | `defaultValue` |
| `DateTimeField.dateOnly()` | `DateOnly` | `DATE` | `defaultValue` |
| `TimeField` | `TimeOnly` | `TIME` | `defaultValue` |
| `DateRangeField` | `DateRange` | `DATERANGE` | none |
| `DateTimeRangeField` | `DateTimeRange` | `TSTZRANGE` | none |
| `DurationField` | `Duration` | `INT8`, or `FLOAT4` when `withDecimals` | `storeAs` (required), `withDecimals` (required) |
| `UuidField` | `String` | `UUID` | `autoAllocate` (default `false`), `defaultValue` |
| `UuidField.asString` | `String` | `VARCHAR(200)` | same as `UuidField` |
| `EnumField<E>` | `E` (a `DbEnum`) | `VARCHAR` or `INT2`, foreign key to the enum table | `defaultValue`, `onDelete` |
| `BinaryField` | `Uint8List` | `BYTEA` | `defaultValue` |
| `JsonField` / `JsonField<T>` | `Object` / `T` | `JSONB` | `defaultValue` |
| `ArrayField(itemField)` | `Iterable<T>` | `<item column> ARRAY` | `minItems`, `maxItems` |
| `ReferenceTo<XEntity>` | `Reference<X>` | type of the target key, foreign key | see [§2.9](#29-references) |
| `HashField` | `String` | `VARCHAR(1024)` | `defaultValue` |
| `SecretField` | `String` | `TEXT` | `defaultValue` |
| `ErrorField` | `String` | `TEXT` | `defaultValue` |
| `StackTraceField` | `String` | `TEXT` | `defaultValue` |

### 2.1. Strings

```dart
final name = StringField(maxLength: 200);
final description = StringField(maxLength: 2000).nullable();
final sku = StringField(maxLength: 100, charCase: .upper, collation: "C");
```

Behavior of `StringField` on assignment (`sing_core/lib/src/std/field_def/string.dart`):

- `trim` (default `true`) removes leading and trailing spaces.
- `charCase` (`StringCharCase.normal`, `lower`, `upper`, `capitalize`) changes the case.
- `singleLine` (default `true`) rejects a value with a line break. Use `MemoField` for multi-line text.
- `minLength` defaults to `1`: an empty string is rejected. Represent "no value" with `null` on a nullable field.
- `truncateIfTooLong` defaults to `true`: a value longer than `maxLength` is **silently cut**. Set it to `false` to get an error instead.
- `padding` (`StringPadding.none`, `left`, `right`) pads the value to `maxLength` with `padWith`.
- `regExp`: a value that does not match is rejected.
- `collation` sets the column collation. A `ModelIndex` on the field uses it too.

`MemoField` has no length limit and no check.

### 2.2. Numbers

```dart
final quantity = IntField(lowBound: 1);
final lineIndex = IntField().immutable();
final unitPrice = DoubleField();
final amount = DecimalField(precision: 10, scale: 2);
```

- `lowBound` and `highBound` are checked on assignment.
- `IntField` column width: `width:` (2, 4 or 8 bytes) wins. Without it, the column is `INT4`, or `INT8` when a bound exceeds 2^32 in absolute value. The bounds never give `INT2`.
- `DoubleField(decimals: n)` rounds the value to `n` decimals on assignment.
- Use `DecimalField` for money when exact decimal arithmetic matters. Its value type is `Decimal` (`sing_core`), not `double`.
- `OidField` is an auto-increment integer key, filled by the database.

### 2.3. Dates and Times

```dart
final orderDate = DateTimeField.utc().immutable();
final deliveryDay = DateTimeField.dateOnly().nullable();
final meetingAt = DateTimeField.local();
final openingTime = TimeField();
```

Choose the factory by meaning:

| Factory | Use for | Rule |
| ------- | ------- | ---- |
| `DateTimeField.utc()` | timestamps: creation, payment, shipment | stored with time zone; a client may convert it for display |
| `DateTimeField.local()` | a wall-clock time tied to a place (a meeting at a known site) | stored and displayed as is, never converted |
| `DateTimeField.dateOnly()` | a calendar day (birth date, delivery day) | no time part, never converted |

The three factories take only `fieldName`, `fieldProps` and `defaultValue`. Server code reads the client clock through `CallContext.clientClock`.

`DateRangeField` and `DateTimeRangeField` hold a range (`DateRange`, `DateTimeRange`). They cannot be GET (URL) parameters.

### 2.4. Durations

```dart
final preparationTime = DurationField(
  storeAs: StoreDuration.asMinutes,
  withDecimals: false,
);
```

`storeAs` is one of `asDays`, `asHours`, `asMinutes`, `asSeconds`, `asMilliseconds`, `asMicroseconds`. The column stores the duration in this unit: an integer (`INT8`), or a `FLOAT4` when `withDecimals` is `true`. With `withDecimals: false`, the part below the unit is lost.

### 2.5. UUIDs

```dart
final uuid = UuidField(autoAllocate: true).primaryKey().immutable();
```

`autoAllocate: true` gives each new row a fresh UUID. With `false` (the default), the value must be set by the code. The column type is `UUID`; `UuidField.asString(...)` stores it as `VARCHAR(200)`.

### 2.6. Enums

`EnumField<E>` only accepts an enum that implements `DbEnum` (`sing_core/lib/src/types/db_enum.dart`). Each value carries:

- `uuid`: a stable, non-empty, unique identity. It keeps the stored rows attached to the value when the value is renamed.
- `key`: what data columns store. It must be unique.

Two storage kinds exist. Use the matching mixin:

| Mixin | `key` | Column |
| ----- | ----- | ------ |
| `DbStringEnumMixin` | `name` | `VARCHAR`, at least 8 characters |
| `DbIntEnumMixin` | `index` (override `key` to choose) | `INT2` |

Declare the enums in the `common` package (`common/lib/src/enums/`), exported by `common/lib/common.dart`. Example from `example/common/lib/src/enums/orders.dart`:

```dart
enum OrderStatus with DbStringEnumMixin {
  pending("387006cd-ca97-4046-b1c2-19752550b01e"),
  processing("b0fa9a4a-7f41-4950-9c18-0a353191cc61"),
  shipped("7d1cdc00-3b0c-4508-8f14-383b057f7068");

  const OrderStatus(this.uuid);

  @override
  final String uuid;
}
```

```dart
final status = EnumField<OrderStatus>(defaultValue: .pending);
final previousStatus = EnumField<OrderStatus>().nullable();
```

- Generate a new UUID for each new value. Never reuse or change an existing one.
- Each `DbEnum` gets a table `enum_<ident>` whose rows follow the enum values. The enum field column has a foreign key to it (`ON UPDATE CASCADE`).
- `onDelete` (default `ReferentialAction.error`) is the `ON DELETE` rule of the foreign key to the enum table. `setToNull` needs a nullable field. `setDefault` needs a `defaultValue`.
- `@DbEnumKey(key: ..., ident: ...)` on the enum sets its stable type key (default: the Dart name) and its table name (default: the snake_case of the Dart name). Use `key` to rename the enum without losing its table.
- A `DbEnum` that implements neither `DbStringEnum` nor `DbIntEnum` is skipped with a warning.
- On the wire, an enum value always travels by its `name`, whatever its `key` ([Data exchange](AUTO_JSON.md#33-enums)).

A plain Dart enum (without `DbEnum`) cannot be an `EnumField`. It can still travel as a service parameter, a service result or a property of a `@serializable` class.

### 2.7. JSON and Arrays

```dart
final options = JsonField().nullable();
final quote = JsonField<ShippingQuote>().nullable();
final tags = ArrayField(StringField(maxLength: 20)).nullable();
final quantities = ArrayField(IntField(), maxItems: 10);
```

- `JsonField()` holds free JSON. `JsonField<T>()` holds a `T` written through the JSON adapter of `T`: a `@serializable` class ([Data exchange](AUTO_JSON.md#4-serializable-classes-dtos)).
- `ArrayField` takes the item field as its first argument, written in place. The item field gives the item type and checks. The array is never a primary key.

### 2.8. Server-Side Secrets and Diagnostics

| Field | Behavior |
| ----- | -------- |
| `HashField` | One-way hash (passwords). The value is hashed on assignment through the `PasswordHasher` set with `Cryptography.useHasher` at server start. Always server-only. |
| `SecretField` | Reversible secret, encrypted at rest through the `SecretCipher` set with `Cryptography.useCipher`. Always server-only. |
| `ErrorField` | Text holding an error. `fieldValue.assignError(e)` (extension `ErrorFieldAssignment`) stores an `AppError` as its JSON `{code, params}` form. |
| `StackTraceField` | Text holding a stack trace. |

Without a configured cipher or hasher, `SecretField` and `HashField` throw on store and read (`sing_core/lib/src/std/field_def/cryptography.dart`).

### 2.9. References

```dart
final customer = ReferenceTo<CustomerEntity>(onDelete: ReferentialAction.error);
final order = ReferenceTo<OrderEntity>(onDelete: .cascade);
final shippingAddress = ReferenceTo<AddressEntity>(
  onDelete: ReferentialAction.error,
).nullable();
```

`ReferenceTo<T>` names the **definition** class of the target entity (`CustomerEntity`), not the generated one. The target must have a single-field primary key. The column takes the type of that key.

| Parameter | Default | Effect |
| --------- | ------- | ------ |
| `onDelete` | `ReferentialAction.error` | `error`, `cascade`, `setToNull` (field must be nullable), `setDefault` |
| `autoIndex` | `true` | creates an index on the column |
| `declareForeignKey` | `true` | declares the SQL foreign key |
| `deferred` | `false` | checks the constraint at commit time |

`ReferenceTo<T>.ownKey()` declares a reference with **no column**: it points at the row of a view keyed by the primary key of the row holding it. See [Views](DATA_MODEL.md#62-own-key-references-to-a-view).

Relationship patterns (one-to-many, many-to-many, self references, cascade choices) are in [Relationships](CONCEPTS_RELATIONSHIPS.md).

## 3. Modifiers

A modifier is a method chained after the constructor. It returns a modified copy.

| Modifier | Effect |
| -------- | ------ |
| `.nullable()` | accepts `null` (column `NULL`) |
| `.primaryKey()` | part of the primary key. One primary key field makes the entity referenceable. |
| `.immutable()` | assigned once: a second assignment with another value throws, and an update sent by a client never writes it |
| `.readOnly()` | sent to clients, but a client write through the standard CRUD services is dropped. Server code can still write it. |
| `.serverOnly()` | never sent to clients (same effect as `@serverSideOnly`) |
| `.withDbName("col")` | forces the column name |
| `.withLib("Label")` | short label, published in the model definition and OpenAPI |
| `.withDescr("Text")` | description |
| `.tagged(tag)` | attaches a `FieldTag` (see [§4](#4-field-annotations)) |

Each flag modifier takes an optional boolean: `.nullable(false)` clears what an earlier `.nullable()` set.

`ReferenceTo` also has `.autoIndexed(...)`, but the builder does not read it and stops the generation. Use the `autoIndex:` constructor parameter.

Do not pass `fieldProps: FieldProps(...)` to a constructor to set these flags. The builder only sees the modifiers, so the generated types would not match the field.

## 4. Field Annotations

| Annotation | Effect |
| ---------- | ------ |
| `@serverSideOnly` | the field does not exist on clients and is never written to JSON |
| `@DbName("col")` | forces the column name |
| `@AutoSearch.no` | leaves the field out of the generated search class ([Searches](SEARCHES.md#12-field-annotations)) |
| `@SearchOnlyField()` | the field has **no column**. It is only a parameter of the search class, read by `$applySearchOnlyFilters` ([Searches](SEARCHES.md#6-server-filters-applysearchonlyfilters)) |
| `@NoReverseSearch()` | on a reference: no `whereXxx` reverse criterion on the target's search class ([Searches](SEARCHES.md#52-reverse-criteria-wherexxx)) |
| `@Tag(myTag)` | attaches a `FieldTag`. `myTag` must be a top-level constant or a static constant of a class. Sing gives tags no meaning: the application reads them from `field.fieldProps.tags`. |

```dart
const redacted = FieldTag("redacted");

class CustomerEntity extends ModelEntity with UuidPrimaryKeyMixin {
  @Tag(redacted)
  final phone = StringField(maxLength: 50).nullable();

  @serverSideOnly
  final internalNote = StringField(maxLength: 500).nullable();

  @SearchOnlyField()
  final hasOpenOrder = BoolField();
}
```

`@AccessToken.xxx` written on a field is **not** read. Use the `accessToken:` constructor parameter.

## 5. How a Field May Be Written

The builder reads the model source with the Dart analyzer. It never runs it. A field is read from the expression that initializes it, and only these shapes are accepted (`sing_builder/lib/analyser/fields/field_chain.dart`):

1. a constructor call, named or not: `StringField(maxLength: 50)`, `UuidField.asString()`;
2. a static factory of a field class: `DateTimeField.utc()`;
3. a modifier from [§3](#3-modifiers) applied to one of these: `StringField(maxLength: 50).nullable()`;
4. a call to a function or static method whose body is a single expression (`=> ...`). The builder reads its body;
5. inside such a function: a parameter (its argument or its default value), and a conditional whose condition is a parameter bound to a `true` or `false` literal.

```dart
// Accepted: a constructor, then two modifiers.
final email = StringField(maxLength: 120).nullable().immutable();

// Accepted: a factory written as one expression.
Field<String> shortCode({bool optional = false}) =>
    optional ? StringField(maxLength: 20).nullable() : StringField(maxLength: 20);

final promoCode = shortCode(optional: true);

// Refused: a field read from a variable.
final copy = sharedEmailField;

// Refused: a modifier the builder does not know.
final address = ReferenceTo<AddressEntity>().autoIndexed(false);
```

Any other shape stops the generation with an error naming the file and line. A field without an initializer is refused too.

Static properties and getters are not fields. A getter that answers a field (`get selectorField => kind`) names an existing field and adds none.

## 6. Default Values

```dart
final isActive = BoolField(defaultValue: true);
final status = EnumField<OrderStatus>(defaultValue: .pending);
final reorderDelay = IntField(defaultValue: 30);
```

- The default becomes the column `DEFAULT`.
- Assigning `null` to a field with a default gives it the default value.
- A non-nullable field without default must get a value before insert. Otherwise the insert fails.
- `DurationField`, `DateRangeField`, `DateTimeRangeField` and `ArrayField` have no `defaultValue` parameter.
