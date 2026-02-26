# System Architecture

Monad follows a modular architecture designed to separate core logic, server infrastructure, and client interfaces. The project is organized into distinct Swift targets, each with a specific responsibility.

## Module Overview

### MonadCore: The engine room
Contains the foundational library for all domain logic, data models, and business rules. Models are organized into focused subdirectories (`Agents/`, `Chat/`, `Configuration/`, `Context/`, `Database/`, `Tools/`, `Workspace/`).
- **Data Models**: `Message`, `Memory`, `Job`, `Agent`, `Timeline` (the persistent conversation record, formerly `ConversationSession`). Persistent `Note` records have been removed in favour of filesystem-based Context Notes.
- **Configuration**: `LLMConfiguration` is the canonical config type, replacing the old `Configuration` wrapper struct. Split into `LLMProvider`, `ProviderConfiguration`, and `ToolCallFormat` files. MCP configuration has been removed.
- **Workspace Types**: `WorkspaceReference`, `WorkspaceURI`, `WorkspaceToolDefinition`, `WorkspaceAttachment`—each in its own file under `Models/Workspace/`.
- **Persistence**: Managed via `PersistenceService` using [GRDB](https://github.com/groue/GRDB.swift) for SQLite storage. `CompactificationNode` records have been removed.
- **Context Engine**: Handles RAG logic via `ContextManager` (Notes + Semantic Search via `SemanticSearchResult`).
- **Session Management**: Lifecycle of `Timeline` sessions via `SessionManager`.
- **Tool Logic**: Workspace-aware tool resolution via `ToolRouter`. `ToolReference` is a dedicated type for referencing tools. `StreamingParser` lives in `Services/LLM/`.

### MonadShared: Common types
Lightweight, dependency-free models used by all modules to prevent circular dependencies.
- **Types**: `ToolReference`, `WorkspaceReference`, `AnyCodable`, `ChatDelta`.

### MonadPrompt: Context DSL
A declarative DSL for constructing LLM prompts with built-in token management.
- **@ContextBuilder**: Composable prompt sections.
- **Budgeting**: Priority-based token allocation and compression strategies.

### MonadServer: The gateway
The backend server hosting the agent and exposing the brain to clients.
- **API Layer**: [Hummingbird](https://github.com/hummingbird-project/hummingbird) REST endpoints. API contract types are split into category-specific files (`ChatAPI`, `ClientAPI`, `CommonAPI`, etc.).
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
3. **Context Assembly**: `ChatEngine` uses `ContextManager` to gather RAG data and `ContextBuilder` (MonadPrompt) to construct the LLM prompt. Session history is stored in the `Timeline` record.
4. **Tool Execution**: If the LLM requests a tool, `ToolRouter` determines if the tool is local (server) or remote (client) and executes it in the appropriate context. Tool identity is tracked via `ToolReference`.
5. **Streaming**: Partial responses and tool execution status are streamed back via SSE using `ChatEvent`. `StreamingParser` (in `Services/LLM/`) handles incremental token parsing.
