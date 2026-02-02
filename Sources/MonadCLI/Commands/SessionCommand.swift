import ArgumentParser
import Foundation
import MonadClient

struct SessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Manage chat sessions",
        subcommands: [List.self, New.self, History.self, Delete.self]
    )

    // MARK: - List

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all sessions"
        )

        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let client = MonadClient(configuration: globals.configuration)

            do {
                let sessions = try await client.listSessions()

                if sessions.isEmpty {
                    TerminalUI.printInfo("No sessions found.")
                    return
                }

                print("")
                print(TerminalUI.bold("Sessions:"))
                print("")

                for session in sessions {
                    let title = session.title ?? "Untitled"
                    let dateStr = TerminalUI.formatDate(session.createdAt)
                    print(
                        "  \(TerminalUI.dim(session.id.uuidString.prefix(8).description))  \(title)  \(TerminalUI.dim(dateStr))"
                    )
                }
                print("")
            } catch {
                TerminalUI.printError("Failed to list sessions: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }

    // MARK: - New

    struct New: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new session"
        )

        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let client = MonadClient(configuration: globals.configuration)

            do {
                let session = try await client.createSession()
                print("Created session: \(session.id.uuidString)")
            } catch {
                TerminalUI.printError("Failed to create session: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }

    // MARK: - History

    struct History: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "View session history"
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(
            help: "Session ID (supports tab completion)",
            completion: .custom { _ in SessionCompletion.complete() })
        var sessionId: String

        func run() async throws {
            guard let uuid = UUID(uuidString: sessionId) else {
                TerminalUI.printError("Invalid session ID: \(sessionId)")
                throw ExitCode.failure
            }

            let client = MonadClient(configuration: globals.configuration)

            do {
                let messages = try await client.getHistory(sessionId: uuid)

                if messages.isEmpty {
                    TerminalUI.printInfo("No messages in this session.")
                    return
                }

                print("")
                for message in messages {
                    let roleLabel =
                        switch message.role {
                        case .user: TerminalUI.userColor("You")
                        case .assistant: TerminalUI.assistantColor("Assistant")
                        case .system: TerminalUI.systemColor("System")
                        case .tool: TerminalUI.toolColor("Tool")
                        }

                    print("\(roleLabel): \(message.content)")
                    print("")
                }
            } catch {
                TerminalUI.printError("Failed to fetch history: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }

    // MARK: - Delete

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a session"
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(
            help: "Session ID (supports tab completion)",
            completion: .custom { _ in SessionCompletion.complete() })
        var sessionId: String

        @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
        var force: Bool = false

        func run() async throws {
            guard let uuid = UUID(uuidString: sessionId) else {
                TerminalUI.printError("Invalid session ID: \(sessionId)")
                throw ExitCode.failure
            }

            if !force {
                print(
                    "Are you sure you want to delete session \(sessionId)? [y/N] ", terminator: "")
                guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
                    print("Cancelled.")
                    return
                }
            }

            let client = MonadClient(configuration: globals.configuration)

            do {
                try await client.deleteSession(uuid)
                print("Deleted session: \(sessionId)")
            } catch {
                TerminalUI.printError("Failed to delete session: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Session Completion

enum SessionCompletion {
    @Sendable
    static func complete() -> [String] {
        // Tab completion with async API is challenging in Swift 6 strict concurrency.
        // For now, return empty and let the user type the full ID.
        // A future enhancement could cache session IDs to a file.
        return []
    }
}
