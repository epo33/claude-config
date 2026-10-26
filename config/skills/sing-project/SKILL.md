---
name: sing-project
description: "Expert on the Sing Dart framework for database-backed applications. Use for any task or question on a project that depends on Sing (packages sing_model, sing_core, sing_server, sing_client, sing_postgresql, sing_builder)."
---

Use this skill for any task or question related to the Sing framework.

## 1. What Is Sing?

Sing is a Dart framework for business applications with a large relational data model (dozens or hundreds of entities). It targets:
- data stored in PostgreSQL (the only database implemented, version 18 or later);
- a server tier with direct database access and client tiers (Flutter or other) that reach data only through HTTP services;
- full consistency between the model, the database schema, the server services and the client code.

### 1.1. Model-First Workflow

1. Describe the domain in plain Dart with `sing_model`: a `Model`, `ModelNameSpace` classes, `ModelEntity` classes with fields, and service mixins.
2. Run `dart run sing_builder:sing_emit` from the model package. The builder reads the model with the Dart analyzer (it never executes it) and generates server code, common code and a type-safe client API.
3. The server creates the generated registry, migrates the database from the model, and exposes the services over HTTP.
4. Clients create the generated client registry and call the same services with the same types.
5. Developers add business logic in service mixins (`*.services.dart`), never in generated files.

### 1.2. Packages

| Package | Role | Used by |
|---|---|---|
| `sing_model` | DSL to declare the model (`Model`, `ModelNameSpace`, `ModelEntity`, `ReferenceTo`, annotations) | model package |
| `sing_core` | Shared runtime: fields, `DataRow`, `DataLoader`, searches, access tokens, `AppError`, JSON adapters, cube | everything (re-exported by server and client) |
| `sing_server` | Server runtime: `ServerDataRegistry`, `CallContext`, queries, migrations, HTTP dispatch, notifications | model package, server app |
| `sing_postgresql` | PostgreSQL implementation: `PgDataControler` (pool, transactions, introspection) | server app |
| `sing_client` | Client runtime: `ClientDataControler`, `ClientDataRegistry`, service calls over HTTP | client package and apps |
| `sing_builder` | Code generator (`sing_emit`) | dev dependency of the model package |
| `sing_debug` | Debug printers (console, socket, WebSocket) | optional |
| `sing_flutter` | Small Flutter widgets that rebuild on `DataPacket` / `FieldValue` changes | optional |

Applications depend on Sing packages by `path:` to a checkout of the Sing repository. The Sing sources, the OrderHub example and the coverage tests are in that checkout: follow the `path:` entries of the project's `pubspec.yaml` files to find them.

## 2. Documentation Map

### 2.1. Where to Start for a Task

| I need to... | Read |
|---|---|
| Create a new project | [INIT_PROJECT.md](./skills/INIT_PROJECT.md), [PROJECT_STRUCTURE.md](./skills/PROJECT_STRUCTURE.md) |
| Add or change an entity, a namespace, an index | [DATA_MODEL.md](./skills/DATA_MODEL.md) |
| Choose a field type or field option | [FIELD_TYPES.md](./skills/FIELD_TYPES.md) |
| Link entities (foreign keys, one-to-many, many-to-many) | [CONCEPTS_RELATIONSHIPS.md](./skills/CONCEPTS_RELATIONSHIPS.md) |
| Regenerate code, fix a builder error, find a generated symbol | [GENERATED_CODE.md](./skills/GENERATED_CODE.md) |
| Write a custom service | [SERVICES.md](./skills/SERVICES.md) |
| Read or write data in a service | [QUERIES.md](./skills/QUERIES.md), [QUERY_EXPRESSIONS.md](./skills/QUERY_EXPRESSIONS.md) |
| Work with rows and loaders (`DataRow`, `Order$Instance`, `DataLoader`) | [DATA_CLASSES.md](./skills/DATA_CLASSES.md) |
| Expose a search service or filter rows | [SEARCHES.md](./skills/SEARCHES.md) |
| Control who can call a service or read a field | [ACCESS_CONTROL.md](./skills/ACCESS_CONTROL.md) |
| Handle and raise errors | [ERRORS.md](./skills/ERRORS.md) |
| Use transactions, sub-transactions, after-commit actions | [TRANSACTIONS.md](./skills/TRANSACTIONS.md) |
| React to inserts/updates/deletes, send notifications | [NOTIFICATIONS.md](./skills/NOTIFICATIONS.md) |
| Change the database schema or run data migrations | [MIGRATIONS.md](./skills/MIGRATIONS.md) |
| Set up or change the server application | [APP_SERVER.md](./skills/APP_SERVER.md) |
| Set up or change a client application | [APP_CLIENT.md](./skills/APP_CLIENT.md) |
| Send a DTO or another type between client and server | [AUTO_JSON.md](./skills/AUTO_JSON.md) |
| Build an entity computed by a query (no table) | [VIEW_ENTITIES.md](./skills/VIEW_ENTITIES.md) |
| Build multidimensional aggregates (pivot tables, dashboards) | [CUBE.md](./skills/CUBE.md) |
| Reuse a model inside another model | [SUBMODELS.md](./skills/SUBMODELS.md) |
| Test code that uses Sing | [TESTING.md](./skills/TESTING.md) |
| See the generated SQL, trace operations | [DEBUGGING.md](./skills/DEBUGGING.md) |

### 2.2. Recommended Reading Order

For a first contact: [PROJECT_STRUCTURE.md](./skills/PROJECT_STRUCTURE.md), [DATA_MODEL.md](./skills/DATA_MODEL.md), [GENERATED_CODE.md](./skills/GENERATED_CODE.md), [SERVICES.md](./skills/SERVICES.md), [QUERIES.md](./skills/QUERIES.md). Read the other documents when the task needs them.

## 3. Example Project

The `example/` directory of the Sing repository contains OrderHub, a small working application. Use it as the reference for patterns and names.
- `model/`: the model (`lib/model/`), with the `Orders` and `Products` namespaces and the entities `Order`, `OrderLine`, `OrderAuditTrace`, `OrderSummary` (view entity), `Customer`, `Address` and `Product`. Service mixins are in `*.services.dart` files next to the entities. Generated server code is in `lib/sing/`.
- `foundation/`: a plain Dart package that `model` depends on. It provides the hand-written `AuditTraceEntity` base that `OrderAuditTraceEntity` extends. It is not a Sing model and nothing is generated for it.
- `common/`: enumerations (`DbEnum`), DTOs and generated common code (`lib/src/sing/`, including the `OrderHubRegistry` interface).
- `model_sing_client/`: generated client API.
- `orderhub_server/`: server application skeleton.

The `coverage/` directory of the Sing repository contains test models and tests that exercise almost every feature. It is not a functional example, but its tests show real usage of rare APIs.

## 4. Rules for LLM Agents

- **The model is the source of truth.** Read the entity and namespace definitions before writing code that uses them.
- **Never edit generated code.** Files in `model/lib/sing/`, `common/lib/src/sing/` and `model_sing_client/lib/` are rewritten by each emission. Every other file in these folders is deleted. Change the model or a service mixin, then regenerate.
- **Regenerate after every model change.** Run `dart run sing_builder:sing_emit` from the model package. One run emits the model and every model it mounts. If the run refuses the model, nothing is written: fix the reported declarations first ([GENERATED_CODE.md](./skills/GENERATED_CODE.md)).
- **Put business logic in service mixins** attached with `@Implementor(...)`. Keep one mixin per entity or namespace concern.
- **Stay type-safe.** Use generated accessors (`order.orderNumber`, `$Order.fields`, `Order$Search`) and the expression DSL. Avoid `dynamic`, string field names and raw SQL.
- **Follow `example/`.** Before inventing a pattern, check how OrderHub solves the same problem.
- **`$` prefix.** Members whose name starts with `$` belong to the framework or to generated code (`$Order`, `$query`, `$rowVersion`). Model identifiers (entities, fields, services, namespaces) cannot contain `$`, so these names never collide. They are part of the public API and can be used.
- **Check access tokens.** A service without an explicit token requires an authenticated account ([ACCESS_CONTROL.md](./skills/ACCESS_CONTROL.md)).
