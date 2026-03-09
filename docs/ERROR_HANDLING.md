# Error Handling

Monad uses a structured error handling approach based on the `ErrorKit` library. This ensures that errors are traceable, informative for developers, and user-friendly for end-users.

---

## The `Throwable` Protocol

All major error types in the system conform to the `Throwable` protocol (defined in `ErrorKit`). This protocol extends the standard Swift `Error` and `LocalizedError` protocols with additional requirements for user-facing communication.

### Protocol Definition

```swift
public protocol Throwable: Error, LocalizedError, Sendable {
    /// Technical description for logs and debugging (inherited from LocalizedError)
    var errorDescription: String? { get }

    /// A clear, actionable message suitable for display to the end-user
    var userFriendlyMessage: String { get }

    /// (Optional) Suggested steps to resolve the error
    var remediation: String? { get }
}
```

---

## Error Tiers

Errors are categorized by the module that defines them, allowing for clear provenance during debugging.

### 1. MonadClient Errors (`MonadClientError`)
Located in: `Sources/MonadClient/ClientModels.swift`

Handles networking, HTTP status codes, and server reachability issues.
- **Example**: `.serverNotReachable` -> "The Monad server is not reachable. Please ensure it is running."

### 2. MonadCore Errors
Located throughout `Sources/MonadCore/`

Domain-specific errors for the engine's subsystems:
- `TimelineError`: Issues with session lifecycle.
- `WorkspaceError`: Permission denials, path jailing, or connection failures to client-side workspaces.
- `ToolExecutorError`: Missing tool definitions or execution failures.
- `ContextManagerError`: Failures in RAG, semantic search, or memory retrieval.
- `EmbeddingError`: Issues generating vector embeddings.
- `AgentInstanceError`: Errors related to agent creation and attachment.

### 3. MonadServer Errors
Located in `Sources/MonadServer/`

Infrastructure and persistence errors:
- `RPCError`: Timeouts and connection losses during remote tool execution.
- `DatabaseManagerError`: System-level database initialization failures.
- `PersistenceError`: Inconsistent data formats in the database.

---

## Best Practices

### 1. Use the Logger
Always log the full technical error before presenting it to the user.

```swift
do {
    try await performOperation()
} catch {
    logger.error("Operation failed: \(error)")
    TerminalUI.printError(error.localizedDescription)
}
```

### 2. Provide Granular Recovery
In the CLI and Server, catch errors at the finest grain possible to allow partial success. For example, if one workspace fails to re-attach, log it and continue with the others.

### 3. Leverage User-Friendly Messages
When building UI components, prefer `userFriendlyMessage` over `localizedDescription` for a more polished experience.

---

## Tracing

By using `ErrorKit`, Monad supports future integration with distributed tracing systems. Each `Throwable` can carry context that helps identify exactly where in the pipeline an error originated.
