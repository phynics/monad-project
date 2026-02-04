import ArgumentParser
import Foundation
import MonadClient

@main
struct MonadCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "monad",
        abstract: "Monad AI Assistant CLI",
        discussion: """
            An interactive AI assistant for your terminal.

            MODES:
              monad                         Start interactive chat (default)
              monad query "question"        Quick one-shot query
              monad command "task"          Generate shell commands

            INTERACTIVE COMMANDS:
              /help                         Show available commands
              /config                       View/edit configuration
              /sessions, /memories, /notes  Manage data
              /quit                         Exit

            ENVIRONMENT VARIABLES:
              MONAD_API_KEY                 API key for authentication
              MONAD_SERVER_URL              Server URL (default: http://127.0.0.1:8080)
            """,
        version: "1.0.0",
        subcommands: [
            ChatSubcommand.self,
            QueryCommand.self,
            ShellCommand.self,
            WorkspaceCommand.self,
            PruneCommand.self,
        ],
        defaultSubcommand: ChatSubcommand.self,
        helpNames: [.short, .long]
    )
}

// MARK: - Chat Subcommand (Default)

struct ChatSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Start interactive chat session"
    )

    @Option(name: .long, help: "Server URL (defaults to auto-discovery or localhost)")
    var server: String?

    @Option(name: .long, help: "API key for authentication")
    var apiKey: String?

    @Flag(name: .long, help: "Enable verbose debug logging")
    var verbose: Bool = false

    @Option(name: .shortAndLong, help: "Session ID to resume")
    var session: String?

    @Option(name: .long, help: "Persona to use for new session")
    var persona: String?

    func run() async throws {
        // Load local config
        let localConfig = LocalConfigManager.shared.getConfig()

        // Determine explicit URL (Flag > Local Config)
        // We do NOT use Env var here because ClientConfiguration.autoDetect handles it,
        // but autoDetect prefers explicitURL over Env.
        // So we should only pass localConfig if flag is missing.

        let explicitURL: URL?
        if let serverFlag = server {
            explicitURL = URL(string: serverFlag)
        } else {
            explicitURL = localConfig.serverURL.flatMap { URL(string: $0) }
        }

        let config = await ClientConfiguration.autoDetect(
            explicitURL: explicitURL,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["MONAD_API_KEY"]
                ?? localConfig.apiKey,
            verbose: verbose
        )

        let client = MonadClient(configuration: config)

        // Check server health
        guard try await client.healthCheck() else {
            // If we used a cached config and it failed, maybe we should try discovery?
            // For now, just report error.
            TerminalUI.printError("Cannot connect to server at \(config.baseURL.absoluteString)")
            throw ExitCode.failure
        }

        // Save successful configuration
        LocalConfigManager.shared.updateServerURL(config.baseURL.absoluteString)

        // Check configuration
        do {
            let config = try await client.getConfiguration()
            if !config.isValid {
                let screen = ConfigurationScreen(client: client)
                try await screen.show()
            }
        } catch {
            TerminalUI.printWarning("Configuration check failed: \(error.localizedDescription)")
            TerminalUI.printInfo("You can configure the CLI using the '/config' command in chat.")
        }

        // Resulting session to use
        var sessionToUse: Session?

        // 1. Try to resume from flag or config
        var targetSessionId = session.flatMap { UUID(uuidString: $0) }

        // If no flag, check config
        if targetSessionId == nil, let lastId = localConfig.lastSessionId,
            let uuid = UUID(uuidString: lastId)
        {
            targetSessionId = uuid
        }

        if let uuid = targetSessionId {
            do {
                _ = try await client.getHistory(sessionId: uuid)
                sessionToUse = Session(id: uuid, title: nil)
                TerminalUI.printInfo("Resumed session \(uuid.uuidString.prefix(8))")
            } catch {
                TerminalUI.printWarning(
                    "Could not resume session \(uuid.uuidString.prefix(8)): \(error.localizedDescription)"
                )
                // If this was from config, it might be stale.
                if uuid.uuidString == localConfig.lastSessionId {
                    // Update config to remove stale? For now just ignore.
                }
            }
        }

        // 2. Fallback to interactive menu if no session resolved
        if sessionToUse == nil {
            print("")
            print(TerminalUI.bold("No active session found."))
            print("  [1] Create New Session")
            print("  [2] List Existing Sessions")
            print("")
            print("Select an option [1]: ", terminator: "")

            let choice = readLine()?.trimmingCharacters(in: .whitespaces) ?? "1"

            if choice == "2" {
                // List sessions
                do {
                    let sessions = try await client.listSessions()
                    if sessions.isEmpty {
                        print("No sessions found. Creating new one.")
                        sessionToUse = try await client.createSession(persona: persona)
                    } else {
                        print("")
                        for (i, s) in sessions.enumerated() {
                            let title = s.title ?? "Untitled"
                            let date = TerminalUI.formatDate(s.updatedAt)
                            print("  [\(i+1)] \(title) (\(s.id.uuidString.prefix(8))) - \(date)")
                        }
                        print("")
                        print("Select a session [1]: ", terminator: "")
                        let indexStr = readLine()?.trimmingCharacters(in: .whitespaces) ?? "1"
                        let index = (Int(indexStr) ?? 1) - 1

                        if index >= 0 && index < sessions.count {
                            // Convert SessionResponse to Session
                            let s = sessions[index]
                            sessionToUse = Session(id: s.id, title: s.title)
                        } else {
                            TerminalUI.printError("Invalid selection.")
                            throw ExitCode.failure
                        }
                    }
                } catch {
                    TerminalUI.printError("Failed to list sessions: \(error.localizedDescription)")
                    throw ExitCode.failure
                }
            } else {
                // Default to new session
                do {
                    sessionToUse = try await client.createSession(persona: persona)
                    TerminalUI.printInfo(
                        "Created new session \(sessionToUse!.id.uuidString.prefix(8))")
                } catch {
                    TerminalUI.printError("Failed to create session: \(error.localizedDescription)")
                    // Fallback for offline/error state just to enter loop?
                    // If server is down, we probably failed healthCheck already.
                    // But if create fails... provide dummy?
                    sessionToUse = Session(id: UUID(), title: "Offline Session")
                }
            }
        }

        guard let finalSession = sessionToUse else {
            throw ExitCode.failure
        }

        // 3. Persist successful session ID
        LocalConfigManager.shared.updateLastSessionId(finalSession.id.uuidString)

        TerminalUI.printWelcome()

        // Start REPL
        let repl = ChatREPL(client: client, session: finalSession)
        try await repl.run()
    }
}
