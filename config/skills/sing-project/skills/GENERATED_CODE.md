# Generated Code by `sing_builder`

## 1. Model Reconstruction
Code generation (or *model reconstruction*) is performed by executing `dart run build/sing_build.dart` from the `model/` package (the script calls `produceSingCode(model: createOrderHubModel(), pathToSing: ...)` from `sing_builder/commands.dart`). This command will:
1. Instantiate the model description (`createOrderHubModel()` in `model/lib/model/model.dart`, returning a `Model`)
2. Analyze the definitions (root namespace or children recursively, entities, decorators, sub-models, versions, etc.)
3. Generate all model source files (in folders `model/lib/sing`, `common/lib/src/sing` and `model_sing_client/lib/src`), the previous content being kept aside in a sibling `_save` folder
4. Run `dart format` on these three folders
5. Run `dart analyze` on them to check that every produced symbol resolves
6. In case of error, the previous content is restored and the rejected code is moved to a sibling folder suffixed `.incorrect` (e.g. `model/lib/sing.incorrect`)

With a model defining a hundred entities, the operation takes less than a minute and generates approximately 100kLOC and around 300 files.

## 2. Generated Files Organization

### 2.1. Model-level files

For a model `OrderHub`:
- `OrderHub$Layer` (`model/lib/sing/server.dart`, `extends sing.ServerModelLayer`; `model_sing_client/lib/src/client.dart`, `extends sing.ModelLayer`): const class carrying what the model brings to a registry (`name`, `uuid`, `version`, `compiledAt`, `pathInfo`, `enumDefs`, `tupleDefs`, `jsonAdapters`, `registerTokens()`, server-side `majorVersions`).
- `OrderHubRegistry<E extends sing.EntityDef>` (`common/lib/src/sing/registry.dart`): model interface implementing `sing.DataRegistry<E>` and the interfaces of the [sub-models](SUBMODELS.md).
- `OrderHubServerRegistry` (`server.dart`) and `OrderHubClientRegistry` (`client.dart`): `abstract interface class` with a factory (`dataControler:`, `debugger:`, server-side `debugMode:`) and a `static const modelLayers`. The implementation `_OrderHub$Registry` (`extends sing.ServerDataRegistryBase` / `sing.ClientDataRegistryBase`) is private.
- `OrderHub$RegistryTokens` (`server_tokens.dart` / `client_tokens.dart`): access tokens registration, called by `OrderHub$Layer.registerTokens()`.
- `OrderHub` (`order_hub.dart`): root namespace class with `static PathInfo get pathInfos`; one class per namespace in the same layout (`order_hub/orders.dart`, ...).
- Client side, `OrderHub$Ent` / `OrderHub$Svc` (`client_ent.dart`, `client_svc.dart`): access chains to entity defs and services, typed on `OrderHubClientRegistry`.
- `server_common.dart`, `server_searches.dart`, `server_mixins.dart`, `server_exports.dart`, `server_init.dart` (`$EntitiesFields`, `$ServicesInfos`) and their `client_*.dart` counterparts; `common.dart`, `searches.dart`, `consts.dart` (`$Identifiers`), `registry.dart`, `sing.dart` in the common package.

### 2.2. Entity-level files

The generated files are organized as follows (e.g., `Order`):
- `Order` - Abstract interface class. An **entity** in Sing is therefore an abstract interface. These are generic types that allow specializing the behavior of existing classes in `sing_core` (sometimes redefined in `sing_server` and `sing_client`). It exposes `static const String tupleKey` (the root-less entity path, e.g. `"orders/orders"`), resolvable through `dataRegistry.tupleDefByKey(Order.tupleKey)`; a generated tuple class carries its model key the same way (e.g. `TopicCount.tupleKey == "topics.topicCount"`).
- `$Order` - Abstract class with static access methods. Often used to retreive entity services (client side, `$Order.services( dataRegistry)`) or queries (server side, `$Order.query( callContext)`).
- `_Order$Impl`: Private class used only by the framework
  - Implementation of ServerEntityDef<Order, String> (in /model/lib/sing)
  - Implementation of ClientEntityDef<Order, String> (in /model_sing_client)
- `Order$Services`: EntityServerServices<Order, String>
  - Server-side services in /model/lib/sing
  - Client-side services in /model_sing_client
- `Order$Search` - Class for typed searches
- `Order$SearchMixin` - Mixin for search functionalities
- `Order$Instance` - Alias for DataRowValues<Order>
- `Order$ReferenceExtension` - Extension on Reference<Order>
- `EntityFieldList$Order` - Extension on EntityFieldsList<Order> (access to field definitions)
- `FieldsView$Order` - Extension on EntityFieldsView<Order> (navigation in fields)
- `DataRowValues$Order` - Extension on DataRowValues<Order> (access to field values)

Unless otherwise specified, when the entity is private ([`@serverSideOnly` decorator](DATA_MODEL.md)), the definitions are located in `model/lib/sing` (or a subdirectory), otherwise in a file in `common/lib/src/sing`. Server-side, each entity has one file `model/lib/sing/{root}/{namespace}/{entity_name}.dart` (e.g. `model/lib/sing/order_hub/orders/order.dart`) holding `$Order`, `_Order$Impl` and `Order$Services`.

## 3. Instructions for LLM

### 3.1. Entity Namespace Location
To find the namespace in which an entity is defined (e.g., `Order`):
1. Search in model/lib/sing where the `_Order$Impl` class is defined (i.e., an `order.dart` file containing the text `class _Order$Impl extends`).
2. Let `model/lib/sing/dir1/dir2/.../dirN/order.dart` be the file name where this definition is found
3. for each directory `dirX`, read `dirX.dart` in it's parent directory an search a `class DirX extends sing.ServerNameSpace` to obtain the valid name of the namespace class.
  
Then, namespace `dir1` contains namespace `dir2`, which contains ..., which contains namespace `dirN` which contains `Order`.

### 3.2. Entity Fields and Types
To find the list of fields and their types for an entity (e.g., `Order`):
1. Search for the definition of the DataRowValues<Entity> extension (e.g., `DataRowValues<Order>`) by searching for the text `extension DataRowValues$Order on [POSSIBLE ALIAS]DataRowValues<Order>` in `common/lib/src/sing/common.dart` or in `model/lib/sing/server_common.dart` (if the entity is decorated with `@serverSideOnly`).
2. Each `get` method of this extension defines a field:
   - Named by the method name
   - Typed:
     - `FieldValue<T>` which indicates that the field is of type `T`
     - or `FieldValueRef<R, PK>` which indicates that the field is a reference to entity `R` whose primary key is of type `PK`.

Examples:
```dart
extension DataRowValues$Order on sing.DataRowValues<Order> {
  sing.FieldValue<String> get orderNumber =>  // Field orderNumber of type String
      (this[$Identifiers.orderNumber] as sing.FieldValue<String>);

  sing.FieldValue<sing.UtcDateTime> get orderDate =>  // Field orderDate of type UtcDateTime
      (this[$Identifiers.orderDate] as sing.FieldValue<sing.UtcDateTime>);

  sing.FieldValueRef<Customer, String> get customer =>  // Field customer which is a reference (FK) to entity Customer
      (this[$Identifiers.customer] as sing.FieldValueRef<Customer, String>);
}
```

### 3.3. Entity Search Filters
To find the filters defined by an entity's search service (e.g., `Order`): all parameters of all search services can be found in `common/lib/src/sing/searches.dart` or `model/lib/sing/server_searches.dart` by searching for the definition of a class derived from `SearchOnEntity` associated with the entity (e.g., `class Order$Search<E extends Order> extends sing.SearchOnEntity<E>`).

Example:
```dart
class Order$Search<E extends Order> extends sing.SearchOnEntity<E> {
    Order$Search( {
        // ...
    });

  final sing.SearchOnField<String>? orderNumber;

  final sing.SearchOnField<sing.UtcDateTime>? orderDate;

  final sing.SearchOnEntity<Customer>? customer;

  // ...
}
```
See [search filters](SEARCHES.md).
