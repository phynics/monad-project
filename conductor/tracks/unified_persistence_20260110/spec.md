# Track Spec: Unified Agent Interface and SQL-Driven Persistence Refactor

## Overview
This track implements a major architectural shift in how Monad Assistant interacts with its persistence layer. We will unify the tool interface provided to the LLM and provide the agent with a "RAW SQL" capability, allowing it wide latitude to manage its own tables while enforcing strict immutability for Notes and Archives.

## Functional Requirements

### 1. Unified Tool Interface
- Consolidate disparate data tools into a simplified interface that focuses on direct database interaction and high-level reasoning.

### 2. RAW SQL Execution Tool
- Implement a `ExecuteSQLTool` that allows the agent to run arbitrary SQLite commands.
- **Agent Latitude:** The agent is encouraged to create its own tables and manage state as it sees fit, using the core schema only as a starting point.

### 3. Database-Level Protection (SQLite Constraints)
- **Notes Immutability:** Implement SQLite triggers or authorizer rules to ensure `Note` records cannot be deleted.
- **Archive Immutability:** Ensure the `Archive` (Conversation History) cannot be deleted or modified once written.
- **Permission Layer:** Explore using SQLite's internal permission mechanisms to block forbidden operations programmatically.

### 4. Refined Context Logic
- **Global Notes:** Remove the `alwaysAppend` flag. Effectively, all records in the `Notes` table are now always appended to the system prompt.
- **Opportunistic Memory:** Refine the `ContextManager` to inject `Memory` records only when semantically relevant (recall-based).

### 5. Interaction Proxy & Confirmation
- Implement a proxy layer for the `ExecuteSQLTool`.
- **Optional Prompt:** Certain operations (e.g., table creation, large updates) can trigger a UI prompt requiring explicit user confirmation before execution.

### 6. Prompting and Instruction Updates
- Update all system instructions and default notes to reflect the new agent capabilities and persistence rules.

## Technical Details
- **Module:** `MonadCore` (Persistence and Tool logic), `MonadUI` (Confirmation prompts).
- **SQLite:** Leverage triggers and potentially `sqlite3_set_authorizer` for enforcement.
- **Swift:** Update `PersistenceService` to support raw execution while maintaining safety.

## Acceptance Criteria
- Agent can successfully create and query its own custom tables via SQL.
- Attempts to `DELETE` or `UPDATE` archived messages or notes fail at the database level.
- All notes are present in the system prompt regardless of previous flags.
- User is prompted for confirmation when specific SQL operations are attempted.
