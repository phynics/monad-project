import ArgumentParser
import Foundation
import MonadClient

@main
struct MonadCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "monad",
        abstract: "Monad AI Assistant CLI",
        version: "1.0.0",
        subcommands: [
            ChatCommand.self,
            SessionCommand.self,
            MemoryCommand.self,
            NoteCommand.self,
            ToolCommand.self,
        ],
        defaultSubcommand: ChatCommand.self
    )
}

// MARK: - Shared Options

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Server URL")
    var server: String = "http://127.0.0.1:8080"

    @Option(name: .long, help: "API key for authentication")
    var apiKey: String?

    var configuration: ClientConfiguration {
        ClientConfiguration(
            baseURL: URL(string: server) ?? URL(string: "http://127.0.0.1:8080")!,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["MONAD_API_KEY"]
        )
    }
}
