import ArgumentParser
import Foundation
import Logging
import MonadClient
import MonadShared

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
        initializeLogging()

        let buildResult = try await buildAndVerifyClient()
        var client = buildResult.client
        client = await registerClient(client, config: buildResult.config)

        // Save successful configuration
        LocalConfigManager.shared.updateServerURL(buildResult.config.baseURL.absoluteString)

        try await validateConfiguration(client: client)

        let finalTimeline = try await resolveAndPersistTimeline(client: client)

        let restoredAgent = await restoreOrCreateAgent(client: client, timelineId: finalTimeline.id)

        TerminalUI.printWelcome()

        // Start REPL
        let repl = ChatREPL(client: client, timeline: finalTimeline, agent: restoredAgent)
        try await repl.run()
    }

    // MARK: - Setup Phases

    private func initializeLogging() {
        LoggingSystem.bootstrap { label in
            var handler = MonadLogHandler(label: label)
            handler.logLevel = verbose ? .debug : .info
            return handler
        }
    }

    private func buildAndVerifyClient() async throws -> (client: MonadClient, config: ClientConfiguration) {
        let localConfig = LocalConfigManager.shared.getConfig()

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

        do {
            guard try await client.healthCheck() else {
                throw MonadClientError.serverNotReachable
            }
        } catch {
            printConnectionError(baseURL: config.baseURL, error: error)
            throw ExitCode.failure
        }

        return (client, config)
    }

    private func printConnectionError(baseURL: URL, error: Error) {
        print("")
        TerminalUI.printError(
            "Could not connect to Monad Server at \(baseURL.absoluteString)"
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
    }

    private func registerClient(_ client: MonadClient, config: ClientConfiguration) async -> MonadClient {
        do {
            let identity = try await RegistrationManager.shared.ensureRegistered(client: client)
            let configWithId = ClientConfiguration(
                baseURL: config.baseURL,
                apiKey: config.apiKey,
                clientId: identity.clientId,
                timeout: config.timeout,
                verbose: config.verbose
            )
            return MonadClient(configuration: configWithId)
        } catch {
            Logger.module(named: "registration").warning(
                "Client registration failed: \(error.localizedDescription)"
            )
            TerminalUI.printWarning(
                "Client registration failed. Some client-side tools may not be available."
            )
            return client
        }
    }

    private func validateConfiguration(client: MonadClient) async throws {
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
    }

    private func resolveAndPersistTimeline(client: MonadClient) async throws -> Timeline {
        let localConfig = LocalConfigManager.shared.getConfig()
        let cliTimelineManager = CLITimelineManager(client: client)
        let finalTimeline = try await cliTimelineManager.resolveTimeline(
            explicitId: timeline,
            localConfig: localConfig
        )

        LocalConfigManager.shared.updateLastSessionId(finalTimeline.id.uuidString)
        await cliTimelineManager.handleWorkspaceReattachment(
            timeline: finalTimeline, localConfig: localConfig
        )

        return finalTimeline
    }

    private func restoreOrCreateAgent(client: MonadClient, timelineId: UUID) async -> AgentInstance? {
        let localConfig = LocalConfigManager.shared.getConfig()
        let logger = Logger.module(named: "startup")
        var restoredAgent: AgentInstance?

        if let agentIdStr = localConfig.lastAgentInstanceId,
           let agentId = UUID(uuidString: agentIdStr) {
            do {
                restoredAgent = try await client.chat.getAgentInstance(id: agentId)
            } catch {
                logger.warning("Failed to restore last agent (\(agentId)): \(error.localizedDescription)")
            }
        }

        if restoredAgent == nil {
            do {
                restoredAgent = try await ensureDefaultAgent(client: client, timelineId: timelineId)
            } catch {
                logger.error("Failed to ensure default agent: \(error.localizedDescription)")
                TerminalUI.printWarning(
                    "Could not attach an agent to the timeline. AI responses may fail until an agent is attached."
                )
            }
        }

        return restoredAgent
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
