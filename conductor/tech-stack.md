# Tech Stack

## Programming Language
- **Swift 6.0:** Utilizing modern features like Structured Concurrency (Actors, Task) and the Observation framework.

## Server Framework
- **Hummingbird:** A modern, high-performance HTTP server framework for Swift, used to power MonadServer.
- **ArgumentParser:** Used for both MonadServer and MonadCLI command-line interfaces.

## Logic and Architecture
- **MonadCore:** A dedicated pure logic framework responsible for context management, persistence, and tool execution.
- **MonadServerCore:** A server-side framework providing RESTful API controllers and session management.
- **MonadClient:** HTTP client library for communicating with the server.
- **MonadCLI:** Command-line interface for interacting with the server.
- **Modular Design:** Separation of concerns into Core, Server, and Client modules.
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

## Build and Dependency Management
- **xcodegen:** For project generation from `project.yml`, ensuring a consistent Xcode environment.
- **Swift Package Manager (SPM):** For managing external library dependencies.
