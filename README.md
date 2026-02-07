# Conductor

![Spark, a curious lynx](docs/assets/spark.png)
ok

A headless AI assistant built for deep context integration. Conductor focuses on how your data and documents integrate with Large Language Models through a server/CLI architecture.

Built with **Swift 6.0**, it features a modular architecture designed for high performance and a local-first approach.

## Architecture

- **MonadCore**: Pure logic framework with session management, context engine, persistence (GRDB/SQLite), and tool execution
- **MonadServer**: REST API server with streaming chat support
- **MonadClient**: HTTP client library for server communication
- **MonadCLI**: Command-line interface for interacting with the server

## Context & Semantic Memory

The heart of Monad is its context engine, moving beyond simple message history with sophisticated retrieval.

- **Semantic Retrieval & Tag Boosting**: Uses vector embeddings to find relevant memories and notes with LLM-driven tag-boosting for precision
- **Adaptive Learning**: Refines retrieval strategy over time, learning which memories were useful in past interactions

## Virtual Document Workspace

Documents are active parts of your conversation, not static attachments.

- **Stateful Management**: Documents are loaded, unloaded, or pinned to keep context clean while keeping critical data accessible
- **Autonomous Toolset**: The LLM can search excerpts, summarize content, and switch between document views

## Getting Started

### Quick Start (SPM)

```bash
# Build everything
swift build

# Run tests
swift test

# Start the server
swift run MonadServer

# In another terminal, use the CLI
swift run MonadCLI chat

# Check server status
swift run MonadCLI status
```

### With Xcode

```bash
# Install xcodegen if needed
brew install xcodegen

# Generate Xcode project
make generate

# Open in Xcode
make open
```

### Development Commands

```bash
make help          # Show all available commands
make build         # Build the server
make run-server    # Run the server
make test          # Run tests
make clean         # Clean build artifacts
```

## License

MIT License. See [LICENSE](LICENSE) for details.