# Implementation Plan - MonadServer REST API

## Phase 1: Infrastructure & Cleanup
Goal: Remove legacy gRPC code and set up the new Hummingbird server environment.

- [~] Task: Remove existing gRPC targets and dependencies.
    - [ ] Remove `MonadServer`, `MonadServerCore`, and any gRPC-related client targets from `project.yml`.
    - [ ] Remove `SwiftGRPC` and `SwiftProtobuf` dependencies from `project.yml`.
    - [ ] Delete `Sources/MonadServer`, `Sources/MonadServerCore`, and `Sources/MonadCore/Generated`.
    - [ ] Delete gRPC-specific services in `MonadCore` (e.g., `Sources/MonadCore/Services/gRPC/`).
    - [ ] Cleanup `MonadUI` and `MonadCore` to remove any references to gRPC services or clients.
    - [ ] Delete gRPC-related tests (e.g., `Tests/MonadCoreTests/ChatViewModelgRPCTests.swift`, `Tests/MonadCoreTests/gRPCServiceTests.swift`).
    - [ ] Run `make generate` to clean up the Xcode project.
- [ ] Task: Initialize new `MonadServer` target with Hummingbird.
    - [ ] Update `project.yml` to add a new executable target `MonadServer`.
    - [ ] Add `Hummingbird` dependency to `project.yml`.
    - [ ] Create `Sources/MonadServer/main.swift` with a basic "Hello World" Hummingbird app.
    - [ ] Ensure it builds and runs via a new `make run-server` command.
- [ ] Task: Implement Basic Configuration & Auth Middleware.
    - [ ] Create `AppConfiguration` struct to load settings (Port, API Key, Dev Mode).
    - [ ] Implement `APIKeyMiddleware` to check `X-API-Key`.
    - [ ] Add unit tests for middleware (reject invalid keys, allow all in dev mode).
- [ ] Task: Conductor - User Manual Verification 'Infrastructure & Cleanup' (Protocol in workflow.md)

## Phase 2: Session Management & Core Integration
Goal: Enable multiple concurrent chat sessions and link to MonadCore.

- [ ] Task: Implement Session Manager.
    - [ ] Create `SessionManager` actor to hold active `ContextManager` instances in memory.
    - [ ] Define `Session` struct (ID, created_at, last_active).
    - [ ] Implement `POST /sessions` to create a new session ID.
    - [ ] Implement cleanup logic for stale sessions.
- [ ] Task: Create Session-Scoped Dependency Injection.
    - [ ] Ensure `MonadCore` services (Persistence, LLM) can be safely shared or instantiated per session.
    - [ ] Update `SessionManager` to initialize a `ContextManager` for each new session using shared core services.
- [ ] Task: Conductor - User Manual Verification 'Session Management & Core Integration' (Protocol in workflow.md)

## Phase 3: Chat & LLM Endpoints
Goal: Expose chat functionality with streaming support.

- [ ] Task: Implement Chat Endpoint.
    - [ ] Define Request/Response models (`ChatRequest`, `ChatResponse`).
    - [ ] Create `POST /sessions/{id}/chat` endpoint.
    - [ ] Wire up `LLMService` to handle the request using the session's context.
- [ ] Task: Implement Streaming Responses (SSE).
    - [ ] Update `ChatController` to support Server-Sent Events (SSE).
    - [ ] Bridge `LLMService` async stream to Hummingbird's response writer.
    - [ ] Verify streaming works with `curl -N`.
- [ ] Task: Conductor - User Manual Verification 'Chat & LLM Endpoints' (Protocol in workflow.md)

## Phase 4: Data Management (Memories, Notes, Tools)
Goal: Expose CRUD operations for persistent data and tools.

- [ ] Task: Implement Memories API.
    - [ ] `GET /memories` (search/list).
    - [ ] `POST /memories` (create).
    - [ ] `DELETE /memories/{id}`.
    - [ ] Connect to `PersistenceService`.
- [ ] Task: Implement Notes API.
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
