import Foundation
@testable import MonadCLI
import Testing

/// Tests for `SlashCommandRegistry` — command lookup, alias resolution, and deduplication.
@Suite struct SlashCommandParsingTests {
    // MARK: - Stub command for testing

    private struct StubCommand: SlashCommand {
        let name: String
        let aliases: [String]
        let description: String
        var usage: String {
            "/\(name)"
        }

        var category: String? {
            nil
        }

        func run(args _: [String], context _: ChatContext) async throws {}
    }

    // MARK: - Registration

    @Test("Registered command is retrievable by its name")
    func register_commandRetrievableByName() async {
        let registry = SlashCommandRegistry()
        let cmd = StubCommand(name: "quit", aliases: [], description: "Quit the REPL")
        await registry.register(cmd)

        let found = await registry.getCommand("quit")
        #expect(found?.name == "quit")
    }

    @Test("Registered command is retrievable by its alias")
    func register_commandRetrievableByAlias() async {
        let registry = SlashCommandRegistry()
        let cmd = StubCommand(name: "quit", aliases: ["exit", "bye"], description: "Quit")
        await registry.register(cmd)

        let foundByAlias = await registry.getCommand("exit")
        #expect(foundByAlias?.name == "quit")

        let foundBySecondAlias = await registry.getCommand("bye")
        #expect(foundBySecondAlias?.name == "quit")
    }

    @Test("Multiple commands can be registered without conflict")
    func register_multipleCommandsCoexist() async {
        let registry = SlashCommandRegistry()
        await registry.register(StubCommand(name: "help", aliases: [], description: "Help"))
        await registry.register(StubCommand(name: "quit", aliases: [], description: "Quit"))
        await registry.register(StubCommand(name: "status", aliases: [], description: "Status"))

        #expect(await registry.getCommand("help")?.name == "help")
        #expect(await registry.getCommand("quit")?.name == "quit")
        #expect(await registry.getCommand("status")?.name == "status")
    }

    // MARK: - Lookup normalization

    @Test("getCommand is case-insensitive")
    func getCommand_caseInsensitive() async {
        let registry = SlashCommandRegistry()
        await registry.register(StubCommand(name: "help", aliases: [], description: "Help"))

        #expect(await registry.getCommand("HELP")?.name == "help")
        #expect(await registry.getCommand("Help")?.name == "help")
        #expect(await registry.getCommand("hElP")?.name == "help")
    }

    @Test("getCommand strips leading slash")
    func getCommand_stripsLeadingSlash() async {
        let registry = SlashCommandRegistry()
        await registry.register(StubCommand(name: "ls", aliases: [], description: "List files"))

        #expect(await registry.getCommand("/ls")?.name == "ls")
        #expect(await registry.getCommand("ls")?.name == "ls")
    }

    @Test("getCommand returns nil for unknown command")
    func getCommand_unknown_returnsNil() async {
        let registry = SlashCommandRegistry()
        let found = await registry.getCommand("nonexistent")
        #expect(found == nil)
    }

    @Test("getCommand returns nil for empty registry")
    func getCommand_emptyRegistry_returnsNil() async {
        let registry = SlashCommandRegistry()
        #expect(await registry.getCommand("anything") == nil)
    }

    // MARK: - allCommands deduplication

    @Test("allCommands returns unique commands without alias duplicates")
    func allCommands_deduplicated() async {
        let registry = SlashCommandRegistry()
        let cmd = StubCommand(name: "quit", aliases: ["exit", "q"], description: "Quit")
        await registry.register(cmd)

        let all = await registry.allCommands
        let quitCount = all.filter { $0.name == "quit" }.count
        #expect(quitCount == 1, "Should not include aliases as separate entries")
    }

    @Test("allCommands returns all registered commands sorted by name")
    func allCommands_sortedByName() async {
        let registry = SlashCommandRegistry()
        await registry.register(StubCommand(name: "status", aliases: [], description: ""))
        await registry.register(StubCommand(name: "help", aliases: [], description: ""))
        await registry.register(StubCommand(name: "cancel", aliases: [], description: ""))

        let all = await registry.allCommands
        let names = all.map { $0.name }
        #expect(names == names.sorted())
    }

    @Test("allCommands count matches number of registered commands")
    func allCommands_correctCount() async {
        let registry = SlashCommandRegistry()
        for index in 1 ... 5 {
            await registry.register(StubCommand(name: "cmd\(index)", aliases: [], description: ""))
        }

        let all = await registry.allCommands
        #expect(all.count == 5)
    }

    // MARK: - Overwrite behavior

    @Test("Registering a command with the same name overwrites the previous one")
    func register_overwritesSameName() async {
        let registry = SlashCommandRegistry()
        await registry.register(StubCommand(name: "help", aliases: [], description: "Old help"))
        await registry.register(StubCommand(name: "help", aliases: [], description: "New help"))

        let found = await registry.getCommand("help")
        #expect(found?.description == "New help")
    }
}
