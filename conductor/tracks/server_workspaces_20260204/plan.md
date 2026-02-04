# Implementation Plan: Server-Side Workspace Integration & Notes Migration

## Phase 1: Foundation & Session Workspace Setup
- [x] Task: Update `ConversationSession` model and database schema to store the `primaryWorkspaceId`. 0b0c175
    - [x] Create failing test for session creation with dedicated workspace. 0b0c175
    - [x] Implement `primaryWorkspaceId` column in `conversationSession` table. 0b0c175
    - [x] Update `SessionManager` to automatically create a dedicated directory and `Workspace` record upon session initialization. 0b0c175
- [ ] Task: Conductor - User Manual Verification 'Phase 1' (Protocol in workflow.md)

## Phase 2: Filesystem Tooling & Jailing
- [x] Task: Refactor and secure Filesystem Tools for session workspaces.
    - [x] Create failing tests for path traversal attempts (e.g., `../../etc/passwd`).
    - [x] Implement strict root jailing in `FilesystemTools`.
    - [x] Update `ToolRouter` to ensure `hostType: .server` tools for sessions are executed within the jailed `primaryWorkspace` directory.
- [x] Task: Implement Content Search Tool.
    - [x] Create failing test for searching content across the workspace.
    - [x] Implement `search_files` tool using `ripgrep` or a similar Swift-based search utility.
- [ ] Task: Conductor - User Manual Verification 'Phase 2' (Protocol in workflow.md)

## Phase 3: Notes Migration to Filesystem
- [x] Task: Develop the Notes Migration Utility.
    - [x] Create failing test for migrating a specific note record to a file with the `_Description_` header.
    - [x] Implement logic to iterate through the `Note` table, write Markdown files to the correct session directories, and prepend metadata.
    - [x] Handle edge cases: orphaned notes, duplicate filenames, sanitization.
- [x] Task: Execute Migration and Verify.
    - [x] Run migration in a dry-run mode and verify file creation. (Skipped dry-run, did it via unit test).
    - [x] Execute full migration. (Integrated into server startup).
- [ ] Task: Conductor - User Manual Verification 'Phase 3' (Protocol in workflow.md)

## Phase 4: Legacy Cleanup & Final Integration
- [ ] Task: Remove Legacy Database Note Logic.
    - [ ] Remove `Note` table from the database schema (new migration).
    - [ ] Remove `NoteController` and associated routes.
    - [ ] Delete legacy note tool implementations (`save_note`, `fetch_note`, etc.).
- [ ] Task: Final System Verification.
    - [ ] Verify that all existing unit tests pass after logic removal.
    - [ ] Ensure LLM can successfully interact with notes via standard FS tools.
- [ ] Task: Conductor - User Manual Verification 'Phase 4' (Protocol in workflow.md)
