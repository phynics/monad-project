import Foundation
import MonadClient

struct MemoryCommand: SlashCommand {
    let name = "memory"
    let aliases = ["memories"]
    let description = "Manage memories"
    let category: String? = "Data Management"
    let usage = "/memory [all|list|search] <query>"

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.first

        // Default to active list if no args
        if subcommand == nil {
            try await listActive(context: context)
            return
        }

        switch subcommand {
        case "all":
            let screen = MemoryScreen(client: context.client)
            try await screen.show()
        case "list", "ls":
            // "list" can be ambiguous, let's make it show active too?
            // Or keep it as TUI? The user request said "info to direct user to /memory all".
            // Let's make "list" alias to active list for consistency with other commands perhaps?
            // Actually, keep "list" as TUI might be confusing if /memory listActive is default.
            // Let's make 'list' show active, and 'all' show TUI.
            try await listActive(context: context)
        case "search":
            if args.count > 1 {
                let query = args.dropFirst().joined(separator: " ")
                let screen = MemoryScreen(client: context.client)
                try await screen.show(initialQuery: query)
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
            // Fallback to active list
            try await listActive(context: context)
        }
    }

    private func listActive(context: ChatContext) async throws {
        let memories = try await context.client.listMemories()
        let config = try await context.client.getConfiguration()
        let limit = config.memoryContextLimit
        let activeMemories = Array(memories.prefix(limit))

        print(
            "\n\(TerminalUI.bold("Active Context Memories (\(activeMemories.count)/\(limit)):"))\n")

        if activeMemories.isEmpty {
            print(TerminalUI.dim("  No active memories."))
        } else {
            for memory in activeMemories {
                let contentPreview = String(memory.content.prefix(60)).replacingOccurrences(
                    of: "\n", with: " ")
                print(
                    "  \(TerminalUI.dim(memory.id.uuidString.prefix(8).description)) | \(contentPreview)..."
                )
            }
        }

        print("")
        print(TerminalUI.dim("Use '/memory all' to manage all \(memories.count) memories."))
        print("")
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
}
