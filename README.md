# Monad Assistant

A native AI assistant for macOS and iOS built for speed and deep context. Instead of just a chat interface, Monad focuses on how your personal data and documents integrate with Large Language Models.

Now featuring an **enterprise-grade distributed architecture**, Monad leverages high-performance gRPC communication, professional observability, and robust error handling to deliver a seamless, local-first experience.

## Key Features

### Context & Semantic Memory
The heart of Monad is its context engine. It moves beyond simple message history by using a sophisticated retrieval system to pull in relevant information when needed.

- **Semantic Retrieval & Tag Boosting**: Uses vector embeddings to find relevant memories and notes. It employs an LLM-driven tag-boosting system to prioritize specific context, ensuring the retrieval is both broad and precise.
- **Adaptive Learning**: The system refines its retrieval strategy over time, learning which memories were actually useful in past interactions to improve future relevance.

### Virtual Document Workspace
Monad allows you to treat documents as active parts of your conversation rather than just static attachments.

- **Stateful Management**: Documents are managed in a workspace where they can be loaded, unloaded, or pinned. This keeps the LLM's context window clean while keeping critical data accessible.
- **Autonomous Toolset**: The LLM can interact with your documents directly—searching for excerpts, summarizing content, and switching between different document views to find the answers you need.

### Distributed & Robust Architecture
Monad is built on a modular, Service-Provider architecture designed for scalability and reliability.

- **Service-Provider Pattern**: Server components are managed via a centralized orchestrator, ensuring clean lifecycle management and dependency injection.
- **High-Performance gRPC**: Core logic and UI are decoupled, communicating via typed gRPC protocols.
- **Professional Observability**: Integrated **SwiftPrometheus** and **SwiftMetrics** provide real-time telemetry on performance, latency, and error rates.
- **Centralized Error Handling**: A unified error handler maps domain errors to gRPC statuses and automatically records telemetry.

## Architecture

The project is organized into modular targets:

- **MonadCore**: The pure logic framework containing the context engine, persistence (via GRDB/SQLite), and tool execution logic. Shared by both client and server.
- **MonadServerCore**: Contains server-specific logic, including gRPC handlers, the ServiceProvider orchestrator, and observability infrastructure.
- **MonadUI**: A shared SwiftUI framework for macOS and iOS components.
- **MonadTestSupport**: A dedicated target for test mocks and utilities.

## Testing

Monad employs a "Gold Standard" testing strategy:
- **Unit Tests**: comprehensive coverage for core logic.
- **E2E Integration Tests**: Validates server flows using an in-process gRPC server and transient database.
- **Fuzz Testing**: Ensures resilience against malformed inputs using data-driven fuzz tests and `libFuzzer` infrastructure.
- **Performance Benchmarking**: Tracks latency for critical paths like memory search and chat processing.

See [TESTING.md](TESTING.md) for detailed instructions.

## Getting Started

1. **Generate Project**:
   ```bash
   make generate
   ```
2. **Dependencies**:
   ```bash
   make install-deps
   ```
3. **Build & Run**:
   ```bash
   make build
   make run
   ```

## License
MIT License. See [LICENSE](LICENSE) for details.
