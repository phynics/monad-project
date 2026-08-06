# AGENTS

Quick reference for agents working with the Monad application repository.

## Project Essentials

- **Language:** Swift 6.0 (macOS 15+)
- **Build System:** Swift Package Manager
- **Architecture:** Monad is now primarily an application host around the shared runtime modules in `PositronicKit` (a standalone repo).
- **Key Tech:** Hummingbird (REST/SSE), GRDB/SQLite, swift-service-lifecycle, ErrorKit

## Repository Split

- `Monad` contains the app-facing targets: `MonadServer`, `MonadClient`, `MonadCLI`, and their tests.
- `PositronicKit` (standalone repo at `/Volumes/Development/PositronicKit`, upstream `github.com/phynics/PositronicKit`) contains the shared runtime, prompt, contracts, and test-support modules consumed by Monad.
- `Package.swift` wires Monad to `PositronicKit` as a **remote** SwiftPM package (`github.com/phynics/PositronicKit.git`) pinned to a released semver — `Package.swift` is the source of truth for the current pin. To test a local PositronicKit change before pushing, temporarily swap the dependency to a path pointing at `/Volumes/Development/PositronicKit` (e.g. `.package(path: "../../PositronicKit")`) and `swift package resolve`; revert before committing. See the root `../CLAUDE.md` "Local-dev override" section.

## Working Boundary

- If the change is about chat orchestration, timelines, agents, tools, prompt assembly, context gathering, shared contracts, or test-support infrastructure, inspect the `PositronicKit` repo (`/Volumes/Development/PositronicKit`) first. That is the source of truth now.
- If the change is about HTTP APIs, GRDB-backed persistence wiring, CLI flows, client networking, app bootstrapping, or Monad-specific hosting behavior, it likely belongs in this repository.
- Prefer fixing shared abstractions in `PositronicKit` rather than re-implementing them in Monad.
- Keep Monad transport- and host-specific. Keep reusable runtime logic in `PositronicKit`.

## Quick Commands

```bash
swift build                                # Build Monad app targets
swift test                                 # Run Monad tests
swift test --filter MonadServerTests       # Run specific Monad test target
swift run monad server                     # Start server
swift run monad chat                       # Interactive CLI (default)
```

For shared-runtime work in `PositronicKit` (`/Volumes/Development/PositronicKit`):

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

Monad consumes several `PositronicKit` products — the core runtime (`PositronicKit`), contracts (`PKShared`), prompt system (`PKPrompt`), embeddings (`PKLocalEmbeddings`), provider adapters, and test support (`PKTestSupport`). `Package.swift` is the source of truth for the exact product list.

## PositronicKit Guidance

`../PositronicKit/AGENTS.md` is authoritative for shared-runtime modules, invariants, and
extension points — read it before changing anything upstream. The Monad-relevant rules:

- Keep concrete transport, RPC, and client/server hosting concerns downstream in Monad unless the abstraction is clearly reusable.
- Prefer neutral seams (persistence protocols, workspace creators, prompt section providers, tool routers) over embedding Monad-specific deployment details in shared runtime code. Avoid leaking host-specific terminology into shared APIs when a neutral alternative exists.
- Drive the runtime through the `PositronicKit` facade and its public seams; `ChatEngine` and the turn pipeline are internal implementation details of the shared runtime.
- Treat prompt IR and assembled prompt artifacts as owned by `PKPrompt`. Monad consumes them; it does not reimplement prompt-tree semantics locally.

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
- Use explicit constructor injection: pass stores, managers, routers, and services into initializers. There is no ambient/service-locator DI.
- `MonadServerFactory` is the composition root; group route wiring in `RouteDependencies`.
- In tests, compose collaborators explicitly via `PKTestSupport.TestRuntime` or direct construction rather than ambient overrides.

## Working Conventions

- Prefer small, focused changes that preserve the Monad/PositronicKit boundary.
- When shared public APIs change, update imports, package references, docs, and Monad call sites together.
- Keep examples and tests aligned with any shared-runtime API change; `PositronicKitExamples` is a useful reference for intended composition.
- Add or update tests with behavioral changes, using `PKTestSupport` where it fits.
- Prefer composition over inheritance, narrow protocols, explicit `throws`, and structured logging.

## Documentation

See `docs/INDEX.md` for Monad documentation.
See `../PositronicKit/AGENTS.md` for the authoritative shared-runtime guidance.

## Workflow Artifacts

This repo holds **reference docs only** (`docs/` — architecture, API reference, etc.).
Agentic-workflow scaffolding (superpowers specs/plans, decomposed tickets, brainstorm output)
lives centrally at the workspace root under `workflow/`, namespaced by project:

```text
../workflow/
  Monad/plans/                        # this project's plans
  PositronicKit/plans/ specs/ tickets/
  Shuttle/plans/ specs/
  Yakamoz/plans/ specs/ checkpoints/ tickets/ brainstorm/
  workspace/plans/                    # cross-cutting workspace plans
```

Put new specs/plans/tickets under `../workflow/Monad/...`, **not** back inside `docs/`.
See the root `../CLAUDE.md` for the full layout.
