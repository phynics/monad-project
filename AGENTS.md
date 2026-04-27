# AGENTS

Quick reference for agents working with the Monad application repository.

## Project Essentials

- **Language:** Swift 6.0 (macOS 15+)
- **Build System:** Swift Package Manager
- **Architecture:** Monad is now primarily an application host around the shared runtime modules in `../PositronicKit`
- **Key Tech:** Hummingbird (REST/SSE), GRDB/SQLite, swift-service-lifecycle, swift-dependencies, ErrorKit

## Repository Split

- `Monad` contains the app-facing targets: `MonadServer`, `MonadClient`, `MonadCLI`, and their tests.
- `../PositronicKit` contains the shared runtime, prompt, contracts, and test-support modules consumed by Monad.
- `Package.swift` wires Monad to `PositronicKit` via `.package(path: "../PositronicKit")`.

## Working Boundary

- If the change is about chat orchestration, timelines, agents, tools, prompt assembly, context gathering, shared contracts, or test-support infrastructure, inspect `../PositronicKit` first. That is the source of truth now.
- If the change is about HTTP APIs, GRDB-backed persistence wiring, CLI flows, client networking, app bootstrapping, or Monad-specific hosting behavior, it likely belongs in this repository.
- Prefer fixing shared abstractions in `PositronicKit` rather than re-implementing them in Monad.
- Keep Monad transport- and host-specific. Keep reusable runtime logic in `PositronicKit`.

## Quick Commands

```bash
swift build                                # Build Monad app targets
swift test                                 # Run Monad tests
swift test --filter MonadServerTests       # Run specific Monad test target
swift run MonadServer                      # Start server
swift run MonadCLI chat                    # Interactive CLI
```

For shared-runtime work in `../PositronicKit`:

```bash
swift build                                # Build current package
swift test                                 # Run current package tests
swift run PositronicKitExamples            # Run shared runtime examples
```

## Local Target Architecture

Monad defines three main app targets:

1. `MonadServer` — Hummingbird API host, SSE/WebSocket endpoints, GRDB persistence adapters, service lifecycle.
2. `MonadClient` — Client-side networking and shared API consumption.
3. `MonadCLI` — Command-line interface built on top of `MonadClient`.

Monad consumes these products from `PositronicKit`:

1. `PositronicKit` — Shared runtime orchestration (`ChatEngine`, `TimelineManager`, `ContextManager`, `ToolRouter`, agent services, LLM services).
2. `PKShared` — Shared API/runtime contracts and utility models.
3. `PKPrompt` — Prompt DSL, prompt assembly artifacts, and token/compression primitives.
4. `PKTestSupport` — Reusable test helpers and fixtures.

## PositronicKit Guidance

- Treat `PositronicKit` as the agent-building toolkit centered on timelines, workspaces, agents, tools, pipelines, and orchestration stages.
- Keep concrete transport, RPC, and client/server hosting concerns downstream in Monad unless the abstraction is clearly reusable.
- Prefer neutral seams like persistence protocols, workspace creators, prompt section providers, and tool routers over embedding Monad-specific deployment details in shared runtime code.
- `TimelineManager`, `WorkspaceManager`, `ToolRouter`, `ChatEngine`, and prompt/context pipeline code should remain transport-neutral.
- Preserve stable core concepts such as `Timeline`, `WorkspaceReference`, `AgentInstance`, tool metadata, and prompt artifacts. Avoid leaking host-specific terminology into shared APIs when a neutral alternative exists.

## Prompt And Pipeline Guidance

- Both context gathering and prompt assembly use the generic `Pipeline<Context, Event>` pattern in shared runtime code.
- `ContextManager` delegates to a `ContextPipeline`; `PromptBuilder` delegates to a `PromptAssemblyPipeline`.
- Build custom pipelines with the corresponding DSL/builders or per-request overrides instead of hard-coding branching logic into `ChatEngine`.
- In prompt work, treat prompt IR and assembled prompt artifacts as owned by the shared prompt module. Monad should consume them, not reimplement prompt-tree semantics locally.
- Preserve both requested compression strategy and realized compression outcome when changing token-budgeting behavior.

## Critical Conventions

### Error Handling
- Use [ErrorKit](https://github.com/FlineDev/ErrorKit) for structured error handling.
- New errors should conform to `Throwable`.

### Concurrency
- Use `AsyncThrowingStream` for streaming/progress.
- Use actors for thread-safe state management.
- Favor Swift 6 concurrency defaults such as `Sendable`, actor isolation, and `@MainActor` where appropriate.
- Avoid shared mutable state; use `Mutex<T>` only for narrow cases that do not fit actor ownership.

### Graceful Shutdown
- Services in `ServiceGroup` must wrap work in `cancelWhenGracefulShutdown { ... }` from `ServiceLifecycle`.
- Do not rely on `Task.isCancelled` alone.

### Dependency Injection
- Use Point-Free's `swift-dependencies` (`@Dependency`).
- Keep `@Dependency` fields on focused services/stages instead of central coordinators when possible.

## Working Conventions

- Prefer small, focused changes that preserve the Monad/PositronicKit boundary.
- When shared public APIs change, update imports, package references, docs, and Monad call sites together.
- Keep examples and tests aligned with any shared-runtime API change; `PositronicKitExamples` is a useful reference for intended composition.
- Add or update tests with behavioral changes, using `PKTestSupport` where it fits.
- Prefer composition over inheritance, narrow protocols, explicit `throws`, and structured logging.

## Documentation

See `docs/INDEX.md` for Monad documentation.
See `../PositronicKit/AGENTS.md` for the authoritative shared-runtime guidance.
