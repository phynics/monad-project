# AGENTS.md

Quick reference for agents working with the Monad project.

## Project Essentials

- **Language:** Swift 6.0 (macOS 15+)
- **Architecture:** Server/CLI with six modular targets (no circular dependencies)
- **Build System:** Swift Package Manager
- **Key Tech:** Hummingbird (REST/SSE), GRDB/SQLite, USearch (embeddings), swift-dependencies

## Quick Commands

```bash
swift build                          # Build all targets
swift build -c release               # Release build
swift test                           # All tests
swift test --filter MonadCoreTests   # Specific module
swift run MonadServer                # Start server
swift run MonadCLI chat              # Interactive CLI
make lint                            # SwiftLint check (full project)
swiftlint lint Sources/              # Lint only Sources directory
swiftlint --fix Sources/             # Auto-fix violations in Sources
```

## Code Quality & Linting

SwiftLint enforces code style and quality. Common violations and fixes:

**Running SwiftLint:**
> **Note:** `swiftlint --fix Sources/` is the recommended way to run the linter to automatically fix formatting issues.
- `make lint` — lint entire project (includes Tests)
- `swiftlint lint Sources/` — lint only production code
- `swiftlint --fix Sources/` — auto-fix formatting issues (whitespace, line breaks, etc.)

**Common Violations:**
- **Identifier names** — Variables must be 3+ characters. Use descriptive names:
  - ❌ `let c = ...` → ✅ `let contentValue = ...`
  - ❌ `let i = 0` → ✅ `let index = 0`
  - Exception: Builder closures can use `builder` instead of `b`
- **Line length** — 120 chars (warning), 200 chars (error). Break long lines:
  ```swift
  // ❌ Too long
  func foo(a: String, b: String, c: String, d: String, e: String) -> String

  // ✅ Multi-line
  func foo(
      a: String,
      b: String,
      c: String
  ) -> String
  ```
- **Large tuples** — Max 2 members. Create named types for 3+ fields:
  ```swift
  // ❌ Large tuple
  func foo() -> (String, Int, Bool)

  // ✅ Named type
  struct FooResult {
      let name: String
      let count: Int
      let isValid: Bool
  }
  func foo() -> FooResult
  ```
- **Function parameters** — Max 5 parameters. Group into config objects:
  ```swift
  // ❌ Too many parameters
  func process(a: String, b: Int, c: Bool, d: Double, e: String, f: Int)

  // ✅ Configuration object
  struct ProcessConfig {
      let name: String
      let count: Int
      let enabled: Bool
      ...
  }
  func process(config: ProcessConfig)
  ```
- **Snake_case in JSON models** — Use `// swiftlint:disable:next identifier_name` for API-matching names:
  ```swift
  struct APIResponse: Codable {
      // swiftlint:disable:next identifier_name
      let created_at: String  // Matches API field name
  }
  ```
- **Set operations** — Prefer `isDisjoint(with:)` over `intersection(_:).isEmpty`

**Workflow:**
1. `swift build` — ensure code compiles
2. `swiftlint --fix Sources/` — auto-fix simple issues
3. `swiftlint lint Sources/` — check remaining violations
4. Fix manually: identifier names, large tuples, function signatures
5. Repeat until clean

## Module Architecture

Six targets with strict dependency hierarchy:

1. **MonadPrompt** — Standalone DSL for prompt construction (`@ContextBuilder`). No dependencies.
2. **MonadCore** — Core business logic. Contains `ChatEngine`, `SessionManager`, `ContextManager`, `ToolRouter`/`ToolExecutor`, LLM providers (OpenAI/Ollama/OpenRouter), embeddings, persistence. **Works as a standalone library.**
3. **MonadShared** — Common types for client/server (`ToolReference`, `WorkspaceReference`, `AnyCodable`, `ChatEvent`).
4. **MonadServer** — Hummingbird REST API, SSE streaming, GRDB persistence, WebSocket, service lifecycle.
5. **MonadClient** — Client library with Bonjour auto-discovery.
6. **MonadCLI** — Command-line interface with slash commands.

### MonadCore Model Layout

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

Sources/MonadCore/Stores/
└── WorkspaceStore.swift   — Actor cache for hydrated WorkspaceProtocol instances (used by FilesAPIController)
```

> **Note:** `SessionStore` was removed — its responsibilities are fully covered by `SessionManager`.

**Key Model Notes:**
- **`Timeline`** — persistent conversation record (formerly `ConversationSession`)
- **`LLMConfiguration`** — multi-provider config supporting OpenAI, OpenRouter, Ollama, OpenAI-compatible. Split into `LLMProvider`, `ProviderConfiguration`, `ToolCallFormat`.
- **`Message`** — includes Chain of Thought support via optional `think` field
- **`ToolReference`** / **`WorkspaceReference`** — dedicated types
- **`AnyTool`** — type-erased tool wrapper with optional `provenance` for labeling

### Core Services

```
Sources/MonadCore/Services/
├── ChatEngine.swift              — Unified chat/agent engine
├── Agents/                       — AgentExecutor, AgentRegistry
├── Configuration/                — ConfigurationServiceProtocol
├── Context/                      — ContextManager, ContextRanker
├── Database/                     — Persistence protocols (7 store protocols)
├── Embeddings/                   — EmbeddingService, LocalEmbeddingService, OpenAIEmbeddingService
├── LLM/                          — LLMService, StreamingParser, StreamingCoordinator
│   └── Providers/                — OpenAI, Ollama, OpenRouter clients
├── Prompting/                    — DefaultInstructions, PromptSections
├── Session/                      — SessionManager, SessionToolManager
├── Tools/                        — SystemToolRegistry, ToolExecutor, ToolRouter
│   └── Agent/                    — LaunchSubagentTool, AgentAsTool
├── Vector/                       — VectorStore, MockVectorStore
├── Workspace/                    — WorkspaceManager, WorkspaceRepository

Sources/MonadCore/Stores/
└── WorkspaceStore                — Actor cache for workspace instances
```

## Critical Conventions

### Concurrency
- Use `AsyncThrowingStream` for streaming/progress (not callbacks)
- Use **actors** for thread-safe state management (`SessionManager`, `ContextManager`, `ToolRouter`, `WorkspaceManager`)
- Use `Locked<T>` (wraps `OSAllocatedUnfairLock`) for fine-grained locking
- All code uses Swift structured concurrency (async/await)

### Graceful Shutdown
- Services in `ServiceGroup` **must** wrap work in `cancelWhenGracefulShutdown { ... }` from `ServiceLifecycle`
- **CRITICAL:** DO NOT rely on `Task.isCancelled` alone — it deadlocks (only set after all services return from `run()`)
- Reference: `Sources/MonadServer/BonjourAdvertiser.swift`

### Dependency Injection
- Uses Point-Free's `swift-dependencies` (`@Dependency`)
- Keys in `Sources/MonadCore/Dependencies/`: `LLMDependencies.swift`, `OrchestrationDependencies.swift`, `StorageDependencies.swift`
- Usage: `@Dependency(\.sessionManager) private var sessionManager`
- Configure with `withDependencies { ... }`

### Tool Protocol
- All tools conform to `Tool` (see `Sources/MonadCore/Models/Tools/Tool.swift`)
- Required: `id`, `name`, `description`, `requiresPermission`, `parametersSchema`, `canExecute()`, `execute(parameters:)` → `ToolResult`
- Optional: `summarize(parameters:result:)`, `toToolParam()`
- Use `ToolParameterSchema.object { ... }` builder for schemas
- Use `PathSanitizer.safelyResolve()` for secure path handling
- Return `ToolResult.success(_)` or `ToolResult.failure(_)`

### Context System
- **ContextManager** assembles prompts from:
  1. System instructions (`DefaultInstructions.swift`)
  2. Context notes from `Notes/` directory in workspace
  3. Semantic memories (vector search + tag boosting, re-ranked)
  4. Tool definitions (formatted with provenance labels)
  5. Chat history (auto-truncated)
  6. User query
- Token budgeting via `MonadPrompt`: priority-based sections with `keep`/`truncate`/`summarize`/`drop` strategies
- `gatherContext()` returns `AsyncThrowingStream<ContextGatheringEvent>` with progress

### Workspace Model
- Sessions have a **primary workspace** (private sandbox with `Notes/` directory)
- Can attach **shared project directories** (attached workspaces)
- Workspace types: `WorkspaceReference` (metadata), `WorkspaceProtocol` (interface), `WorkspaceURI` (identifier)
- Host types: `.server`, `.serverSession`, `.client`
- Trust levels: `.full`, `.restricted`
- Tool provenance labels: `[System]`, `[Workspace: Name]`, `[Session]`

### Logging
- Use `Logger.module(named: "ComponentName")` throughout
- **Never** use `Logger(label: ...)` directly
- Extension: `Sources/MonadCore/Utilities/Logger+Extensions.swift`

### Testing
- Mock services in `Sources/MonadCore/TestSupport/`: `MockLLMService`, `MockPersistenceService`, `MockEmbeddingService`, `MockConfigurationService`, `MockLocalWorkspace`
- Server tests use `HummingbirdTesting`

## Environment Variables

- `MONAD_API_KEY` — API key for LLM access
- `MONAD_VERBOSE=true` — Enable verbose logging

## Key Architectural Patterns

### Streaming Response Pattern
- `ChatEngine.chatStream()` returns `AsyncThrowingStream<ChatEvent, Error>`
- Phases: `generationContext` → `thought` / `delta` → `toolCall` → `toolExecution` → `generationCompleted`
- `StreamingParser` extracts Chain of Thought from `<think>...</think>` tags

### Tool Execution Flow
1. LLM requests tool via `ToolCall`
2. `ToolRouter` resolves workspace containing tool
3. Execute locally (server) or throw `ToolError.clientExecutionRequired` (client)
4. Result fed back to LLM as new message
5. LLM continues with result context

### Multi-Provider LLM Support
- `LLMConfiguration` supports OpenAI, OpenRouter, Ollama, OpenAI-compatible
- `activeProvider` determines which `ProviderConfiguration` is used
- Each provider has: `endpoint`, `apiKey`, `modelName`, `utilityModel`, `fastModel`, `toolFormat`, `timeoutInterval`, `maxRetries`
- Validation on load: ensures active provider configured, API key present (except Ollama)

## System Tools (15 implemented)

**Filesystem (7):**
- `cd`, `find`, `inspect_file`, `ls`, `cat`, `grep`, `search_files`

**Agent (2):**
- `LaunchSubagentTool`, `AgentAsTool`

**System (2):**
- `system_memory_search`, `system_web_search`

**Job Queue (1):**
- `JobQueueGatewayTool`

**Client (1):**
- `AskAttachPWDTool`

**Context (1):**
- `ContextTool` (marker protocol)

## Documentation

See **[docs/INDEX.md](docs/INDEX.md)** for comprehensive documentation index.

**Quick Links:**
- **[DEVELOPMENT.md](DEVELOPMENT.md)** — Developer guide (creating tools, endpoints, workflows)
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — System architecture deep dive
- **[docs/CONTEXT_SYSTEM.md](docs/CONTEXT_SYSTEM.md)** — Context assembly pipeline
- **[docs/API_REFERENCE.md](docs/API_REFERENCE.md)** — MonadServer API endpoints
- **[docs/workspaces_feature_overview.md](docs/workspaces_feature_overview.md)** — Workspace system
- **[docs/guides/CORE_GUIDE.md](docs/guides/CORE_GUIDE.md)** — Agent framework guide
