# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Monad — a headless AI assistant with deep context integration, built in Swift 6.0 for macOS 15+. Server/CLI architecture with modular targets managed by Swift Package Manager.

## Build & Test Commands

```bash
swift build                          # Build all targets
swift build -c release               # Release build
swift test                           # Run all tests
swift test --filter MonadCoreTests   # Run tests for a specific module
swift test --filter ChatEngineTests  # Run a specific test suite
swift run MonadServer                # Start the server
swift run MonadCLI chat              # Interactive CLI (requires running server)
make lint                            # SwiftLint (requires swiftlint installed)
```

## Module Architecture

Six targets with a strict dependency hierarchy (no circular dependencies):

- **MonadCore** — Core business logic: `ChatEngine`, `SessionManager`, `ContextManager`, `ToolRouter`/`ToolExecutor`, LLM providers (OpenAI/Ollama/OpenRouter), embeddings, persistence models. Depends on MonadPrompt, OpenAI, USearch, swift-dependencies. This should work as a standalone library.
- **MonadServer** — Server implementation using MonadCore. Hummingbird REST API with SSE streaming, GRDB/SQLite persistence, WebSocket support, service lifecycle. Controllers live in `Sources/MonadServer/Controllers/`.
- **MonadClient** — Client library for MonadServer with Bonjour auto-discovery.
- **MonadCLI** — Command-line interface using MonadClient with slash commands.
- **MonadShared** — Common types used by **MonadClient** and **MonadServer**.
- **MonadPrompt** — Standalone DSL for prompt construction using `@ContextBuilder` result builder. No external dependencies.

## Key Conventions

**Concurrency**: Use `AsyncThrowingStream` for streaming/progress, not closure callbacks. Use actors for thread-safe state. All code uses Swift structured concurrency (async/await).

**Graceful Shutdown**: Services registered with `ServiceGroup` must wrap long-running work in `cancelWhenGracefulShutdown { ... }`. Do NOT rely on `Task.isCancelled` alone — it deadlocks because it's only set after all services return from `run()`. See `BonjourAdvertiser` for reference.

**Dependency Injection**: Uses Point-Free's `swift-dependencies` (`@Dependency`).

**Tool Protocol**: All tools conform to `Tool` with `id`, `name`, `description`, `parametersSchema`, `execute(parameters:)` returning `ToolResult`, and `summarize(parameters:result:)` for context compression.

**Context System**: `ContextManager` assembles prompts from system instructions, context notes, semantic memories (vector search with tag boosting), tool definitions, chat history (auto-truncated), and user query. Token budgeting uses priority-based sections with `keep`/`truncate`/`summarize` strategies.

**Workspace Model**: Sessions have a primary workspace (private sandbox with `Notes/` directory) and can attach shared project directories. Tools are labeled with provenance: `[System]`, `[Workspace: Name]`, or `[Session]`.

## Testing

Mock services are in `Sources/MonadCore/TestSupport/`: `MockLLMService`, `MockPersistenceService`, `MockEmbeddingService`, `MockConfigurationService`. Server tests use `HummingbirdTesting`.

## Environment Variables

- `MONAD_API_KEY` — API key for LLM access
- `MONAD_VERBOSE=true` — Enable verbose logging
