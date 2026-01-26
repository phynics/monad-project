# Track Specification: MonadServer REST API

## 1. Overview
The goal of this track is to implement `MonadServer`, a standalone server application that exposes all core functionalities of `MonadAssistant` (currently driven by `MonadUI`) via a RESTful API. This server will replace the existing gRPC infrastructure. It will be built using the **Hummingbird** framework to leverage modern Swift concurrency and provide a high-performance, lightweight interface for external clients to interact with the Monad ecosystem.

## 2. Functional Requirements

### 2.1 Session Management
*   **Concurrency:** Support multiple simultaneous chat sessions for the single user.
*   **Mechanism:**
    *   API to generate/start a new Session ID.
    *   Chat endpoints must accept a `session_id` to maintain separate conversation contexts (history, active tools) for each interaction flow.
    *   Ensure server state handles multiple independent `ContextManager` (or equivalent) instances keyed by session.

### 2.2 Core API Capabilities (Parity with MonadUI)
The server must expose endpoints for:
*   **Chat & LLM:**
    *   Send messages and receive streaming responses (scoped to a `session_id`).
    *   Manage conversation context and history.
*   **Memory & Notes:**
    *   CRUD operations for Memories and Notes.
    *   Semantic search/retrieval of relevant context.
*   **Tools & MCP:**
    *   List available tools and execute tool calls.
    *   Support Model Context Protocol (MCP) client features.
*   **Configuration:**
    *   Read and update system configuration (e.g., model selection, API keys).

### 2.3 Persistence (SQLite)
*   **Integration:** All data (Memories, Notes, Conversations) must continue to be persisted in the existing **SQLite** database via the `MonadCore` `PersistenceService`.
*   **Session Persistence:** Decide if session metadata should be persistent in SQLite or in-memory for the server lifecycle.

### 2.4 Framework & Architecture
*   **Framework:** Use **Hummingbird** for the HTTP server implementation.
*   **Logic:** Reuse `MonadCore` services directly. The server acts as a translation layer between HTTP and `MonadCore` actors.
*   **Cleanup:** Remove all existing gRPC-related code, dependencies, and targets (`monad.proto`, `SwiftGRPC`, etc.) from the project.

### 2.5 Authentication & Security
*   **Mechanism:** Simple API Key authentication (e.g., `X-API-Key` header).
*   **Development Mode:** Include a configuration flag to bypass authentication for easier testing.

## 3. Non-Functional Requirements
*   **Swift 6.0 Compliance:** Adhere to strict concurrency standards.
*   **Performance:** Minimal latency; efficient streaming (Server-Sent Events).
*   **Modularity:** Keep server logic distinct from Core business logic.

## 4. Acceptance Criteria
*   [ ] Existing gRPC artifacts are completely removed.
*   [ ] `MonadServer` builds and runs successfully using Hummingbird.
*   [ ] REST endpoints exist and function for: Sessions, Chat, Memories, Notes, Tools, and Config.
*   [ ] Data is correctly read from and written to the SQLite database.
*   [ ] Multiple chat sessions can be active simultaneously without state collision.
*   [ ] Streaming responses for chat work correctly over SSE.
*   [ ] Authentication works as specified (with dev-mode bypass).

## 5. Out of Scope
*   Implementation of a frontend client for this API.
*   User management/Multi-tenancy.
