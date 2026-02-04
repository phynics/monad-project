# Implementation Plan: CLI/Server Sync, Workspace Robustness, and Prune Command Completion

## Phase 1: CLI Session Lifecycle & Workspace Recovery
Goal: Ensure the CLI handles session resumption and new session initialization with persona selection.

- [x] Task: Write Tests: Verify `LocalConfigManager` handles `lastSessionId` and `clientWorkspaces` persistence.
- [x] Task: Implement Feature: Update `MonadCLI` to automatically resume the last session or show the new session menu.
- [x] Task: Implement Feature: Add persona selection menu to the new session flow in `MonadCLI`.
- [x] Task: Write Tests: Verify CLI prompts for re-attachment of local workspaces on session resumption.
- [x] Task: Implement Feature: Implement the confirmation and re-attachment logic for client-side workspaces in `MonadCLI`.
- [x] Task: Conductor - User Manual Verification 'Phase 1: Session Lifecycle' (Protocol in workflow.md)

## Phase 2: Server-Side Seeding & Persona Management
Goal: Seed the primary workspace and fix persona application.

- [x] Task: Write Tests: Verify `SessionManager` seeds `Notes/` and `Personas/` upon workspace initialization.
- [x] Task: Implement Feature: Update `SessionManager` to seed default files (`Welcome.md`, default personas).
- [x] Task: Write Tests: Verify `/api/sessions/{id}/persona` endpoint (or equivalent) updates session state.
- [x] Task: Implement Feature: Fix the persona update logic in `SessionManager` and expose/verify the endpoint.
- [x] Task: Conductor - User Manual Verification 'Phase 2: Seeding & Personas' (Protocol in workflow.md)

## Phase 3: Workspace-Aware Filesystem Commands
Goal: Replace legacy note commands with robust, workspace-aware filesystem slash commands.

- [x] Task: Write Tests: Verify `ChatREPL` correctly parses workspace identifiers (e.g., `@ws/path`) from commands.
- [x] Task: Implement Feature: Implement `/ls`, `/cat`, `/edit`, `/rm`, and `/write` in `ChatREPL`.
- [x] Task: Implement Feature: Ensure these commands target the primary workspace by default and support scoped identifiers.
- [x] Task: Implement Feature: Remove legacy `/notes` and `/note` command handlers.
- [x] Task: Conductor - User Manual Verification 'Phase 3: FS Commands' (Protocol in workflow.md)

## Phase 4: Prune Command Implementation
Goal: Complete the bulk deletion functionality for memories, sessions, and messages.

- [x] Task: Write Tests: Verify `PersistenceService` can prune sessions and messages/archives by age/date range.
- [x] Task: Implement Feature: Implement `pruneSessions` and `pruneMessages` in `PersistenceService`.
- [x] Task: Implement Feature: Wire up `PruneController` and `MonadClient` for the new prune types.
- [x] Task: Implement Feature: Update `PruneCommand` in the CLI to support all pruning types with confirmation prompts.
- [x] Task: Conductor - User Manual Verification 'Phase 4: Prune Command' (Protocol in workflow.md)

## Phase 5: Agent Prompting & Intrinsic Tools
Goal: Update agent instructions and ensure client-side tools are available immediately.

- [x] Task: Write Tests: Verify `offer_attach_pwd` is sent to the server as a client tool even when no workspaces are attached.
- [x] Task: Implement Feature: Refactor `RegistrationManager` or `ChatREPL` to inject "intrinsic" client tools upon connection.
- [x] Task: Implement Feature: Update `PromptBuilder` and system instructions to include workspace-aware operating procedures.
- [x] Task: Implement Feature: Add instructions for the agent to automatically populate `Project.md` in new sessions.
- [x] Task: Conductor - User Manual Verification 'Phase 5: Agent Awareness' (Protocol in workflow.md)