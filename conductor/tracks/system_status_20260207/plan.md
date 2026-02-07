# Implementation Plan - Implement System Status & Health Check

## Phase 1: Server-Side Implementation
- [ ] Task: Define Status Models
    - [ ] Create `StatusResponse` and `ComponentStatus` structs in `MonadCore` (shared models).
    - [ ] Ensure they are `Codable` and `Sendable`.
- [ ] Task: Implement Service Health Protocols
    - [ ] Create a `HealthCheckable` protocol in `MonadCore`.
    - [ ] Implement this protocol in `DatabaseService` (check connection).
    - [ ] Implement this protocol in `AIService` (check config/connectivity).
- [ ] Task: Create Status Controller
    - [ ] Create `StatusController` in `MonadServer`.
    - [ ] Implement `GET /status` handler.
    - [ ] Wire up dependency injection to access services.
- [ ] Task: Register Route & Verify
    - [ ] Register the controller in `MonadServer/App.swift`.
    - [ ] Write a unit test in `MonadServerTests` to verify the JSON response format.
- [ ] Task: Conductor - User Manual Verification 'Server-Side Implementation' (Protocol in workflow.md)

## Phase 2: CLI Implementation
- [ ] Task: Add Client Support
    - [ ] Update `MonadClient` to include a `getStatus()` method.
    - [ ] Map the JSON response to the shared `StatusResponse` model.
- [ ] Task: Implement CLI Command
    - [ ] Create `Status.swift` command in `MonadCLI/Commands`.
    - [ ] Use `MonadClient` to fetch status.
- [ ] Task: Format Output
    - [ ] Implement a standardized formatter (table/list) for the status response.
    - [ ] Add color support (Green for OK, Red for Error).
- [ ] Task: Conductor - User Manual Verification 'CLI Implementation' (Protocol in workflow.md)

## Phase 3: Integration & Polish
- [ ] Task: End-to-End Test
    - [ ] Run `MonadServer`.
    - [ ] Run `swift run MonadCLI status` and verify output.
- [ ] Task: Documentation
    - [ ] Update `API_REFERENCE.md` with the new endpoint.
    - [ ] Update `README.md` with the new command.
- [ ] Task: Conductor - User Manual Verification 'Integration & Polish' (Protocol in workflow.md)
