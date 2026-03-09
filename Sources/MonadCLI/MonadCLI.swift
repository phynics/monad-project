import ArgumentParser
import Foundation
import MonadClient
import MonadShared
import Logging

@main
struct MonadCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "monad",
        abstract: "Monad AI Assistant CLI",
        discussion: """
        An interactive AI assistant for your terminal.

        COMMANDS:
          chat                          Start an interactive REPL (Default)
          status                        Show server and component status

        INTERACTIVE COMMANDS (Slash commands):
          /help                         Show available commands
          /status                       Show server status
          /config                       View/edit configuration
          /debug                        Show rendered prompt & raw output
          /quit                         Exit (or :q)

          TIMELINE & WORKSPACE:
          /new                          Start a new timeline
          /timeline info/list/switch    Manage chat timelines
          /workspace all/list/attach    Manage workspaces
          /workspace attach-pwd         Attach current local directory

          FILES & CONTEXT:
          /ls, /cat, /write, /edit      Explore & modify workspace files
          /memory list/add/search       Manage timeline memories
          /job list/add                 Track tasks for the assistant
        """,
        version: "1.0.0",
        subcommands: [Chat.self, Status.self, Query.self, Command.self],
        defaultSubcommand: Chat.self
    )
}

struct Chat: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Start an interactive chat timeline (Default)"
    )

    @Option(name: .long, help: "Server URL (defaults to auto-discovery or localhost)")
    var server: String?

    @Option(name: .long, help: "API key for authentication")
    var apiKey: String?

    @Flag(name: .long, help: "Enable verbose debug logging")
    var verbose: Bool = false

    @Option(name: .shortAndLong, help: "Timeline ID to resume")
    var timeline: String?

    func run() async throws {
        // Initialize Logging
        LoggingSystem.bootstrap { label in
            var handler = MonadLogHandler(label: label)
            handler.logLevel = verbose ? .debug : .info
            return handler
        }

        // Load local config
        let localConfig = LocalConfigManager.shared.getConfig()

        // Determine explicit URL (Flag > Local Config)
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

        var client = MonadClient(configuration: config)

        // Check server health
        do {
            guard try await client.healthCheck() else {
                throw MonadClientError.serverNotReachable
            }
        } catch {
            print("")
            TerminalUI.printError(
                "Could not connect to Monad Server at \(config.baseURL.absoluteString)"
            )
            print("")
            print("  \(TerminalUI.bold("Troubleshooting:"))")
            print("  1. Ensure the server is running:")
            print("     \(TerminalUI.dim("make run-server"))")
            print("  2. Check if the server is running on a different port")
            print("  3. Verify your configuration with --server <url>")
            print("")

            if verbose {
                print("  \(TerminalUI.dim("Error: \(error.localizedDescription)"))")
                print("")
            }
            throw ExitCode.failure
        }

        // Register this client (idempotent — reuses stored identity on re-runs) and recreate the
        // client with the resolved clientId so it's included in every chat request, allowing the
        // server to look up and include client-side tools (e.g. ask_attach_pwd).
        do {
            let identity = try await RegistrationManager.shared.ensureRegistered(client: client)
            let configWithId = ClientConfiguration(
                baseURL: config.baseURL,
                apiKey: config.apiKey,
                clientId: identity.clientId,
                timeout: config.timeout,
                verbose: config.verbose
            )
            client = MonadClient(configuration: configWithId)
        } catch {
            Logger.module(named: "registration").warning("Client registration failed: \(error.localizedDescription)")
            TerminalUI.printWarning("Client registration failed. Some client-side tools may not be available.")
        }

        // Save successful configuration
        LocalConfigManager.shared.updateServerURL(config.baseURL.absoluteString)

        // Check configuration validity
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

        // Resulting timeline to use
        let cliTimelineManager = CLITimelineManager(client: client)
        let finalTimeline = try await cliTimelineManager.resolveTimeline(
            explicitId: timeline,
            localConfig: localConfig
        )

        // Persist successful timeline ID and handle re-attachment
        LocalConfigManager.shared.updateLastSessionId(finalTimeline.id.uuidString)
        await cliTimelineManager.handleWorkspaceReattachment(
            timeline: finalTimeline, localConfig: localConfig
        )

        TerminalUI.printWelcome()

        // Restore last agent instance if available; fall back to auto-creating a default one
        // so there is always an agent attached before entering the REPL.
        var restoredAgent: AgentInstance?
        let logger = Logger.module(named: "startup")

        if let agentIdStr = localConfig.lastAgentInstanceId,
           let agentId = UUID(uuidString: agentIdStr)
        {
            do {
                restoredAgent = try await client.chat.getAgentInstance(id: agentId)
            } catch {
                logger.warning("Failed to restore last agent (\(agentId)): \(error.localizedDescription)")
            }
        }

        if restoredAgent == nil {
            do {
                restoredAgent = try await ensureDefaultAgent(client: client, timelineId: finalTimeline.id)
            } catch {
                logger.error("Failed to ensure default agent: \(error.localizedDescription)")
                TerminalUI.printWarning("Could not attach an agent to the timeline. AI responses may fail until an agent is attached.")
            }
        }

        // Start REPL
        let repl = ChatREPL(client: client, timeline: finalTimeline, agent: restoredAgent)
        try await repl.run()
    }
}

// MARK: - Helpers

/// Returns an agent instance suitable for the given timeline, creating one if none exist.
/// The agent is attached to the timeline before returning.
private func ensureDefaultAgent(client: MonadClient, timelineId: UUID) async throws -> AgentInstance {
    let agents = try await client.chat.listAgentInstances()
    let agent: AgentInstance
    if let existing = agents.first {
        agent = existing
    } else {
        agent = try await client.chat.createAgentInstance(name: "Assistant", description: "")
    }
    try await client.chat.attachAgent(agentId: agent.id, to: timelineId)
    return agent
}
