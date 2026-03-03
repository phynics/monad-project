# Documentation Index

Comprehensive guide to Monad documentation.

## Quick Start

### For Getting Started
- **[../README.md](../README.md)** — Project overview, quick start, and basic usage

### For AI Assistants
- **[../AGENTS.md](../AGENTS.md)** — Quick reference: build commands, architecture, conventions, model layout, critical patterns

### For Developers
- **[../DEVELOPMENT.md](../DEVELOPMENT.md)** — Developer guide: setup, creating tools/endpoints/agents, testing, troubleshooting

## Core Documentation

### Architecture & Design

**[ARCHITECTURE.md](ARCHITECTURE.md)** — System architecture, module overview, and data flow
- Module responsibilities (MonadCore, MonadServer, MonadClient, etc.)
- Dependency hierarchy
- Data flow: user input → context assembly → LLM → tool execution → response
- SSE streaming protocol

**[guides/CORE_GUIDE.md](guides/CORE_GUIDE.md)** — Agent framework guide
- Core concepts (Agents, Jobs, Orchestration)
- Defining and customizing agents
- Inter-agent communication patterns
- Best practices and troubleshooting

### Features & Systems

**[CONTEXT_SYSTEM.md](CONTEXT_SYSTEM.md)** — Context assembly pipeline
- Context gathering process
- Context Notes and the `Notes/` directory
- Agent model and persona system
- `@ContextBuilder` DSL and token budgeting
- Semantic search with tag boosting
- Workspace-tool relationship

**[workspaces_feature_overview.md](workspaces_feature_overview.md)** — Workspace & tool execution
- Workspace concepts (URI, host types, trust levels)
- Session and workspace relationship
- Tool execution flow (discovery, routing, execution)
- Security & isolation (jails, trust levels)
- Workflows (attaching projects, client-managed workspaces)

**[STORES.md](STORES.md)** — State Stores
- In-memory actor caches for the persistence layer
- `WorkspaceStore` caching for continuous file access
- `SessionStore` (removed)

### API Reference

**[API_REFERENCE.md](API_REFERENCE.md)** — MonadServer HTTP API
- System status endpoints
- Session management (CRUD, messages)
- Chat streaming (SSE protocol, event types)
- Memory operations (search, CRUD)
- Workspace management
- Jobs and background tasks
- Client registration
- Configuration endpoints

## Documentation by Role

### For AI Assistants

Start with **[../AGENTS.md](../AGENTS.md)** for:
- Build commands and testing (`swift build`, `swift test`, `make lint`)
- Module architecture and model layout
- Critical conventions:
  - Concurrency (actors, `AsyncThrowingStream`, `Locked`)
  - Graceful shutdown (`cancelWhenGracefulShutdown`)
  - Dependency injection (`@Dependency`)
  - Logging (`Logger.module(named:)`)
  - Tool protocol
- System tools (15 implementations)
- References to detailed docs

### For Developers

Start with **[../DEVELOPMENT.md](../DEVELOPMENT.md)** for:
- Development setup and workflows
- Creating new features:
  - Tools (implementing `Tool` protocol)
  - API endpoints (Hummingbird controllers)
  - Custom prompts (`@ContextBuilder` DSL)
  - Agents (database records + execution)
- CLI usage and slash commands
- Testing strategies (mocks, HummingbirdTesting)
- Troubleshooting common issues

### For System Understanding

Read in this order:
1. **[ARCHITECTURE.md](ARCHITECTURE.md)** — Overall system design, module responsibilities, data flow
2. **[CONTEXT_SYSTEM.md](CONTEXT_SYSTEM.md)** — How context is assembled, RAG pipeline
3. **[workspaces_feature_overview.md](workspaces_feature_overview.md)** — Tool execution model, security
4. **[guides/CORE_GUIDE.md](guides/CORE_GUIDE.md)** — Agent orchestration, job system

### For API Integration

Start with **[API_REFERENCE.md](API_REFERENCE.md)** for:
- Endpoint specifications (paths, methods, parameters)
- Request/response formats (JSON schemas)
- SSE streaming protocol (event types, phases)
- Authentication and configuration

## Key Concepts

### Timeline
The persistent conversation record. Represents a continuous thread of interaction between user and AI. Formerly called `ConversationSession`.

**Fields:** `id`, `title`, `createdAt`, `updatedAt`, `isArchived`, `tags`, `workingDirectory`, `primaryWorkspaceId`, `attachedWorkspaceIds`

### LLMConfiguration
Canonical configuration type supporting multiple LLM providers.

**Providers:** OpenAI, OpenRouter, Ollama, OpenAI-compatible

**Structure:**
- `activeProvider: LLMProvider` — Currently active provider
- `providers: [LLMProvider: ProviderConfiguration]` — Per-provider configs
- `memoryContextLimit: Int` — Max tokens for memory context
- `documentContextLimit: Int` — Max tokens for document context
- `version: Int` — Config schema version

**Per-Provider Config:**
- `endpoint` — API endpoint URL
- `apiKey` — API key (optional for Ollama)
- `modelName` — Primary model
- `utilityModel` — For utility tasks (tagging, summarization)
- `fastModel` — For fast, simple tasks
- `toolFormat` — OpenAI / JSON / XML
- `timeoutInterval` — Request timeout
- `maxRetries` — Retry count

### Message
UI message model with Chain of Thought support.

**Fields:** `id`, `content`, `role`, `timestamp`, `think` (optional reasoning), `toolCalls`, `toolCallId`, `parentId`, `recalledMemories`, `isSummary`, `summaryType`

**Roles:** `.user`, `.assistant`, `.system`, `.tool`, `.summary`

### ToolReference & WorkspaceReference
Dedicated types for referencing tools and workspaces.

**ToolReference:**
```swift
enum ToolReference {
    case known(id: String)
    case custom(definition: WorkspaceToolDefinition)
}
```

**WorkspaceReference:**
Metadata about a workspace (ID, URI, host type, owner, tools, root path, trust level, status).

### Context Notes
Files in the `Notes/` directory of the Primary Workspace. Read by `ContextManager` and included in prompts with high priority. The LLM can update these files to persist state and instructions across sessions.

**Default Files:**
- `Welcome.md` — Introduction and usage guide
- `Project.md` — Project-specific context

### Workspace Model
**Primary Workspace:** Private session sandbox with `Notes/` directory. Created automatically with session. Host type: `.serverSession`.

**Attached Workspaces:** Shared project directories. Attached via `/workspace attach` or `attach-pwd`. Host types: `.server` (local disk) or `.client` (remote RPC).

**Tool Provenance:** Tools labeled as `[System]`, `[Workspace: Name]`, or `[Session]` to help LLM reason about context.

## Model Organization

MonadCore models are organized into focused subdirectories:

```
Sources/MonadCore/Models/
├── Agents/        Agent
├── Chat/          APIRequests, APIResponseMetadata, ChatEvent, Message, ToolCall
├── Configuration/ LLMConfiguration, LLMProvider, ProviderConfiguration, ToolCallFormat
├── Context/       ActiveMemory, ContextFile, DebugSnapshot
├── Database/      ConversationMessage, DatabaseBackup, Memory, SemanticSearchResult, Timeline
├── Tools/         Tool, ToolReference, ToolError, ToolParameters, …
│   ├── Filesystem/  (7 tools: cd, find, inspect, ls, cat, grep, search)
│   ├── JobQueue/    JobQueueGatewayTool, Job, JobQueueContext
│   └── ToolContext/ ContextTool, ToolContext, ToolContextSession
└── Workspace/     WorkspaceAttachment, WorkspaceLock, WorkspaceProtocol,
                   WorkspaceReference, WorkspaceTool, WorkspaceToolDefinition,
                   WorkspaceToolError, WorkspaceURI
```

## Service Organization

Core services in `Sources/MonadCore/Services/`:

```
├── ChatEngine.swift              — Unified chat/agent engine
├── Agents/                       — AgentExecutor, AgentRegistry
├── Configuration/                — ConfigurationServiceProtocol
├── Context/                      — ContextManager, ContextRanker
├── Database/                     — Persistence protocols (7 store protocols)
├── Embeddings/                   — EmbeddingService implementations
├── LLM/                          — LLMService, StreamingParser, StreamingCoordinator
│   └── Providers/                — OpenAI, Ollama, OpenRouter clients
├── Prompting/                    — DefaultInstructions, PromptSections
├── Session/                      — SessionManager, SessionToolManager
├── Tools/                        — SystemToolRegistry, ToolExecutor, ToolRouter
│   └── Agent/                    — LaunchSubagentTool, AgentAsTool
├── Vector/                       — VectorStore, MockVectorStore
└── Workspace/                    — WorkspaceManager, WorkspaceRepository
```

## System Tools (15 Implemented)

### Filesystem Tools (7)
Location: `Sources/MonadCore/Models/Tools/Filesystem/`

1. `ChangeDirectoryTool` (`cd`) — Change working directory
2. `FindFileTool` (`find`) — Find files by pattern
3. `InspectFileTool` (`inspect_file`) — File metadata
4. `ListDirectoryTool` (`ls`) — List directory contents
5. `ReadFileTool` (`cat`) — Read file content (1MB limit)
6. `SearchFileContentTool` (`grep`) — Search within files
7. `SearchFilesTool` (`search_files`) — Search for files

### Agent Tools (2)
Location: `Sources/MonadCore/Services/Tools/Agent/`

1. `LaunchSubagentTool` — Launch isolated agent task
2. `AgentAsTool` — Wrap agent as callable tool

### System Tools (2)
Location: `Sources/MonadCore/Services/Tools/SystemToolRegistry.swift`

1. `system_memory_search` — Search long-term memories
2. `system_web_search` — Web search (placeholder)

### Job Queue Tools (1)
Location: `Sources/MonadCore/Models/Tools/JobQueue/`

1. `JobQueueGatewayTool` — Submit background jobs

### Client Tools (1)
Location: `Sources/MonadClient/Tools/`

1. `AskAttachPWDTool` — Client-side workspace attachment

### Context Tools (1)
Location: `Sources/MonadCore/Models/Tools/ToolContext/`

1. `ContextTool` — Marker protocol for context-aware tools

## Architectural Patterns

### Streaming Response Pattern
Multi-phase streaming with `AsyncThrowingStream<ChatEvent, Error>`:

**Phases:**
1. `generationContext` — Initial metadata (session, agent, workspace)
2. `thought` / `delta` — LLM output (CoT reasoning / user-facing content)
3. `toolCall` — Tool request from LLM
4. `toolExecution` — Tool execution status (attempting / success / failed)
5. `generationCompleted` — Final message + metadata
6. `streamCompleted` — End of stream

**Parser:** `StreamingParser` extracts Chain of Thought from `<think>...</think>` tags

### Tool Execution Flow
1. LLM requests tool via `ToolCall`
2. `ToolRouter` resolves workspace containing tool
3. Execute locally (server) or throw `ToolError.clientExecutionRequired` (client)
4. Result fed back to LLM as new `Message` with role `.tool`
5. LLM continues generation with result context

### Context Assembly Pipeline
`ContextManager.gatherContext()` returns `AsyncThrowingStream<ContextGatheringEvent>`:

**Events:**
- `.augmenting` — Augmenting query with conversation history
- `.tagging` — Generating search tags via LLM
- `.embedding` — Creating query embedding
- `.searching` — Parallel semantic + tag-based search
- `.ranking` — Re-ranking combined results
- `.complete` — Context ready

**Process:**
1. Read `Notes/` directory from primary workspace
2. Augment query with recent conversation history
3. Generate search tags via LLM (`generateTags()`)
4. Create embedding for augmented query
5. **Parallel search:** semantic (vector) + tag-based
6. Re-rank combined results with `ContextRanker`
7. Return top N memories

## Deprecated/Removed

These types/concepts have been removed from the codebase:

- `MessageDebugInfo` — Removed
- `SubagentContext` — Removed
- `CompactificationNode` — Removed
- `Configuration` wrapper struct — Replaced by `LLMConfiguration`
- MCP configuration — Removed from config system
- Custom `Locked` wrapper — Now uses Swift 6 `OSAllocatedUnfairLock`
- `ConversationSession` — Renamed to `Timeline`

## Assets

- **[assets/](assets/)** — Images and diagrams (e.g., `spark.png`)
