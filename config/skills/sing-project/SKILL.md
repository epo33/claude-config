---
name: sing-project
description: "Expert on the Sing Dart framework for database-backed applications. Use on project having dependencies on Sing (package sing_core, sing_model, sing_client or sing_server).
---

Use this skill for any task or question related to the Sing framework.

## 1. What is Sing?

**Sing** is a Dart framework designed to simplify development of applications with complex data structures that:
- Store data in relational databases (PostgreSQL, Oracle, ...)
- Handle dozens or hundreds of entities with complex relationships
- Support multiple development tiers (server with direct DB access, clients without DB access)
- Ensure complete synchronization between model, database schema, server services, and client code

### 1.1. Core Philosophy

Sing follows a **model-first approach**:
1. Define your data model using classes from `sing_model` (`Model`, `ModelEntity`, `ModelNameSpace`)
2. Sing auto-generates service implementations, JSON serialization, and database schema based on your entity definitions and optional decorators
3. Same type-safe model is shared between server and client applications
4. Developers extend generated code with custom business logic

## 2. Key Concepts

### 2.1. Essential Topics

- [Initialize a project with Sing support](./skills/INIT_PROJECT.md)
- [Project Structure & Naming Conventions](./skills/PROJECT_STRUCTURE.md)
- [Model entities, namespaces, fields, CRUD services, search services](./skills/DATA_MODEL.md)
- [Defining services on entities or namespaces](./skills/SERVICES.md)
- [Control accesses to services or entity data](./skills/ACCESS_TOKEN.md)
- [How to prepare database schema migration](./skills/MIGRATIONS.md)
- [How to use Sing in server applications](./skills/APP_SERVER.md)
- [How to use Sing in client applications](./skills/APP_CLIENT.md)

### 2.2. Advanced Topics

- [Standards search services](./skills/SEARCHES.md)
- [Entity Relationships in Detail](./skills/CONCEPTS_RELATIONSHIPS.md)
- [Data Encapsulation Classes (DataRowValues, DataLoader, DataRow)](./skills/DATA_CLASSES.md)
- [Database Queries and Security](./skills/QUERIES.md)
- [Auto-JSON Serialization](./skills/AUTO_JSON.md)
- [Generated code principles - How to find entity fields, search params or namespaces](./skills/GENERATED_CODE.md)

## 3. Example Project

The **`example/orderhub`** directory contains a complete example:
- `model/` - Order, OrderLine, Product entities with relationships
- `common/` - Shared enumerations (OrderStatus, PaymentMethod, etc.)
- `model_sing_client/` - Auto-generated client API
- `orderhub_server/` - Backend server implementation
- `orderhub_client/` - Flutter client application

This example demonstrates:
- Multi-namespace model design
- One-to-Many relationships with cascade deletion
- Custom service implementation (adding orders with line items)
- Server-client separation

Use the orderhub example as reference for implementing similar applications.

## 4. Important Notes for LLM Agents

- **Always check entity definitions first**: The model is the source of truth
- **Generated code is sacred**: Don't modify files in `model/lib/sing/`, `common/lib/src/sing` or `model_sing_client/lib` manually - regenerate instead
- **Regenerate or rebuild code**: execute `dart run model/bin/sing_build.dart`. [Generated code principles](./skills/GENERATED_CODE.md)
- **Use mixins for service composition**: Don't create monolithic service classes
- **Type safety**: Leverage compile-time checking - avoid `dynamic` and string-based access
- **Patterns matter**: Follow examples in orderhub/ for consistency
- **Reference existing code**: Before creating new patterns, check how orderhub/ solves similar problems
- **`$` prefix convention**: Field/method names starting with `$` exist in some framework classes. This **avoids conflicts** with identifiers defined by the developer in the model (entity, field, service, namespace; no entity, namespace, service, or field identifier can contain `$`). These methods or fields can be legitimately used.

## 5. Reference Documentation Location

When this skill is invoked from a Sing project, additional documentation files are available in the `AGENT/` directory at the project root. These files provide detailed information on the topics mentioned above.
