# Application Sing client

Une application Sing cliente est **par définition** une application qui dépend du package `model_sing_client` pour accèder au modèle. Ce package est entièrement généré à chaque [reconstruction du modèle](GENERATED_CODE.md).

## Basic Sing Client Application

Une application Sing cliente **doit** construire son registre par la fabrique de l'interface générée dans `model_sing_client/lib/src/client.dart` (exportée par `model_sing_client/lib/client.dart`), eg `OrderHubClientRegistry(dataControler: ...)`. `OrderHubClientRegistry` est une `abstract interface class` qui empile `sing.ClientDataRegistry` et l'interface de modèle `OrderHubRegistry<ClientEntityDef>` (générée dans `common/lib/src/sing/registry.dart`) ; sa fabrique prend `dataControler` (requis, un `ClientDataControler`) et `debugger` (`DebugPrinter?`). L'implémentation `_OrderHub$Registry extends sing.ClientDataRegistryBase` est privée au fichier généré : le code applicatif nomme l'interface, ne l'étend pas et n'écrit jamais `ClientDataRegistry(...)`. La statique `OrderHubClientRegistry.modelLayers` liste les `ModelLayer` (`OrderHub$Layer` et ceux des [sous-modèles](SUBMODELS.md)) dont le registre est construit. Les chaînes d'accès générées `OrderHub$Ent`/`OrderHub$Svc` typent leur `$dataRegistry` sur `OrderHubClientRegistry`.

```dart
// In main function (Flutter app probably but can be a command line tool).
Future<void> main() async {
    // No network call, very fast operation.
    final dataRegistry = OrderHubClientRegistry(
      dataControler: AppDataControler(Uri.parse("https://host/app")),
    );
    // Call services, ...
}

class AppDataControler implements sing.ClientDataControler {
    AppDataControler( this.singServerUri);

    @override
    final Uri singServerUri;

  @override
  Future<http.Response> callService(
    Uri path, {
    required Map<String, dynamic> params,
    required Map<String, String> httpHeaders,
  }) async {
    // Use HTTP client library to call path and return Response (dio, ...)
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    // Report errors raised by service calls
  }

  // Checks performed on each service call against the server headers
  @override
  bool get checkVersion => true;
  @override
  bool get checkModelVersion => true;
  @override
  bool get checkServiceSignature => true;
}
```

`sing_client` fournit `DebugClientDataControler` (aucun appel réseau, toutes les vérifications désactivées) pour les tests.

Le framework Sing n'effectue **jamais** d'appel HTTP directement mais utilise le paramètre `dataControler` fourni au contructeur de `dataRegistry` pour cela.

## Utiliser le modèle

Toute utilisation du modèle **nécessite** un accès à l'instance du modèle créée (eg `dataRegistry`). 

### In a widget

L'approche préconisée est de définir un `InheritedWidget` :
```dart
class AppModel extends InheritedWidget {
  static OrderHubClientRegistry of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<AppModel>();
    if (widget == null) {
      throw Exception("No AppModel found in context");
    }
    return widget.dataRegistry;
  }

  AppModel({super.key, required this.dataRegistry, required super.child});

  final OrderHubClientRegistry dataRegistry;

  @override
  bool updateShouldNotify(AppModel oldWidget) =>
      oldWidget.dataRegistry != dataRegistry;
}
```

et placer une instance de ce widget le plus haut possible dans la hiérarchie des widgets de l'application.

### In a Controler class

La plupart des opérations faites sur le modèle de données se font par appel d'un service défini dans le modèle. Cet appel pourrait donc être réalisé directement dans le code des écrans de l'application :
```dart

class OrderView extend StatelessWidget {
    OrderView( { super.key, this.order});

    final Order$Instance order;

    Widget build( BuildContext context) => Column( children: [
        Text( order.orderNumber.value)
        // ...
        TextButton( 
            onPressed :() => $Order.services( AppMode.of(context)).deleteThisKey( order.uuid.value);
            child: Text( "Delete"),
        )
    ])
}
```
Cette approche n'est cependant pas recommandée pour les raisons suivantes :
- 