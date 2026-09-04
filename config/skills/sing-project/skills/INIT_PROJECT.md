# How to Start a Project Using the Sing Framework

## 1. Steps to Use Sing in a Development Project

1. From the project root directory, execute the command `dart create model` which will create the skeleton of the Dart `model` package. The `model/test` and `model/bin` directories can be deleted. Tests for a Sing model are performed elsewhere.
2. Modify `model/pubspec.yaml` to add a dev dependency on the `sing_builder` package from the Sing framework.
3. Execute the command `cd model; dart run sing_builder:init PATH_TO_SING` where PATH_TO_SING is the path to the Sing framework sources (`sing_builder/bin/init.dart`, which calls `initModelPackages` with `clientPackagePath: "../model_sing_client"` and `commonPackagePath: "../common"`).

## 2. Result

Files and directories created or modified (`sing_builder/lib/src/commands/init_package.dart`):
    - model
      - build
        - sing_build.dart  # `produceSingCode(model: createModelModel())`: rebuilds the generated code
        - sing_init.dart   # `initModelPackages(...)`: re-runs this initialization
      - lib
        - model
          - model.dart     # `Model createModelModel() => Model(modelName: 'Model');` the root object of the data model
        - sing
          - README.md      # warning "do not modify the content of this directory"
          - server.dart    # generated at each build
        - server.dart      # `export 'sing/server.dart';`
      - pubspec.yaml: adds dependencies to `sing_model`, `sing_server` and `../common`
    - model_sing_client
      - lib
        - client.dart      # `export 'src/client.dart';`
        - src
          - README.md
          - client.dart    # generated at each build
      - pubspec.yaml: depends on `sing_client`
    - common
      - lib
        - common.dart      # `export 'src/sing/sing.dart';`
        - src/sing
          - README.md
          - common.dart, consts.dart, sing.dart  # generated at each build
      - pubspec.yaml: depends on `sing_core`

[More details on the structure](PROJECT_STRUCTURE.md). [More details on generated code](GENERATED_CODE.md).

**Recommended**

- Add an entry in `launch.json` with data :
```json
    {
        "name": "Build model",
        "cwd": "model",
        "request": "launch",
        "type": "dart",
        "program": "build/sing_build.dart"
    },
```

- Create a file `model/lib/model.dart` exporting the framework, the model definitions and the common package, so that a model file imports a single library (from `example/model/lib/model.dart`):
```dart
export 'package:sing_model/sing_model.dart';
export 'package:sing_server/sing_server.dart';
export 'model/model.dart';
export 'package:common/common.dart';
```
Server applications import `package:model/server.dart` (generated entities, services, `OrderHubServerRegistry`) and `package:model/model.dart`.

## 3. Next Step

- Open the file `model/lib/model/model.dart`
- Define a class `MyModelRootNameSpace extends ModelNameSpace {}`. This is the **root namespace** of the model.
- Modify the `Model(...)` constructor call by providing the parameter `rootNameSpace: MyModelRootNameSpace()` (`example/model/lib/model/model.dart` shows the `Model` of the `OrderHub` example, with `clientPackagePath`, `commonPackagePath` and `aliases`)
- [Define sub-namespaces and entities](DATA_MODEL.md)
