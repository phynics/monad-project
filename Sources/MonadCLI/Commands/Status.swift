import ArgumentParser
import ErrorKit
import Foundation
import MonadClient
import MonadShared
import PKShared

public struct Status: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show which server the client is configured to use, and whether it's reachable",
        discussion: """
        Reports, without starting or stopping anything:
          - the server URL the client would use for `monad chat`/`monad query`/`monad command`
          - whether that server responds to a health check
          - whether an API key is configured on the client side
          - whether the server's active LLM provider is configured and reachable

        This never starts a server. If nothing responds, start one yourself first:
          monad server
        """
    )

    @Option(name: .long, help: "Server URL to check (defaults to auto-detected/local config value)")
    var server: String?

    @Option(name: .long, help: "API key for authentication")
    var apiKey: String?

    @Flag(name: .long, help: "Enable verbose debug logging")
    var verbose: Bool = false

    public init() {}

    public func run() async throws {
        let localConfig = LocalConfigManager.shared.getConfig()

        let resolvedApiKey = apiKey ?? ProcessInfo.processInfo.environment["MONAD_API_KEY"] ?? localConfig.apiKey

        let config = await ClientConfiguration.autoDetect(
            explicitURL: CLICommandSupport.resolvedServerURL(serverFlag: server, localConfig: localConfig),
            apiKey: resolvedApiKey,
            verbose: verbose
        )

        let client = MonadClient(configuration: config)

        TerminalUI.printLoading("Checking Monad server at \(config.baseURL.absoluteString)...")

        let report = await Self.buildReport(
            client: client,
            serverURL: config.baseURL.absoluteString,
            apiKeyConfigured: (resolvedApiKey?.isEmpty == false)
        )

        print("")
        for line in StatusReportFormatter.format(report) {
            print(line)
        }
        print("")

        if case .unreachable = report.reachability {
            throw ExitCode.failure
        }
    }

    /// Fetches server status/configuration and assembles a `StatusReport`. Split out from
    /// `run()` so the pure formatting/classification logic in `StatusReportFormatter` and the
    /// `ConfigurationReadiness` classification below can be exercised independently of a live
    /// server (see `StatusReportTests`), while this method stays the thin part that talks to
    /// the network.
    static func buildReport(
        client: MonadClient,
        serverURL: String,
        apiKeyConfigured: Bool
    ) async -> StatusReport {
        let reachability: StatusReport.ServerReachability
        do {
            let status = try await client.getStatus()
            reachability = .reachable(status)
        } catch {
            reachability = .unreachable(message: ErrorKit.userFriendlyMessage(for: error))
        }

        let configurationReadiness: StatusReport.ConfigurationReadiness
        switch reachability {
        case .unreachable:
            configurationReadiness = .unknown(message: "server unreachable")
        case let .reachable(status):
            do {
                let llmConfig = try await client.getConfiguration()
                configurationReadiness = Self.classifyConfiguration(config: llmConfig, status: status)
            } catch {
                configurationReadiness = .unknown(message: ErrorKit.userFriendlyMessage(for: error))
            }
        }

        return StatusReport(
            serverURL: serverURL,
            apiKeyConfigured: apiKeyConfigured,
            reachability: reachability,
            configuration: configurationReadiness
        )
    }

    static func classifyConfiguration(
        config: LLMConfiguration,
        status: StatusResponse
    ) -> StatusReport.ConfigurationReadiness {
        guard config.isValid else {
            return .needsSetup(reason: "no valid provider configuration (missing model name or API key)")
        }

        let aiStatus = status.components["ai_provider"]?.status
        guard aiStatus == .ok else {
            return .needsSetup(reason: "provider \(config.activeProvider.rawValue) configured but not reachable")
        }

        return .ready
    }
}
