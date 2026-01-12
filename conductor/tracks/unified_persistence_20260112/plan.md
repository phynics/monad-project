# Track Plan: Unified Agent Interface and SQL-Driven Persistence Refactor

## Phase 1: Database-Level Protection and Note Refactor [checkpoint: 8ea3fe2]
Enforce core immutability and simplify the Note model.

- [x] Task: Refactor: Remove the `alwaysAppend` property from the `Note` model and update all related database schema definitions. 97f992b
- [x] Task: Implement Feature: Update `DatabaseSchema.swift` to add SQLite triggers that block `DELETE` on notes and `DELETE/UPDATE` on archived messages and sessions. 489a7bb
- [x] Task: Write Tests: Create `PersistenceImmutabilityTests.swift` to verify that trigger violations correctly throw errors at the database level. 489a7bb
- [ ] Task: Conductor - User Manual Verification 'Database-Level Protection and Note Refactor' (Protocol in workflow.md)

## Phase 2: Table Directory and RAW SQL Tool [checkpoint: 06264ed]
Implement the self-documenting schema system and the unified agent tool.

- [x] Task: Implement Feature: Create the `table_directory` table and implement the synchronization logic in `PersistenceService` to track table creation/deletion. 025f795
- [x] Task: Implement Feature: Implement `ExecuteSQLTool` in `MonadCore` using `GRDB` raw execution, ensuring results are returned in a JSON-compatible format. 025f795
- [x] Task: Implement Feature: Consolidate existing data retrieval tools into the unified `ExecuteSQLTool` and update `ChatViewModel+Tools`. 142bef0
- [x] Task: Write Tests: Verify `table_directory` sync and `ExecuteSQLTool` functionality for custom table management. 025f795
- [ ] Task: Conductor - User Manual Verification 'Table Directory and RAW SQL Tool' (Protocol in workflow.md)

## Phase 3: UI Proxy and Safety Layer
Add the user-confirmation step for sensitive database operations.

- [x] Task: Implement Feature: Add a confirmation proxy in `ChatViewModel` that intercepts SQL calls and detects sensitive patterns (CREATE, DROP, DELETE). 489a7bb
- [x] Task: Implement Feature: Update `ContentView` to display a SwiftUI confirmation dialog for intercepted SQL operations. 489a7bb
- [ ] Task: Write Tests: Verify that the proxy correctly pauses execution and respects user 'Cancel' vs 'Execute' decisions.
- [ ] Task: Conductor - User Manual Verification 'UI Proxy and Safety Layer' (Protocol in workflow.md)

## Phase 4: Context Engine Refinement and Instructions
Finalize the prompting logic and update system-level guidance.

- [ ] Task: Implement Feature: Update `ContextManager` to inject all database notes globally into the system prompt.
- [ ] Task: Implement Feature: Refine `DefaultInstructions.swift` and default system notes to explain the new SQL latitude and persistence constraints.
- [ ] Task: Refactor: Remove all obsolete tool implementation files from `MonadCore`.
- [ ] Task: Conductor - User Manual Verification 'Context Engine Refinement and Instructions' (Protocol in workflow.md)
