# Monad

![Spark, a curious lynx](docs/assets/spark.png)

Monad is the application host around the shared `PositronicKit` runtime.

- The `monad` executable provides the server and interactive CLI subcommands.
- `MonadClient` is the importable Swift client API for future app integrations.
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
# `swift run monad` defaults to chat; it never auto-starts a server.
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
