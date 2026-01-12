# Spec: Persistent and Autonomous Job Queue

## Problem Statement
The current `JobQueueContext` manages jobs in an in-memory array (`_jobs`). This means all pending and in-progress tasks are lost when the application restarts. This limits the assistant's ability to handle long-running background tasks or maintain a persistent "To-Do" list across sessions.

## Objectives
1. **Persistent Storage:** Move the job queue from memory to the local SQLite database.
2. **SQL Integration:** Ensure the `job` table is fully integrated into the SQL latitude system, allowing the agent to query and manage it via `execute_sql` if necessary.
3. **Robust Autonomy:** Support the `autoDequeueEnabled` feature across restarts, enabling the agent to resume work automatically.
4. **Architectural Consistency:** Follow the existing project pattern of actor-based persistence and protocol-oriented logic.

## Functional Requirements
- **Database Schema:** A `job` table with columns: `id` (UUID), `title`, `description`, `priority` (INT), `status` (TEXT), `createdAt` (DATETIME), `updatedAt` (DATETIME).
- **CRUD Operations:** `PersistenceService` must support adding, updating, fetching, and deleting jobs.
- **Context Synchronization:** `JobQueueContext` must fetch from and save to the database.
- **Self-Documentation:** The `job` table must be automatically registered in the `table_directory`.

## Success Criteria
- Jobs created in one session persist after an app restart.
- The `ExecuteSQLTool` can query the `job` table successfully.
- All unit tests for `JobQueueContext` pass with the new persistent backend.
- Code coverage for the new persistence logic is >80%.
