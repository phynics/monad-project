# Plan: Persistent and Autonomous Job Queue

## Phase 1: Database Migration and Model Refactor [checkpoint: 6506f03]
Move the `Job` model to the persistence layer and create the database table.

- [x] Task: Refactor: Update the `Job` model to conform to `GRDB` protocols (`FetchableRecord`, `PersistableRecord`). 6506f03
- [x] Task: Implement Feature: Add migration v14 to `DatabaseSchema.swift` to create the `job` table. 6506f03
- [x] Task: Write Tests: Verify the `job` table creation and basic persistence in a new test file `JobPersistenceTests.swift`. 6506f03

## Phase 2: Persistence Service Integration [checkpoint: 6506f03]
Implement the backend logic for job management.

- [x] Task: Implement Feature: Add job-related methods to `PersistenceServiceProtocol` and `PersistenceService`. 6506f03
- [x] Task: Write Tests: Extend `JobPersistenceTests.swift` to cover CRUD operations through `PersistenceService`. 6506f03

## Phase 3: JobQueueContext Refactoring [checkpoint: 6506f03]
Update the tool context to use the persistent store.

- [x] Task: Refactor: Update `JobQueueContext` to use `PersistenceService` instead of in-memory storage. 6506f03
- [x] Task: Write Tests: Update existing `JobQueueTests.swift` (or create if missing) to verify tool-based job management. 6506f03

## Phase 4: Integration and Agent Awareness [checkpoint: 6506f03]
Finalize the feature and update agent guidance.

- [x] Task: Implement Feature: Ensure `table_directory` is synced after the `job` table is created. 6506f03
- [x] Task: Implement Feature: Update `DefaultInstructions.swift` to explain the persistent job queue and SQL access. 6506f03
- [x] Task: Conductor - User Manual Verification 'Persistent and Autonomous Job Queue' 6506f03

# Track Complete