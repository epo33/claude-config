# Access Control

Sing controls access with **access tokens**. An `Account` holds tokens. A service, a field or an entity requires a token. This document explains how to declare the tokens, how to give them to accounts, and what Sing checks.

## 1. Access Tokens and Accounts

### 1.1. AccessToken

`AccessToken` (`sing_core/lib/src/control_access/access_token.dart`) is a name, usually a path:

```dart
const approveRefund = AccessToken(
  "/orders/approveRefund",
  documentation: AccessTokenDocumentation(
    lib: "Approve a refund",
    description: "Allows a refund above the automatic limit.",
    deniedMsg: "You cannot approve refunds.",
  ),
);
```

- Two tokens are equal when their names are equal, **ignoring case**.
- Names starting with `/sys/` are reserved for Sing. Nothing checks it: just do not use this prefix.
- A token name cannot contain `+`, `|`, `(` or `)`: compound tokens use these characters.
- `AccessTokenDocumentation` (`lib`, `description`, `deniedMsg`) is documentation. It does not change the check.

Built-in tokens:

| Token | Name | Granted to |
| --- | --- | --- |
| `AccessToken.anonymous` | `/sys/anonymous` | everybody, even without session |
| `AccessToken.authentified` | `/sys/authentified` | accounts that hold it. **Sing does not add it**: give it to your users. |
| `AccessToken.me` | `/sys/me` | accounts whose tokens contain their own uuid (every `Account` built with `Account(...)`) |
| `AccessToken.system` | `/sys/system` | accounts that hold it. It grants **every** token. |
| `AccessToken.maintenance` | `/maintenance` | accounts that hold it. For technical administration (reference data imports, maintenance screens). |

### 1.2. Compound Tokens

`CompoundAccessToken` combines tokens:

```dart
const refundManager = CompoundAccessToken.all(
  tokens: [AccessToken.authentified, approveRefund],
);
const anyOrderReader = CompoundAccessToken.one(
  tokens: [OrderHub$RegistryTokens.ordersOrdersRead, AccessToken.maintenance],
);
```

`.all` is granted when every token is granted, `.one` when at least one is. Its `name` is computed from the tokens (`a+b`, `a|b`). Compounds can be nested.

To guard a service with several tokens, use the annotation `@CompoundToken` (see [2.3](#23-tokens-on-a-service)).

### 1.3. Account

`Account` (`sing_core/lib/src/control_access/account.dart`) is the identity of a call:

```dart
Account(
  user.uuid.value,
  displayName: user.name.value,
  tokens: [AccessToken.authentified, $Order.tokens.read],
);
```

- `Account(uuid, displayName: ..., tokens: ...)`: a user. Sing adds `AccessToken(uuid)` to its tokens. This makes `AccessToken.me` work. Sing does **not** add `AccessToken.authentified`.
- `Account.system(uuid, {displayName, tokens})`: a technical account. Its default tokens are `[AccessToken.system]`: it passes every check.
- Predefined accounts: `Account.anonymous` (only `AccessToken.anonymous`), `Account.sessions`, `Account.migration`, `Account.authentificator` (system accounts).
- `account.tokenGranted(token)` answers `true` or `false`.
- `account.checkGranted(token)` throws `AppError(SessionErrorCodes.codeAccessDenied, {"token": token.name})` when the token is not granted.

Build the `Account` of a user in your session manager, when you load the session. See [APP_SERVER.md](APP_SERVER.md#5-sessions-and-authentication).

### 1.4. How a Token Is Granted

`token.granted(account, tokens)` applies these rules, in this order:

1. `AccessToken.licenceGuard`, when the application sets it. It answers `true` (grant), `false` (deny) or `null` (go on). It runs **before every other rule, `system` included**.
2. `AccessToken.anonymous`: granted.
3. The account holds `AccessToken.system`: granted.
4. `AccessToken.me`: granted when the account tokens contain the account uuid.
5. Otherwise: granted when the account holds a token with the same name.

`licenceGuard` closes a feature for the whole installation (a module that is not licensed). It does not receive the account. Set it once at startup:

```dart
AccessToken.licenceGuard = (token) =>
    token == approveRefund && !licence.hasRefunds ? false : null;
```

## 2. Tokens on Services

### 2.1. Where Sing Checks Service Tokens

Each service has exactly one token. Sing checks it **only for HTTP calls**: the server reads the account of the session key and calls `account.checkGranted(service.accessToken)`. A denied call answers HTTP 400 with `AppError` code `sing.errors.accessDenied` (`SessionErrorCodes.codeAccessDenied`), and `params["token"]` names the missing token. See [ERRORS.md](ERRORS.md#3-errors-sing-raises).

A service called from server code (`$Order.services(callContext).loadThisKey(...)`) is **not** checked.

### 2.2. How the Token of a Service Is Chosen

The builder computes the token of each service (`sing_builder/lib/analyser/generators/services_infos.dart`). First match wins:

1. `@CompoundToken.all(...)` / `@CompoundToken.one(...)` on the method.
2. A plain token on the method: `@AccessToken.xxx`, any `const AccessToken(...)`.
3. The token of the mixin: `@Implementor(SomeServices, accessToken: ...)`, or the token of a standard annotation (`@LoadServices(accessToken: ...)`, `@StdEntityServices(readToken: ...)`, ...).
4. When the service asks for a verb: the token of the verb in the token context of the entity. See [3](#3-token-contexts). A service asks for a verb with `@ActionToken(...)` on the method or on the mixin. Standard services ask for `read` (load, search) or `write` (insert, update, upsert, delete).
5. The `@AccessToken.xxx` on the entity, or on the nearest namespace above it.
6. Nothing: `AccessToken.authentified` at run time.

Read the result in the generated code: the `accessTokens:` map of `Order$Services` (in `model/lib/sing/order_hub/orders/order.dart`):

```dart
$Identifiers.search: OrderHub$RegistryTokens.ordersOrdersRead,
$Identifiers.addOrder: sing.AccessToken.authentified,
$Identifiers.loadThisKey: OrderHub$RegistryTokens.ordersOrdersRead,
```

In OrderHub, the root namespace has `@AccessToken.authentified` (`example/model/lib/model/model.dart`). So custom services such as `addOrder` need `authentified`, and the load and search services of `Order` need `/orders/orders/read`.

### 2.3. Tokens on a Service

| Annotation | Where | Effect |
| --- | --- | --- |
| `@AccessToken.anonymous`, `@AccessToken.authentified`, `@approveRefund` (any const token) | method | The service needs this token. |
| `@ActionToken("verb")` | method or mixin | The service needs the token of `verb` in the entity context: `<context path>/<verb>`. Without a verb, the verb is the service name. |
| `@ActionToken.read()` / `@ActionToken.write()` | method or mixin | Same, verb `read` or `write`. |
| `@CompoundToken.all(tokens: [...], actions: [...])` | method | The service needs every token. `actions` are `ActionToken`s resolved in the entity context. |
| `@CompoundToken.one(tokens: [...], actions: [...])` | method | The service needs one of the tokens. |

A method states one token annotation at most. A method annotation overrides the mixin annotation.

```dart
mixin OrderServices on EntityServerServices<Order, String> {
  @ActionToken("cancel", "Cancel an order")
  Future<void> cancelOrder({
    required CallContext callContext,
    required String orderUuid,
  }) async { ... }

  @CompoundToken.all(
    tokens: [AccessToken.maintenance],
    actions: [ActionToken.write()],
  )
  Future<void> purgeOrders({required CallContext callContext}) async { ... }
}
```

Here `cancelOrder` needs `/orders/orders/cancel`, and `purgeOrders` needs `/maintenance` and `/orders/orders/write`. (These two services are not in the example.)

A sign-in service must be callable without session: mark it `@AccessToken.anonymous`.

### 2.4. Standard Services

`@StdEntityServices` (`sing_server/lib/src/std_services/std_entity_services.dart`) accepts three tokens:

```dart
@StdEntityServices(readToken: AccessToken.authentified, writeToken: AccessToken.maintenance)
class ProductEntity extends ModelEntity { ... }
```

- `readToken`: load services.
- `writeToken`: insert, update, upsert, delete.
- `accessToken`: every service without a more specific token.

Without these parameters, the standard services take the `read` / `write` token of the token context. This is usually the better choice: it gives each entity its own tokens.

**Pitfall**: `@AccessToken.maintenance` written on an entity does **not** guard its standard services. Standard services ask for a verb, and the verb token of the context wins (step 4 before step 5 in [2.2](#22-how-the-token-of-a-service-is-chosen)). Use `@StdEntityServices(writeToken: ...)` or `@TokenContext(mapping: ...)`.

## 3. Token Contexts

### 3.1. Derived Tokens

Each namespace and each entity has a token context with a path:
- the root namespace has the empty path;
- a namespace adds its name: `/orders`;
- an entity adds its name: `/orders/orders`.

The verbs come from the services of the node (`read`, `write`, `@ActionToken` verbs). Each verb gives a token `<path>/<verb>`. An entity always has a `read` token: Sing uses it to guard references, cubes and reverse search criteria.

The builder writes these tokens in `model/lib/sing/server_tokens.dart`:

```dart
class OrderHub$RegistryTokens {
  static const ordersOrdersRead = sing.AccessToken(
    r"/orders/orders/read",
    documentation: sing.AccessTokenDocumentation(lib: "read"),
  );
  ...
  static void registerTokens() => sing.AccessToken.registerKnownTokens([...]);
}
```

The registry registers them at startup. `AccessToken.allTokens` lists every known token: use it to build an administration screen of rights.

Typed access, without strings:
- `$Order.tokens.read` (extension `Order$Tokens` on `EntityTokens<Order>`);
- `Orders.tokens.<verb>` for a namespace (extension on `NameSpaceTokens<Orders>`).

Use these getters when you build accounts. Do not write the path by hand.

### 3.2. @TokenContext

`@TokenContext` (`sing_model/lib/src/token_context.dart`) goes on a namespace or an entity. Without it, a node takes the settings of the nearest namespace above it.

| Parameter | Effect |
| --- | --- |
| `mapping: {"verb": token}` | Use `token` for this verb, instead of the derived token. A `null` value removes the verb token: the services of this verb then fall back on `AccessToken.authentified`. Inherited by the nodes below. |
| `others: [ActionToken("verb", "label")]` | Extra tokens that guard no service: thresholds, bypass flags that your code reads with `tokenGranted`. The verb is required. |
| `of: SomeNameSpace` | This node uses the context of another namespace or entity. |
| `readSuffix:`, `writeSuffix:` | Labels of the `read` / `write` verbs in the tree of rights. Write them once on the root namespace. |

`@TokenContext.generic()` goes on a generic entity class: each concrete entity takes the context of the entity bound to its type parameter. A trace entity then has the rights of what it traces.

Examples:

```dart
// example/model/lib/model/orders/order_summary.dart
@TokenContext(mapping: {"read": AccessToken.me})
class OrderSummaryEntity extends ModelEntity { ... }

// coverage/coverage_model: a flag read by business code, not a service guard.
@TokenContext(others: [ActionToken("bypassStockCheck", "Bypass the stock check")])
class StocksNameSpace extends ModelNameSpace { ... }
```

```dart
if (!callContext.userAccount.tokenGranted(Stocks.tokens.bypassStockCheck)) {
  await checkStock(callContext, lines);
}
```

### 3.3. Strict Mode

`Model(strictAccessTokens: true, ...)` (`sing_model/lib/src/model.dart`) makes the build fail when a token is forgotten:

- an entity that publishes services, with no `@TokenContext` on itself, a parent class or a namespace above it, and no `@AccessToken` on itself;
- a service that states no token and finds no `@AccessToken` above it.

To leave an entity open on purpose, write `@TokenContext()` on it, or `@AccessToken.authentified` on the service.

## 4. Tokens on Data

Field and entity tokens protect data, not services. Sing applies them to the **account of the `CallContext`**, in every query: HTTP calls and server code alike. A system account sees everything.

### 4.1. Field Tokens

```dart
final internalNote = StringField(maxLength: 200, accessToken: approveRefund).nullable();
```

The default field token is `AccessToken.anonymous` (no restriction). For an account without the token:
- the field is removed from `SELECT` and `RETURNING`: its value is `null` on the rows the account reads;
- an insert writes the field, but the returned row has `null`;
- an update does not touch the stored value;
- a search sent by a client that filters on the field is refused (`sing.errors.accessDenied`).

Example in the tests: `coverage/coverage_model/lib/model/dml/token_bag.dart`.

### 4.2. Entity Read Tokens and Masked References

The read token of an entity is the token of its load services, or else the `read` token of its context. When a query resolves a reference to an entity the account cannot read, Sing does not load the target rows. It marks the reference as **masked** (`DataPacket.isMasked(ref)`, `maskedRefs` in the JSON packet). On the client, `order.customer.isMasked` is `true`.

So tell apart:
- `isMasked`: the target exists, but the account cannot read it;
- not resolved: the caller did not ask for it.

A client search that crosses an entity the account cannot read (foreign or reverse criterion) is refused with `sing.errors.accessDenied`.

## 5. Pitfalls

- **`authentified` missing.** `Account(...)` does not add `AccessToken.authentified`. Without it, a signed-in user gets `sing.errors.accessDenied` on every service of OrderHub.
- **Server code is not checked.** Service tokens are checked only for HTTP calls. Check rights yourself in a service that calls other services: `callContext.userAccount.checkGranted(token)`.
- **Field tokens apply in server code too.** A service reads a protected field with the account of the caller, and gets `null` if the caller lacks the token. To read it anyway, use `callContext.subTransaction((ctx) => ..., userAccount: Account.system("refunds"))`. It is a separate transaction.
- **A protected field written and read back is `null`.** Do not conclude that the write failed.
- **`Account.system` passes everything**, except a `licenceGuard` that answers `false`.
- **Entity `@AccessToken` does not guard standard services.** See [2.4](#24-standard-services).
- **Token paths change with the model.** Renaming an entity or a namespace renames its derived tokens. Rights stored in the database by path must be migrated. Use the typed getters (`$Order.tokens.read`) in code.

## 6. Testing Access Control

- Decide a right without HTTP: `expect(account.tokenGranted($Order.tokens.read), isFalse)`.
- Test field and read tokens: run a query with a restricted account (`registry.startOperation(..., userAccount: restricted, executor: ...)`) and check the `null` values or `isMasked`.
- Test a service token: send an HTTP request to `registry.processRequest(request: HttpRequest(...), sessionManager: ...)` with a session key that maps to the restricted account, then check status 400 and `body["code"] == SessionErrorCodes.codeAccessDenied`. Example: `coverage/coverage_model/test/reverse_search_read_token_test.dart`.

## 7. See Also

- [SERVICES.md](SERVICES.md): writing services.
- [APP_SERVER.md](APP_SERVER.md#5-sessions-and-authentication): sessions, accounts, sign-in.
- [ERRORS.md](ERRORS.md): the access denied error and the other errors.
- [DATA_MODEL.md](DATA_MODEL.md): annotations on entities and namespaces.
