# Development Guide

Comprehensive guide for developing with Monad.

## Table of Contents

- [Building and Running](#building-and-running)
- [Development Conventions](#development-conventions)
- [Creating New Features](#creating-new-features)
- [CLI Usage](#cli-usage)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Building and Running

### Swift Package Manager (Standard)

```bash
# Build all targets
swift build

# Release build
swift build -c release

# Run Server
swift run MonadServer

# Run CLI (Interactive Chat)
swift run MonadCLI chat

# Run Tests
swift test

# Run specific test suite
swift test --filter ChatEngineTests

# Run specific test
swift test --filter ChatEngineTests.testBasicChat
```

### Make Commands

The project includes a `Makefile` for convenience:

```bash
make build         # Build the server
make run-server    # Run the server
make run-cli       # Interactive chat mode
make test          # Run tests
make clean         # Clean build artifacts
make lint          # Run swiftlint
make install       # Install MonadCLI to /usr/local/bin/monad
```

### Xcode Development

To generate the Xcode project (requires `xcodegen`):

```bash
make generate      # Generate Xcode project
make open          # Open in Xcode
```

## Development Conventions

### Concurrency

#### AsyncThrowingStream for Streaming/Progress

Use `AsyncThrowingStream` for processes that emit progress updates, rather than closure callbacks.

```swift
// Good
func processData() -> AsyncThrowingStream<Progress, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            continuation.yield(.processing(percent: 50))
            continuation.yield(.complete(result))
            continuation.finish()
        }
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }
}

// Usage
for try await progress in processData() {
    print(progress)
}
```

**Examples in codebase:**
- `ChatEngine.chatStream()` → `AsyncThrowingStream<ChatEvent, Error>`
- `ContextManager.gatherContext()` → `AsyncThrowingStream<ContextGatheringEvent, Error>`

#### Actors for Thread Safety

Use actors for managing shared mutable state:

```swift
public actor SessionManager {
    internal var sessions: [UUID: Timeline] = [:]
    internal var contextManagers: [UUID: ContextManager] = [:]

    public func createSession(title: String) async throws -> Timeline {
        let session = Timeline(...)
        sessions[session.id] = session
        return session
    }
}
```

**Examples:** `SessionManager`, `ContextManager`, `ToolRouter`, `WorkspaceManager`

#### Locked for Fine-Grained Synchronization

For fine-grained locking, use `Locked<T>` (wraps Swift 6's `OSAllocatedUnfairLock`):

```swift
let counter = Locked(initialValue: 0)
counter.withLock { value in
    value += 1
}
```

**File:** `Sources/MonadCore/Utilities/Locked.swift`

### Graceful Shutdown

Any `Service` registered with `ServiceGroup` **must** wrap long-running work in `cancelWhenGracefulShutdown { ... }` from `ServiceLifecycle`.

**CRITICAL:** Do NOT rely on `Task.isCancelled` alone—it is only set *after* all services have returned from `run()`, which will deadlock if services are waiting for it.

```swift
import ServiceLifecycle

final class MyService: Service {
    func run() async throws {
        try? await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(1))
                // Do work
            }
        }
        // Cleanup
    }
}
```

**Reference Implementation:** `Sources/MonadServer/BonjourAdvertiser.swift`

### Dependency Injection

Uses Point-Free's `swift-dependencies`:

```swift
import Dependencies

@Dependency(\.sessionManager) private var sessionManager
@Dependency(\.llmService) private var llmService
@Dependency(\.persistenceService) private var persistenceService
```

**Registration:**

```swift
withDependencies {
    $0.sessionManager = mySessionManager
    $0.llmService = myLLMService
} operation: {
    // Use dependencies here
}
```

**Dependency Key Files:**
- `Sources/MonadCore/Dependencies/LLMDependencies.swift`
- `Sources/MonadCore/Dependencies/OrchestrationDependencies.swift`
- `Sources/MonadCore/Dependencies/StorageDependencies.swift`

### Logging

Use `Logger.module(named:)` throughout all targets. **Never** use `Logger(label: ...)` directly.

```swift
import Logging

private let logger = Logger.module(named: "ChatEngine")
logger.info("Processing message", metadata: ["sessionId": "\(sessionId)"])
```

**Extension:** `Sources/MonadCore/Utilities/Logger+Extensions.swift`

### Code Structure

- `Sources/`: Application source code organized by module
- `Tests/`: Unit and integration tests mirroring source structure
- Models organized into focused subdirectories (see AGENTS.md for layout)

### Formatting & Linting

The project uses `swiftlint`. Run `make lint` to check for style violations.

### Environment Variables

- `MONAD_API_KEY`: API key for LLM access
- `MONAD_VERBOSE`: Set to `true` for verbose logging

## Creating New Features

### Creating a Tool

Implement the `Tool` protocol in MonadCore.

```swift
import MonadCore
import Foundation

struct MyCustomTool: Tool {
    let id: String = "my_custom_tool"
    let name: String = "my_custom_tool"
    let description: String = "Does something useful"
    let requiresPermission: Bool = false

    var parametersSchema: [String: AnyCodable] {
        ToolParameterSchema.object {
            ToolParameterSchema.string(
                name: "input",
                description: "The input to process",
                required: true
            )
        }
    }

    func canExecute() async -> Bool {
        true
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let input = parameters["input"] as? String else {
            return ToolResult.failure("Missing 'input' parameter")
        }

        // Do something with input
        let result = "Processed: \(input)"

        return ToolResult.success(result)
    }

    func summarize(parameters: [String: Any], result: ToolResult) -> String {
        "Processed input successfully"
    }
}
```

**Reference:** `Sources/MonadCore/Models/Tools/Filesystem/ReadFileTool.swift`

**Key Points:**
- Use `ToolParameterSchema.object { ... }` builder for schemas
- Use `PathSanitizer.safelyResolve()` for secure path handling in filesystem tools
- Return `ToolResult.success(_)` or `ToolResult.failure(_)`
- Implement `canExecute()` for runtime availability checks

**Available System Tools:**
- **Filesystem (7):** `cd`, `find`, `inspect_file`, `ls`, `cat`, `grep`, `search_files`
- **Agent (2):** `LaunchSubagentTool`, `AgentAsTool`
- **System (2):** `system_memory_search`, `system_web_search`
- **Job Queue (1):** `JobQueueGatewayTool`
- **Client (1):** `AskAttachPWDTool`

### Adding an API Endpoint

Endpoints are handled by Controllers in `Sources/MonadServer/Controllers`.

```swift
import Hummingbird
import MonadCore

struct MyController<Context: RequestContext>: Sendable {
    // Add dependencies here
    let myService: MyService

    func addRoutes(to router: Router<Context>) {
        router.get("/my-endpoint", use: handleRequest)
        router.post("/my-endpoint", use: handlePost)
    }

    @Sendable
    func handleRequest(_ request: Request, context: Context) async throws -> Response {
        let data = MyResponseData(message: "Hello from MyController!")
        return try Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(data: JSONEncoder().encode(data))
        )
    }

    @Sendable
    func handlePost(_ request: Request, context: Context) async throws -> Response {
        let requestData = try await request.decode(as: MyRequestData.self, context: context)
        // Process request
        return try Response(status: .created)
    }
}
```

**API Contract Types:**
API types are split into category-specific files in `Sources/MonadShared/Models/`:
- `ChatAPI.swift` — Chat request/response, streaming deltas
- `ClientAPI.swift` — Client connection types
- `MemoryAPI.swift` — Memory CRUD types
- `SessionAPI.swift` — Session management types
- `WorkspaceAPI.swift` — Workspace types
- `ToolAPI.swift` — Tool-related types
- `CommonAPI.swift` — Shared types
- `SystemStatus.swift` — Health/status types

### Custom Prompts with MonadPrompt DSL

Use the `@ContextBuilder` DSL to construct type-safe, optimized prompts.

```swift
import MonadPrompt
import MonadCore

let prompt = Prompt {
    SystemSection(
        priority: 100,
        content: DefaultInstructions.system,
        strategy: .keep
    )

    // Prioritize critical context
    ContextNotesSection(
        priority: 90,
        notes: notes,
        strategy: .summarize
    )

    // Include relevant memories
    MemorySection(
        priority: 80,
        memories: memories,
        strategy: .truncate(tail: true)
    )

    // Dynamic tool inclusion
    if allowTools {
        ToolSection(
            priority: 70,
            tools: tools,
            strategy: .keep
        )
    }

    // Conversation history (truncated automatically)
    HistorySection(
        priority: 60,
        messages: history,
        strategy: .truncate(tail: false)
    )

    UserQuerySection(
        priority: 10,
        query: queryString,
        strategy: .keep
    )
}

let messages = prompt.buildMessages(budget: 8000)
```

**Compression Strategies:**
- `.keep` — Do not compress; drop if no budget
- `.truncate(tail: Bool)` — Clip text from start or end
- `.summarize` — Use smaller LLM to produce summary
- `.drop` — Drop section if budget exceeded

See **[docs/CONTEXT_SYSTEM.md](docs/CONTEXT_SYSTEM.md)** for details on token budgeting.

### Creating an Agent

Agents are defined as records in the database.

```swift
import MonadCore
import Foundation

let researcher = Agent(
    id: UUID(),
    name: "Research Agent",
    description: "Specializes in searching and summarizing information.",
    systemPrompt: """
    You are a Researcher. Your goal is to provide deep insights on any topic.
    Use the search tools extensively. Be thorough and cite sources.
    """,
    personaPrompt: "Analytical, curious, detail-oriented.",
    guardrails: "Do not fabricate sources. Always verify information."
)

// Persist the agent
try await persistenceService.saveAgent(researcher)
```

**Using Agents:**
- Launch via `LaunchSubagentTool`
- Wrap as callable tool via `AgentAsTool`
- Execute via `AgentExecutor`

See **[docs/guides/CORE_GUIDE.md](docs/guides/CORE_GUIDE.md)** for agent orchestration patterns.

## CLI Usage

The CLI provides a rich REPL with slash commands for administration and interaction.

### Common Slash Commands

**Chat Management:**
- `/help` — Show available commands
- `/quit` — Exit the CLI
- `/new` — Start a new session
- `/clear` — Clear screen

**Session Management:**
- `/session list` — List all sessions
- `/session switch <id>` — Switch to a session
- `/session new <title>` — Create new session
- `/session delete <id>` — Delete a session
- `/session rename <title>` — Rename current session
- `/session log` — View session message history

**Memory & Data:**
- `/memory search <query>` — Search memories
- `/memory all` — List all memories
- `/memory view <id>` — View specific memory
- `/prune` — Clean up old data

**Workspace Management:**
- `/workspace list` — List all workspaces
- `/workspace attach <path>` — Attach a directory
- `/workspace attach-pwd` — Attach current directory
- `/workspace detach <id>` — Detach workspace

**Jobs:**
- `/job list` — List background jobs
- `/job add <title>` — Create a job
- `/job delete <id>` — Delete a job

**File Operations:**
- `/ls [path]` — List directory contents
- `/cat <file>` — Read file contents
- `/write <file> <content>` — Write to file
- `/edit <file>` — Edit file
- `/rm <file>` — Remove file

**System:**
- `/debug` — View last prompt and LLM metadata
- `/config` — Edit server settings interactively
- `/status` — Server status
- `/tool` — List available tools
- `/client` — List connected clients

## Testing

### Running Tests

```bash
# All tests
swift test

# Specific module
swift test --filter MonadCoreTests

# Specific test suite
swift test --filter ChatEngineTests

# Specific test
swift test --filter ChatEngineTests.testBasicChat
```

### Mock Services

Mock services are available in `Sources/MonadCore/TestSupport/`:

```swift
import MonadCore
import XCTest

final class MyTests: XCTestCase {
    func testMyFeature() async throws {
        let mockLLM = MockLLMService()
        let mockPersistence = MockPersistenceService()

        let engine = ChatEngine(
            llmService: mockLLM,
            persistenceService: mockPersistence
        )

        // Test your feature
    }
}
```

**Available Mocks:**
- `MockLLMService` — Mock LLM provider
- `MockPersistenceService` — In-memory persistence (umbrella)
- `MockSessionPersistence`
- `MockMessageStore`
- `MockMemoryStore`
- `MockJobStore`
- `MockAgentStore`
- `MockWorkspacePersistence`
- `MockToolPersistence`
- `MockEmbeddingService` — Mock embeddings
- `MockConfigurationService` — Mock configuration
- `MockLocalWorkspace` — Mock workspace

### Server Testing

Server tests use `HummingbirdTesting`:

```swift
import HummingbirdTesting
import MonadServer

final class APITests: XCTestCase {
    func testEndpoint() async throws {
        let app = buildApplication()

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/status", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
            }
        }
    }
}
```

## Troubleshooting

### Common Issues

**Segmentation Faults:**
- Often caused by circular dependencies in `DependencyKey` definitions
- Check for actor reentrancy issues
- Verify all dependencies are properly configured

**Job Not Starting:**
- Ensure `JobRunnerService` is running
- Verify `agentId` in job matches a registered agent
- Check database for job status

**Missing Context:**
- Verify `ContextManager` is properly hydrated for the session
- Check `Notes/` directory exists in primary workspace
- Verify semantic search is working (embeddings generated)

**Tool Not Found:**
- Check tool is registered in `SessionToolManager`
- Verify workspace is attached and healthy
- Check tool provenance matches expected workspace

**Streaming Hangs:**
- Verify `StreamingParser` is handling all response types
- Check for unclosed `<think>` tags
- Verify LLM provider is responding

**Configuration Errors:**
- Run `try config.validate()` to check configuration
- Verify API key is set for non-Ollama providers
- Check endpoint URLs are valid HTTP/HTTPS

## Additional Resources

- **[AGENTS.md](AGENTS.md)** — Quick reference for AI assistants (symlinked as CLAUDE.md)
- **[docs/INDEX.md](docs/INDEX.md)** — Complete documentation index
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — System architecture
- **[docs/guides/CORE_GUIDE.md](docs/guides/CORE_GUIDE.md)** — Agent framework guide
- **[docs/API_REFERENCE.md](docs/API_REFERENCE.md)** — API endpoints reference
- **[docs/CONTEXT_SYSTEM.md](docs/CONTEXT_SYSTEM.md)** — Context assembly pipeline
- **[docs/workspaces_feature_overview.md](docs/workspaces_feature_overview.md)** — Workspace system
