import ArgumentParser
import Foundation
import MonadClient

struct MemoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memory",
        abstract: "Manage memories",
        subcommands: [List.self, Search.self, Show.self, Delete.self]
    )

    // MARK: - List

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all memories"
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .shortAndLong, help: "Maximum number of memories to show")
        var limit: Int?

        func run() async throws {
            let client = MonadClient(configuration: globals.configuration)

            do {
                var memories = try await client.listMemories()

                if let limit = limit {
                    memories = Array(memories.prefix(limit))
                }

                if memories.isEmpty {
                    TerminalUI.printInfo("No memories found.")
                    return
                }

                print("")
                print(TerminalUI.bold("Memories:"))
                print("")

                for memory in memories {
                    let preview = String(memory.content.prefix(60)).replacingOccurrences(
                        of: "\n", with: " ")
                    let tags =
                        memory.tags.isEmpty ? "" : " [\(memory.tags.joined(separator: ", "))]"
                    print(
                        "  \(TerminalUI.dim(memory.id.uuidString.prefix(8).description))  \(preview)...\(TerminalUI.dim(tags))"
                    )
                }
                print("")
            } catch {
                TerminalUI.printError("Failed to list memories: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }

    // MARK: - Search

    struct Search: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Search memories"
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Search query")
        var query: String

        @Option(name: .shortAndLong, help: "Maximum number of results")
        var limit: Int = 10

        func run() async throws {
            let client = MonadClient(configuration: globals.configuration)

            do {
                let memories = try await client.searchMemories(query, limit: limit)

                if memories.isEmpty {
                    TerminalUI.printInfo("No memories found matching '\(query)'.")
                    return
                }

                print("")
                print(TerminalUI.bold("Search Results:"))
                print("")

                for memory in memories {
                    print("  \(TerminalUI.dim(memory.id.uuidString.prefix(8).description))")
                    print("  \(memory.content)")
                    if !memory.tags.isEmpty {
                        print("  \(TerminalUI.dim("Tags: \(memory.tags.joined(separator: ", "))"))")
                    }
                    print("")
                }
            } catch {
                TerminalUI.printError("Failed to search memories: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }

    // MARK: - Show

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show memory details"
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Memory ID")
        var memoryId: String

        func run() async throws {
            // For now, list memories and find the one matching
            guard let uuid = UUID(uuidString: memoryId) else {
                TerminalUI.printError("Invalid memory ID: \(memoryId)")
                throw ExitCode.failure
            }

            let client = MonadClient(configuration: globals.configuration)

            do {
                let memories = try await client.listMemories()

                guard let memory = memories.first(where: { $0.id == uuid }) else {
                    TerminalUI.printError("Memory not found: \(memoryId)")
                    throw ExitCode.failure
                }

                print("")
                print(TerminalUI.bold("Memory \(memory.id.uuidString.prefix(8))"))
                print("")
                print(memory.content)
                print("")
                if !memory.tags.isEmpty {
                    print(TerminalUI.dim("Tags: \(memory.tags.joined(separator: ", "))"))
                }
                print(TerminalUI.dim("Created: \(TerminalUI.formatDate(memory.createdAt))"))
                print("")
            } catch {
                TerminalUI.printError("Failed to show memory: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }

    // MARK: - Delete

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a memory"
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Memory ID")
        var memoryId: String

        @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
        var force: Bool = false

        func run() async throws {
            guard let uuid = UUID(uuidString: memoryId) else {
                TerminalUI.printError("Invalid memory ID: \(memoryId)")
                throw ExitCode.failure
            }

            if !force {
                print("Are you sure you want to delete memory \(memoryId)? [y/N] ", terminator: "")
                guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
                    print("Cancelled.")
                    return
                }
            }

            let client = MonadClient(configuration: globals.configuration)

            do {
                try await client.deleteMemory(uuid)
                print("Deleted memory: \(memoryId)")
            } catch {
                TerminalUI.printError("Failed to delete memory: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}
