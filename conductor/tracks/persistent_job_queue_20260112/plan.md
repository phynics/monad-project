# Plan: Persistent and Autonomous Job Queue

## Phase 1: Database Migration and Model Refactor
Move the `Job` model to the persistence layer and create the database table.

- [x] Task: Refactor: Update the `Job` model to conform to `GRDB` protocols (`FetchableRecord`, `PersistableRecord`).
- [x] Task: Implement Feature: Add migration v14 to `DatabaseSchema.swift` to create the `job` table. 58cb52c
- [x] Task: Write Tests: Verify the `job` table creation and basic persistence in a new test file `JobPersistenceTests.swift`. 58cb52c

## Phase 2: Persistence Service Integration [checkpoint: 58cb52c]
Implement the backend logic for job management.

- [x] Task: Implement Feature: Add job-related methods to `PersistenceServiceProtocol` and `PersistenceService`. 58cb52c
- [x] Task: Write Tests: Extend `JobPersistenceTests.swift` to cover CRUD operations through `PersistenceService`. 9229a3e

## Phase 3: JobQueueContext Refactoring [checkpoint: 9229a3e]
Update the tool context to use the persistent store.

- [x] Task: Refactor: Update `JobQueueContext` to use `PersistenceService` instead of in-memory storage. 9229a3e
- [x] Task: Write Tests: Update existing `JobQueueTests.swift` (or create if missing) to verify tool-based job management. 9229a3e

## Phase 4: Integration and Agent Awareness [checkpoint: 9229a3e]
Finalize the feature and update agent guidance.

- [x] Task: Implement Feature: Ensure `table_directory` is synced after the `job` table is created. 9229a3e
- [x] Task: Implement Feature: Update `DefaultInstructions.swift` to explain the persistent job queue and SQL access. 9229a3e
- [x] Task: Conductor - User Manual Verification 'Persistent and Autonomous Job Queue' 9229a3e

# Track Complete
