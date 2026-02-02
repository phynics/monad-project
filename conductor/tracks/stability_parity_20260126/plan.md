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

## Phase 2: Server API Stability and Standardized Error Handling [checkpoint: 871a6b4]
Goal: Provide reliable and consistent error responses for all REST endpoints.

- [x] Task: Standardize error handling in `MonadServer`. [15a7b08]
    - [x] Update `ErrorMiddleware` to return simple HTTP status codes without detailed bodies (per specification).
    - [x] Refactor `ChatController`, `MemoryController`, `NoteController`, and `SessionController` to use standard error throwing.
- [x] Task: Implement comprehensive tests for MonadServer endpoints. [82eede7]
    - [x] Expand `Tests/MonadServerTests/ChatControllerTests.swift` with edge cases.
    - [x] Expand `Tests/MonadServerTests/MemoryControllerTests.swift` and `NoteControllerTests.swift`.
    - [x] Ensure all endpoints return appropriate status codes for success and common failure modes (400, 401, 404, 500, 503).
- [x] Task: Conductor - User Manual Verification 'Server API Stability and Standardized Error Handling' (Protocol in workflow.md)

## Phase 3: Logic De-duplication and Shared Utilities
Goal: Reduce code debt by centralizing common logic and utilities in `MonadCore`.

- [ ] Task: Centralize shared utility functions.
    - [ ] Identify replicated date formatters, string helpers, and logging configurations.
    - [ ] Refactor into `Sources/MonadCore/Utilities/`.
- [ ] Task: Consolidate prompt construction and tool handling.
    - [ ] Review `ChatViewModel` (UI) and `ChatController` (Server) for duplicated prompt assembly logic.
    - [ ] Move shared logic into `PromptBuilder` or a new `PromptCoordinator` in `MonadCore`.
    - [ ] Ensure tool registration and mapping logic is shared between UI and Server.
- [ ] Task: Conductor - User Manual Verification 'Logic De-duplication and Shared Utilities' (Protocol in workflow.md)

## Phase 4: Feature Parity - Tools and Configuration
Goal: Enable full UI capabilities within the MonadServer REST API.

- [ ] Task: Implement full Tool execution support in `MonadServer`.
    - [ ] Ensure `ToolController` can access and execute all tools registered in the system.
    - [ ] Standardize the tool execution request/response format.
    - [ ] Write unit tests for tool execution via REST.
- [ ] Task: Implement Configuration management API.
    - [ ] Create `ConfigController` in `MonadServerCore`.
    - [ ] Implement `GET /config` and `POST /config` to read and update API keys/models.
    - [ ] Write tests for configuration persistence and safety.
- [ ] Task: Conductor - User Manual Verification 'Feature Parity - Tools and Configuration' (Protocol in workflow.md)

## Phase 5: Final System Integration and Logging Pass
Goal: Verify the end-to-end data flow with consistent logging.

- [ ] Task: Implement consistent logging across core services.
    - [ ] Audit `LLMService`, `PersistenceService`, and `ToolExecutor` for logging gaps.
    - [ ] Ensure all critical transitions and errors are logged with appropriate levels.
- [ ] Task: Perform final end-to-end integration test sweep.
    - [ ] Run all test suites across `MonadCore`, `MonadUI`, and `MonadServer`.
    - [ ] Perform manual verification of unified functions between UI and Server.
- [ ] Task: Conductor - User Manual Verification 'Final System Integration and Logging Pass' (Protocol in workflow.md)
