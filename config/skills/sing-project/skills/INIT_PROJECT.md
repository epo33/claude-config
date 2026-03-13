# How to Start a Project Using the Sing Framework

## 1. Steps to Use Sing in a Development Project

1. From the project root directory, execute the command `dart create model` which will create the skeleton of the Dart `model` package. The `model/test` and `model/bin` directories can be deleted. Tests for a Sing model are performed elsewhere.
2. Modify `model/pubspec.yaml` to add a dev dependency on the `sing_builder` package from the Sing framework.
3. Execute the command `cd model; dart run sing_builder:init PATH_TO_SING` where PATH_TO_SING is the path to the Sing framework sources.

## 2. Result

Files and directories created or modified:
    - model
      - bin
        - sing_build.dart
        - sing_init.dart
      - lib
        - model
          - model.dart  # Initializes the root object of the data model
        - sing
          - README.md: warning "do not modify the content of this directory"
          - server.dart
      - pubspec.yaml: adds dependencies to `sing_model`, `sing_server` and `../common`
    - model_sing_client
    - common

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

- Create a file `model/lib/server.dart` with:
```dart
export 'model/model.dart';
export 'sing/sing.dart';
```
This file can be imported in any model file to access generated entities and services (e.g., `import 'package:model/server.dart';`).

## 3. Next Step

- Open the file `model/lib/model/model.dart`
- Define a class `MyModelRootNameSpace extends ModelNameSpace {}`. This is the **root namespace** of the model.
- Modify the `Model(...)` constructor call by providing the parameter `rootNameSpace: MyModelRootNameSpace()`
- [Define sub-namespaces and entities](DATA_MODEL.md)