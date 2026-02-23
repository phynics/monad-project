# Specification: Workspace Management System

## Overview
Implement a `Workspace` management system within `MonadCore`. This system will be responsible for isolating user sessions, managing their respective context engines, and handling persistence boundaries.

## Requirements
- **Session Isolation**: Each `Workspace` must represent a unique session with its own memory and context.
- **Persistence**: Workspaces must be able to save and load their state using the existing GRDB/SQLite infrastructure.
- **Context Integration**: Each workspace should own an instance of the context engine and vector memory.
- **API Support**: MonadServer should be able to create, switch, and delete workspaces via REST/WebSocket.

## Architecture
- `WorkspaceManager`: A central actor/class to manage the lifecycle of multiple workspaces.
- `Workspace`: A data structure or class representing a single session's state.
- `WorkspaceStorage`: Integration with GRDB to persist workspace-specific data.
