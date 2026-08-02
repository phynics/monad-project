# Documentation Index

Monad documentation for the post-refactor architecture.

## Start Here

- `../README.md` — project overview and quick start
- `../AGENTS.md` — repository guidance for agents and contributors
- `../DEVELOPMENT.md` — development workflow and contributor notes
- `../PositronicKit/AGENTS.md` — authoritative shared-runtime guidance

## Core Docs

- `ARCHITECTURE.md` — current Monad/PositronicKit split and data flow
- `API_REFERENCE.md` — MonadServer HTTP API
- `CLIENT.md` — MonadClient and MonadCLI behavior

The only user-facing executable is `monad`. Run `swift run monad` (defaults to chat),
`swift run monad server`, or `swift run monad status`; the server is never auto-started.
`MonadServerCore` and `MonadCLICore` are internal implementation targets, while
`MonadClient` remains the importable client surface for app integrations.
- `WORKSPACE.md` — workspace registration, trust, and routing concepts
- `AGENT.md` — agent and template concepts
- `TIMELINE.md` — timeline model and lifecycle
- `CONTEXT_SYSTEM.md` — context gathering and prompt assembly concepts
- `ERROR_HANDLING.md` — error handling conventions
- `STORES.md` — persistence and caching notes

## What Lives Where

### In Monad

- HTTP routes and controllers
- GRDB persistence adapters and migrations
- WebSocket/SSE hosting
- CLI flows and local client UX

### In PositronicKit

- Shared runtime orchestration
- Prompt assembly and compression
- Shared API/runtime models
- Reusable test support

## Verification

```bash
swift build
swift test
swift run monad server
swift run monad chat
```
