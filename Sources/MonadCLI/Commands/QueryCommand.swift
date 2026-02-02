import ArgumentParser
import Foundation
import MonadClient

struct QueryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Quick one-shot query to the AI",
        discussion: """
            Send a query and get a response without entering interactive mode.

            EXAMPLES:
              monad query "what is the weather like?"
              monad query --single "explain this error"
              monad query --new "start fresh with this question"
            """
    )

    @Option(name: .long, help: "Server URL")
    var server: String = "http://127.0.0.1:8080"

    @Option(name: .long, help: "API key for authentication")
    var apiKey: String?

    @Flag(name: .long, help: "Enable verbose debug logging")
    var verbose: Bool = false

    @Option(name: .shortAndLong, help: "Session ID to use")
    var session: String?

    @Flag(name: .long, help: "Create a new session (detach from current)")
    var new: Bool = false

    @Flag(name: .long, help: "Single query without persisting to any session")
    var single: Bool = false

    @Argument(parsing: .captureForPassthrough, help: "The query to send")
    var queryParts: [String] = []

    var configuration: ClientConfiguration {
        ClientConfiguration(
            baseURL: URL(string: server) ?? URL(string: "http://127.0.0.1:8080")!,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["MONAD_API_KEY"],
            verbose: verbose
        )
    }

    func run() async throws {
        let query = queryParts.joined(separator: " ")

        guard !query.isEmpty else {
            TerminalUI.printError("Please provide a query")
            print("Usage: monad query \"your question here\"")
            throw ExitCode.failure
        }

        let client = MonadClient(configuration: configuration)

        // Check server health
        guard try await client.healthCheck() else {
            TerminalUI.printError("Cannot connect to server at \(server)")
            throw ExitCode.failure
        }

        // Determine session handling
        let sessionId = try await resolveSession(client: client)

        // Send query and stream response
        print("")

        do {
            let stream = try await client.chatStream(sessionId: sessionId, message: query)

            for try await delta in stream {
                if let content = delta.content {
                    print(content, terminator: "")
                    fflush(stdout)
                }
            }

            print("\n")
        } catch let error as MonadClientError {
            switch error {
            case .unauthorized:
                TerminalUI.printError("Authentication failed")
                print(
                    "  Hint: Check your API key in /config (for Provider) or MONAD_API_KEY (for Server)"
                )
            case .serverNotReachable, .networkError:
                TerminalUI.printError("Cannot reach server")
                print("  Hint: Ensure the server is running with 'make run-server'")
            case .notFound:
                TerminalUI.printError("Session not found")
                // Allow recovery? Maybe resolveSession should handle this earlier, but if it happens mid-stream...
                print("  Hint: Use --new to create a fresh session")
            default:
                TerminalUI.printError(error.localizedDescription)
            }
            throw ExitCode.failure
        } catch {
            TerminalUI.printError("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    // MARK: - Session Management

    private func resolveSession(client: MonadClient) async throws -> UUID {
        // 1. Explicit flags take precedence
        if single {
            return try await client.createSession().id
        }
        if new {
            let session = try await client.createSession()
            saveCurrentSession(session.id)
            TerminalUI.printInfo("Created new session \(session.id.uuidString.prefix(8))")
            return session.id
        }

        // 2. Try specified session
        if let sessionString = session, let uuid = UUID(uuidString: sessionString) {
            do {
                _ = try await client.getHistory(sessionId: uuid)
                return uuid
            } catch {
                TerminalUI.printWarning("Specified session \(uuid.uuidString.prefix(8)) not found.")
                // Fallthrough to interactive selection
            }
        }

        // 3. Try persisted session
        if let savedUUID = loadCurrentSession() {
            do {
                _ = try await client.getHistory(sessionId: savedUUID)
                print(TerminalUI.dim("Using session \(savedUUID.uuidString.prefix(8))..."))
                return savedUUID
            } catch {
                // Saved session invalid or not found, fallthrough to selection
            }
        }

        // 4. No valid session context -> Interactive selection
        return try await interactiveSessionSelection(client: client)
    }

    private func interactiveSessionSelection(client: MonadClient) async throws -> UUID {
        print("")
        TerminalUI.printInfo("No active session found. Choose an option:")
        print("  1. Create new session (default)")
        print("  2. Select from recent sessions")
        print("  3. Temporary session (one-off)")
        print("")
        print("Choice [1]: ", terminator: "")

        // Simple readLine; if nil (e.g. piped input), default to new session
        let choice = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""

        switch choice {
        case "2":
            return try await selectExistingSession(client: client)
        case "3":
            return try await client.createSession().id
        default:
            let session = try await client.createSession()
            saveCurrentSession(session.id)
            TerminalUI.printInfo("Created session \(session.id.uuidString.prefix(8))")
            return session.id
        }
    }

    private func selectExistingSession(client: MonadClient) async throws -> UUID {
        let sessions = try await client.listSessions()
        guard !sessions.isEmpty else {
            TerminalUI.printWarning("No existing sessions found.")
            let session = try await client.createSession()
            saveCurrentSession(session.id)
            return session.id
        }

        print("")
        print(TerminalUI.bold("Recent Sessions:"))
        // Sort by update time descending
        let sorted = sessions.sorted { $0.updatedAt > $1.updatedAt }

        for (i, s) in sorted.prefix(5).enumerated() {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            let dateStr = dateFormatter.string(from: s.updatedAt)

            let title = s.title ?? "Untitled Session"
            let idPrefix = s.id.uuidString.prefix(8)
            print("  \(i+1). \(title) (\(idPrefix)) - \(dateStr)")
        }
        print("")
        print("Select session (1-\(min(sorted.count, 5))): ", terminator: "")

        if let input = readLine(), let index = Int(input),
            index > 0 && index <= min(sorted.count, 5)
        {
            let session = sorted[index - 1]
            saveCurrentSession(session.id)
            print(TerminalUI.dim("Attached to session \(session.id.uuidString.prefix(8))"))
            return session.id
        }

        TerminalUI.printWarning("Invalid selection. Creating new session.")
        let session = try await client.createSession()
        saveCurrentSession(session.id)
        return session.id
    }

    // MARK: - Session Persistence

    private func sessionFilePath() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".monad_session")
    }

    private func loadCurrentSession() -> UUID? {
        let path = sessionFilePath()
        guard let data = try? Data(contentsOf: path),
            let string = String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines),
            let uuid = UUID(uuidString: string)
        else {
            return nil
        }
        return uuid
    }

    private func saveCurrentSession(_ id: UUID) {
        let path = sessionFilePath()
        try? id.uuidString.write(to: path, atomically: true, encoding: .utf8)
    }
}
