# Implementation Plan: Generation Cancellation

## Phase 1: Core Logic & Shared Models
- [ ] Task: Add `generationCancelled` event type to `StreamEventType` in `MonadShared`
- [ ] Task: Implement Task Registry in `SessionManager`
    - [ ] Add `activeTasks: [UUID: Task<Void, Never>]` to `SessionManager` actor
    - [ ] Implement `registerTask(_:for:)` and `cancelGeneration(for:)` methods
- [ ] Task: Update `ChatEngine` to handle cancellation
    - [ ] Check `Task.isCancelled` in `runChatLoop` and `processTurn`
    - [ ] Yield `.error(CancellationError())` to the stream when cancelled
- [ ] Task: Conductor - User Manual Verification 'Core Logic & Shared Models' (Protocol in workflow.md)

## Phase 2: API Implementation
- [ ] Task: Update `ChatAPIController`
    - [ ] Implement `POST /api/sessions/{id}/chat/cancel` endpoint
    - [ ] Update `chatStream` to register the generation task with `SessionManager`
    - [ ] Update SSE loop to catch `CancellationError` and yield `generationCancelled` event
- [ ] Task: Add `cancelChat(sessionId:)` to `MonadClient`
- [ ] Task: Write failing integration tests for API cancellation in `ChatControllerStreamingTests`
- [ ] Task: Implement minimal fix to pass tests
- [ ] Task: Conductor - User Manual Verification 'API Implementation' (Protocol in workflow.md)

## Phase 3: CLI Integration
- [ ] Task: Implement "Double Escape" detection in `ChatREPL`
    - [ ] Update input loop to monitor for specific key sequences during active streaming
- [ ] Task: Implement `cancelCurrentGeneration()` in `ChatREPL`
    - [ ] Call `client.cancelChat()` and cancel local streaming task
- [ ] Task: Add `/cancel` slash command as a fallback
- [ ] Task: Update CLI output to handle and display `generationCancelled` event
- [ ] Task: Conductor - User Manual Verification 'CLI Integration' (Protocol in workflow.md)
