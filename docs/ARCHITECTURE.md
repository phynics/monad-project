# System Architecture

Monad follows a modular architecture designed to separate core logic, server infrastructure, and client interfaces. The project is organized into distinct Swift targets, each with a specific responsibility.

## Module Overview

### 1. MonadCore (Shared Logic)
**Responsibility**: The foundational library containing all domain logic, data models, and business rules shared across the system. It is platform-agnostic (though primarily macOS) and acts as the source of truth.

- **Domain Models**: Defines the core data structures used throughout the application, such as `Message`, `Session`, `Memory`, `Note`, and `Tool`.
- **Persistence Layer**: Manages all database interactions via `PersistenceService`. It uses [GRDB](https://github.com/groue/GRDB.swift) for typesafe SQLite access, handling migrations, CRUD operations, and thread-safe actor isolation.
- **LLM Integration**: encapsulating interactions with AI providers (OpenAI, Ollama) through `LLMService`. It handles request formatting, token estimation, and response parsing.
- **Context Management**: Responsible for Retrieval-Augmented Generation (RAG) logic, including embedding generation (`EmbeddingService`), vector search for memories, and context window compression (`ContextManager`).
- **Session Management**: `SessionManager` maintains the state of active conversations, ensuring context is preserved and updated across requests.
- **Tool Logic**: Defines the `Tool` protocol and the `ToolExecutor` which orchestrates the execution of tools, although the specific implementations may vary or be injected.

### 2. MonadShared (Common Types)
**Responsibility**: Contains the fundamental data structures and protocols shared by all other targets. Prevents circular dependencies.
- **Core Models**: `Message`, `Memory`, `ToolCall`, `ChatDelta`.
- **Protocols**: `Tool`, `LLMClientProtocol`.

### 3. MonadPrompt (Context DSL)
**Responsibility**: A domain-specific language (DSL) for constructing LLM prompts in a declarative, type-safe manner.
- **@ContextBuilder**: A Swift result builder that allows composing prompts from sections like `SystemInstructions`, `ChatHistory`, and `ContextNotes`.
- **Compression**: Logic for token budgeting and history truncation.

### 4. MonadServer (Executable Application)
**Responsibility**: The backend server that hosts the agent. It acts as the "brain," running as a background process to manage state, orchestrate AI interactions, and expose an API for clients.

- **API Layer**: Built on [Hummingbird](https://github.com/hummingbird-project/hummingbird), it exposes REST endpoints (e.g., `/chat`, `/session`) and handles HTTP request/response lifecycles.
- **State Management**: `SessionManager` maintains the in-memory state of active conversations, ensuring context is preserved and updated across requests.
- **Streaming & Concurrency**: Manages real-time communication using Server-Sent Events (SSE). It coordinates concurrent tasks such as generating AI responses while simultaneously streaming partial results to the client.
- **Tool Execution Environment**: Hosts the actual execution environment for tools, including file system access (sandboxed), shell command execution, and other side effects requested by the agent.
- **Network Discovery**: Uses `BonjourAdvertiser` to broadcast its presence on the local network, allowing clients to auto-discover the server without manual IP configuration.

### 3. MonadClient (Client Library)
**Responsibility**: A networking library that abstracts the complexity of communicating with the Monad Server. It provides a clean, Swift-native API for any client application.

- **Networking Abstraction**: Encapsulates HTTP requests, authenticates with the server, and handles connection errors.
- **SSE Parsing**: Includes `SSEStreamReader` to parse the raw event stream from the server into structured Swift objects (e.g., `ChatDelta`, `ToolCall`, `Usage`), simplifying real-time UI updates.
- **Server Discovery**: Implements the client-side logic for Bonjour discovery to find running Monad Servers.

### 4. MonadCLI (Command-Line Interface)
**Responsibility**: The primary user interface for interacting with Monad. It is a "thin client" that relies entirely on `MonadClient` and `MonadServer` for intelligence.

- **Interactive REPL**: Provides a rich terminal user interface using `ChatREPL` and `LineReader`. It supports input history, line editing, and tab-completion for a developer-friendly experience.
- **Slash Commands**: Implements local commands (e.g., `/connect`, `/clear`, `/memory`) that control the client or trigger specific server actions.
- **Rendering**: Formats and displays the conversation, including markdown parsing (if applicable in terminal) and real-time streaming updates from the agent.

## Data Flow

1.  **Input**: User types a prompt in **MonadCLI**.
2.  **Transport**: **MonadCLI** uses **MonadClient** to send the message to **MonadServer** via HTTP.
3.  **Orchestration**: **MonadServer** receives the request.
    *   It retrieves conversation history and relevant memories using **MonadCore** (`PersistenceService`).
    *   It constructs a context window.
    *   It sends the context to the LLM via **MonadCore** (`LLMService`).
4.  **Processing**: The LLM generates a response or a tool call.
    *   If a tool call, **MonadServer** executes it and feeds the result back.
5.  **Output**: **MonadServer** streams the response (tokens, thoughts, tool outputs) back to the client via SSE.
6.  **Display**: **MonadCLI** parses the stream and renders the response to the user in real-time.
