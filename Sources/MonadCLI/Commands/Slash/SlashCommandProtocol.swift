import Foundation
import MonadClient

/// Protocol for a slash command in the chat REPL
protocol SlashCommand: Sendable {
    var name: String { get }
    var aliases: [String] { get }
    var description: String { get }
    var usage: String { get }
    var category: String? { get }

    func run(args: [String], context: ChatContext) async throws
}

extension SlashCommand {
    var aliases: [String] { [] }
    var usage: String { "/\(name)" }
    var category: String? { nil }
}

/// Context passed to slash commands
struct ChatContext {
    let client: MonadClient
    let session: Session
    let output: TerminalOutput
    let repl: ChatREPLController
}

/// Protocol to interact with the REPL state
protocol ChatREPLController: Sendable {
    func stop() async
    func switchSession(_ session: Session) async
    func setSelectedWorkspace(_ id: UUID?) async
    func getSelectedWorkspace() async -> UUID?
    func refreshContext() async
}

/// Registry for slash commands
public actor SlashCommandRegistry {
    private var commands: [String: SlashCommand] = [:]

    public init() {}

    func register(_ command: SlashCommand) {
        commands[command.name] = command
        for alias in command.aliases {
            commands[alias] = command
        }
    }

    func getCommand(_ name: String) -> SlashCommand? {
        // Handle case-insensitive and slash prefix
        let cleaned = name.lowercased().trimmingCharacters(in: ["/"])
        return commands[cleaned]
    }

    var allCommands: [SlashCommand] {
        // Return unique commands, sorted by name (deduplicate by name)
        var seen = Set<String>()
        var result: [SlashCommand] = []
        for cmd in commands.values {
            if !seen.contains(cmd.name) {
                seen.insert(cmd.name)
                result.append(cmd)
            }
        }
        return result.sorted { $0.name < $1.name }
    }
}

/// Abstraction for output to allow testing/mocking
protocol TerminalOutput: Sendable {
    func printsystem(_ text: String)
    func printError(_ text: String)
    func printSuccess(_ text: String)
    func printInfo(_ text: String)
}

struct StandardOutput: TerminalOutput {
    func printsystem(_ text: String) { TerminalUI.printInfo(text) }  // Mapping system to info/dim for now or create specific
    func printError(_ text: String) { TerminalUI.printError(text) }
    func printSuccess(_ text: String) { TerminalUI.printSuccess(text) }
    func printInfo(_ text: String) { TerminalUI.printInfo(text) }
}
