import Foundation
import MonadClient

struct MemoryCommand: SlashCommand {
    let name = "memory"
    let aliases = ["memories"]
    let description = "Manage memories"
    let category: String? = "Data Management"
    let usage = "/memory [list|search] <query>"

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.first ?? "list"
        switch subcommand {
        case "list", "ls":
            try await listMemories(context: context)
        case "search":
            if args.count > 1 {
                try await searchMemories(args.dropFirst().joined(separator: " "), context: context)
            } else {
                TerminalUI.printError("Usage: /memory search <query>")
            }
        case "view":
            if args.count > 1 {
                try await viewMemory(args[1], context: context)
            } else {
                TerminalUI.printError("Usage: /memory view <id>")
            }
        default:
            try await listMemories(context: context)
        }
    }

    private func viewMemory(_ idPrefix: String, context: ChatContext) async throws {
        let memories = try await context.client.listMemories()

        let matches = memories.filter {
            $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased())
        }

        if matches.isEmpty {
            TerminalUI.printError("No memory found with ID starting with '\(idPrefix)'")
            return
        }

        if matches.count > 1 {
            TerminalUI.printWarning("Multiple memories match '\(idPrefix)':")
            for m in matches.prefix(5) {
                print("  \(m.id.uuidString.prefix(8)) - \(String(m.content.prefix(30)))...")
            }
            return
        }

        let memory = matches[0]

        print("")
        print(TerminalUI.bold("Memory Details:"))
        print(TerminalUI.dim("ID: \(memory.id.uuidString)"))
        print(TerminalUI.dim("Created: \(TerminalUI.formatDate(memory.createdAt))"))
        if !memory.tagArray.isEmpty {
            print(TerminalUI.dim("Tags: \(memory.tagArray.joined(separator: ", "))"))
        }
        print("")
        print(memory.content)
        print("")
    }

    private func listMemories(context: ChatContext) async throws {
        let memories = try await context.client.listMemories()
        let config = try await context.client.getConfiguration()
        let activeLimit = config.memoryContextLimit

        if memories.isEmpty {
            TerminalUI.printInfo("No memories found.")
            return
        }

        print("\n\(TerminalUI.bold("Memories:"))")
        print(
            TerminalUI.dim("(\(min(memories.count, activeLimit)) active / \(memories.count) total)")
        )
        print("")

        for (index, memory) in memories.prefix(20).enumerated() {
            let isActive = index < activeLimit
            let status = isActive ? TerminalUI.green("●") : TerminalUI.dim("○")
            let dateStr = TerminalUI.formatDate(memory.createdAt)
            let preview = String(memory.content.prefix(50)).replacingOccurrences(
                of: "\n", with: " ")

            print(
                "  \(status) \(TerminalUI.dim(memory.id.uuidString.prefix(8).description))  \(preview)\(memory.content.count > 50 ? "..." : "")  \(TerminalUI.dim(dateStr))"
            )
        }

        if memories.count > 20 {
            print("  \(TerminalUI.dim("... and \(memories.count - 20) more"))")
        }
        print("")
    }

    private func searchMemories(_ query: String, context: ChatContext) async throws {
        let memories = try await context.client.searchMemories(query, limit: 10)

        if memories.isEmpty {
            TerminalUI.printInfo("No memories found matching: \(query)")
            return
        }

        print("\n\(TerminalUI.bold("Search Results:"))\n")

        for memory in memories {
            print(
                "  \(TerminalUI.bold(String(memory.content.prefix(60))))\(memory.content.count > 60 ? "..." : "")"
            )
            if !memory.tagArray.isEmpty {
                print("  \(TerminalUI.dim("Tags: \(memory.tagArray.joined(separator: ", "))"))")
            }
            print("")
        }
    }
}
