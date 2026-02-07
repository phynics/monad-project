# Implementation Plan - Implement System Status & Health Check

## Phase 1: Server-Side Implementation [checkpoint: dfcd01c]
- [x] Task: Define Status Models b4a508a
    - [ ] Create `StatusResponse` and `ComponentStatus` structs in `MonadCore` (shared models).
    - [ ] Ensure they are `Codable` and `Sendable`.
- [x] Task: Implement Service Health Protocols b26ec3d
    - [ ] Create a `HealthCheckable` protocol in `MonadCore`.
    - [ ] Implement this protocol in `DatabaseService` (check connection).
    - [ ] Implement this protocol in `AIService` (check config/connectivity).
- [x] Task: Create Status Controller c32f7d9
    - [ ] Create `StatusController` in `MonadServer`.
    - [ ] Implement `GET /status` handler.
    - [ ] Wire up dependency injection to access services.
- [x] Task: Register Route & Verify b635b0a
    - [ ] Register the controller in `MonadServer/App.swift`.
    - [ ] Write a unit test in `MonadServerTests` to verify the JSON response format.
- [x] Task: Conductor - User Manual Verification 'Server-Side Implementation' (Protocol in workflow.md)

## Phase 2: CLI Implementation
- [x] Task: Add Client Support 6759b76
    - [ ] Update `MonadClient` to include a `getStatus()` method.
    - [ ] Map the JSON response to the shared `StatusResponse` model.
- [x] Task: Implement CLI Command 6759b76
    - [ ] Create `Status.swift` command in `MonadCLI/Commands`.
    - [ ] Use `MonadClient` to fetch status.
- [x] Task: Format Output 6759b76
    - [ ] Implement a standardized formatter (table/list) for the status response.
    - [ ] Add color support (Green for OK, Red for Error).
- [x] Task: Conductor - User Manual Verification 'CLI Implementation' (Protocol in workflow.md)

## Phase 3: Integration & Polish
- [ ] Task: End-to-End Test
    - [ ] Run `MonadServer`.
    - [ ] Run `swift run MonadCLI status` and verify output.
- [ ] Task: Documentation
    - [ ] Update `API_REFERENCE.md` with the new endpoint.
    - [ ] Update `README.md` with the new command.
- [ ] Task: Conductor - User Manual Verification 'Integration & Polish' (Protocol in workflow.md)
