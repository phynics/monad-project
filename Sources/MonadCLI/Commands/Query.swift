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

        let support = CLICommandSupport(server: server, apiKey: apiKey, verbose: verbose)
        let client = try await support.buildClient()
        let targetTimeline = try await support.resolveTimeline(client: client, explicitTimelineID: timeline)

        // Stream the response
        let stream = try await client.chat.execute(timelineId: targetTimeline.id, message: questionText)

        for try await delta in stream {
            if let content = delta.textContent {
                print(content, terminator: "")
                fflush(stdout)
            }
        }
        print("")
    }
}
