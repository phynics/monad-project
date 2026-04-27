# System Architecture

Monad is now a host application layered on top of the shared runtime in `../PositronicKit`.

## Repository Split

### Monad

Monad owns the app-facing targets and deployment-specific behavior:

1. `MonadServer` — Hummingbird HTTP API, SSE/WebSocket endpoints, GRDB persistence, service lifecycle
2. `MonadClient` — client-side HTTP/SSE API wrappers and local registration/workspace flows
3. `MonadCLI` — terminal UX and slash-command flows built on `MonadClient`

### PositronicKit

`../PositronicKit` owns the reusable runtime stack:

1. `PositronicKit` — orchestration runtime (`ChatEngine`, `TimelineManager`, `ToolRouter`, workspace and agent services, LLM services)
2. `PKShared` — shared contracts, tools, API models, logging, and utility types
3. `PKPrompt` — prompt IR, assembly, rendering, and compression primitives
4. `PKTestSupport` — shared test helpers and fixtures

## Dependency Shape

```text
PKShared
  ↑
PKPrompt
  ↑
PositronicKit

MonadClient  ────────→ PKShared
MonadCLI     ────────→ MonadClient
MonadServer  ────────→ PositronicKit, PKShared, PKPrompt
```

## Boundary Rules

- Put reusable runtime logic in `PositronicKit`.
- Put transport, persistence adapters, server routing, and CLI behavior in Monad.
- Prefer shared abstractions such as persistence protocols, request-origin stores, workspace creators, and tool routers over Monad-specific forks.

## Core Concepts

### Timelines

- `TimelineManager` lives in `PositronicKit`.
- MonadServer wires timeline persistence and exposes timeline APIs.

### Workspaces

- Shared workspace metadata lives in `PKShared`.
- Runtime-owned workspaces use `WorkspaceLocation.runtime`.
- Attached external workspaces use `WorkspaceLocation.attached` and are typically associated with a request origin.

### Request Origins

- The old client identity model is now represented by request origins in shared code.
- Monad preserves compatibility at the app layer, but new shared abstractions should use request-origin terminology.

### Prompt And Context Pipelines

- Context gathering and prompt assembly both use the shared `Pipeline<Context, Event>` pattern.
- `ContextManager` and `PromptBuilder` live in `PositronicKit`.
- Monad consumes those services rather than reimplementing prompt assembly locally.

## Runtime Flow

1. Client sends a chat request to `MonadServer`.
2. MonadServer resolves timeline state, persistence, and transport context.
3. `PositronicKit` orchestrates context gathering, prompt assembly, tool routing, and LLM execution.
4. MonadServer streams events back over SSE or WebSocket.
5. MonadCLI or other clients render results and handle local flows like workspace registration and write-access prompts.

## Verification Commands

```bash
swift build
swift test
swift run MonadServer
swift run MonadCLI chat
```
