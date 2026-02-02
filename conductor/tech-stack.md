# Tech Stack

## Programming Language
- **Swift 6.0:** Utilizing modern features like Structured Concurrency (Actors, Task) and the Observation framework.

## Frontend Framework
- **SwiftUI:** For building high-performance, native user interfaces for macOS and iOS.

## Logic and Architecture
- **MonadCore:** A dedicated pure logic framework (Linux-compatible) responsible for context management, persistence, and tool execution.
- **MonadServerCore:** A server-side framework providing RESTful API controllers and session management.
- **Hummingbird:** A modern, high-performance HTTP server framework for Swift, used to power the MonadServer.
- **ArgumentParser:** Used for the MonadServer CLI interface.
- **Modular Design:** Separation of concerns into Core, UI, and specialized modules (like MonadMCP).
- **Architectural Integrity:**
    - **Protocol-Oriented Programming:** Services are defined by protocols to enable mocking and isolation.
    - **Dependency Injection:** Core components like `ContextManager` receive their dependencies via constructor injection, facilitating testability and modularity.
    - **Comprehensive Testing:** Commitment to high code coverage (>80% for core logic) using XCTest and mocking for all external interactions.
    - **Database-Level Protection:** Utilizes SQLite triggers to enforce strict immutability for core data types like Notes and Archives.

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
