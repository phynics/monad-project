# Monad (Conductor)

A headless AI assistant built for deep context integration, focusing on how data and documents integrate with Large Language Models through a server/CLI architecture.

## Project Overview

*   **Language:** Swift 6.0
*   **Platform:** macOS 15+
*   **Architecture:**
    *   **MonadCore:** Pure logic framework. Handles session management, context engine, persistence (GRDB/SQLite), and tool execution.
    *   **MonadPrompt:** A standalone, type-safe DSL for constructing LLM prompts using Swift result builders.
    *   **MonadServer:** REST API server built with Hummingbird, supporting streaming chat.
    *   **MonadClient:** HTTP client library for communicating with the server.
    *   **MonadCLI:** Command-line interface for interacting with the server.
*   **Key Technologies:**
    *   **Server Framework:** [Hummingbird](https://github.com/hummingbird-project/hummingbird)
    *   **Database:** [GRDB.swift](https://github.com/groue/GRDB.swift) (SQLite)
    *   **Prompting:** Custom `@ContextBuilder` DSL
    *   **AI:** [OpenAI Swift](https://github.com/MacPaw/OpenAI)
    *   **CLI:** [Swift Argument Parser](https://github.com/apple/swift-argument-parser)

## Building and Running

### Swift Package Manager (Standard)

*   **Build Project:**
    ```bash
    swift build
    ```
*   **Run Server:**
    ```bash
    swift run MonadServer
    ```
*   **Run CLI (Interactive Chat):**
    ```bash
    swift run MonadCLI chat
    ```
*   **Run Tests:**
    ```bash
    swift test
    ```

### Make Commands

The project includes a `Makefile` for convenience:

*   **Build:** `make build`
*   **Run Server:** `make run-server`
*   **Run CLI:** `make run-cli` (Interactive chat mode)
*   **Run Tests:** `make test`
*   **Clean:** `make clean`
*   **Lint:** `make lint` (Requires `swiftlint`)
*   **Install CLI:** `make install` (Installs `MonadCLI` to `/usr/local/bin/monad`)

### Xcode Development

To generate the Xcode project (requires `xcodegen`):

```bash
make generate
make open
```

## Development Conventions

*   **Concurrency:** use `AsyncThrowingStream` for processes that emit progress updates, rather than closure callbacks. This allows for cleaner `for try await` loops at the call site.

*   **Code Structure:**
    *   `Sources/`: Application source code.
    *   `Tests/`: Unit and integration tests.
*   **Formatting/Linting:** The project uses `swiftlint`. Run `make lint` to check for style violations.
*   **Environment:**
    *   `MONAD_API_KEY`: Set this environment variable for API access.
    *   `MONAD_VERBOSE`: Set to `true` for verbose logging.

## Developing New Features

### 1. Creating a New Tool (MonadCore)

Tools enable the LLM to interact with the outside world. To create a new tool, implement the `Tool` protocol in `Sources/MonadCore`.

```swift
import Foundation

public struct MyNewTool: Tool, Sendable {
    public let id = "my_new_tool"
    public let name = "My New Tool"
    public let description = "Performs a specific task useful to the user."
    public let requiresPermission = false

    // Define parameters using JSON Schema structure
    public var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "The search query"
                ],
                "limit": [
                    "type": "integer",
                    "description": "Max results to return"
                ]
            ],
            "required": ["query"]
        ]
    }

    public func canExecute() async -> Bool {
        return true
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let query = parameters["query"] as? String else {
            return .failure("Missing 'query' parameter")
        }
        
        // ... Perform logic ...
        let result = "Executed query: \(query)"
        
        return .success(result)
    }

    // Optional: Custom summarization for context compression
    public func summarize(parameters: [String: Any], result: ToolResult) -> String {
        return "[\(id)] → \(result.success ? "Success" : "Failed")"
    }
}
```

### 2. Adding a CLI Command (MonadCLI)

To add a new command to the CLI, create a struct conforming to `AsyncParsableCommand` in `Sources/MonadCLI/Commands`.

```swift
import ArgumentParser
import MonadClient

struct MyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "my-command",
        abstract: "Does something awesome"
    )

    @Argument(help: "Input value")
    var input: String

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() async throws {
        // Use MonadClient if you need to talk to the server
        let client = try MonadClient.autoDetect() 
        
        print("Running with input: \(input)")
        
        // ... implementation ...
    }
}
```
*Note: Remember to register the new command in `MonadCLI.swift`.*

### 3. Adding an API Endpoint (MonadServer)

Endpoints are handled by Controllers in `Sources/MonadServer/Controllers`.

```swift
import Hummingbird
import MonadCore

struct MyController<Context: RequestContext>: Sendable {
    
    // Add dependencies here (e.g. services)
    
    func addRoutes(to router: Router<Context>) {
        router.get("/my-endpoint", use: handleRequest)
    }
    
    @Sendable func handleRequest(_ request: Request, context: Context) async throws -> String {
        return "Hello from MyController!"
    }
}
```

