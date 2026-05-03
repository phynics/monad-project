import ArgumentParser
import Foundation
import MonadClient
import MonadShared

struct CLICommandSupport {
    let server: String?
    let apiKey: String?
    let verbose: Bool
    let localConfig: LocalConfig
    let reportError: @Sendable (String) -> Void

    init(
        server: String? = nil,
        apiKey: String? = nil,
        verbose: Bool = false,
        localConfig: LocalConfig = LocalConfigManager.shared.getConfig(),
        reportError: @escaping @Sendable (String) -> Void = TerminalUI.printError
    ) {
        self.server = server
        self.apiKey = apiKey
        self.verbose = verbose
        self.localConfig = localConfig
        self.reportError = reportError
    }

    static func resolvedServerURL(serverFlag: String?, localConfig: LocalConfig) -> URL? {
        if let serverFlag {
            return URL(string: serverFlag)
        }

        return localConfig.serverURL.flatMap(URL.init(string:))
    }

    func buildClient() async throws -> MonadClient {
        let config = await ClientConfiguration.autoDetect(
            explicitURL: Self.resolvedServerURL(serverFlag: server, localConfig: localConfig),
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["MONAD_API_KEY"] ?? localConfig.apiKey,
            verbose: verbose
        )

        let client = MonadClient(configuration: config)

        do {
            guard try await client.healthCheck() else {
                throw MonadClientError.serverNotReachable
            }
        } catch {
            reportError("Could not connect to Monad Server at \(config.baseURL.absoluteString)")
            throw ExitCode.failure
        }

        return client
    }

    func resolveTimeline(
        explicitTimelineID: String?,
        listTimelines: () async throws -> [TimelineResponse],
        createTimeline: () async throws -> TimelineResponse
    ) async throws -> TimelineResponse {
        if let explicitTimelineID, let uuid = UUID(uuidString: explicitTimelineID) {
            let timelines = try await listTimelines()
            guard let found = timelines.first(where: { $0.id == uuid }) else {
                reportError("Timeline not found: \(explicitTimelineID)")
                throw ExitCode.failure
            }
            return found
        }

        if let lastID = localConfig.lastSessionId, let uuid = UUID(uuidString: lastID) {
            let timelines = try await listTimelines()
            if let found = timelines.first(where: { $0.id == uuid }) {
                return found
            }
        }

        return try await createTimeline()
    }

    func resolveTimeline(client: MonadClient, explicitTimelineID: String?) async throws -> TimelineResponse {
        try await resolveTimeline(
            explicitTimelineID: explicitTimelineID,
            listTimelines: { try await client.chat.listTimelines() },
            createTimeline: { try await client.chat.createTimeline() }
        )
    }
}
