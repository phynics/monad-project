# System Architecture

Monad follows a modular architecture designed to separate core logic, server infrastructure, and client interfaces. The project is organized into distinct Swift targets, each with a specific responsibility.

## Module Overview

### MonadCore: The engine room
Contains the foundational library for all domain logic, data models, and business rules.
- **Data Models**: `Message`, `Memory`, `Job`, `Agent`, `Workspace`. (Persistent `Note` records have been removed in favor of filesystem-based Context Notes).
- **Persistence**: Managed via `PersistenceService` using [GRDB](https://github.com/groue/GRDB.swift) for SQLite storage.
- **Context Engine**: Handles RAG logic via `ContextManager` (Notes + Semantic Search).
- **Session Management**: Lifecycle of `ConversationSession` objects.
- **Tool Logic**: Workspace-aware tool resolution via `ToolRouter`.

### MonadShared: Common types
Lightweight, dependency-free models used by all modules to prevent circular dependencies.
- **Types**: `Message`, `ToolCall`, `ChatDelta`, `ToolReference`, `WorkspaceReference`, `AnyCodable`.

### MonadPrompt: Context DSL
A declarative DSL for constructing LLM prompts with built-in token management.
- **@ContextBuilder**: Composable prompt sections.
- **Budgeting**: Priority-based token allocation and compression strategies.

### MonadServer: The gateway
The backend server hosting the agent and exposing the brain to clients.
- **API Layer**: [Hummingbird](https://github.com/hummingbird-project/hummingbird) REST endpoints.
- **SSE Streaming**: Real-time event delivery protocol.
- **Environment**: Executes tool calls securely within workspace jails.
- **Discovery**: Auto-discovery via Bonjour/mDNS.

### MonadClient: Client library
Swift library for cross-platform integration, abstracting server communication.
- **RPC**: Forwards tool execution to client-hosted workspaces.
- **Discovery**: Client-side Bonjour discovery.

### MonadCLI: Development interface
A powerful REPL and command-line tool.
- **Interactive REPL**: Rich terminal interface for chat and debugging.
- **Slash Commands**:
  - **Chat**: `/help`, `/quit`, `/new`, `/clear`
  - **Session**: `/session` (info, list, switch, delete, rename, log)
  - **Data**: `/memory` (all, search, view), `/prune`
  - **Environment**: `/tool`, `/workspace`, `/job`, `/client`
  - **Filesystem**: `/ls`, `/cat`, `/rm`, `/write`, `/edit`
  - **System**: `/debug`, `/config`, `/status`

---

## Data Flow

1. **Input**: User sends a message via `MonadCLI` -> `MonadClient` -> `MonadServer`.
2. **Orchestration**: `MonadServer` routes the request to `ChatEngine`.
3. **Context Assembly**: `ChatEngine` uses `ContextManager` to gather RAG data and `ContextBuilder` (MonadPrompt) to construct the LLM prompt.
4. **Tool Execution**: If the LLM requests a tool, `ToolRouter` determines if the tool is local (server) or remote (client) and executes it in the appropriate context.
5. **Streaming**: Partial responses and tool execution status are streamed back via SSE using `ChatEvent`.
