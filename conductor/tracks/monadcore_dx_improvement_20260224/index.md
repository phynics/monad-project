# Track monadcore_dx_improvement_20260224 Context

- [Specification](./spec.md)
- [Implementation Plan](./plan.md)
- [Metadata](./metadata.json)

---

# MonadCore Developer Experience Improvement Plan

## Context

MonadCore is the core business logic library for Monad, used by MonadServer, MonadCLI, and MonadClient. Its current DX has several pain points:

- **God protocol**: `PersistenceServiceProtocol` has 40+ methods across 7 domains, making mocking painful (342-line mock) and protocol conformance heavy.
- **Stringly-typed tool APIs**: Tool parameters are `[String: Any]` with runtime casting — no compile-time safety.
- **Runtime `fatalError` traps**: Dependency keys crash at runtime if not configured, with no compile-time guidance.
- **Inconsistent testing**: Mixed XCTest/Swift Testing, no test data builders, large boilerplate per test.
- **Missing documentation**: No module-level docs, no architecture overview, incomplete DocC coverage.
- **Silent error swallowing**: ChatEngine catches and logs errors without surfacing them to callers.

This plan addresses all areas in 6 phases, ordered by impact and dependency.

---

## Phase 1: Split PersistenceServiceProtocol into Domain Protocols

**Why**: This is the single highest-impact change. Every mock, every test, every new feature pays the tax of this 78-method god protocol.

### 1.1 Define domain-specific protocols

**File**: `Sources/MonadCore/Services/Database/PersistenceServiceProtocol.swift`

Split into 7 focused protocols. Each protocol is independently conformable and mockable:

```swift
// Sources/MonadCore/Services/Database/MemoryStoreProtocol.swift
public protocol MemoryStoreProtocol: Sendable {
    func saveMemory(_ memory: Memory, policy: MemorySavePolicy) async throws -> UUID
    func fetchMemory(id: UUID) async throws -> Memory?
    func fetchAllMemories() async throws -> [Memory]
    func searchMemories(query: String) async throws -> [Memory]
    func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws -> [(memory: Memory, similarity: Double)]
    func searchMemories(matchingAnyTag tags: [String]) async throws -> [Memory]
    func deleteMemory(id: UUID) async throws
    func updateMemory(_ memory: Memory) async throws
    func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) async throws
    func vacuumMemories(threshold: Double) async throws -> Int
}

// Sources/MonadCore/Services/Database/MessageStoreProtocol.swift
public protocol MessageStoreProtocol: Sendable {
    func saveMessage(_ message: ConversationMessage) async throws
    func fetchMessages(for sessionId: UUID) async throws -> [ConversationMessage]
    func deleteMessages(for sessionId: UUID) async throws
}

// Sources/MonadCore/Services/Database/SessionStoreProtocol.swift  (the persistence one, not the existing SessionStore)
public protocol SessionPersistenceProtocol: Sendable {
    func saveSession(_ session: ConversationSession) async throws
    func fetchSession(id: UUID) async throws -> ConversationSession?
    func fetchAllSessions(includeArchived: Bool) async throws -> [ConversationSession]
    func deleteSession(id: UUID) async throws
}

// Sources/MonadCore/Services/Database/JobStoreProtocol.swift
public protocol JobStoreProtocol: Sendable {
    func saveJob(_ job: Job) async throws
    func fetchJob(id: UUID) async throws -> Job?
    func fetchAllJobs() async throws -> [Job]
    func fetchJobs(for sessionId: UUID) async throws -> [Job]
    func fetchPendingJobs(limit: Int) async throws -> [Job]
    func deleteJob(id: UUID) async throws
    func monitorJobs() async -> AsyncStream<JobEvent>
}

// Sources/MonadCore/Services/Database/AgentStoreProtocol.swift
public protocol AgentStoreProtocol: Sendable {
    func saveAgent(_ agent: Agent) async throws
    func fetchAgent(id: UUID) async throws -> Agent?
    func fetchAgent(key: String) async throws -> Agent?
    func fetchAllAgents() async throws -> [Agent]
    func hasAgent(id: String) async -> Bool
}

// Sources/MonadCore/Services/Database/WorkspacePersistenceProtocol.swift
public protocol WorkspacePersistenceProtocol: Sendable {
    func saveWorkspace(_ workspace: WorkspaceReference) async throws
    func fetchWorkspace(id: UUID) async throws -> WorkspaceReference?
    func fetchWorkspace(id: UUID, includeTools: Bool) async throws -> WorkspaceReference?
    func fetchAllWorkspaces() async throws -> [WorkspaceReference]
    func deleteWorkspace(id: UUID) async throws
}

// Sources/MonadCore/Services/Database/ClientStoreProtocol.swift
public protocol ClientStoreProtocol: Sendable {
    func saveClient(_ client: ClientIdentity) async throws
    func fetchClient(id: UUID) async throws -> ClientIdentity?
    func fetchAllClients() async throws -> [ClientIdentity]
    func deleteClient(id: UUID) async throws -> Bool
}
```

### 1.2 Redefine PersistenceServiceProtocol as composition

**File**: `Sources/MonadCore/Services/Database/PersistenceServiceProtocol.swift`

```swift
// Before (line 4):
public protocol PersistenceServiceProtocol: HealthCheckable {
    // ... 40+ methods ...
}

// After:
public protocol PersistenceServiceProtocol:
    MemoryStoreProtocol,
    MessageStoreProtocol,
    SessionPersistenceProtocol,
    JobStoreProtocol,
    AgentStoreProtocol,
    WorkspacePersistenceProtocol,
    ClientStoreProtocol,
    ToolPersistenceProtocol,
    HealthCheckable
{
    func resetDatabase() async throws
}
```

**Backward compatibility**: Existing code that depends on `PersistenceServiceProtocol` continues to work unchanged. The split only adds new capabilities — consumers can now depend on just `MemoryStoreProtocol` instead of the full protocol.

### 1.3 Update consumers to depend on narrow protocols

Each service should declare the narrowest dependency it needs:

| Consumer | Current | After |
|----------|---------|-------|
| `ContextManager` (line 8) | `PersistenceServiceProtocol` | `MemoryStoreProtocol & MessageStoreProtocol` |
| `SessionManager` (line 33) | `PersistenceServiceProtocol` | `SessionPersistenceProtocol & MessageStoreProtocol` |
| `WorkspaceStore` (line 5) | `PersistenceServiceProtocol` | `WorkspacePersistenceProtocol` |
| `SessionStore` | `PersistenceServiceProtocol` | `SessionPersistenceProtocol` |

**Files to update**:
- `Sources/MonadCore/Services/Context/ContextManager.swift` (lines 8, 24-25)
- `Sources/MonadCore/Services/Session/SessionManager.swift` (line 33)
- `Sources/MonadCore/Stores/WorkspaceStore.swift`
- `Sources/MonadCore/Stores/SessionStore.swift`

### 1.4 Split MockPersistenceService into domain mocks

**File**: `Sources/MonadCore/TestSupport/MockPersistenceService.swift` (342 lines → split)

Create focused mocks:

```swift
// Sources/MonadCore/TestSupport/MockMemoryStore.swift (~40 lines)
public final class MockMemoryStore: MemoryStoreProtocol, @unchecked Sendable {
    public var memories: [Memory] = []
    public var searchResults: [(memory: Memory, similarity: Double)] = []
    public init() {}
    // ... only memory methods ...
}

// Sources/MonadCore/TestSupport/MockMessageStore.swift (~15 lines)
// Sources/MonadCore/TestSupport/MockSessionPersistence.swift (~20 lines)
// Sources/MonadCore/TestSupport/MockJobStore.swift (~25 lines)
// etc.
```

Keep `MockPersistenceService` as a convenience that composes all domain mocks (or conforms to all sub-protocols). Tests that only need memory operations can use `MockMemoryStore` directly.

---

## Phase 2: Type-Safe Tool Parameter System

**Why**: Every tool currently hand-constructs `[String: Any]` schemas and casts parameters at runtime. This is error-prone and undiscoverable.

### 2.1 Add ToolParameterSchema builder

**New file**: `Sources/MonadCore/Models/Tools/ToolParameterSchema.swift`

```swift
/// Type-safe JSON Schema builder for tool parameters
public struct ToolParameterSchema: Sendable {
    public let schema: [String: Any]

    public static func object(_ build: (inout ObjectBuilder) -> Void) -> ToolParameterSchema {
        var builder = ObjectBuilder()
        build(&builder)
        return ToolParameterSchema(schema: builder.build())
    }

    public struct ObjectBuilder {
        private var properties: [String: [String: Any]] = [:]
        private var required: [String] = []

        public mutating func string(_ name: String, description: String, required isRequired: Bool = false) {
            properties[name] = ["type": "string", "description": description]
            if isRequired { required.append(name) }
        }

        public mutating func integer(_ name: String, description: String, required isRequired: Bool = false) {
            properties[name] = ["type": "integer", "description": description]
            if isRequired { required.append(name) }
        }

        public mutating func boolean(_ name: String, description: String, required isRequired: Bool = false) {
            properties[name] = ["type": "boolean", "description": description]
            if isRequired { required.append(name) }
        }

        public mutating func stringEnum(_ name: String, description: String, values: [String], required isRequired: Bool = false) {
            properties[name] = ["type": "string", "description": description, "enum": values]
            if isRequired { required.append(name) }
        }

        func build() -> [String: Any] {
            var result: [String: Any] = ["type": "object", "properties": properties]
            if !required.isEmpty { result["required"] = required }
            return result
        }
    }
}
```

### 2.2 Add type-safe parameter extraction

**New file**: `Sources/MonadCore/Models/Tools/ToolParameters.swift`

```swift
/// Type-safe wrapper around tool parameter dictionaries
public struct ToolParameters: Sendable {
    private let raw: [String: Any]

    public init(_ parameters: [String: Any]) { self.raw = parameters }

    public func require<T>(_ key: String, as type: T.Type = T.self) throws -> T {
        guard let value = raw[key] else {
            throw ToolError.missingArgument(key)
        }
        guard let typed = value as? T else {
            throw ToolError.invalidArgument(key, expected: String(describing: T.self), got: String(describing: Swift.type(of: value)))
        }
        return typed
    }

    public func optional<T>(_ key: String, as type: T.Type = T.self) -> T? {
        raw[key] as? T
    }
}
```

### 2.3 Migrate ReadFileTool as example (then all tools)

**File**: `Sources/MonadCore/Models/Tools/Filesystem/ReadFileTool.swift`

```swift
// Before (lines 34-53):
public var parametersSchema: [String: Any] {
    return [
        "type": "object",
        "properties": [
            "path": [
                "type": "string",
                "description": "The path to the file to read",
            ]
        ],
        "required": ["path"],
    ]
}

public func execute(parameters: [String: Any]) async throws -> ToolResult {
    guard let pathString = parameters["path"] as? String else {
        let errorMsg = "Missing required parameter: path."
        ...
    }

// After:
public var parametersSchema: [String: Any] {
    ToolParameterSchema.object { b in
        b.string("path", description: "The path to the file to read", required: true)
    }.schema
}

public func execute(parameters: [String: Any]) async throws -> ToolResult {
    let params = ToolParameters(parameters)
    let pathString = try params.require("path", as: String.self)
    ...
}
```

### 2.4 Add ToolError cases for better parameter validation

**File**: `Sources/MonadCore/Models/Tools/ToolError.swift`

```swift
// Add to existing enum (currently missing these specific cases):
case invalidArgument(String, expected: String, got: String)
// errorDescription: "Invalid argument '\(name)': expected \(expected), got \(got)"
```

---

## Phase 3: Dependency Safety — Replace fatalError with Compile-Time Guidance

**Why**: 8 dependency keys use `fatalError()` as default — developers discover misconfiguration only at runtime.

### 3.1 Add actionable error messages to all DependencyKeys

**Files**:
- `Sources/MonadCore/Dependencies/OrchestrationDependencies.swift` (lines 11-33)
- `Sources/MonadCore/Dependencies/StorageDependencies.swift` (lines 7-14)
- `Sources/MonadCore/Dependencies/LLMDependencies.swift`

```swift
// Before (OrchestrationDependencies.swift, line 11-14):
public enum SessionManagerKey: DependencyKey {
    public static let liveValue: SessionManager = {
        fatalError("SessionManager must be configured before use.")
    }()
}

// After:
public enum SessionManagerKey: DependencyKey {
    public static let liveValue: SessionManager = {
        fatalError("""
            SessionManager must be configured before use.

            Configure it in your app's entry point:
                withDependencies {
                    $0.sessionManager = SessionManager(workspaceRoot: myRoot)
                } operation: { ... }
            """)
    }()
}
```

### 3.2 Add a dependency validation helper

**New file**: `Sources/MonadCore/Dependencies/DependencyValidator.swift`

```swift
/// Validates that required dependencies are configured before use.
/// Call at app startup to get clear errors instead of runtime fatalError.
public struct DependencyValidator {
    /// Validates all required MonadCore dependencies are configured.
    /// Returns a list of missing dependency names, or empty if all OK.
    public static func validateRequired() -> [String] {
        var missing: [String] = []
        // Check each required dependency by attempting access in a safe context
        // This uses swift-dependencies' withDependencies to test without crashing
        // Implementation will test each key and collect names of unconfigured ones
        return missing
    }
}
```

---

## Phase 4: Testing Experience Improvements

**Why**: Tests have 10-25 lines of boilerplate per suite, no data builders, and mixed frameworks.

### 4.1 Add test data builders

**New file**: `Sources/MonadCore/TestSupport/TestFixtures.swift`

```swift
/// Convenience builders for test data with sensible defaults
public enum TestFixtures {

    public static func memory(
        id: UUID = UUID(),
        title: String = "Test Memory",
        content: String = "Test content",
        tags: [String] = [],
        embedding: [Double] = [0.1, 0.2, 0.3]
    ) -> Memory {
        Memory(id: id, title: title, content: content, tags: tags.joined(separator: ","), embedding: embedding.description)
    }

    public static func session(
        id: UUID = UUID(),
        title: String = "Test Session",
        isArchived: Bool = false
    ) -> ConversationSession {
        ConversationSession(id: id, title: title, isArchived: isArchived)
    }

    public static func message(
        id: UUID = UUID(),
        sessionId: UUID = UUID(),
        role: MessageRole = .user,
        content: String = "Test message"
    ) -> ConversationMessage {
        ConversationMessage(id: id, sessionId: sessionId, role: role, content: content)
    }

    public static func job(
        id: UUID = UUID(),
        sessionId: UUID = UUID(),
        status: JobStatus = .pending,
        priority: Int = 0
    ) -> Job {
        Job(id: id, sessionId: sessionId, status: status, priority: priority)
    }
}
```

### 4.2 Add stream collection test helper

**File**: `Sources/MonadCore/TestSupport/TestHelpers.swift` (currently 12 lines)

```swift
// Add to existing file:

/// Collect all elements from an AsyncThrowingStream into an array
public func collect<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> [T] {
    var results: [T] = []
    for try await element in stream {
        results.append(element)
    }
    return results
}

/// Collect elements from an AsyncThrowingStream with a timeout
public func collect<T>(_ stream: AsyncThrowingStream<T, Error>, timeout: Duration = .seconds(5)) async throws -> [T] {
    try await withThrowingTaskGroup(of: [T].self) { group in
        group.addTask {
            var results: [T] = []
            for try await element in stream {
                results.append(element)
            }
            return results
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw CancellationError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

### 4.3 Add dependency setup helper for tests

**File**: `Sources/MonadCore/TestSupport/TestHelpers.swift`

```swift
/// Run a test body with standard MonadCore mock dependencies configured
public func withMockDependencies<T>(
    configureMocks: ((MockMemoryStore, MockMessageStore, MockLLMService) -> Void)? = nil,
    body: @Sendable (MockMemoryStore, MockMessageStore, MockLLMService) async throws -> T
) async throws -> T {
    let memoryStore = MockMemoryStore()
    let messageStore = MockMessageStore()
    let mockLLM = MockLLMService()

    configureMocks?(memoryStore, messageStore, mockLLM)

    return try await withDependencies {
        $0.persistenceService = MockPersistenceService()  // full mock for backward compat
        $0.llmService = mockLLM
        $0.embeddingService = MockEmbeddingService()
    } operation: {
        try await body(memoryStore, messageStore, mockLLM)
    }
}
```

---

## Phase 5: Documentation

**Why**: No module-level documentation exists. Key types lack DocC. New developers have no architecture guide.

### 5.1 Add MonadCore module documentation

**New file**: `Sources/MonadCore/MonadCore.docc/MonadCore.md`

DocC landing page covering:
- Module purpose and scope
- Architecture overview (ChatEngine → SessionManager → ContextManager → LLMService)
- Dependency injection setup guide
- Quick start code example

### 5.2 Add DocC to undocumented public types

Priority types missing docs (add `///` comments with parameter descriptions):

| File | Type | Lines |
|------|------|-------|
| `Models/Tools/ToolError.swift` | `ToolError` enum + all cases | 5-32 |
| `Models/Tools/Tool.swift` | `ToolResult` struct | 151-166 |
| `Models/Configuration/Configuration.swift` | `LLMConfiguration` | all public properties |
| `Services/Database/PersistenceServiceProtocol.swift` | Each new sub-protocol | — |
| `Dependencies/OrchestrationDependencies.swift` | All `DependencyKey` enums | 7-33 |
| `Services/Context/ContextManager.swift` | `gatherContext` parameters | 41-46 (partial, needs enrichment) |

### 5.3 Add inline comments for complex logic

Priority locations:
- `ChatEngine.runChatLoop()` (lines 114-160): Document the event emission sequence and error handling strategy
- `ChatEngine.processTurn()` (lines 500-534): Document why tool errors are caught and continued
- `ContextManager.gatherContext()` (lines 80-99): Document the priority-based token budgeting flow

---

## Phase 6: Error Handling Improvements

**Why**: Errors are silently swallowed in ChatEngine's run loop, and error types lack remediation guidance.

### 6.1 Surface tool execution errors via ChatEvent

**File**: `Sources/MonadCore/Services/ChatEngine.swift`

Currently (lines 151-159), tool execution errors are logged but not emitted to the stream. Add a new `ChatEvent` case or use the existing error event to surface these:

```swift
// In the catch block of processTurn/tool execution:
// Before: just log
// After: emit a diagnostic event so callers can observe failures
continuation.yield(.toolExecutionError(toolId: call.id, error: error.localizedDescription))
```

This requires adding a case to `ChatEvent` if one doesn't exist for tool-level errors.

### 6.2 Add remediation hints to ToolError

**File**: `Sources/MonadCore/Models/Tools/ToolError.swift`

```swift
// Add a computed property:
public var remediation: String? {
    switch self {
    case .missingArgument(let name):
        return "Provide the '\(name)' parameter in the tool call arguments."
    case .toolNotFound(let id):
        return "Check available tools with the session's tool manager. Tool '\(id)' may not be registered."
    case .clientNotConnected:
        return "Ensure the client workspace is connected before executing remote tools."
    case .workspaceNotFound:
        return "Verify the workspace ID exists and is attached to the current session."
    default:
        return nil
    }
}
```

### 6.3 Add configuration validation errors

**File**: `Sources/MonadCore/Models/Configuration/Configuration.swift`

Replace the boolean `isValid` with a method that returns specific validation failures:

```swift
// Before (line ~251):
public var isValid: Bool { ... }

// After (keep isValid for backward compat, add):
public func validate() -> [ConfigurationError] {
    var errors: [ConfigurationError] = []
    if apiKey.isEmpty { errors.append(.missingAPIKey) }
    if model.isEmpty { errors.append(.missingModel) }
    return errors
}

public enum ConfigurationError: LocalizedError {
    case missingAPIKey
    case missingModel
    // ...
}
```

---

## Verification

After each phase, run:

```bash
swift build                          # Ensure no compilation errors
swift test                           # All existing tests pass
swift test --filter MonadCoreTests   # MonadCore-specific tests pass
```

Phase-specific checks:
- **Phase 1**: Verify `MockPersistenceService` still conforms to `PersistenceServiceProtocol`. Verify tests using domain-specific mocks compile and pass.
- **Phase 2**: Write a new test using `ToolParameterSchema` and `ToolParameters` to verify type-safe extraction.
- **Phase 3**: Verify `fatalError` messages include setup instructions. Test `DependencyValidator`.
- **Phase 4**: Rewrite one existing test (e.g., `ContextManagerTests`) to use `TestFixtures` and `withMockDependencies` — verify it's shorter and clearer.
- **Phase 5**: Run `swift package generate-documentation` if DocC plugin is available.
- **Phase 6**: Write a test that triggers a tool error and verify it appears in the `ChatEvent` stream.

---

## Files Modified/Created Summary

**New files** (11):
- `Sources/MonadCore/Services/Database/MemoryStoreProtocol.swift`
- `Sources/MonadCore/Services/Database/MessageStoreProtocol.swift`
- `Sources/MonadCore/Services/Database/SessionPersistenceProtocol.swift`
- `Sources/MonadCore/Services/Database/JobStoreProtocol.swift`
- `Sources/MonadCore/Services/Database/AgentStoreProtocol.swift`
- `Sources/MonadCore/Services/Database/WorkspacePersistenceProtocol.swift`
- `Sources/MonadCore/Services/Database/ClientStoreProtocol.swift`
- `Sources/MonadCore/Models/Tools/ToolParameterSchema.swift`
- `Sources/MonadCore/Models/Tools/ToolParameters.swift`
- `Sources/MonadCore/Dependencies/DependencyValidator.swift`
- `Sources/MonadCore/TestSupport/TestFixtures.swift`

**Modified files** (12+):
- `Sources/MonadCore/Services/Database/PersistenceServiceProtocol.swift` — redefine as composition
- `Sources/MonadCore/Services/Context/ContextManager.swift` — narrow dependency type
- `Sources/MonadCore/Services/Session/SessionManager.swift` — narrow dependency type
- `Sources/MonadCore/Stores/WorkspaceStore.swift` — narrow dependency type
- `Sources/MonadCore/Stores/SessionStore.swift` — narrow dependency type
- `Sources/MonadCore/TestSupport/MockPersistenceService.swift` — split into domain mocks
- `Sources/MonadCore/TestSupport/TestHelpers.swift` — add helpers
- `Sources/MonadCore/Dependencies/OrchestrationDependencies.swift` — improve error messages
- `Sources/MonadCore/Dependencies/StorageDependencies.swift` — improve error messages
- `Sources/MonadCore/Models/Tools/ToolError.swift` — add cases + remediation
- `Sources/MonadCore/Models/Tools/Filesystem/ReadFileTool.swift` — migrate to ToolParameterSchema
- `Sources/MonadCore/Services/ChatEngine.swift` — surface tool errors
- `Sources/MonadCore/Models/Configuration/Configuration.swift` — add validate()
- All other tool files — migrate to ToolParameterSchema (incremental)
