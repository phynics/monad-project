# Monad Assistant

A native AI assistant for macOS and iOS built for speed and deep context. Instead of just a chat interface, Monad focuses on how your personal data and documents integrate with Large Language Models.

Built with **Swift 6.0** and **SwiftUI**, it utilizes a modular architecture designed for high performance and local-first privacy.

## Context & Semantic Memory
The heart of Monad is its context engine. It moves beyond simple message history by using a sophisticated retrieval system to pull in relevant information when needed.

- **Semantic Retrieval & Tag Boosting**: Uses vector embeddings to find relevant memories and notes. It employs an LLM-driven tag-boosting system to prioritize specific context, ensuring the retrieval is both broad and precise.
- **Adaptive Learning**: The system refines its retrieval strategy over time, learning which memories were actually useful in past interactions to improve future relevance.

## Virtual Document Workspace
Monad allows you to treat documents as active parts of your conversation rather than just static attachments.

- **Stateful Management**: Documents are managed in a workspace where they can be loaded, unloaded, or pinned. This keeps the LLM's context window clean while keeping critical data accessible.
- **Autonomous Toolset**: The LLM can interact with your documents directly—searching for excerpts, summarizing content, and switching between different document views to find the answers you need.

## Architecture
- **MonadCore**: A pure logic framework containing the context engine, persistence (via GRDB/SQLite), and tool execution logic.
- **MonadUI**: A shared SwiftUI framework for macOS and iOS components.
- **Modern Swift**: Fully embraces Swift 6 concurrency, Actors, and the Observation framework.

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