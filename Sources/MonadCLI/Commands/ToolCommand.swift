import ArgumentParser
import Foundation
import MonadClient

struct ToolCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tool",
        abstract: "Manage tools",
        subcommands: [List.self, Enable.self, Disable.self]
    )

    // MARK: - List

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List available tools"
        )

        @OptionGroup var globals: GlobalOptions

        func run() async throws {
            let client = MonadClient(configuration: globals.configuration)

            do {
                let tools = try await client.listTools()

                if tools.isEmpty {
                    TerminalUI.printInfo("No tools available.")
                    return
                }

                print("")
                print(TerminalUI.bold("Tools:"))
                print("")

                for tool in tools {
                    let status = tool.isEnabled ? TerminalUI.green("✓") : TerminalUI.dim("○")
                    print("  \(status) \(TerminalUI.bold(tool.name))")
                    print("    \(TerminalUI.dim(tool.description))")
                }
                print("")
            } catch {
                TerminalUI.printError("Failed to list tools: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }

    // MARK: - Enable

    struct Enable: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Enable a tool"
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Tool name")
        var name: String

        func run() async throws {
            let client = MonadClient(configuration: globals.configuration)

            do {
                try await client.enableTool(name)
                print("Enabled tool: \(name)")
            } catch {
                TerminalUI.printError("Failed to enable tool: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }

    // MARK: - Disable

    struct Disable: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Disable a tool"
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Tool name")
        var name: String

        func run() async throws {
            let client = MonadClient(configuration: globals.configuration)

            do {
                try await client.disableTool(name)
                print("Disabled tool: \(name)")
            } catch {
                TerminalUI.printError("Failed to disable tool: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}
