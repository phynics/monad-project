@testable import monad
import MonadCLICore
import MonadServerCore
import Testing

@Suite struct MonadCommandTests {
    @Test("root command exposes the CLI and server subcommands")
    func rootCommandExposesExpectedSubcommands() {
        let subcommandNames = Monad.configuration.subcommands.map { $0.configuration.commandName }

        #expect(subcommandNames == ["chat", "server", "status", "query", "command"])
        #expect(Monad.configuration.defaultSubcommand == Chat.self)
    }

    @Test("server preserves its bind and logging flags")
    func serverPreservesExistingFlags() throws {
        let server = try Server.parse(["--hostname", "0.0.0.0", "--port", "3000", "--verbose"])

        #expect(server.hostname == "0.0.0.0")
        #expect(server.port == 3000)
        #expect(server.verbose)
    }
}
