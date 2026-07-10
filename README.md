# Monad

![Spark, a curious lynx](docs/assets/spark.png)

Monad is the application host around the shared `PositronicKit` runtime.

- `MonadServer` provides the Hummingbird HTTP/SSE/WebSocket host and GRDB-backed persistence.
- `MonadClient` provides the Swift client API for talking to the server.
- `MonadCLI` provides the interactive terminal interface.
- `../PositronicKit` provides the shared runtime, prompt system, contracts, and test support used by this repo.

## Architecture

Monad now depends on these `PositronicKit` products:

- `PositronicKit` for runtime orchestration such as `ChatEngine`, `TimelineManager`, `ToolRouter`, and LLM services
- `PKShared` for shared API and runtime types
- `PKPrompt` for prompt construction and assembly primitives
- `PKTestSupport` for reusable test helpers

Use Monad for transport, persistence wiring, and app-specific behavior. Use `PositronicKit` for reusable agent-runtime logic.

## Getting Started

```bash
swift build
swift test
swift run monad server
swift run monad chat
```

## Working With PositronicKit

For shared runtime work, use the sibling package directly:

```bash
cd ../PositronicKit
swift build
swift test
swift run PositronicKitExamples
```

## Docs

- `AGENTS.md` for repository-specific guidance
- `docs/INDEX.md` for the documentation index
- `../PositronicKit/AGENTS.md` for shared runtime guidance

## License

MIT License. See `LICENSE`.
