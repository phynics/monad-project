import ArgumentParser
import Foundation
import MonadClient

// Shared config options
struct PruneOptions: ParsableArguments {
    @Option(name: .long, help: "Server URL")
    var server: String = "http://127.0.0.1:8080"

    @Option(name: .long, help: "API key for authentication")
    var apiKey: String?

    @Flag(name: .long, help: "Enable verbose debug logging")
    var verbose: Bool = false

    func makeClient() -> MonadClient {
        let config = ClientConfiguration(
            baseURL: URL(string: server) ?? URL(string: "http://127.0.0.1:8080")!,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["MONAD_API_KEY"],
            verbose: verbose
        )
        return MonadClient(configuration: config)
    }
}

struct PruneCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "Prune (bulk delete) notes, memories, or sessions.",
        subcommands: [
            PruneMemories.self,
            PruneSessions.self,
        ]
    )
}

struct PruneMemories: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memories",
        abstract: "Delete memories matching a query"
    )

    @OptionGroup var options: PruneOptions

    @Argument(help: "Search query to match memories for deletion")
    var query: String

    @Flag(name: .shortAndLong, help: "Skip confirmation")
    var force: Bool = false

    func run() async throws {
        if !force {
            print("Are you sure you want to delete memories matching '\(query)'? (y/n)")
            guard let response = readLine(), response.lowercased() == "y" else {
                print("Aborted.")
                return
            }
        }

        let client = options.makeClient()
        let count = try await client.pruneMemories(query: query)
        print("Deleted \(count) memories.")
    }
}

struct PruneSessions: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sessions",
        abstract: "Delete sessions older than a number of days"
    )

    @OptionGroup var options: PruneOptions

    @Option(name: .long, help: "Delete sessions older than N days")
    var days: Int

    @Flag(name: .shortAndLong, help: "Skip confirmation")
    var force: Bool = false

    func run() async throws {
        if !force {
            print("Are you sure you want to delete sessions older than \(days) days? (y/n)")
            guard let response = readLine(), response.lowercased() == "y" else {
                print("Aborted.")
                return
            }
        }

        let client = options.makeClient()
        let count = try await client.pruneSessions(olderThanDays: days)
        print("Deleted \(count) sessions.")
    }
}
