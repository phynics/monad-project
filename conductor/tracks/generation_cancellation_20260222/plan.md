# Implementation Plan: Generation Cancellation

## Phase 1: Core Logic & Shared Models [checkpoint: 4df5c4a]
- [x] Task: Add `generationCancelled` event type to `StreamEventType` in `MonadShared` (6d83916)
- [x] Task: Implement Task Registry in `SessionManager` (b887131)
    - [x] Add `activeTasks: [UUID: Task<Void, Never>]` to `SessionManager` actor
    - [x] Implement `registerTask(_:for:)` and `cancelGeneration(for:)` methods
- [x] Task: Update `ChatEngine` to handle cancellation (bdeb1c0)
    - [x] Check `Task.isCancelled` in `runChatLoop` and `processTurn`
    - [x] Yield `.generationCancelled()` to the stream when cancelled
- [x] Task: Conductor - User Manual Verification 'Core Logic & Shared Models' (Protocol in workflow.md)

## Phase 2: API Implementation [checkpoint: 4df5c4a]
- [x] Task: Update `ChatAPIController` (bdeb1c0)
    - [x] Implement `POST /api/sessions/{id}/chat/cancel` endpoint
    - [x] Update `chatStream` to register the generation task with `SessionManager`
    - [x] Update SSE loop to catch `CancellationError` and yield `generationCancelled` event
- [x] Task: Add `cancelChat(sessionId:)` to `MonadClient` (bdeb1c0)
- [x] Task: Write failing integration tests for API cancellation in `ChatControllerStreamingTests` (bdeb1c0)
- [x] Task: Implement minimal fix to pass tests (bdeb1c0)
- [x] Task: Conductor - User Manual Verification 'API Implementation' (Protocol in workflow.md)

## Phase 3: CLI Integration [checkpoint: e55c159]
- [x] Task: Implement "Double Escape" detection in `ChatREPL` (e55c159)
    - [x] Update input loop to monitor for specific key sequences during active streaming
- [x] Task: Implement `cancelCurrentGeneration()` in `ChatREPL` (e55c159)
    - [x] Call `client.cancelChat()` and cancel local streaming task
- [x] Task: Add `/cancel` slash command as a fallback (e55c159)
- [x] Task: Update CLI output to handle and display `generationCancelled` event (e55c159)
- [x] Task: Conductor - User Manual Verification 'CLI Integration' (Protocol in workflow.md)
