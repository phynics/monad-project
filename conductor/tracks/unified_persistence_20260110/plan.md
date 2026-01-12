# Track Plan: Unified Agent Interface and SQL-Driven Persistence Refactor

## Phase 1: Database-Level Protection [checkpoint: c13df42]
Implement strict immutability for core data types using SQLite-level constraints.

- [x] Task: Write Tests: Verify that `DELETE` operations on the `note` table and `UPDATE/DELETE` on the `message` (archive) table fail at the database level. c13946b
- [x] Task: Implement Feature: Update `DatabaseSchema.swift` to add SQLite triggers or an authorizer callback to enforce immutability for Notes and Archives. c13946b
- [x] Task: Refactor: Remove the `alwaysAppend` property from the `Note` model and update related database migrations. c13946b
- [x] Task: Conductor - User Manual Verification 'Database-Level Protection' (Protocol in workflow.md) [checkpoint: c13df42]

## Phase 2: RAW SQL Tool and Interface Unification [checkpoint: 1136460]
Enable the agent to manage its own persistence while consolidating the tool surface.

- [x] Task: Write Tests: Verify that a new `ExecuteSQLTool` can successfully create custom tables, insert data, and query it. 18ece97
- [x] Task: Implement Feature: Create `ExecuteSQLTool` in `MonadCore` using `GRDB`'s raw execution capabilities. 18ece97
- [x] Task: Implement Feature: Consolidate existing search/load tools into a unified interface that encourages SQL-based data retrieval. 18ece97
- [x] Task: Conductor - User Manual Verification 'RAW SQL Tool and Interface Unification' (Protocol in workflow.md) [checkpoint: 1136460]

## Phase 3: Context Engine Refinement and UI Proxy [checkpoint: eeff2bd]
Update the prompt construction logic and implement the user confirmation safety layer.

- [x] Task: Implement Feature: Refine `ContextManager` to inject all notes globally and use vector-based recall for memories only. 48a5e3c
- [x] Task: Write Tests: Verify that the SQL execution proxy correctly identifies "sensitive" operations and requests user confirmation. 48a5e3c
- [x] Task: Implement Feature: Add a confirmation proxy in `ChatViewModel` that intercepts `ExecuteSQLTool` calls and triggers a SwiftUI confirmation dialog for specific patterns (e.g., `CREATE TABLE`, `DROP TABLE`). 48a5e3c
- [x] Task: Conductor - User Manual Verification 'Context Engine Refinement and UI Proxy' (Protocol in workflow.md) [checkpoint: eeff2bd]

## Phase 4: Prompting and Instruction Updates
Update all system instructions and default notes to reflect the new agent capabilities and persistence rules.

- [~] Task: Implement Feature: Update `DefaultInstructions.swift` and system prompt building logic to explain the `ExecuteSQLTool` and the latitude provided for database management.
- [ ] Task: Implement Feature: Update default system notes to remove outdated `alwaysAppend` references and provide clear guidance on the protected status of Archives and Notes.
- [ ] Task: Conductor - User Manual Verification 'Prompting and Instruction Updates' (Protocol in workflow.md)
