# Sing Client Application

A Sing client application (Flutter app or command-line tool) depends on the generated client package (e.g. `model_sing_client`). It has no database access: every data operation is a service call to a Sing server. The client package is fully regenerated at each [model build](GENERATED_CODE.md). Never edit it.

## 1. Startup Sequence

1. Load the model description from the server (`<mount>/_model.json`).
2. Build the registry with this description and your `ClientDataControler`.
3. Sign in (call your sign-in service) and keep the session key.
4. Call services.

```dart
import "package:model_sing_client/client.dart";

Future<OrderHubClientRegistry> startClient() async {
  final serverUri = Uri.parse("https://host/app");
  final dataControler = OrderHubDataControler(serverUri);
  final modelField = await dataControler.loadModelDefinition();
  return OrderHubClientRegistry(
    dataControler: dataControler,
    modelField: modelField,
  );
}
```

`serverUri` is the URL of the Sing mount point on the server (see [APP_SERVER.md](APP_SERVER.md#41-mount-the-handler)).

## 2. The Registry

Build the registry with the factory of the interface generated in `model_sing_client/lib/src/client.dart` (exported by `package:model_sing_client/client.dart`). `OrderHubClientRegistry` is an `abstract interface class`: it implements `sing.ClientDataRegistry` and the model interface `OrderHubRegistry<ClientEntityDef>`.

| Parameter | Type | Role |
| --- | --- | --- |
| `dataControler` | `ClientDataControler` (required) | Makes the HTTP calls. |
| `modelField` | `Map<String, Object?>` (required) | Model description served by the server. |
| `debugger` | `DebugPrinter?` | Debug output. |

The concrete class is private: use the interface type, never write `ClientDataRegistry(...)`. Create **one** registry and share it in the whole application. In the rest of this document it is called `dataRegistry`.

## 3. The Data Controler

Sing never makes HTTP calls by itself. It calls your `ClientDataControler` (`sing_client/lib/src/controler.dart`):

| Member | Role |
| --- | --- |
| `Uri get singServerUri` | Base URL of the Sing mount point. |
| `Future<http.Response> callService(Uri path, {required Map<String, dynamic> params, required Map<String, String> httpHeaders})` | Send one service call and return the raw response. `path` is the full service URL, `params` the JSON-ready body, `httpHeaders` the Sing headers. |
| `void onError(Object error, StackTrace stackTrace)` | Available for your own error reporting. Sing itself does not call it. |
| `bool get checkVersion` | Send `X-Sing-Version`: the server refuses the call if its model version differs. |
| `bool get checkModelVersion` | Send `X-Sing-Model-Version`: the server refuses the call if its model build date differs. |
| `bool get checkServiceSignature` | Send `X-Sing-Service-Signature`: the server refuses the call if the service signature differs. |

Typical implementation with `package:http`:

```dart
import "dart:convert";

import "package:http/http.dart" as http;
import "package:model_sing_client/client.dart";
import "package:sing_client/sing_client.dart" as sing;

class OrderHubDataControler implements sing.ClientDataControler {
  OrderHubDataControler(this.singServerUri);

  @override
  final Uri singServerUri;

  String? sessionKey;

  Future<Map<String, Object?>> loadModelDefinition() async {
    final uri = singServerUri.replace(
      path: "${singServerUri.path}/${sing.DataRegistry.modelDefinitionPath}",
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw StateError("Model description unavailable: ${response.statusCode}");
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>;
  }

  @override
  Future<http.Response> callService(
    Uri path, {
    required Map<String, dynamic> params,
    required Map<String, String> httpHeaders,
  }) => http.post(
    path,
    headers: {
      ...httpHeaders,
      "content-type": "application/json",
      if (sessionKey != null) "authorization": "Bearer $sessionKey",
    },
    body: jsonEncode(params),
  );

  @override
  void onError(Object error, StackTrace stackTrace) {}

  @override
  bool get checkVersion => true;
  @override
  bool get checkModelVersion => true;
  @override
  bool get checkServiceSignature => true;
}
```

Rules for `callService`:
- Send a **POST** with the JSON body and `Content-Type: application/json`. The server ignores a body with another content type.
- Keep all headers of `httpHeaders`. They also carry the client time zone (`X-Sing-Client-Timezone-Offset`, `X-Sing-Client-Timezone-Name`), used by the server for local dates.
- Add the session key yourself: `Authorization: Bearer <key>`. Sing does not manage it.
- Return the response as is. Sing reads the status code and decodes the body.

For tests that never reach a server, `sing_client` provides `DebugClientDataControler` (every call throws `UnimplementedError`, every check is off).

## 4. Model Description and Version Checks

The client builds its field definitions from the description the server sends, not from a copy in the generated code. So it needs this description before it builds the registry.

- The server answers `GET <mount>/_model.json` (`DataRegistry.modelDefinitionPath`) without session.
- Build the URL by appending to the path, as above. Do not use `singServerUri.resolve("_model.json")`: without a trailing `/`, it replaces the last path segment (`https://host/app` gives `https://host/_model.json`).
- The response has an `ETag` and `Cache-Control: no-cache`. A client that sends `If-None-Match` gets 304 while the model is unchanged.
- Without this description the application cannot start. Retry, or show a clear message.

When it builds each entity definition, the client compares the digest in its generated code with the digest the server sends. If they differ, the client was generated from another model, and the build throws a `StateError`: `"<entity> is served by a model this client was not generated from. Generate the client again against this server."` Fix: regenerate the client from the model the server runs, and deploy both together.

At each service call, the server can also refuse a client built from another version (`checkVersion`, `checkModelVersion`) or a service whose signature changed (`checkServiceSignature`). It then answers an `AppError` with code `sing.errors.incompatibleVersion` or `sing.errors.invalidServiceSignature`. Ask the user to update or reload the application.

## 5. Errors

`$callService` (`sing_client/lib/src/services.dart`) throws an `AppError` for a 400 answer with a JSON object, and a `String` for any other status >= 400. Network failures throw the exception of your HTTP library. Catch `AppError` first, then `Object`:

```dart
try {
  await $Order.services(dataRegistry).loadThisKey(key: uuid).exactlyOne();
} on AppError catch (e) {
  showMessage(translate(e.code, e.params));
} on Object catch (e) {
  showMessage("Unexpected error: $e");
}
```

Handle `SessionErrorCodes.codeSessionExpired` (show the sign-in screen) and `SessionErrorCodes.codeAccessDenied` in every application; the data controler is a good single place for them. The list of codes and what to do for each: see [ERRORS.md](ERRORS.md#3-errors-sing-raises).

## 6. Calling Services

### 6.1. Find the Services Class

Each entity and namespace has a generated services class with the same services as the server, without the `callContext` parameter:

```dart
final orderServices = $Order.services(dataRegistry);          // entity
final ordersServices = Orders$Services(dataRegistry);         // namespace
final sameOrderServices = OrderHub$Svc(dataRegistry).orders.orders(); // path chain
```

Entity definitions: `$Order.of(dataRegistry)` or `OrderHub$Ent(dataRegistry).orders.orders`.

### 6.2. Value Results

A service that returns `Future<T>` on the server returns `Future<T>` on the client. The call is sent at once:

```dart
final quote = await $Order.services(dataRegistry).quoteShipping(asked: asked);
```

### 6.3. DataLoader Results

A service that returns `DataLoader<E>` returns a `DataLoader<E>` on the client. **Nothing is sent until you run it.** Shape the result first, then run it once:

```dart
final order = await $Order
    .services(dataRegistry)
    .loadThisKey(key: uuid)
    .fields((fields) => [fields.orderNumber, fields.customer.name])
    .resolve((fields) => [fields.customer])
    .exactlyOne();
```

Run methods: `listValues()`, `list()`, `one()`, `exactlyOne()`, `execute()`, `count()`. `fields`, `resolve` and `sort` travel with the call, and the server applies them. See [DATA_CLASSES.md](DATA_CLASSES.md) and, for search services, [SEARCHES.md](SEARCHES.md).

Do not run the same `DataLoader` twice by mistake: each run is a new HTTP call.

### 6.4. Writing Data

Create a row on the client, fill it, and send it to a standard or custom service:

```dart
final order = $Order.of(dataRegistry).createInstance(
  filler: (values) => values..orderNumber.value = "ORD-0001",
);
final saved = await $Order
    .services(dataRegistry)
    .addOrder(order: order, orderLines: lines)
    .exactlyOne();
```

For standard services, pass the `DataRow`: `insertThis(data: order.$dataRow)`. The server ignores values sent for read-only fields.

### 6.5. Binary and Raw Results

A service returning `Future<Uint8List>` gives the bytes. A service returning `Future<HttpResponse>` on the server gives the raw `http.Response` on the client.

## 7. Using the Registry in a Flutter Application

### 7.1. Give Access to the Registry

Put the registry in an `InheritedWidget` near the root of the widget tree:

```dart
class AppModel extends InheritedWidget {
  const AppModel({super.key, required this.dataRegistry, required super.child});

  final OrderHubClientRegistry dataRegistry;

  static OrderHubClientRegistry of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<AppModel>();
    if (widget == null) throw StateError("No AppModel found in context");
    return widget.dataRegistry;
  }

  @override
  bool updateShouldNotify(AppModel oldWidget) =>
      oldWidget.dataRegistry != dataRegistry;
}
```

### 7.2. Keep Service Calls Out of Widgets

Do not call services directly in `build` methods or button callbacks. Put them in a controller class that owns the registry:

```dart
class OrderController {
  OrderController(this.dataRegistry);

  final OrderHubClientRegistry dataRegistry;

  Future<List<DataRowValues<Order>>> pendingOrders() => $Order
      .services(dataRegistry)
      .search(status: Search.equal(OrderStatus.pending))
      .sort((fields) => [-fields.orderDate])
      .listValues(limit: 100);

  Future<void> deleteOrder(String uuid) =>
      $Order.services(dataRegistry).deleteThisKey(key: uuid).execute();
}
```

Reasons:
- One place for error handling (`AppError`, expired session).
- Widgets stay simple and testable; the controller can be tested with a fake `ClientDataControler`.
- The choice of fields and resolutions (`fields`, `resolve`) stays next to the call, not spread in the UI.
- Loading state and refresh after a write are handled once.

(`deleteThisKey` needs `@DeleteServices()` or `@StdEntityServices()` on the entity; OrderHub only has `@LoadServices()` on `Order`.)

### 7.3. Rebuild Widgets on Data Changes (`sing_flutter`)

The optional `sing_flutter` package has small widgets that rebuild when the rows of a `DataPacket` change (`DataPacket.changeStream`). Get a packet with `loadDataPacket()` on a `DataLoader` ([DATA_CLASSES.md](DATA_CLASSES.md#5-datapackete)). Rows and field values must belong to a packet: the widgets assert it.

| Widget | Rebuilds when |
| ------ | ------------- |
| `DataPacketChangeBuilder(dataPacket:, onChanged:)` | any row of the packet changes |
| `DataPacketRowTypeBuilder<E>(dataPacket:, onChanged:)` | a row of entity `E` changes |
| `DataPacketRowBuilder<E>(row:, onChanged:)` | this row changes |
| `FieldValueChangeBuilder<T>(fieldValue:, onChanged:)` | this field of this row changes |

`onChanged` is `Widget Function(BuildContext)`, except for `FieldValueChangeBuilder`, which also receives the current `FieldValue<T>`:

```dart
FieldValueChangeBuilder<String>(
  fieldValue: order.orderNumber,
  onChanged: (context, value) => Text(value.value),
)
```

## 8. See Also

- [SERVICES.md](SERVICES.md): declaring services.
- [ERRORS.md](ERRORS.md): error codes and how to handle them.
- [ACCESS_CONTROL.md](ACCESS_CONTROL.md): access tokens.
- [APP_SERVER.md](APP_SERVER.md): the server side, sessions and sign-in.
- [DATA_CLASSES.md](DATA_CLASSES.md): `DataLoader`, `DataRowValues`, `DataRow`.
- [SEARCHES.md](SEARCHES.md): search services and criteria.
- [AUTO_JSON.md](AUTO_JSON.md): types that can travel as parameters and results.
- [CUBE.md](CUBE.md): reading a `CubeResult` returned by a service.
- [TESTING.md](TESTING.md): an offline client registry for tests.
