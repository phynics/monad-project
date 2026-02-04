# Track Spec: CLI/Server Sync, Workspace Robustness, and Prune Command Completion

## Overview
This track focuses on harmonizing the Monad CLI and Server after recent architectural shifts to file-based notes and personas. It ensures that the session lifecycle—from resumption to initialization—is seamless, and that the agent has a well-structured primary workspace with appropriate persona-driven context. Additionally, it replaces legacy note commands with workspace-aware filesystem interactions, completes the `/prune` functionality, and ensures the agent can proactively manage client-side workspaces.

## Functional Requirements

### 1. Session & Workspace Lifecycle
- **Automatic Resumption:** The CLI must attempt to resume the last active session stored in local configuration.
- **Client-Side Workspace Recovery:** If a resumed session had client-side (local) workspaces attached, the CLI must prompt the user to confirm each one and attempt to re-create the attachment.
- **New Session Initialization:**
    - Offer an interactive persona selection menu during new session creation.
    - Automatically initialize the primary server-side workspace.
    - **Note Seeding:** Populate the `Notes/` directory in the primary workspace with:
        - `Welcome.md`: A guide to Monad's workspace features.
        - `Project.md`: An agent-populated note describing the current session's goals.
    - **Persona Seeding:** Populate a `Personas/` directory in the primary workspace with a standard set of default personas (e.g., `Default.md`, `ProductManager.md`, `Architect.md`).
- **Client-Side Tool Injection:** Ensure the `offer_attach_pwd` tool is available to the agent immediately upon CLI connection, even if no workspaces are currently attached. This tool should be treated as a "Client-Intrinsic" tool.

### 2. Workspace-Aware Filesystem Slash Commands
Replace legacy commands with direct filesystem interactions. Commands target the **primary workspace** by default but support targeting any attached workspace via an identifier prefix (e.g., `@ws_id/path` or `[uri]/path`).

- **`/ls [path]`**: List files and directories. Defaults to the `Notes/` directory of the primary workspace.
- **`/cat <path>`**: Output the content of a file to the terminal.
- **`/edit <path>`**: Open the specified file in the user's `$EDITOR` (defaulting to `vi`) for modification.
- **`/rm <path>`**: Delete the specified file with a confirmation prompt.
- **`/write <path>`**: Create a new file or overwrite an existing one (interactive content entry).

### 3. Persona & Prune Fixes
- **`/personas` & `/persona`**:
    - Fix `/persona use` to correctly update the active persona for the current session on the server.
    - Ensure personas are loaded from the workspace's `Personas/` directory.
- **`/prune`**:
    - **Memories**: Support bulk deletion matching a query or based on "last used" timestamp.
    - **Archives/Messages**: Support bulk deletion based on creation date range.
    - **Sessions**: Support bulk deletion of sessions based on age (days since last activity).

### 4. Agent & Prompt Updates
- **System Instructions**:
    - **Primary Workspace Purpose**: Instruct the agent that the primary workspace is its persistent "long-term memory" for the session, containing its `Notes/` and `Personas/`.
    - **Workspace Tool Usage**: Teach the agent how to distinguish between and operate on multiple attached workspaces using workspace-scoped tool calls.
    - **Proactive Attachment**: Instruct the agent to proactively use `offer_attach_pwd` if the user's intent involves local development or file access and the current directory is not yet attached.
- **Automatic Seeding:** The agent must be instructed to automatically fill in the `Project.md` note upon first interaction in a new session based on the user's initial request.

## Non-Functional Requirements
- **Robustness**: Graceful handling of server connection failures during session resumption.
- **Security**: Ensure filesystem commands are restricted to the target workspace root (jailing).
- **User Control**: Always confirm sensitive operations like re-attaching local workspaces or pruning data.

## Acceptance Criteria
- [ ] CLI resumes the last session or initializes a new one with persona selection.
- [ ] Primary workspace is correctly seeded with `Welcome.md`, `Project.md`, and default `Personas/`.
- [ ] `offer_attach_pwd` is available to the agent even with zero workspaces attached.
- [ ] Filesystem slash commands (`/ls`, `/cat`, `/edit`, `/rm`, `/write`) function correctly.
- [ ] `/prune` commands for memories, archives, and sessions successfully delete the specified records.
- [ ] The agent proactively offers to attach the local directory when relevant.

## Out of Scope
- Implementation of a graphical file explorer.
- Multi-user workspace permissions.
