# Implementation Plan - MonadServer REST API

## Phase 1: Infrastructure & Cleanup
Goal: Remove legacy gRPC code and set up the new Hummingbird server environment.

- [x] Task: Remove existing gRPC targets and dependencies.
    - [x] Remove `MonadServer`, `MonadServerCore`, and any gRPC-related client targets from `project.yml`.
    - [x] Remove `SwiftGRPC` and `SwiftProtobuf` dependencies from `project.yml`.
    - [x] Delete `Sources/MonadServer`, `Sources/MonadServerCore`, and `Sources/MonadCore/Generated`.
    - [x] Delete gRPC-specific services in `MonadCore` (e.g., `Sources/MonadCore/Services/gRPC/`).
    - [x] Cleanup `MonadUI` and `MonadCore` to remove any references to gRPC services or clients.
    - [x] Delete gRPC-related tests (e.g., `Tests/MonadCoreTests/ChatViewModelgRPCTests.swift`, `Tests/MonadCoreTests/gRPCServiceTests.swift`).
    - [x] Run `make generate` to clean up the Xcode project.
- [x] Task: Initialize new `MonadServer` target with Hummingbird.
    - [x] Update `project.yml` to add a new executable target `MonadServer`.
    - [x] Add `Hummingbird` dependency to `project.yml`.
    - [x] Create `Sources/MonadServer/main.swift` with a basic "Hello World" Hummingbird app.
    - [x] Ensure it builds and runs via a new `make run-server` command.
- [x] Task: Implement Basic Configuration & Auth Middleware.
    - [x] Create `AppConfiguration` struct to load settings (Port, API Key, Dev Mode).
    - [x] Implement `APIKeyMiddleware` to check `X-API-Key`.
    - [x] Add unit tests for middleware (reject invalid keys, allow all in dev mode).
- [x] Task: Conductor - User Manual Verification 'Infrastructure & Cleanup' (Protocol in workflow.md)

## Phase 2: Session Management & Core Integration [checkpoint: 5caa70c]
Goal: Enable multiple concurrent chat sessions and link to MonadCore.

- [x] Task: Implement Session Manager. [19da5a5]
    - [ ] Create `SessionManager` actor to hold active `ContextManager` instances in memory.
    - [ ] Define `Session` struct (ID, created_at, last_active).
    - [ ] Implement `POST /sessions` to create a new session ID.
    - [ ] Implement cleanup logic for stale sessions.
- [x] Task: Create Session-Scoped Dependency Injection. [bb945d4]
    - [ ] Ensure `MonadCore` services (Persistence, LLM) can be safely shared or instantiated per session.
    - [ ] Update `SessionManager` to initialize a `ContextManager` for each new session using shared core services.
- [x] Task: Conductor - User Manual Verification 'Session Management & Core Integration' (Protocol in workflow.md)

## Phase 3: Chat & LLM Endpoints [checkpoint: dae0703]
Goal: Expose chat functionality with streaming support.

- [x] Task: Implement Chat Endpoint. [c1a1106]
    - [ ] Define Request/Response models (`ChatRequest`, `ChatResponse`).
    - [ ] Create `POST /sessions/{id}/chat` endpoint.
    - [ ] Wire up `LLMService` to handle the request using the session's context.
- [x] Task: Implement Streaming Responses (SSE). [2452d4d]
    - [ ] Update `ChatController` to support Server-Sent Events (SSE).
    - [ ] Bridge `LLMService` async stream to Hummingbird's response writer.
    - [ ] Verify streaming works with `curl -N`.
- [x] Task: Conductor - User Manual Verification 'Chat & LLM Endpoints' (Protocol in workflow.md)

## Phase 4: Data Management (Memories, Notes, Tools)
Goal: Expose CRUD operations for persistent data and tools.

- [x] Task: Implement Memories API. [a6603d7]
    - [ ] `GET /memories` (search/list).
    - [ ] `POST /memories` (create).
    - [ ] `DELETE /memories/{id}`.
    - [ ] Connect to `PersistenceService`.
- [x] Task: Implement Notes API. [892530e]
    - [ ] `GET /notes` (search/list).
    - [ ] `POST /notes` (create/update).
    - [ ] `DELETE /notes/{title}`.
- [ ] Task: Implement Tools API.
    - [ ] `GET /tools` (list available tools).
    - [ ] `POST /tools/execute` (direct execution).
- [ ] Task: Conductor - User Manual Verification 'Data Management' (Protocol in workflow.md)

## Phase 5: Final Polish & Verification
Goal: Ensure robust error handling, logging, and comprehensive testing.

- [ ] Task: Enhance Error Handling.
    - [ ] Map `MonadCore` errors to appropriate HTTP Status Codes (404, 400, 500).
    - [ ] Implement structured JSON error responses.
- [ ] Task: Add Logging.
    - [ ] Request/Response logging.
    - [ ] Structured logging for session lifecycle events and errors.
- [ ] Task: End-to-End Testing.
    - [ ] Write an integration test suite simulating a full user flow (Session -> Chat -> Note -> Search).
- [ ] Task: Conductor - User Manual Verification 'Final Polish & Verification' (Protocol in workflow.md)
