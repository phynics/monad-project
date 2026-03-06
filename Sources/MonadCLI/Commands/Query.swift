import ArgumentParser
import Foundation
import MonadClient

#if canImport(Darwin)
    import Darwin
#endif

/// Quick one-shot query subcommand: `monad q what is the capital of France`
struct Query: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "q",
        abstract: "Quick one-shot query without entering REPL"
    )

    @Option(name: .long, help: "Server URL (defaults to auto-discovery or localhost)")
    var server: String?

    @Option(name: .long, help: "API key for authentication")
    var apiKey: String?

    @Flag(name: .long, help: "Enable verbose debug logging")
    var verbose: Bool = false

    @Option(name: .shortAndLong, help: "Timeline ID to use")
    var timeline: String?

    @Argument(parsing: .remaining, help: "The question to ask")
    var question: [String]

    func run() async throws {
        let questionText = question.joined(separator: " ")
        guard !questionText.isEmpty else {
            print("Usage: monad q <question>")
            print("Example: monad q what is the capital of France")
            throw ExitCode.failure
        }

        // Load local config
        let localConfig = LocalConfigManager.shared.getConfig()

        // Determine explicit URL
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
        do {
            guard try await client.healthCheck() else {
                throw MonadClientError.serverNotReachable
            }
        } catch {
            TerminalUI.printError(
                "Could not connect to Monad Server at \(config.baseURL.absoluteString)")
            throw ExitCode.failure
        }

        // Resolve timeline
        let targetTimeline: Timeline
        if let timelineId = timeline, let uuid = UUID(uuidString: timelineId) {
            let timelines = try await client.chat.listTimelines()
            guard let found = timelines.first(where: { $0.id == uuid }) else {
                TerminalUI.printError("Timeline not found: \(timelineId)")
                throw ExitCode.failure
            }
            targetTimeline = found
        } else if let lastId = localConfig.lastSessionId, let uuid = UUID(uuidString: lastId) {
            let timelines = try await client.chat.listTimelines()
            if let found = timelines.first(where: { $0.id == uuid }) {
                targetTimeline = found
            } else {
                targetTimeline = try await client.chat.createTimeline()
            }
        } else {
            targetTimeline = try await client.chat.createTimeline()
        }

        // Stream the response
        let stream = try await client.chat.chatStream(timelineId: targetTimeline.id, message: questionText)

        for try await delta in stream {
            if let content = delta.textContent {
                print(content, terminator: "")
                fflush(stdout)
            }
        }
        print("")
    }
}
