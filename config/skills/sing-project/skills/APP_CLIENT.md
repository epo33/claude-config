# Application Sing client

Une application Sing cliente est **par définition** une application qui dépend du package `model_sing_client` pour accèder au modèle. Ce package est entièrement généré à chaque [reconstruction du modèle](GENERATED_CODE.md).

## Basic Sing Client Application

Une application Sing cliente **doit** instancier la classe dérivée de `ClientServerRegistry` définie dans le `model_sing_client` (eg `OrderHub$Registry` dans `model_sing_client/lib/client.dart`).

```dart
// In main function (Flutter app probably but can be a command line tool).
Future<void> main() async {
    // No network call, very fast operation.
    final dataRegistry = OrderHub$Registry( dataControler : AppDataControler());
    // Call services, ...
}

class AppDataControler implements sing.ClientDataControler {
    AppDataControler( this.singServerUri)

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

}
```

Le framework Sing n'effectue **jamais** d'appel HTTP directement mais utilise le paramètre `dataControler` fourni au contructeur de `dataRegistry` pour cela.

## Utiliser le modèle

Toute utilisation du modèle **nécessite** un accès à l'instance du modèle créée (eg `dataRegistry`). 

### In a widget

L'approche préconisée est de définir un `InheritedWidget` :
```dart
class AppModel extends InheritedWidget {
  static OrderHub$Registry of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<AppModel>();
    if (widget == null) {
      throw Exception("No AppModel found in context");
    }
    return widget.dataRegistry;
  }

  AppModel({super.key, required this.dataRegistry, required super.child});

  final OrderHub$Registry dataRegistry;

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