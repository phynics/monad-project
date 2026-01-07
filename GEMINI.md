# Monad Assistant

## Project Overview

Monad Assistant is a sophisticated AI-powered assistant application developed for macOS and iOS. It leverages Large Language Models (LLMs) like OpenAI's GPT-4 and local models via Ollama to provide an interactive chat experience.

The project is built with **Swift 6.0** and **SwiftUI**, utilizing the modern **Observation** framework for state management. It features a robust architecture with separated Logic (`MonadCore`) and UI (`MonadUI`) modules, specialized support for the Model Context Protocol (MCP), and platform-specific application targets.

### Key Features
*   **Multi-Platform:** Native apps for macOS and iOS sharing core logic and UI.
*   **LLM Integration:** Supports OpenAI (GPT-4o) and local Ollama models.
*   **Persistent Memory:** Stores conversation history, memories, and notes using SQLite (via GRDB).
*   **Model Context Protocol (MCP):** Implements client support for MCP.
*   **Modern Swift:** Uses Actors, Structured Concurrency, and `@Observable`.
*   **Modular Architecture:** Clear separation between Business Logic (Core) and User Interface (UI) to support future server-side deployments (Docker/Linux).

## Architecture

The project follows a modular architecture organized into targets defined in `project.yml` (managed by `xcodegen`).

### Targets
*   **MonadCore:** The pure logic framework (Linux-compatible). Contains:
    *   **Models:** `Configuration`, `Message`, `Memory`, `Note`, `Tool`.
    *   **Services:** `LLMService`, `PersistenceService` (GRDB), `ToolExecutor`, `StreamingCoordinator`.
    *   **Utilities:** Logging, Encoding helpers.
*   **MonadUI:** The UI framework containing:
    *   **Views:** All SwiftUI views (`ContentView`, `MessageBubble`, etc.).
    *   **ViewModels:** `ChatViewModel`.
    *   **Services:** `PersistenceManager` (Observable wrapper for UI), `ConversationArchiver`.
*   **MonadMCP:** A macOS framework implementing the Model Context Protocol client. Depends on `MonadCore`.
*   **MonadAssistant (macOS):** The main macOS application target.
*   **MonadAssistant-iOS:** The main iOS application target.
*   **MonadAssistantTests:** Unit tests.

### Data Flow
1.  **UI (`MonadUI`):** Views observe ViewModels.
2.  **ViewModel (`ChatViewModel`):** Manages state and orchestrates calls to services in `MonadCore`.
3.  **Persistence:**
    *   `PersistenceManager` (`MonadUI`) acts as the `@Observable` bridge for the UI.
    *   `PersistenceService` (`MonadCore`) handles the actual concurrent database access (Actor).
4.  **LLMService (`MonadCore`):** Handles communication with LLM providers.

## Development Setup

### Prerequisites
*   Xcode 15+ (Swift 6.0 support)
*   `xcodegen` (for project generation)
*   `swift-format` (optional, for linting)

### Build & Run
The project uses a `Makefile` to simplify common tasks.

*   **Generate Xcode Project:**
    ```bash
    make generate
    ```
    *Always run this after pulling changes or modifying `project.yml`.*

*   **Install Dependencies:**
    ```bash
    make install-deps
    ```

*   **Build (macOS):**
    ```bash
    make build
    ```

*   **Run (macOS):**
    ```bash
    make run
    ```

*   **Run Tests:**
    ```bash
    make test
    ```

*   **Open in Xcode:**
    ```bash
    make open
    ```

## Code Conventions

*   **Swift Version:** Swift 6.0.
*   **Concurrency:** Strict concurrency checking is enabled. Use `Task`, `actor`, and `Sendable` types appropriately.
*   **State Management:** Use the `@Observable` macro for ViewModels and connected types.
*   **Formatting:** Follow standard Swift community guidelines.
*   **Persistence:** All database access goes through `PersistenceService` (Actor) in Core, exposed to UI via `PersistenceManager`.
*   **Configuration:** LLM settings are stored in `UserDefaults` via `ConfigurationStorage`.

## Key Files
*   `project.yml`: Project definition for `xcodegen`.
*   `Sources/MonadCore/Services/LLMService.swift`: Core logic for LLM communication.
*   `Sources/MonadCore/Services/Database/PersistenceService.swift`: Main interface for data persistence.
*   `Sources/MonadUI/ViewModels/ChatViewModel.swift`: Main UI state management.