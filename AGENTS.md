# AGENTS.md

Quick reference for agents working with the Monad project.

## Project Essentials

- **Language:** Swift 6.0 (macOS 15+)
- **Architecture:** Server/CLI with six modular targets (no circular dependencies)
- **Build System:** Swift Package Manager
- **Key Tech:** Hummingbird (REST/SSE), GRDB/SQLite, USearch (embeddings), swift-dependencies, ErrorKit

## Quick Commands

```bash
swift build                          # Build all targets
swift build -c release               # Release build
swift test                           # All tests
swift test --filter MonadCoreTests   # Specific module
swift run MonadServer                # Start server
swift run MonadCLI chat              # Interactive CLI
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
**Workflow:**
1. `swift build` — ensure code compiles
2. `swiftlint --fix Sources/` — auto-fix simple issues
3. `swiftlint lint Sources/` — check remaining violations
4. Fix manually: identifier names, large tuples, function signatures
5. Repeat until clean

## Module Architecture

Six targets with strict dependency hierarchy:

1. **MonadPrompt** — Standalone DSL for prompt construction (`@ContextBuilder`). No dependencies.
2. **MonadCore** — Core business logic. Contains `ChatEngine`, `TimelineManager`, `AgentInstanceManager`, `ContextManager`, `ToolRouter`/`ToolExecutor`, LLM providers (OpenAI/Ollama/OpenRouter), embeddings, persistence. **Works as a standalone library.**
3. **MonadShared** — Common types for client/server (`AgentInstance`, `AgentTemplate`, `ToolReference`, `WorkspaceReference`, `AnyCodable`, `ChatEvent`). No MonadCore dependency.
4. **MonadServer** — Hummingbird REST API, SSE streaming, GRDB persistence, WebSocket, service lifecycle.
5. **MonadClient** — Core HTTP/SSE networking layer and base client. Exposes `chat` and `workspace` facades for domain-specific operations.
6. **MonadCLI** — Command-line interface with slash commands.

> For detailed model layout and service organization, see **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** and **[docs/INDEX.md](docs/INDEX.md)**.

**Key Model Notes:**
- **`Timeline`** — persistent conversation record (formerly `ConversationSession`). Fields: `attachedAgentInstanceId`, `isPrivate`, `ownerAgentInstanceId` support the agent system.
- **`AgentInstance`** — live runtime agent entity in `MonadShared`. Has private workspace + private timeline.
- **`AgentTemplate`** — static agent template in `MonadShared`. Seeds new `AgentInstance` workspaces.
- **`LLMConfiguration`** — multi-provider config. Split into `LLMProvider`, `ProviderConfiguration`, `ToolCallFormat`.
- **`AnyTool`** — type-erased tool wrapper with optional `provenance` for labeling

## Critical Conventions

### Error Handling (Gradual Rollout)
- We are adopting [ErrorKit](https://github.com/FlineDev/ErrorKit) for structured error handling across the codebase.
- **New errors** should conform to `Throwable` (from ErrorKit) instead of plain `Error`.
- **Existing errors** are being migrated incrementally — do not refactor error types en masse, only convert them when already touching the file.
- Use ErrorKit's built-in types (`NetworkError`, `DatabaseError`, `FileError`, `ValidationError`, `GenericError`, etc.) where they fit.
- Prefer `userFriendlyMessage` over `localizedDescription` when surfacing errors to users or logs.
- The `Catching` protocol (for wrapping nested errors) should be used in types that propagate errors from sub-layers.

### Concurrency
- Use `AsyncThrowingStream` for streaming/progress (not callbacks)
- Use **actors** for thread-safe state management (`TimelineManager`, `AgentInstanceManager`, `ContextManager`, `ToolRouter`, `WorkspaceManager`)
- Use `Mutex<T>` for fine-grained locking
- All code uses Swift structured concurrency (async/await)

### Graceful Shutdown
- Services in `ServiceGroup` **must** wrap work in `cancelWhenGracefulShutdown { ... }` from `ServiceLifecycle`
- **CRITICAL:** DO NOT rely on `Task.isCancelled` alone — it deadlocks (only set after all services return from `run()`)
- Reference: `Sources/MonadServer/BonjourAdvertiser.swift`

### Dependency Injection
- Uses Point-Free's `swift-dependencies` (`@Dependency`)
- Keys in `Sources/MonadCore/Dependencies/`: `LLMDependencies.swift`, `OrchestrationDependencies.swift`, `StorageDependencies.swift`
- Usage: `@Dependency(\.timelineManager) private var timelineManager`
- Configure with `withDependencies { ... }`

### Context System
- **ContextManager** assembles prompts from: system instructions → agent context → context notes → memories → tools → workspaces → timeline context → chat history → user query
- Token budgeting via `MonadPrompt`: priority-based sections with `keep`/`truncate`/`summarize`/`drop` strategies
- `gatherContext()` returns `AsyncThrowingStream<ContextGatheringEvent>` with progress
- See **[docs/CONTEXT_SYSTEM.md](docs/CONTEXT_SYSTEM.md)** for full pipeline details

### Workspace Model
- Agent instances have a **primary workspace** (private sandbox with `Notes/` directory)
- Timelines can have **attached workspaces** (shared project directories)
- Workspace types: `WorkspaceReference` (metadata), `WorkspaceProtocol` (interface), `WorkspaceURI` (identifier)
- Host types: `.server`, `.client`
- Trust levels: `.full`, `.restricted`
- Tool provenance labels: `[System]`, `[Workspace: Name]`, `[Session]`

### Logging
- Use `Logger.module(named: "ComponentName")` throughout
- **Never** use `Logger(label: ...)` directly
- Extension: `Sources/MonadCore/Utilities/Logger+Extensions.swift`

### Testing
- Mock services in `Tests/MonadTestSupport/`: `MockLLMService`, `MockPersistenceService`, `MockEmbeddingService`, `MockConfigurationService`, `MockLocalWorkspace`
- Server tests use `HummingbirdTesting`

## Environment Variables

- `MONAD_API_KEY` — API key for LLM access
- `MONAD_VERBOSE=true` — Enable verbose logging

## System Tools (18 implemented)

**Filesystem (7):**
- `cd`, `find`, `inspect_file`, `ls`, `cat`, `grep`, `search_files`

**AgentTemplate (2):**
- `LaunchSubagentTool`, `AgentTemplateAsTool`

**Timeline (3):**
- `timeline_list`, `timeline_peek`, `timeline_send`

**System (2):**
- `system_memory_search`, `system_web_search`

**Job Queue (1):**
- `BackgroundJobQueueGatewayTool`

**Client (1):**
- `AskAttachPWDTool`

**Context (1):**
- `ContextTool` (marker protocol)

## Documentation

> **Before exploring the codebase**, read **[docs/INDEX.md](docs/INDEX.md)** first — it contains a current map of all key types, services, tools, and where they live.

> **After any refactor** that renames types, moves files, or changes public API: update the relevant files in `docs/` to keep them accurate.

See **[docs/INDEX.md](docs/INDEX.md)** for comprehensive documentation index.

**Quick Links:**
- **[DEVELOPMENT.md](DEVELOPMENT.md)** — Developer guide (creating tools, endpoints, workflows)
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — System architecture deep dive
- **[docs/CONTEXT_SYSTEM.md](docs/CONTEXT_SYSTEM.md)** — Context assembly pipeline
- **[docs/AGENT.md](docs/AGENT.md)** — Agent system (AgentTemplate, AgentInstance, CLI, API)
- **[docs/TIMELINE.md](docs/TIMELINE.md)** — Timeline model, chat stream, SSE events
- **[docs/WORKSPACE.md](docs/WORKSPACE.md)** — Workspace model, tool execution, security
- **[docs/CLIENT.md](docs/CLIENT.md)** — MonadClient library, CLI slash commands
- **[docs/API_REFERENCE.md](docs/API_REFERENCE.md)** — MonadServer API endpoints
