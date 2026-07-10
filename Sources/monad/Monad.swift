import ArgumentParser
import MonadCLICore
import MonadServerCore

@main
struct Monad: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "monad",
        abstract: "Monad AI Assistant",
        subcommands: [Chat.self, Server.self, Status.self, Query.self, Command.self],
        defaultSubcommand: Chat.self
    )
}
