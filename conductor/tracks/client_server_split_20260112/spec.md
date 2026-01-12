# Specification: Client-Server Split and Dockerization

## Overview
This track involves architecting Monad Assistant into a distributed system. The existing application logic (`MonadCore`) will be decoupled from the user interface (`MonadUI`) and hosted on a Dockerized Swift server. Communication between clients and the server will be handled via high-performance gRPC. To prove the flexibility of this architecture, a secondary client based on the Signal protocol will be implemented as a PoC.

## Architecture
- **Server:** A Swift-based backend running on Linux (Docker). It hosts the `MonadCore` logic, manages the SQLite database, and executes agent tools.
- **Main Client:** Native macOS and iOS applications built with `MonadUI`. Communicates via gRPC.
- **PoC Client (Signal):** A standalone service that bridges Signal messaging with the Monad gRPC server, allowing users to interact with their assistant via a standard messaging app.
- **Protocol:** gRPC using Protocol Buffers for typed, efficient, and streaming-capable communication.
- **Persistence:** The primary SQLite database resides on the server, serving as the source of truth for all clients.

## Functional Requirements
### Server-Side
- Host a gRPC server providing services for:
    - **Chat:** Sending prompts and receiving streaming responses.
    - **Memory:** Searching and managing semantic memories.
    - **Notes:** CRUD operations for persistent notes.
    - **Jobs:** Managing the persistent job queue.
- Run `MonadCore` natively on Linux.
- Execute tools (Filesystem, SQL, etc.) within the server environment.
- Dockerfile for easy deployment and isolation.

### Client-Side (Main)
- Implement a gRPC client to interact with the server.
- Support configuration of server endpoint (host/port) in settings.

### PoC Client (Signal)
- Authenticate with the Signal protocol.
- Listen for incoming messages and forward them to the Monad gRPC server.
- Stream responses back to the Signal conversation.

## Non-Functional Requirements
- **Performance:** Maintain low-latency streaming for LLM responses.
- **Portability:** The server must be fully functional within a standard Swift Linux Docker container.
- **Scalability:** The architecture should allow for multiple concurrent clients (Main and Signal).

## Acceptance Criteria
- [ ] A Swift server executable compiles and runs on Linux/Docker.
- [ ] The macOS/iOS client successfully connects to the server via gRPC.
- [ ] A Signal client PoC can send a message to the server and receive an AI-generated response.
- [ ] Database state is correctly persisted on the server and shared across different client types.
- [ ] Tools execute successfully on the server.

## Out of Scope
- User authentication and authorization (trusted local environment assumed for Phase 1).
- Client-side tool execution.
