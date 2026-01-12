# Plan: Client-Server Split and Dockerization

## Phase 1: gRPC Schema and Infrastructure [checkpoint: 148b207]
Define the communication contract and set up code generation.

- [x] Task: Implement Feature: Define the `monad.proto` file covering Chat, Memory, Notes, and Job services. dee891c
- [x] Task: Implement Feature: Update `Package.swift` and `project.yml` with gRPC Swift dependencies and configure the build system for code generation. b18ecb8
- [x] Task: Write Tests: Verify Protobuf-to-Model mapping and serialization for all core types. 61779d1
- [ ] Task: Conductor - User Manual Verification 'gRPC Schema and Infrastructure' (Protocol in workflow.md)

## Phase 2: MonadServer Implementation [checkpoint: ed1f55b]
Build the Swift-based server and containerize it.

- [x] Task: Implement Feature: Create the `MonadServer` target and implement gRPC service handlers that wrap `MonadCore` logic. 5bd21eb
- [x] Task: Implement Feature: Create a `Dockerfile` and `docker-compose.yml` to build and run the server on Linux with persistent volume mounting for the SQLite database. e5cc52b
- [x] Task: Write Tests: Implement server-side integration tests that verify service handlers against a live (or mocked) database. b08b390
- [ ] Task: Conductor - User Manual Verification 'MonadServer Implementation' (Protocol in workflow.md)

## Phase 3: Main Client Transition
Update the macOS/iOS applications to communicate with the remote server.

- [ ] Task: Implement Feature: Create a `gRPCLLMService` and `gRPCPersistenceService` that implement the existing protocols but delegate to the gRPC server.
- [ ] Task: Implement Feature: Update `SettingsView` to allow users to toggle between "Local" and "Remote" modes and configure server endpoints.
- [ ] Task: Write Tests: Verify that the UI remains reactive and handles network-related errors gracefully using mocked gRPC responses.
- [ ] Task: Conductor - User Manual Verification 'Main Client Transition' (Protocol in workflow.md)

## Phase 4: Signal Client PoC
Implement the secondary interface to prove architectural flexibility.

- [ ] Task: Implement Feature: Create a standalone `MonadSignalBridge` (PoC) that listens for Signal messages and forwards them to the Monad gRPC server.
- [ ] Task: Implement Feature: Support basic session management within the Signal bridge to map Signal users to assistant conversations.
- [ ] Task: Write Tests: Functional tests for the bridge logic, ensuring messages flow correctly from the bridge to the server and back.
- [ ] Task: Conductor - User Manual Verification 'Signal Client PoC' (Protocol in workflow.md)

## Phase 5: Distributed Loop Verification
Final end-to-end testing of the entire ecosystem.

- [ ] Task: Write Tests: Create a multi-client integration test where both the Main Client and Signal Client interact with the same shared server state.
- [ ] Task: Implement Feature: Optimize gRPC streaming performance and connection stability.
- [ ] Task: Conductor - User Manual Verification 'Distributed Loop Verification' (Protocol in workflow.md)
