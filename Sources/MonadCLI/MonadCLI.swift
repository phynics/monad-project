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
        let cliSessionManager = CLISessionManager(client: client)
        let finalSession = try await cliSessionManager.resolveSession(
            explicitId: session,
            persona: persona,
            localConfig: localConfig
        )

        // 3. Persist successful session ID and handle re-attachment
        LocalConfigManager.shared.updateLastSessionId(finalSession.id.uuidString)
        await cliSessionManager.handleWorkspaceReattachment(session: finalSession, localConfig: localConfig)

        TerminalUI.printWelcome()

        // Start REPL
        let repl = ChatREPL(client: client, session: finalSession)
        try await repl.run()
    }
}
