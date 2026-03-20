# CLAUDE.md

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

SwiftLint enforces code style and quality.

- `make lint` — lint entire project
- `swiftlint --fix Sources/` — auto-fix formatting issues (whitespace, line breaks, etc.)

## Module Architecture

Six targets with strict dependency hierarchy:

1. **MonadPrompt** — Standalone DSL for prompt construction (`@ContextBuilder`). No dependencies.
2. **MonadCore** — Core business logic. Contains `ChatEngine`, `TimelineManager`, `AgentInstanceManager`, `ContextManager`, `ToolRouter`/`ToolExecutor`, LLM providers, embeddings, persistence.
3. **MonadShared** — Common types for client/server (`AgentInstance`, `AgentTemplate`, `ToolReference`, `WorkspaceReference`, `AnyCodable`, `ChatEvent`).
4. **MonadServer** — Hummingbird REST API, SSE streaming, GRDB persistence, WebSocket, service lifecycle.
5. **MonadClient** — Core HTTP/SSE networking layer and base client.
6. **MonadCLI** — Command-line interface with slash commands.

## Critical Conventions

### Error Handling
- Use [ErrorKit](https://github.com/FlineDev/ErrorKit) for structured error handling.
- New errors should conform to `Throwable`.

### Concurrency
- Use `AsyncThrowingStream` for streaming/progress.
- Use **actors** for thread-safe state management (`TimelineManager`, `AgentInstanceManager`, `ContextManager`, `WorkspaceManager`).
- Use `Mutex<T>` for fine-grained locking.

### Graceful Shutdown
- Services in `ServiceGroup` **must** wrap work in `cancelWhenGracefulShutdown { ... }` from `ServiceLifecycle`.
- **CRITICAL:** DO NOT rely on `Task.isCancelled` alone.

### Dependency Injection
- Uses Point-Free's `swift-dependencies` (`@Dependency`).

## Context & Prompt Pipelines

Both context gathering and prompt assembly use the generic `Pipeline<Context, Event>` pattern (`MonadCore/Utilities/Pipeline.swift`). Each pipeline is composed of discrete, replaceable stages.

### Context Gathering Pipeline
- **ContextManager** delegates to a `ContextPipeline` (alias for `Pipeline<ContextPipelineContext, ContextGatheringEvent>`).
- Default stages: `QueryAugmentationStage` → `MemoryRetrievalStage` → `NoteDiscoveryStage` → `ContextAssemblyStage`.
- Stages live in `Services/Context/Pipeline/Stages/`.
- Build custom pipelines with `@ContextPipelineBuilder` DSL or pass `overridePipeline:` per-request.
- `@Dependency` fields (e.g. `memoryStore`, `embeddingService`) live on stages, not on `ContextManager`.

### Prompt Assembly Pipeline
- **PromptBuilder** delegates to a `PromptAssemblyPipeline` (alias for `Pipeline<PromptAssemblyContext, PromptAssemblyEvent>`).
- Default stages (10): `SystemInstructionsStage`, `AgentContextStage`, `ContextNotesStage`, `MemoriesStage`, `ToolsStage`, `WorkspacesContextStage`, `TimelineContextStage`, `ChatHistoryStage`, `UserQueryStage`, `ExtensionSectionsStage`.
- Stages live in `Services/Prompting/PromptAssemblyStages.swift`; types/DSL in `PromptAssembly.swift`.
- Build custom pipelines with `@PromptAssemblyPipelineBuilder` DSL or pass `overridePipeline:` per-request.
- Custom stages implement `PromptAssemblyStage` protocol (provides `running()` helper for event emission).

### Per-Request Overrides
Both pipelines can be overridden per-request through `MonadCore.run(contextPipeline:assemblyPipeline:)` → `ChatEngine` → `ContextManager`/`PromptBuilder`.

### Token Budgeting
- `MonadPrompt` provides `@ContextBuilder` DSL, `ContextSection` protocol, and compression strategies.
- `PromptBuilder` handles history truncation (`maxHistoryTokens`, `historyTokenBuffer`).

## Documentation

See **[docs/INDEX.md](docs/INDEX.md)** for comprehensive documentation index.
