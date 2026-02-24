# Specification: Generation Cancellation (Feature)

## Overview
This feature allows users to explicitly terminate an ongoing LLM generation turn. It provides both a programmatic way (REST API) and a manual way (CLI interaction) to stop the assistant when it is producing unwanted or excessively long output.

## Functional Requirements

### 1. Backend (Server/Core)
- **Task Tracking**: The `SessionManager` must maintain a registry of active generation `Task`s for each session.
- **Cancel Endpoint**: Implement a `POST /api/sessions/{id}/chat/cancel` endpoint that:
    - Identifies the active task for the given session ID.
    - Triggers cancellation on that specific task.
    - Returns a `200 OK` status upon successful signal delivery.
- **Graceful Termination**: The `ChatEngine` and `ChatAPIController` must detect task cancellation (e.g., via `Task.isCancelled` or `CancellationError`) and:
    - Stop the LLM stream.
    - Yield a final `generationCancelled` event to the SSE stream.
    - Clean up resources associated with that specific turn.

### 2. Frontend (CLI)
- **Input Monitoring**: While a generation is active, the CLI must listen for a "Double Escape" sequence (pressing the `Escape` key twice within a short interval).
- **Cancellation Trigger**: Upon detecting the trigger, the CLI should:
    - Send a request to the server's cancel endpoint.
    - Locally cancel the streaming response task.
- **User Feedback**: Display a warning-colored message `[Generation cancelled]` to indicate the turn has been stopped.

## Acceptance Criteria
- [ ] Programmatic cancellation via `POST /api/sessions/{id}/chat/cancel` immediately stops the streaming response.
- [ ] Pressing `Escape` twice in the CLI during generation stops the output and displays feedback.
- [ ] Server-side tasks are correctly cancelled and do not continue to consume LLM tokens or processing time.
- [ ] Multiple concurrent sessions can be cancelled independently without affecting each other.

## Out of Scope
- Cancelling asynchronous background jobs (only interactive chat turns are covered).
- Reverting/Deleting partial messages already persisted to the database before the cancellation signal was received.
