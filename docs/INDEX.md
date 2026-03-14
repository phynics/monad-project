# Documentation Index

Comprehensive guide to Monad documentation.

> **Before exploring the codebase**, read this file first — it maps all key types, services, tools, and where they live.

## Quick Start

### For Getting Started
- **[../README.md](../README.md)** — Project overview, quick start, and basic usage

### For AI Assistants
- **[../CLAUDE.md](../CLAUDE.md)** — Quick reference: build commands, architecture, conventions, critical patterns

### For Developers
- **[../DEVELOPMENT.md](../DEVELOPMENT.md)** — Developer guide: setup, creating tools/endpoints/agents, testing, troubleshooting

---

## Core Documentation

### Architecture & Design

**[ARCHITECTURE.md](ARCHITECTURE.md)** — System architecture, module overview, and data flow
- Module responsibilities (MonadCore, MonadServer, MonadClient, etc.)
- Dependency hierarchy
- Data flow: user input → context assembly → LLM → tool execution → response
- SSE streaming protocol, concurrency model

**[ERROR_HANDLING.md](ERROR_HANDLING.md)** — Structured error handling
- `Throwable` protocol and `ErrorKit` integration
- Module-specific error tiers (Client, Core, Server)
- User-friendly messaging and technical tracing

**[CONTEXT_SYSTEM.md](CONTEXT_SYSTEM.md)** — Context assembly pipeline
- Context gathering process (RAG)
- Context Notes and the `Notes/` directory
- `@ContextBuilder` DSL and token budgeting
- Semantic search with tag boosting and re-ranking

### Feature Docs

**[AGENT.md](AGENT.md)** — Agent system
- `AgentTemplate` templates vs `AgentInstance` runtime entities
- Creating, attaching, and deleting agents
- Agent identity in prompts (`AgentContext`, `TimelineContext` sections)
- Inter-agent communication (timeline tools)
- CLI commands and API reference

**[TIMELINE.md](TIMELINE.md)** — Timeline (conversation) model
- `Timeline` model fields and types
- Chat stream API and SSE event reference
- Chat flow: message → context → LLM → tools → response
- Timeline tools for cross-agent communication
- `TimelineManager` actor

**[WORKSPACE.md](WORKSPACE.md)** — Workspace & tool execution
- Workspace model (host types, trust levels, URI types)
- Agent workspaces vs. attached workspaces
- Tool execution flow (discovery, routing, server vs. client)
- Security: path jailing, state isolation
- `WorkspaceStore` actor cache
- CLI commands and API reference

**[CLIENT.md](CLIENT.md)** — MonadClient library & MonadCLI
- `MonadClient` configuration and facades (`chat`, `workspace`)
- Client registration and identity management
- CLI startup sequence and auto-attachment
- Full slash command reference
- `LocalConfigManager` (persists timeline/agent across sessions)

### API Reference

**[API_REFERENCE.md](API_REFERENCE.md)** — MonadServer HTTP API (complete endpoint listing)
- System status, timelines, chat streaming
- Memories, workspaces, agent instances, agent templates
- Jobs, clients, configuration

### State Stores

**[STORES.md](STORES.md)** — In-memory actor caches
- `WorkspaceStore` for workspace hydration

---

## Documentation by Role

### For AI Assistants

Start with **[../CLAUDE.md](../CLAUDE.md)** for:
- Build commands and testing (`swift build`, `swift test`, `make lint`)
- Module architecture and model layout
- Critical conventions: concurrency, graceful shutdown, DI, logging
- System tools (14 implementations)

Then check this INDEX for the specific area you're working on.

### For Developers

Start with **[../DEVELOPMENT.md](../DEVELOPMENT.md)** for:
- Development setup and workflows
- Creating new tools, API endpoints, agent templates
- Testing strategies (mocks, HummingbirdTesting)
- Troubleshooting common issues

### For System Understanding

Read in this order:
1. **[ARCHITECTURE.md](ARCHITECTURE.md)** — Overall system design, module responsibilities, data flow
2. **[CONTEXT_SYSTEM.md](CONTEXT_SYSTEM.md)** — How context is assembled, RAG pipeline
3. **[WORKSPACE.md](WORKSPACE.md)** — Tool execution model, security
4. **[AGENT.md](AGENT.md)** — Agent orchestration, job system
5. **[TIMELINE.md](TIMELINE.md)** — Conversation model, streaming

### For API Integration

Start with **[API_REFERENCE.md](API_REFERENCE.md)** for:
- Endpoint specifications (paths, methods, parameters)
- Request/response formats (JSON schemas)
- SSE streaming protocol (event types, phases)

---

## Key Types

### Timeline
Persistent conversation record. Formerly `ConversationSession`.

**Fields:** `id`, `title`, `createdAt`, `updatedAt`, `isArchived`, `tags`, `workingDirectory`, `primaryWorkspaceId`, `attachedWorkspaceIds`, `attachedAgentInstanceId`, `isPrivate`, `ownerAgentInstanceId`

→ See **[TIMELINE.md](TIMELINE.md)** for full details.

### AgentInstance
Live runtime agent entity with its own workspace and private timeline.

**Fields:** `id`, `name`, `description`, `primaryWorkspaceId`, `privateTimelineId`, `lastActiveAt`

→ See **[AGENT.md](AGENT.md)** for full details.

### AgentTemplate
Static agent template used to seed `AgentInstance` workspaces.

**Fields:** `id`, `name`, `description`, `systemPrompt`, `personaPrompt`, `guardrails`, `workspaceFilesSeed`

### LLMConfiguration
Multi-provider LLM config. `activeProvider` → `ProviderConfiguration` → `endpoint`, `apiKey`, `modelName`, `utilityModel`, `fastModel`, `toolFormat`.

### Message
**Roles:** `.user`, `.assistant`, `.system`, `.tool`, `.summary`
**Fields:** `id`, `content`, `role`, `timestamp`, `think` (CoT), `toolCalls`, `agentInstanceId`

---

## Model Organization

```
Sources/MonadCore/Models/
├── Chat/          APIRequests, APIResponseMetadata, ChatEvent, Message, ToolCall
├── Configuration/ LLMConfiguration, LLMProvider, ProviderConfiguration, ToolCallFormat
├── Context/       ActiveMemory, ContextFile, DebugSnapshot
├── Database/      ConversationMessage, DatabaseBackup, Memory, SemanticSearchResult, Timeline
├── Tools/         Tool, ToolReference, ToolError, ToolParameters, …
│   ├── Filesystem/         7 tools: cd, find, inspect, ls, cat, grep, search
│   └── ToolContext/        ContextTool, ToolContext, ToolTimelineContext
└── Workspace/     WorkspaceAttachment, WorkspaceLock, WorkspaceProtocol,
                   WorkspaceReference, WorkspaceTool, WorkspaceToolDefinition,
                   WorkspaceToolError, WorkspaceURI

Sources/MonadShared/SharedTypes/
├── AgentInstance.swift   — Live agent entity (runtime)
├── AgentTemplate.swift   — Agent template (static definition)
├── ChatAPITypes.swift    — TimelineResponse, CreateTimelineRequest, etc.
├── WorkspaceReference.swift, WorkspaceURI.swift
├── ChatEvent.swift, Message.swift, ToolCall.swift
└── LLMConfiguration.swift, ProviderConfiguration.swift, …

Sources/MonadCore/Stores/
└── WorkspaceStore.swift  — Actor cache for hydrated WorkspaceProtocol instances
```

## Service Organization

```
Sources/MonadCore/Services/
├── ChatEngine.swift              — Unified chat/agent engine
├── Agents/                       — AgentInstanceManager
├── Configuration/                — ConfigurationServiceProtocol
├── Context/                      — ContextManager, ContextRanker
├── Database/                     — Persistence protocols (7 store protocols)
├── Embeddings/                   — EmbeddingService, LocalEmbeddingService, OpenAIEmbeddingService
├── LLM/                          — LLMService, StreamingParser, StreamingCoordinator
│   └── Providers/                — OpenAI, Ollama, OpenRouter clients
├── AgentTemplates/               — AgentTemplateExecutor, AgentTemplateRegistry
├── Prompting/                    — DefaultInstructions, PromptSections
├── Timeline/                     — TimelineManager, TimelineToolManager
├── Tools/                        — SystemToolRegistry, ToolExecutor, ToolRouter
│   └── Timeline/                 — TimelineListTool, TimelinePeekTool, TimelineSendTool
├── Vector/                       — VectorStore, MockVectorStore
└── Workspace/                    — WorkspaceManager, WorkspaceRepository
```

## System Tools (14 Implemented)

| Category | Tools |
|:---------|:------|
| Filesystem (7) | `cd`, `find`, `inspect_file`, `ls`, `cat`, `grep`, `search_files` |
| Timeline (3) | `timeline_list`, `timeline_peek`, `timeline_send` |
| System (2) | `system_memory_search`, `system_web_search` |
| Context (1) | `ContextTool` (marker protocol) |
| Permission (1) | `request_write_access` |

## Prompt Sections (Priority Order)

| Section | Priority | Strategy | When |
|:--------|:---------|:---------|:-----|
| `SystemInstructions` | 100 | keep | Always |
| `AgentContext` | 95 | keep | When agent attached |
| `ContextNotes` | 90 | truncate | Always |
| `Memories` | 85 | summarize | Always |
| `Tools` | 80 | keep | Always |
| `WorkspacesContext` | 75 | keep | Always |
| `TimelineContext` | 72 | keep | When timeline available |
| `ChatHistory` | 70 | truncate (oldest first) | Always |
| `UserQuery` | 10 | keep | Always |
