# Track Spec: Unified Agent Interface and SQL-Driven Persistence Refactor

## Overview
This track implements a major architectural shift in how Monad Assistant interacts with its persistence layer. We will unify the tool interface provided to the LLM and provide the agent with a "RAW SQL" capability, allowing it wide latitude to manage its own tables while enforcing strict immutability for Notes and Archives via SQLite triggers.

## Functional Requirements

### 1. Unified Tool Interface
- Consolidate disparate data tools into a simplified interface that focuses on direct database interaction and high-level reasoning.

### 2. RAW SQL Execution Tool
- Implement an `ExecuteSQLTool` that allows the agent to run arbitrary SQLite commands.
- **Agent Latitude:** The agent is encouraged to create its own tables and manage state as it sees fit, using the core schema only as a starting point.

### 3. table_directory System
- Implement a `table_directory` table that stores table names, creation dates, and agent-editable descriptions.
- **Auto-Sync:** The system should automatically detect new and deleted tables to keep this directory up-to-date.

### 4. Database-Level Protection (SQLite Triggers)
- **Notes Immutability:** Implement SQLite triggers to ensure `note` records cannot be deleted.
- **Archive Immutability:** Ensure `conversationMessage` and `conversationSession` (once archived) cannot be deleted or modified.

### 5. Refined Context Logic
- **Global Notes:** Remove the `alwaysAppend` flag from the `Note` model. All notes in the database are now injected globally into the system prompt.
- **Recall-Based Memory:** Refine `ContextManager` to inject `Memory` records based on semantic relevance (recall).

### 6. UI Proxy & Confirmation Layer
- Implement a proxy layer in `ChatViewModel` that intercepts sensitive SQL operations (CREATE, DROP, DELETE).
- **Confirmation Dialog:** Trigger a SwiftUI confirmation dialog for sensitive actions, allowing the user to approve or cancel the execution.

## Technical Details
- **Module:** `MonadCore` (Persistence and Tool logic), `MonadUI` (UI Proxy and Dialogs).
- **Persistence:** GRDB for SQLite interaction and trigger management.
- **Logic:** Refactor `ContextManager` and `PromptBuilder` to align with new injection rules.

## Acceptance Criteria
- Agent can successfully create and query custom tables via SQL.
- `table_directory` correctly tracks schema changes and allows the agent to persist descriptions.
- Database triggers correctly block forbidden operations on core tables.
- All notes are present in the system prompt.
- Sensitive SQL commands trigger a user confirmation dialog.
