# Implementation Plan: Workspace Management System

## Phase 1: Core Data Models & Storage
- [x] Task: Define `Workspace` model and database schema d8f68c0
    - [x] Write unit tests for `Workspace` initialization and database mapping
    - [x] Implement `Workspace` struct and GRDB migrations
- [x] Task: Implement `WorkspaceRepository` for CRUD operations d8f68c0
    - [x] Write tests for saving and retrieving workspaces from SQLite
    - [x] Implement repository logic using GRDB
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Core Data Models & Storage' (Protocol in workflow.md)

## Phase 2: Workspace Manager Lifecycle
- [ ] Task: Create `WorkspaceManager` to handle active sessions
    - [ ] Write tests for creating, fetching, and closing active workspaces
    - [ ] Implement `WorkspaceManager` with thread-safe session tracking
- [ ] Task: Integrate `Workspace` with `ContextEngine`
    - [ ] Write tests ensuring each workspace gets its own context instance
    - [ ] Implement dependency injection for context per workspace
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Workspace Manager Lifecycle' (Protocol in workflow.md)

## Phase 3: API & Server Integration
- [ ] Task: Add REST endpoints for workspace management in `MonadServer`
    - [ ] Write integration tests for `/workspaces` (POST, GET, DELETE)
    - [ ] Implement controller logic in Hummingbird
- [ ] Task: Update `MonadCLI` to support workspace switching
    - [ ] Write tests for CLI workspace commands
    - [ ] Implement CLI interface for `workspace` command
- [ ] Task: Conductor - User Manual Verification 'Phase 3: API & Server Integration' (Protocol in workflow.md)
