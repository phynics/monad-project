import ArgumentParser
import Foundation
import MonadClient

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Start an interactive chat session"
    )

    @OptionGroup var globals: GlobalOptions

    @Option(name: .shortAndLong, help: "Session ID to resume")
    var session: String?

    func run() async throws {
        let client = MonadClient(configuration: globals.configuration)

        // Check server health
        guard try await client.healthCheck() else {
            TerminalUI.printError("Cannot connect to server at \(globals.server)")
            throw ExitCode.failure
        }

        // Get or create session
        let currentSession: Session
        if let sessionId = session, let uuid = UUID(uuidString: sessionId) {
            // Resume existing session - fetch history to verify it exists
            do {
                _ = try await client.getHistory(sessionId: uuid)
                currentSession = Session(id: uuid, title: nil)
                TerminalUI.printInfo("Resuming session \(uuid.uuidString.prefix(8))...")
            } catch {
                TerminalUI.printError("Session not found: \(sessionId)")
                throw ExitCode.failure
            }
        } else {
            currentSession = try await client.createSession()
            TerminalUI.printInfo("Created new session \(currentSession.id.uuidString.prefix(8))...")
        }

        TerminalUI.printWelcome()

        // Start REPL
        let repl = ChatREPL(client: client, session: currentSession)
        try await repl.run()
    }
}

// MARK: - Chat REPL

actor ChatREPL {
    private let client: MonadClient
    private var session: Session
    private var running = true

    init(client: MonadClient, session: Session) {
        self.client = client
        self.session = session
    }

    func run() async throws {
        while running {
            // Read input with vi-style editing via readline
            guard let input = await readInput() else {
                continue
            }

            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                continue
            }

            // Handle slash commands
            if trimmed.hasPrefix("/") {
                await handleSlashCommand(trimmed)
                continue
            }

            // Send message
            await sendMessage(trimmed)
        }
    }

    private func readInput() async -> String? {
        TerminalUI.printPrompt()

        // Use readline for vi-style editing
        guard let line = readLine() else {
            running = false
            return nil
        }

        return line
    }

    private func handleSlashCommand(_ command: String) async {
        let parts = command.lowercased().split(separator: " ", maxSplits: 1)
        let cmd = String(parts[0])

        switch cmd {
        case "/help":
            printHelp()

        case "/new":
            await startNewSession()

        case "/history":
            await showHistory()

        case "/quit", "/q", "/exit":
            running = false
            TerminalUI.printInfo("Goodbye!")

        default:
            TerminalUI.printError("Unknown command: \(cmd). Type /help for available commands.")
        }
    }

    private func printHelp() {
        print(
            """

            \(TerminalUI.bold("Available Commands:"))
              /help      Show this help message
              /new       Start a new chat session
              /history   Show conversation history
              /quit      Exit the chat

            \(TerminalUI.bold("Tips:"))
              • Use vi-style editing (if terminal supports it)
              • Press Ctrl+C to cancel current generation
              • Press Ctrl+D to exit

            """)
    }

    private func startNewSession() async {
        do {
            session = try await client.createSession()
            TerminalUI.printInfo("Started new session \(session.id.uuidString.prefix(8))")
        } catch {
            TerminalUI.printError("Failed to create session: \(error.localizedDescription)")
        }
    }

    private func showHistory() async {
        do {
            let messages = try await client.getHistory(sessionId: session.id)

            if messages.isEmpty {
                TerminalUI.printInfo("No messages in this session yet.")
                return
            }

            print("")
            for message in messages {
                switch message.role {
                case .user:
                    print("\(TerminalUI.userColor("You:"))")
                    print(message.content)
                case .assistant:
                    print("\(TerminalUI.assistantColor("Assistant:"))")
                    print(message.content)
                case .system:
                    print("\(TerminalUI.systemColor("System:"))")
                    print(message.content)
                case .tool:
                    print("\(TerminalUI.toolColor("Tool:"))")
                    print(message.content)
                }
                print("")
            }
        } catch {
            TerminalUI.printError("Failed to fetch history: \(error.localizedDescription)")
        }
    }

    private func sendMessage(_ message: String) async {
        do {
            print("")
            TerminalUI.printAssistantStart()

            let stream = try await client.chatStream(sessionId: session.id, message: message)

            for try await delta in stream {
                if let content = delta.content {
                    print(content, terminator: "")
                    fflush(stdout)
                }
            }

            print("\n")
        } catch {
            print("")
            TerminalUI.printError("Error: \(error.localizedDescription)")
        }
    }
}
