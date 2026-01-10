# Tech Stack

## Programming Language
- **Swift 6.0:** Utilizing modern features like Structured Concurrency (Actors, Task) and the Observation framework.

## Frontend Framework
- **SwiftUI:** For building high-performance, native user interfaces for macOS and iOS.

## Logic and Architecture
- **MonadCore:** A dedicated pure logic framework (Linux-compatible) responsible for context management, persistence, and tool execution.
- **Modular Design:** Separation of concerns into Core, UI, and specialized modules (like MonadMCP).

## Database and Persistence
- **GRDB.swift:** A robust toolkit for SQLite databases, providing high-level Swift interfaces for concurrent database access.
- **SQLite:** The underlying persistent storage for conversation history, memories, and notes.

## LLM Integration and Services
- **OpenAI Swift SDK:** Direct integration with OpenAI's models (e.g., GPT-4o).
- **Local Models (Ollama):** Support for local model execution for privacy and offline use.
- **OpenRouter:** For accessing a wide variety of models through a single API.
- **Model Context Protocol (MCP):** Client-side support for standardized tool and data integration.

## Build and Dependency Management
- **xcodegen:** For project generation from `project.yml`, ensuring a consistent Xcode environment.
- **Swift Package Manager (SPM):** For managing external library dependencies.
