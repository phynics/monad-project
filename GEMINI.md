# Monad

## Project Overview

Monad is a headless AI assistant with a server/CLI architecture. It leverages Large Language Models (LLMs) like OpenAI's GPT-4 and local models via Ollama to provide an interactive chat experience.

The project is built with **Swift 6.0**, utilizing the modern **Observation** framework for state management. It features a robust modular architecture with separated components for logic, server, and CLI.

### Key Features

- **Server Architecture:** REST API server with **Server-Sent Events (SSE)** for real-time streaming
- **CLI Interface:** Advanced command-line client with **autocomplete**, **history**, and **slash commands**
- **LLM Integration:** Supports OpenAI (GPT-4o) and local Ollama models
- **Persistent Memory:** Stores conversation history, memories, and notes using SQLite (via GRDB)
- **Modern Swift:** Uses Actors, Structured Concurrency, and `@Observable`

## Architecture

The project follows a modular architecture organized into targets defined in `project.yml` (managed by `xcodegen`).

### Targets

- **MonadCore:** The pure logic framework. Contains:
  - **Models:** `Configuration`, `Message`, `Memory`, `Note`, `Tool`
  - **Services:** 
    - `LLMService`: Handles interaction with OpenAI/Ollama
    - `PersistenceService`: Actor-isolated GRDB layer for database storage
    - `ToolExecutor`: Manages tool execution
    - `StreamingCoordinator`: Orchestrates real-time SSE streams
    - `ContextManager`: Manages LLM context window and compression
  - **Utilities:** Logging, Encoding helpers

- **MonadServerCore:** Server-specific services including controllers and route handlers.
  - **Controllers:** `ChatController`, `SessionController`, `MemoryController`
  - **Services:** `SessionManager` (Active session state), `ToolRouter` (Routing tool calls)

- **MonadServer:** The REST API server executable. Provides:
  - Chat endpoints (with SSE streaming)
  - Lifecycle management
  - Configuration injection

- **MonadClient:** HTTP client library for communicating with MonadServer.
  - **SSEStreamReader:** Parses structured server-sent events
  - **ClientConfiguration:** Manages API connection settings

- **MonadCLI:** Command-line interface for:
  - **Interactive Chat:** REPL with streaming response rendering
  - **Input Handling:** `LineReader` for raw terminal input, history navigation, and tab-autocomplete
  - **Slash Commands:** Integrated system for commands like `/help`, `/prune`, `/memory`

### Test Targets

- **MonadCoreTests:** Unit tests for core logic
- **MonadServerTests:** Server endpoint tests

## File Structure

```
.
├── Sources
│   ├── MonadCLI           # Command-line interface & commands
│   ├── MonadClient        # Networking & SSE handling
│   ├── MonadCore          # Shared domain logic, models, & DB
│   ├── MonadServer        # Server entry point & setup
│   └── MonadServerCore    # Server controllers & routing
├── Tests                  # Unit & Integration tests
├── project.yml            # XcodeGen project definition
└── Makefile               # Build & utility scripts
```

## Development Flow

1. **User Interaction:** User inputs a message or slash command in `MonadCLI`.
2. **Client Layer:** `MonadClient` serializes the request and sends it to `MonadServer`.
3. **Routing:** `MonadServer` receives the request. `ChatController` or `ToolRouter` handles the logic.
4. **Core Processing:** 
   - `PersistenceService` retrieves context.
   - `LLMService` communicates with the AI model.
   - `ToolExecutor` runs any requested tools.
5. **Streaming:** `StreamingCoordinator` pushes incremental updates (usage data, thoughts, tokens) via SSE.
6. **Rendering:** `MonadCLI` uses `SSEStreamReader` to parse events and render them in real-time to the terminal.

## Important Services

- **PersistenceService (MonadCore):** 
  - Centralized, actor-isolated access to the SQLite database.
  - Handles CRUD operations for `ConversationSession`, `Memory`, and `Note`.
  - Manages database migrations and thread safety.

- **LLMService (MonadCore):**
  - Abtracts interactions with LLM providers (OpenAI, Ollama).
  - Handles token estimation and request formatting.

- **SessionManager (MonadServerCore):**
  - Manages active in-memory session state.
  - Coordinates session lifecycles and context refreshing.

- **ToolRouter (MonadServerCore):**
  - Routes dynamic tool invocations to their respective handlers.
  - Enables the agent to perform actions like web searches or file operations.

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

- `Package.swift`: Swift Package Manager manifest
- `Sources/MonadCore/Services/LLMService.swift`: Core logic for LLM communication
- `Sources/MonadCore/Services/Database/PersistenceService.swift`: Main interface for data persistence
- `Sources/MonadServerCore/Controllers/`: Server endpoint controllers
- `Sources/MonadCLI/Commands/`: CLI command implementations