# Data Exchange Between Client and Server

## 1. JSON and Type Encoding

When exchanging data between a Sing client application and a Sing HTTP server, various types of data must be exchanged. JSON format is used for these exchanges, which poses the problem of encoding and decoding beyond the data types allowed by [the JSON standard](https://datatracker.ietf.org/doc/html/rfc8259):
- string
- int
- double
- bool
- null
- object (untyped)
- array (untyped items)

For all other data types, there **must** be a shared convention between client and server on how to encode (and thus decode) all other data structures. Example: a date/time can be encoded as a character string in ISO-8601 format or as a number of milliseconds elapsed since a reference date/time, or as...

A convention must therefore exist between client and server. It is necessary but sufficient **only** when the decoder knows with certainty the final type of the data to be decoded. Example: the convention indicates that a date/time is exchanged as a character string in ISO-8601 format; the sender sends a JSON object of type `string` and the decoder, **knowing that a date/time is expected**, decodes the string received.

## 2. Type Information in JSON

If the expected data type is not strictly defined, another mechanism must exist. Example: in Sing, standard search services define a [`SearchOnField`](SEARCHES.md) parameter for each entity field. There are several classes derived from `SearchOnField` that a sender can send (e.g. `SearchEquality`, `SearchNull`, `SearchIn`, etc.). In these cases, to correctly decode the data, it is necessary that the encoder indicates **the real type** of the data sent.

### 2.1. The `$kind` Key of Search Criteria

Every `SearchOn` criterion travels as a JSON object carrying a `$kind` key naming its class (`SearchOn.kindKey`), next to its own state. Model identifiers cannot contain `$`, so the key never collides with a field name. This long form is the only accepted one.

```json
{"$kind": "string", "text": "lyo", "type": "contains", "caseSensitive": true}
{"$kind": "int", "value": 10, "other": 20, "type": "between"}
{"$kind": "all", "conditions": [{"$kind": "equal", "value": 1}, {"$kind": "null", "notNull": true}]}
```

`SearchOnField.fromJson<T>(json)` rebuilds the criterion from `$kind`, `T` being the field type the declaring class states. A generated `Xxx$Search` writes its non-empty filters and its `@SearchOnlyField` values, and refuses an unknown key on reading (`SearchOnEntity.checkedMap`).

## 3. Type Adapters

Each type crossing the wire is served by a `JsonTypeAdapter<T>` (`toJson`, `fromJson`, `jsonSchema`). `JsonTypeAdapters.typed<T>()` returns the adapter of a type; a model registers its own adapters through its `ModelLayer.jsonAdapters` (enums: `JsonEnumAdapter<E>`; searches: `SearchOnEntityAdapter`, `SearchOnFieldAdapter<V>`, `SearchOnForeignFieldAdapter<PK, FK>`).

`@Serializable()` (or `@serializable`) registers a type of the model so that it can travel as a service parameter or result:
- on an enum, the enum registers itself;
- on a class, the builder writes its form from its fields (every instance field final and named by a constructor parameter) or routes to the `fromJson`/`toJson` pair the class exposes; exposing only one of the two is refused.

## 4. Wire Form of Rows

A `DataRow` travels as an object holding, next to its field values written through their adapters:
- `$entity`: the `tupleKey` of its entity (its path) or tuple ([see tuples](DATA_MODEL.md));
- `$state`: the row state name;
- `$updated`: the fields it means to write, when some are updated.

Fields marked `@serverSideOnly` are never written. A `DataPacket` (result of a `DataLoader`) travels as `{"$entity": ..., "resultRows": <count>, "dataRows": [...rows...], "paginated": ..., "maskedRefs": [...]}`, `dataRows` holding the result rows followed by the rows resolved through references.


