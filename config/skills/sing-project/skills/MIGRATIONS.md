# Migrations & Schema Evolution

This document explains how Sing manages database schema migrations as your model evolves.

## Overview

Sing's migration system:
- **Detects schema changes** by comparing your model with the database
- **Executes custom migrations** before and after Sing's schema DDL
- **Tracks versions** to determine what needs to be run
- **Runs** on server startup

Key principle: **Your model is the source of truth for the database schema**.

## How Migrations Work

### Core Concepts

**Migration Workflow**:
```
1. Developer defines migration steps (custom SQL)
2. Server startup: Compare database version vs. model version
3. If versions differ: Execute BeforeMigrationStep → Sing DDL → AfterMigrationStep
4. Update database version when complete
```

**Version Tracking**:
- **vBDD** (Database Version): Stored in database or file system or ..., retrieved by `getCurrentVersion()`
- **vModel** (Model Version): Timestamp from `ServerDataRegistry.version` (from code generation)
- **Decision**: If `vModel > vBDD`, run migration steps with timestamp in range (vBDD, vModel]

### Migration Class Structure

Developers create migration classes in the model package:

```dart
// model/lib/model/[namespace]/[entity].migrations.dart
import 'package:sing_server/sing_server.dart';
import 'package:model/server.dart';

class OrderMigrations extends Migrations<Order> {
  /// Version tracking: Used to determine which steps to run
  @override
  int get version => 1;  // Increment when adding migration steps

  /// Migration steps to execute
  @override
  List<MigrationStep> get steps => [
    BeforeMigrationStep(
      timestamp: 1,  // Executes BEFORE Sing's DDL (if version jumping over this)
      description: 'Add temporary column for data migration',
      execute: (context) async {
        await context.database.query(
          'ALTER TABLE orders ADD COLUMN status_temp VARCHAR(50);'
        );
      },
    ),
    // Sing's auto-generated DDL runs here (table creation, column additions, etc.)
    AfterMigrationStep(
      timestamp: 2,  // Executes AFTER Sing's DDL
      description: 'Migrate data from status_temp to status',
      execute: (context) async {
        await context.database.query(
          'UPDATE orders SET status = status_temp WHERE status IS NULL;'
        );
        await context.database.query(
          'ALTER TABLE orders DROP COLUMN status_temp;'
        );
      },
    ),
  ];

  /// Get current database version (must be implemented by developer)
  @override
  Future<int> getCurrentVersion(DataControler dataControler) async {
    try {
      final result = await dataControler.query(
        'SELECT version FROM schema_version ORDER BY version DESC LIMIT 1;'
      );
      if (result.isNotEmpty) {
        return int.parse(result.first['version'].toString());
      }
      return 0;  // No migrations run yet
    } catch (e) {
      return 0;  // Table doesn't exist yet
    }
  }

  /// Set database version after successful migration (must be implemented)
  @override
  Future<void> setCurrentVersion(DataControler dataControler, int version) async {
    await dataControler.query(
      'INSERT INTO schema_version (version, applied_at) VALUES ($version, NOW());'
    );
  }
}
```

## Migration Execution Flow

### Server Startup Sequence

```
┌─────────────────────────────────────────────────────┐
│ Server Starts                                       │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
        ┌─────────────────────┐
        │ Create DataRegistry │
        │ Load ServerEntityDef│
        └──────────┬──────────┘
                   │
                   ▼
    ┌──────────────────────────────────┐
    │ Query: getCurrentVersion()        │
    │ Returns: vBDD (from database)     │
    │ vModel = ServerDataRegistry.version
    └──────────────┬───────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
        ▼                     ▼
    vModel > vBDD       vModel == vBDD
        │                     │
        │                     ▼
        │                 ✅ Ready (no migration needed)
        │
        ▼
  ┌─────────────────────────────────────┐
  │ For each migration step:             │
  │   if step.timestamp > vBDD:          │
  │     Execute the step                 │
  │   (timestamps order execution)       │
  └─────────────────────────────────────┘
        │
        ├─ BeforeMigrationStep (timestamp <= vModel)
        ├─ Sing DDL operations
        ├─ AfterMigrationStep (timestamp <= vModel)
        │
        ▼
  ┌──────────────────────────┐
  │ setCurrentVersion(vModel)│
  └──────────────────────────┘
        │
        ▼
  ✅ Ready (migrations complete)
```

## Example: Renaming an Entity Field

### Scenario
Rename `status` to `orderStatus` in OrderEntity to avoid naming conflicts.

### Step 1: Define Migration

```dart
// model/lib/model/orders/order.migrations.dart
class OrderMigrations extends Migrations<Order> {
  @override
  List<MigrationStep> get steps => [
    BeforeMigrationStep(
      timestamp: 1,
      description: 'Create orderStatus column',
      execute: (context) async {
        await context.database.query(
          'ALTER TABLE orders ADD COLUMN order_status VARCHAR(50);'
        );
      },
    ),
    // Sing's DDL will handle the old 'status' column
    AfterMigrationStep(
      timestamp: 2,
      description: 'Migrate data from status to orderStatus',
      execute: (context) async {
        await context.database.query(
          'UPDATE orders SET order_status = status;'
        );
        await context.database.query(
          'ALTER TABLE orders DROP COLUMN status;'
        );
      },
    ),
  ];

  @override
  Future<int> getCurrentVersion(DataControler dataControler) async {
    // Implementation (see above)
  }

  @override
  Future<void> setCurrentVersion(DataControler dataControler, int version) async {
    // Implementation (see above)
  }
}
```

### Step 2: Update Model

```dart
// model/lib/model/orders/order.dart
@StdEntityServices()
class OrderEntity extends ModelEntity with UuidPrimaryKeyMixin {
  final customerName = StringField(maxLength: 100);
  final orderStatus = EnumStringField<OrderStatus>();  // ← Renamed!
  final totalAmount = DoubleField();
}
```

### Step 3: Increment Version

```dart
class OrderMigrations extends Migrations<Order> {
  @override
  int get version => 2;  // Increment to trigger migration
  // ... steps and implementations
}
```

### Step 4: Regenerate and Deploy

```bash
# Regenerate with new model
dart run sing_builder generate

# Deploy and start server (migrations run automatically)
dart run orderhub_server
```

## Idempotency & Safety

### Sing's Guarantees

Sing's generated DDL operations are **idempotent**:
- `CREATE TABLE IF NOT EXISTS` (safe if table exists)
- `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` (safe if column exists)
- `CREATE INDEX IF NOT EXISTS` (safe if index exists)

**Developer Responsibility**: Custom migration steps must also be idempotent.

### Making Custom Steps Idempotent

```dart
// ❌ BAD: Not idempotent
AfterMigrationStep(
  timestamp: 1,
  description: 'Add column',
  execute: (context) async {
    await context.database.query(
      'ALTER TABLE orders ADD COLUMN status_old VARCHAR(50);'
    );  // Fails if column already exists
  },
),

// ✅ GOOD: Idempotent
AfterMigrationStep(
  timestamp: 1,
  description: 'Add column',
  execute: (context) async {
    await context.database.query(
      'ALTER TABLE orders ADD COLUMN IF NOT EXISTS status_old VARCHAR(50);'
    );  // Safe to run multiple times
  },
),

// Or use conditional check
AfterMigrationStep(
  timestamp: 2,
  description: 'Update data if needed',
  execute: (context) async {
    final result = await context.database.query(
      'SELECT COUNT(*) FROM orders WHERE status_old IS NOT NULL;'
    );
    if (result.first['count'] == 0) {
      // Only update if needed
      await context.database.query(
        'UPDATE orders SET status_old = status;'
      );
    }
  },
),
```

## Version Comparison & Handling

### Example: Multiple Migrations

When you have several migrations and multiple versions need to run:

```dart
// Model version = 5 (current)
// Database version = 2 (last run)
// Action: Run all steps with timestamp > 2 and <= 5

List<MigrationStep> steps = [
  BeforeMigrationStep(timestamp: 1, ...),   // Skip (1 <= 2)
  BeforeMigrationStep(timestamp: 3, ...),   // Run (3 > 2)
  BeforeMigrationStep(timestamp: 5, ...),   // Run (5 > 2)
  AfterMigrationStep(timestamp: 4, ...),    // Run (4 > 2)
];

// Execution order: sorted by timestamp
// 1. All BeforeMigrationStep steps (ascending timestamp)
// 2. Sing's DDL operations
// 3. All AfterMigrationStep steps (ascending timestamp)
```

### Error Handling

If migration fails, it's your responsibility to:
1. **Check database state** - Determine what succeeded
2. **Fix the issue** - Correct the invalid data or SQL
3. **Restart server** - Migrations re-run from scratch (idempotency)

**Warning**: If your custom steps are NOT idempotent and fail halfway, manual database cleanup may be required.

## Migration Context

The `context` parameter provides database access:

```dart
class MigrationContext {
  /// Direct database access
  final DataControler database;

  /// Current migration step info
  final String stepDescription;
  final int stepTimestamp;

  /// Logging
  final Function(String) log;
}

// Usage
BeforeMigrationStep(
  timestamp: 1,
  description: 'Complex migration',
  execute: (context) async {
    context.log('Step 1: Starting migration');

    final rows = await context.database.query('SELECT COUNT(*) FROM orders');
    context.log('Found ${rows.first["count"]} orders');

    // Modify data
    await context.database.query('UPDATE orders SET ...');

    context.log('Migration complete');
  },
),
```

## Best Practices

### ✅ Good: Additive Changes

```dart
// Safe: Add new nullable column
class OrderEntity extends ModelEntity {
  final shippingAddress = StringField(maxLength: 255).nullable();
}

// Generated migration: ALTER TABLE orders ADD COLUMN IF NOT EXISTS ...
// No custom steps needed
```

### ✅ Good: Plan Data Migrations

```dart
// When changing field type, plan the migration
BeforeMigrationStep(
  timestamp: 1,
  description: 'Create temporary column for migration',
  execute: (context) async {
    await context.database.query(
      'ALTER TABLE orders ADD COLUMN IF NOT EXISTS quantity_new INT;'
    );
  },
),

AfterMigrationStep(
  timestamp: 2,
  description: 'Convert quantity from string to int',
  execute: (context) async {
    await context.database.query(
      'UPDATE orders SET quantity_new = CAST(quantity AS INTEGER) WHERE quantity IS NOT NULL;'
    );
    await context.database.query(
      'ALTER TABLE orders DROP COLUMN quantity;'
    );
    await context.database.query(
      'ALTER TABLE orders RENAME COLUMN quantity_new TO quantity;'
    );
  },
),
```

### ✅ Good: Test Migrations

```bash
# 1. Test on development database
export DATABASE_URL=postgres://user:pass@localhost/orderhub_dev
dart run orderhub_server

# 2. Verify schema
psql orderhub_dev -c "\d orders"

# 3. Check data
psql orderhub_dev -c "SELECT COUNT(*) FROM orders;"

# 4. Then deploy to staging/production
```

### ❌ Bad: Removing Fields Without Migration

```dart
// Old model
class OrderEntity extends ModelEntity {
  final status = StringField();
  final legacyField = StringField();  // To be removed
}

// Simply deleting field without migration
class OrderEntity extends ModelEntity {
  final status = StringField();
  // ❌ legacyField removed, data lost!
}
```

### ❌ Bad: Non-Idempotent Steps

```dart
// Problem: If server restarts, runs migration twice
AfterMigrationStep(
  timestamp: 1,
  description: 'Insert default data',
  execute: (context) async {
    // ❌ This will fail on second run (duplicate key)
    await context.database.query(
      "INSERT INTO order_statuses VALUES ('pending', 'Pending Order');"
    );
  },
),

// Solution: Use INSERT ... ON CONFLICT DO NOTHING
AfterMigrationStep(
  timestamp: 1,
  description: 'Insert default data',
  execute: (context) async {
    // ✅ Safe on multiple runs
    await context.database.query(
      "INSERT INTO order_statuses VALUES ('pending', 'Pending Order') "
      "ON CONFLICT (status) DO NOTHING;"
    );
  },
),
```

## Multi-Environment Migrations

### Development

Migrations run automatically:
```dart
final registry = OrderHub$Registry(
  dataControler: PgDataControler(
    host: 'localhost',
    database: 'orderhub_dev',
  ),
);
// ✅ Migrations run, schema updated
```

### Production

Requires manual execution:
```dart
// 1. Deploy code (but don't start server)
// 2. Run migrations manually
dart run sing_builder run-migrations \
  --database postgres://user:pass@prod/orderhub

// 3. Verify success
psql -h prod-db orderhub -c "\d orders"

// 4. Start server
dart run orderhub_server
```

## Integration with sing_processes

Sing uses `SingMigrationProcess` to coordinate migrations:

```dart
// From sing_processes package
import 'package:sing_processes/sing_processes.dart';

class SingMigrationProcess {
  /// Runs all pending migrations
  Future<MigrationResult> runMigrations(
    DataRegistry registry,
    List<Migrations> allMigrations,
  );

  /// Reports on migration status
  Future<MigrationStatus> getStatus();
}
```

Reference: `sing_processes/lib/src/migrations/migration_process.dart`

## Troubleshooting

### Issue: Migration Fails Midway

```
Error: Cannot apply migration, constraint violation
```

**Solution**:
```bash
# 1. Check what succeeded
psql orderhub -c "\d orders"

# 2. Fix the issue (correct data or SQL)
psql orderhub -c "UPDATE orders SET ... WHERE ..."

# 3. Restart server (idempotent steps re-run safely)
dart run orderhub_server
```

### Issue: Database Version Out of Sync

```
Error: Database version 3, model version 5 (gap > 1)
```

**Solution**:
```bash
# 1. Check database version
psql orderhub -c "SELECT * FROM schema_version ORDER BY version DESC LIMIT 1;"

# 2. Check model version (from generated code)
grep "const version" model/lib/sing/server_registry.dart

# 3. If database behind, delete intermediate versions and let migration run
psql orderhub -c "DELETE FROM schema_version WHERE version > 3;"
```

---

**Related Code**:
- Migration implementation: `sing_server/lib/src/migrations/migrations.dart`
- Migration orchestration: `sing_processes/lib/src/migrations/migration_process.dart`
- Example entities: `example/orderhub/model/lib/model/`

