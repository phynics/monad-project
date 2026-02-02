# Implementation Plan - General Stability Pass and Feature Parity

## Phase 1: Model Consolidation and Serialization Testing [checkpoint: 2b1dd3c]
Goal: Ensure a single source of truth for data models and robust persistence logic.

- [x] Task: Audit and consolidate shared data models. [467b541]
    - [x] List all model definitions in `MonadCore`, `MonadServerCore`, and `MonadUI`.
    - [x] Move any redundant definitions to `MonadCore`.
    - [x] Update imports across the workspace to use `MonadCore` models.
- [x] Task: Implement serialization tests for core data models. [bb2a019]
    - [x] Create `Tests/MonadCoreTests/ModelSerializationTests.swift`.
    - [x] Write failing tests for JSON and SQLite serialization/deserialization for `Message`, `Session`, `Memory`, `Note`, and `Tool`.
    - [x] Ensure edge cases (empty strings, large blobs, special characters) are handled.
    - [x] Implement fixes in models to pass tests.
- [x] Task: Conductor - User Manual Verification 'Model Consolidation and Serialization Testing' (Protocol in workflow.md)

## Phase 2: Server API Stability and Standardized Error Handling [checkpoint: 8273af1]
Goal: Provide reliable and consistent error responses for all REST endpoints.

- [x] Task: Standardize error handling in `MonadServer`. [15a7b08]
    - [x] Update `ErrorMiddleware` to return simple HTTP status codes without detailed bodies (per specification).
    - [x] Refactor `ChatController`, `MemoryController`, `NoteController`, and `SessionController` to use standard error throwing.
- [x] Task: Implement comprehensive tests for MonadServer endpoints. [82eede7]
    - [x] Expand `Tests/MonadServerTests/ChatControllerTests.swift` with edge cases.
    - [x] Expand `Tests/MonadServerTests/MemoryControllerTests.swift` and `NoteControllerTests.swift`.
    - [x] Ensure all endpoints return appropriate status codes for success and common failure modes (400, 401, 404, 500, 503).
- [x] Task: Conductor - User Manual Verification 'Server API Stability and Standardized Error Handling' (Protocol in workflow.md)

## Phase 3: Logic De-duplication and Shared Utilities [checkpoint: b6129f6]
Goal: Reduce code debt by centralizing common logic and utilities in `MonadCore`.

- [x] Task: Centralize shared utility functions. [8273af1]
    - [x] Identify replicated date formatters, string helpers, and logging configurations.
    - [x] Refactor into `Sources/MonadCore/Utilities/`.
- [x] Task: Consolidate prompt construction and tool handling. [8273af1]
    - [x] Review `ChatViewModel` (UI) and `ChatController` (Server) for duplicated prompt assembly logic.
    - [x] Move shared logic into `PromptBuilder` or a new `PromptCoordinator` in `MonadCore`.
    - [x] Ensure tool registration and mapping logic is shared between UI and Server.
- [x] Task: Conductor - User Manual Verification 'Logic De-duplication and Shared Utilities' (Protocol in workflow.md)

## Phase 4: Feature Parity - Tools and Configuration [checkpoint: 3578771]
Goal: Bring `MonadServer` to feature parity with `MonadUI` regarding tools and settings.

- [x] Task: Implement full Tool execution support in `MonadServer`. [8273af1]
    - [x] Refactor core tool services (`ToolExecutor`, `SessionToolManager`, `DocumentManager`, `ToolContextSession`, `JobQueueContext`) to `actor`s for concurrent safety.
    - [x] Update `SessionManager` to manage tool infrastructure per session.
    - [x] Standardize the tool execution request/response format in `ToolController`.
    - [x] Write unit tests for tool execution via REST.
- [x] Task: Implement Configuration management APIs in `MonadServer`. [8273af1]
    - [x] Create `ConfigurationController` to expose LLM settings.
    - [x] Ensure settings are persisted correctly using `ConfigurationStorage`.
    - [x] Implement validation logic for provider settings.

## Phase 5: System Integration and Final Polishing
Goal: Ensure the entire system is cohesive, well-logged, and fully tested.

- [x] Task: Conduct a consistent logging sweep across all modules. [8273af1]
    - [x] Ensure all key operations (LLM calls, DB queries, Server requests) use the standardized `Logger` categories.
    - [x] Remove any legacy `print` statements or non-standard logging.
- [x] Task: Perform end-to-end integration tests. [8273af1]
    - [x] Verify `MonadUI` works correctly with the refactored Core services.
    - [x] Verify `MonadServer` supports full conversation lifecycle including tools and settings.
- [x] Task: Conductor - Final System Verification (Protocol in workflow.md)
