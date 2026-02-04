# Specification: Server-Side Workspace Integration & Notes Migration

## Overview
This track focuses on the deep integration of the Workspace feature on the server side. The primary change is the shift from database-backed "Notes" to a filesystem-based approach where each session has its own dedicated, persistent directory. Existing notes will be migrated into this new structure, and the legacy database note tools will be replaced by jail-restricted filesystem tools.

## Functional Requirements

### 1. Session Workspace Lifecycle
- Every conversation session must be associated with a dedicated, persistent directory on the server.
- This directory serves as the "Primary Workspace" for the session.
- The directory must persist as long as the session exists.

### 2. Filesystem-Based Notes
- Notes are no longer stored primarily in the database.
- Notes will be stored as Markdown files under `[primary-workspace]/Notes/*.md`.
- **Note Format Convention:** The first line of each note file must contain its description in the format: `_Description: [Actual Description]_`.

### 3. Tool Execution & Jailing
- **Legacy Removal:** Remove all tools specifically designed for database-backed notes (e.g., `save_note`, `fetch_note`, `list_notes` from the DB).
- **Standard FS Tools:** Enable `list_files`, `read_file`, `write_file`, `delete_file`, `move_file`, and `create_directory` for session workspaces.
- **Search Tool:** Enable a `search_files` tool (grep-style) for searching content within the workspace.
- **Strict Jailing (Root Restriction):** All filesystem operations must be strictly confined to the session's directory. Any attempt to access paths outside the root (e.g., via `../`) must be blocked and return a warning/error to the LLM.

### 4. Data Migration
- Implement a migration process that:
    1. Iterates through all existing `Note` records in the database.
    2. Identifies the associated session (or creates a default one if orphaned).
    3. Writes the note content to the session's `Notes/` directory as a `.md` file.
    4. Prepends the `_Description_` header using the note's database metadata.
    5. Safely decommissions the `Note` database table after verification.

## Non-Functional Requirements
- **Performance:** Filesystem operations and jailing checks should add minimal latency to tool execution.
- **Data Integrity:** The migration must ensure no note content is lost and that file paths are sanitized.

## Acceptance Criteria
- [ ] New sessions automatically create a dedicated directory.
- [ ] Notes created by the LLM or user appear as `.md` files in the workspace.
- [ ] Standard FS tools can manipulate these files but cannot escape the session root.
- [ ] Legacy note tools are no longer available in the tool registry.
- [ ] Existing database notes are successfully migrated to the filesystem.

## Out of Scope
- Implementing cloud-based workspace sync (this track focuses on local/server-local filesystem).
- Multi-user permission sets for a single session workspace (beyond the basic owner check).
