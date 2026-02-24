# Implementation Plan: Workspace Management System

## Phase 1: Core Data Models & Storage [checkpoint: 1484b17]
- [x] Task: Define `Workspace` model and database schema d8f68c0
    - [x] Write unit tests for `Workspace` initialization and database mapping
    - [x] Implement `Workspace` struct and GRDB migrations
- [x] Task: Implement `WorkspaceRepository` for CRUD operations d8f68c0
    - [x] Write tests for saving and retrieving workspaces from SQLite
    - [x] Implement repository logic using GRDB
- [x] Task: Conductor - User Manual Verification 'Phase 1: Core Data Models & Storage' (Protocol in workflow.md)

## Phase 2: Workspace Manager Lifecycle [checkpoint: d8e0d4b]
- [x] Task: Create `WorkspaceManager` to handle active sessions
    - [x] Write tests for creating, fetching, and closing active workspaces
    - [x] Implement `WorkspaceManager` with thread-safe session tracking
- [x] Task: Integrate `Workspace` with `ContextEngine`
    - [x] Write tests ensuring each workspace gets its own context instance
    - [x] Implement dependency injection for context per workspace
- [x] Task: Conductor - User Manual Verification 'Phase 2: Workspace Manager Lifecycle' (Protocol in workflow.md)

## Phase 3: API & Server Integration [checkpoint: d8e0d4b]
- [x] Task: Add REST endpoints for workspace management in `MonadServer`
    - [x] Write integration tests for `/workspaces` (POST, GET, DELETE)
    - [x] Implement controller logic in Hummingbird
- [x] Task: Update `MonadCLI` to support workspace switching
    - [x] Write tests for CLI workspace commands
    - [x] Implement CLI interface for `workspace` command
- [x] Task: Conductor - User Manual Verification 'Phase 3: API & Server Integration' (Protocol in workflow.md)