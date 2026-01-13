# Monad Assistant

A native AI assistant for macOS and iOS that treats your personal data as a first-class citizen. This project is a technical playground for exploring high-performance, local-first AI architectures using **Swift 6.0** and **SwiftUI**.

Instead of just a chat wrapper, Monad focuses on **advanced prompting strategies**, **context management**, and **tool use** to integrate Large Language Models with your local documents and memories.

## Core Concepts

### 🧠 The Context Engine
The "magic" isn't in the model, but in the prompt. Monad uses a sophisticated retrieval system to construct the perfect prompt for every query.

- **Semantic Injection**: Uses vector embeddings to find relevant memories and notes, dynamically injecting them into the system prompt.
- **LLM-Driven Tagging**: An auxiliary LLM call analyzes your input to generate search tags, boosting retrieval precision beyond simple vector similarity.
- **Reasoning Models**: Native support for models that use `<think>` tags (like DeepSeek R1), rendering the reasoning process separately from the final answer.

### 🚪 Gateway Tool Innovation
We treat tools not just as functions, but as a gateway to the outside world.

- **Protocol-First Design**: The agent interacts with a standardized tool protocol, making it easy to plug in new capabilities like filesystem access or web browsing without rewriting the core loop.
- **The "Tool Loop"**: The system supports multi-step tool execution loops. If a tool output requires further action (e.g., "File not found, list directory?"), the agent stays in the loop until the task is done, autonomously navigating your environment.

### 💾 SQLite Playground
Most assistants hide the database. Monad hands the keys to the agent.

- **Raw SQL Execution**: The agent has the power to execute raw SQL queries. It can create its own tables to store structured data, perform complex joins for deep insights, or index its own memories.
- **Protected Core**: While the agent plays in the sandbox, core tables (like your message history) are protected by strict immutability triggers, ensuring the AI can't accidentally wipe your existence.

### 📄 Virtual Document Workspace
Documents aren't just static attachments; they are tools.

- **Active Workspace**: You (or the agent) can load, unload, and pin documents. This keeps the context window focused on what matters right now.
- **Agentic Tools**: The LLM uses tools to interact with your files—searching for keywords, reading specific sections, or summarizing content—mimicking a human workflow.

### 🛠️ Architecture (The Fun Stuff)
This project explores a distributed, modular architecture to separate the "brain" from the "face".

- **Headless Core**: `MonadCore` contains all the logic, persistence (GRDB/SQLite), and tool execution. It runs anywhere Swift runs (macOS, Linux, Docker).
- **gRPC Communication**: The Core acts as a server, communicating with the native UI clients via high-performance, typed gRPC APIs.
- **Service-Provider Pattern**: A clean way to manage the lifecycle of internal services (LLM, Persistence, Metrics) without turning the codebase into spaghetti.
- **Observability**: Integrated **Prometheus** metrics because seeing real-time graphs of token speeds and latency is cool.

## Project Structure

- **MonadCore**: The shared brain (Logic, DB, Tools).
- **MonadServerCore**: Server-specific wrappers and the gRPC handler implementations.
- **MonadUI**: Shared SwiftUI components for macOS and iOS.
- **MonadTestSupport**: Mocks and utilities for the test suite.

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
