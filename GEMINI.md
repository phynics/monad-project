# Monad

## Project Overview

Monad is a headless AI assistant with a server/CLI architecture. It leverages Large Language Models (LLMs) like OpenAI's GPT-4 and local models via Ollama to provide an interactive chat experience.

The project is built with **Swift 6.0**, utilizing the modern **Observation** framework for state management. It features a robust modular architecture with separated components for logic, server, and CLI.

### Key Features

- **Server Architecture:** REST API server with streaming chat support
- **CLI Interface:** Command-line client for interacting with the server
- **LLM Integration:** Supports OpenAI (GPT-4o) and local Ollama models
- **Persistent Memory:** Stores conversation history, memories, and notes using SQLite (via GRDB)
- **Modern Swift:** Uses Actors, Structured Concurrency, and `@Observable`

## Architecture

The project follows a modular architecture organized into targets defined in `project.yml` (managed by `xcodegen`).

### Targets

- **MonadCore:** The pure logic framework. Contains:
  - **Models:** `Configuration`, `Message`, `Memory`, `Note`, `Tool`
  - **Services:** `LLMService`, `PersistenceService` (GRDB), `ToolExecutor`, `StreamingCoordinator`
  - **Utilities:** Logging, Encoding helpers

- **MonadServerCore:** Server-specific services including controllers and route handlers.

- **MonadServer:** The REST API server executable. Provides:
  - Chat endpoints (with streaming)
  - Session management
  - Memory and note CRUD
  - Tool management

- **MonadClient:** HTTP client library for communicating with MonadServer.

- **MonadCLI:** Command-line interface for:
  - Interactive chat sessions
  - Session management
  - Memory and note operations

### Test Targets

- **MonadCoreTests:** Unit tests for core logic
- **MonadServerTests:** Server endpoint tests

### Data Flow

1. **CLI (`MonadCLI`):** User interacts via command line, requests sent to server
2. **Client (`MonadClient`):** HTTP/SSE client library
3. **Server (`MonadServer`):** Receives requests, orchestrates core services
4. **Core (`MonadCore`):** Business logic, persistence, LLM communication

## Development Setup

### Prerequisites

- Xcode 15+ (Swift 6.0 support)
- `xcodegen` (for project generation)

### Build & Run

The project uses a `Makefile` to simplify common tasks.

#### Swift Package Manager (Recommended)

```bash
# Build everything
swift build

# Run tests
swift test

# Run the server
swift run MonadServer

# Run the CLI
swift run MonadCLI chat
```

#### With Xcode

```bash
# Generate Xcode Project
make generate

# Build
make build

# Run Tests
make test

# Open in Xcode
make open
```

## Code Conventions

- **Swift Version:** Swift 6.0
- **Concurrency:** Strict concurrency checking is enabled. Use `Task`, `actor`, and `Sendable` types appropriately.
- **State Management:** Use the `@Observable` macro for reactive types.
- **Formatting:** Follow standard Swift community guidelines.
- **Persistence:** All database access goes through `PersistenceService` (Actor) in Core.

## Key Files

- `project.yml`: Project definition for `xcodegen`
- `Package.swift`: Swift Package Manager manifest
- `Sources/MonadCore/Services/LLMService.swift`: Core logic for LLM communication
- `Sources/MonadCore/Services/Database/PersistenceService.swift`: Main interface for data persistence
- `Sources/MonadServerCore/Controllers/`: Server endpoint controllers
- `Sources/MonadCLI/Commands/`: CLI command implementations