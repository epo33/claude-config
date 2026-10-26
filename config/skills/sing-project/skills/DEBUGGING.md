# Debugging a Sing Application

Sing traces what it does as operations: HTTP calls, transactions, services, SQL orders. You can read these traces in three ways: a `DebugPrinter` given to the registry, the `operations` stream of the server registry, and the `sing_debug` package (console and multi-process printers).

Sources: `sing_core/lib/src/debug_printer.dart`, `sing_core/lib/src/debug_message.dart`, `sing_server/lib/src/operation.dart`, `sing_server/lib/src/data_registry.dart`, `sing_server/lib/src/call_context.dart`, package `sing_debug`.

## 1. How Do I See the Generated SQL?

### 1.1. Quick Way: a Console Printer

```dart
import "package:sing_debug/sing_debug.dart";

final registry = OrderHubServerRegistry(
  dataControler: dataControler,
  debugger: ConsoleDebugPrinter("server"),
  debugMode: true,
);
```

`ConsoleDebugPrinter(name)` prints each message as `name : message`. For a SQL order it also prints the SQL text.

### 1.2. In Code: the `operations` Stream

`ServerDataRegistry.operations` is a broadcast `Stream<Operation>`. SQL orders are `SqlOperation`s:

```dart
registry.operations
    .where((operation) => operation is SqlOperation && !operation.running)
    .listen((operation) {
      final sql = operation as SqlOperation;
      print("${sql.sqlOrder}\n${sql.params} -> ${sql.rowCount} rows in ${sql.duration}");
    });
```

Useful members of `Operation`: `lib`, `type` (`OperationType.sql`, `OperationType.httpRequest`, `OperationType.transaction`, ...), `level`, `running`, `duration`, `selfDuration`, `error`, `stackTrace`, `operationStack`, `transactionUuid`. `SqlOperation` adds `sqlOrder`, `params`, `rowCount`.

Each operation is emitted **twice**: once when it starts (`running` is `true`) and once when it ends. Filter on `running`, or collect in a `Set`. See [TESTING.md](TESTING.md) for the test pattern.

## 2. Registry Parameters

The generated server registry factory takes two debug parameters:

```dart
OrderHubServerRegistry({
  required ServerDataControler dataControler,
  DebugPrinter? debugger,
  bool debugMode,
});
```

The client registry factory takes `debugger` only.

- `debugger`: receives one `DebugMessage` per operation event.
- `debugMode` (default `false`): when a service fails with an error that is not an `AppError`, the HTTP 500 response carries the error text. Without it, the 500 response has no text. Turn it on in development only: the text can quote SQL or values the caller may not see. An `AppError` is always sent as JSON with status 400, whatever `debugMode` says (see [ERRORS.md](ERRORS.md)).

## 3. How Do I Write My Own Printer?

Extend `DebugPrinter` and override `call` and `hasConsumer`:

```dart
class FileDebugPrinter extends DebugPrinter {
  FileDebugPrinter(super.name, this.sink, {required this.enabled});

  final IOSink sink;
  final bool Function() enabled;

  @override
  bool get hasConsumer => enabled();

  @override
  void call(DebugMessage message) {
    try {
      sink.writeln(message.isSqlOrder ? message.sqlOrder : message.msg);
    } catch (_) {}
  }
}
```

- `call(DebugMessage message)` gets every message. Useful fields: `msg`, `level` (`OperationLevel.trace`, `debug`, `info`, `warning`, `error`), `typeOperation`, `isSqlOrder`, `sqlOrder`, `sqlParams`, `sqlRowCount`, `depth`, `running`, `totalDuration`, `userAccountUuid`, `transactionUuid`, `operationUuid`, `parentUuid`, `from`.
- `hasConsumer` says if someone reads messages below the warning level. When it is `false`, the server sends only warnings and errors, and it skips the costly traces: service parameters and JSON responses are not encoded.
- `call` must never throw. A printer must not break the traced process.
- Combine printers with a printer that forwards to a list of printers. Its `hasConsumer` is `true` when one of them has a consumer.

## 4. The `sing_debug` Package

| Class | Use |
| --- | --- |
| `ConsoleDebugPrinter(name)` | Prints to standard output. |
| `MainDebugPrinter([name])` | In the main process: forwards messages to connected consoles. |
| `SubProcessDebugPrinter.bindToMaster(name, {args, masterSocketPort})` | In a worker process: sends messages to the `MainDebugPrinter` of the master. |
| `DebugSubscriber`, `DebugSubscriberResolver` | Decide which web socket console may connect, and what it sees. |

### 4.1. Main Process

```dart
final debugger = await MainDebugPrinter("server").bind(
  ioSocketPort: 4500,
  webSocketPort: 4501,
  resolveSubscriber: (ticket) async {
    final account = await accountOfTicket(ticket);
    return account == null
        ? null
        : DebugSubscriber(userAccountUuid: account.uuid, seeEverything: account.isAdmin);
  },
);
```

`accountOfTicket` and `isAdmin` stand for your own code.

- `ioSocketPort`: raw socket for local consoles and worker processes.
- `webSocketPort` (with optional `webSocketAddress`, default `localhost`): web socket for consoles. `resolveSubscriber` is then required, or `bind` throws `ArgumentError`.
- A web socket console must first send `{"ticket": "..."}`. The resolver returns a `DebugSubscriber`, or `null` to reject. A subscriber sees only its own messages (same `userAccountUuid`), unless `seeEverything` is `true`. Without a valid ticket within 10 seconds, the connection is closed.
- `hasConsumer` is `true` only while a console is connected. So tracing costs almost nothing when nobody watches.

### 4.2. Worker Process

```dart
final debugger = await SubProcessDebugPrinter.bindToMaster(
  "worker",
  args: arguments,
  masterSocketPort: 4500,
);
```

- It returns `null` when the master cannot be reached (10 second timeout). Handle `null`: run without a debugger.
- `args`: the process arguments. It reads the parent message from `sing_parentMessageUuid` and `sing_parentMessageDepth` (`DebugPrinter.paramParentMessageUuid`, `DebugPrinter.paramparentMessageDepth`), so worker traces nest under the operation that started the worker.
- `hasConsumer` follows the master: it is `true` only while a console reads the master.

## 5. Tracing Your Own Code

On the server, `CallContext` offers:
- `trace(lib, {level, type})`: one message, done at once;
- `traceCall(lib, call, {level, type})` and `traceCallAsync(lib, call, {level, type})`: run `call` as a child operation with its duration;
- `debugPrint(msg, ...)`: one message sent straight to the debugger;
- `tracesRead`: `true` when someone reads the traces. Test it before building a costly trace text.

```dart
if (callContext.tracesRead) {
  callContext.trace("quote input\n${jsonEncode(request)}");
}
```

## 6. Pitfalls

- **Each operation is emitted twice** on `operations`: at start and at end.
- **`hasConsumer` defaults to `true`.** `DebugPrinter` and `ConsoleDebugPrinter` return `true`. With no debugger at all, the server also acts as if traces are read. Service parameters and JSON responses are then encoded for every call, even if nobody reads them. In production, give a printer whose `hasConsumer` is `false` when nobody listens (`MainDebugPrinter` does this).
- **`traceCall` and `traceCallAsync` swallow errors.** An exception thrown by `call` is recorded on the trace, then dropped: it does not reach your code. Do not wrap business code that must fail in them.
- **`debugMode` leaks details.** Keep it off in production.
- **A non-`AppError` error shows as a bare 500.** Turn on `debugMode` to read its text, or watch the operation error in the debugger.

## 7. See Also

- [APP_SERVER.md](APP_SERVER.md): registry setup, monitoring.
- [TESTING.md](TESTING.md): capture SQL in tests.
- [ERRORS.md](ERRORS.md): `AppError` and HTTP status codes.
