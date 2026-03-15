import Foundation
import MonadClient

actor PruneSlashCommand: SlashCommand {
    nonisolated let name = "prune"
    nonisolated let description = "Bulk delete data"
    nonisolated let category: String? = "Data Management"
    nonisolated let usage = "/prune [memories|timelines|confirm] <args>"

    private enum PendingOperation {
        case memoriesQuery(String)
        case memoriesDays(Int)
        case timelines(days: Int)
        case memory(Memory)
    }

    private var pendingOperation: PendingOperation?

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.first ?? "help"

        switch subcommand {
        case "memories":
            try await handleMemoriesSubcommand(args: args, context: context)
        case "memory":
            try await handleMemorySubcommand(args: args, context: context)
        case "timelines", "session":
            try await handleTimelinesSubcommand(args: args, context: context)
        case "confirm":
            try await executePendingOperation(context: context)
        default:
            printUsage()
        }
    }

    // MARK: - Subcommand Routing

    private func handleMemoriesSubcommand(args: [String], context: ChatContext) async throws {
        guard args.count > 1 else {
            TerminalUI.printError("Usage: /prune memories <query|days|olderThan N>")
            return
        }
        if let days = Int(args[1]) {
            try await planPruneMemories(days: days, context: context)
        } else if args[1].lowercased() == "olderthan", args.count > 2, let days = Int(args[2]) {
            try await planPruneMemories(days: days, context: context)
        } else {
            let query = args.dropFirst().joined(separator: " ")
            try await planPruneMemories(query: query, context: context)
        }
    }

    private func handleMemorySubcommand(args: [String], context: ChatContext) async throws {
        guard args.count > 1 else {
            TerminalUI.printError("Usage: /prune memory <id|olderThan>")
            return
        }
        if args[1].lowercased() == "olderthan" {
            guard args.count > 2, let days = Int(args[2]) else {
                TerminalUI.printError("Usage: /prune memory olderThan <days>")
                return
            }
            try await planPruneMemories(days: days, context: context)
        } else {
            try await planPruneSingleMemory(idPrefix: args[1], context: context)
        }
    }

    private func handleTimelinesSubcommand(args: [String], context: ChatContext) async throws {
        guard args.count > 1 else {
            TerminalUI.printError("Usage: /prune timelines <older-than-days|all>")
            return
        }
        let arg = args[1].lowercased()
        let days: Int
        if arg == "all" {
            days = 0
        } else if let parsed = Int(arg) {
            days = parsed
        } else {
            TerminalUI.printError("Usage: /prune timelines <older-than-days|all>")
            return
        }
        try await planPruneTimelines(days: days, context: context)
    }

    // MARK: - Usage

    private func printUsage() {
        print(TerminalUI.bold("Prune Commands:"))
        print("  /prune memories <query|days>   Plan deletion of memories (by query or age)")
        print("  /prune memory <id>             Plan deletion of a specific memory")
        print("  /prune memory olderThan <days> Plan deletion of memories older than N days")
        print("  /prune timelines <days|all>     Plan deletion of timelines older than N days")
        print("  /prune confirm                 Execute the planned deletion")
    }

    private func planPruneMemories(query: String, context: ChatContext) async throws {
        TerminalUI.printLoading("Checking memories...")
        let count = try await context.client.chat.pruneMemories(query: query, dryRun: true)

        if count == 0 {
            TerminalUI.printInfo("No memories found matching '\(query)'.")
            pendingOperation = nil
            return
        }

        pendingOperation = .memoriesQuery(query)
        print("")
        print(TerminalUI.bold("⚠️  Dry Run Results:"))
        print("   Would delete \(TerminalUI.cyan("\(count)")) memories matching '\(query)'.")
        print("")
        print(TerminalUI.bold("To execute this deletion, run:"))
        print("   /prune confirm")
        print("")
    }

    private func planPruneMemories(days: Int, context: ChatContext) async throws {
        TerminalUI.printLoading("Checking memories...")
        let count = try await context.client.chat.pruneMemories(olderThanDays: days, dryRun: true)

        if count == 0 {
            TerminalUI.printInfo("No memories found older than \(days) days.")
            pendingOperation = nil
            return
        }

        pendingOperation = .memoriesDays(days)
        print("")
        print(TerminalUI.bold("⚠️  Dry Run Results:"))
        print("   Would delete \(TerminalUI.cyan("\(count)")) memories older than \(days) days.")
        print("")
        print(TerminalUI.bold("To execute this deletion, run:"))
        print("   /prune confirm")
        print("")
    }

    private func planPruneTimelines(days: Int, context: ChatContext) async throws {
        TerminalUI.printLoading("Checking timelines...")
        // Exclude current timeline for count accuracy check
        let currentTimelineId = context.timeline.id
        let count = try await context.client.chat.pruneTimelines(
            olderThanDays: days, excluding: [currentTimelineId], dryRun: true
        )

        if count == 0 {
            TerminalUI.printInfo("No timelines found to prune.")
            pendingOperation = nil
            return
        }

        pendingOperation = .timelines(days: days)
        let criteria = days == 0 ? "all timelines" : "timelines older than \(days) days"

        print("")
        print(TerminalUI.bold("⚠️  Dry Run Results:"))
        print("   Would delete \(TerminalUI.cyan("\(count)")) timelines matching \(criteria).")
        print("   (Current timeline will be preserved)")
        print("")
        print(TerminalUI.bold("To execute this deletion, run:"))
        print("   /prune confirm")
        print("")
    }

    private func planPruneSingleMemory(idPrefix: String, context: ChatContext) async throws {
        TerminalUI.printLoading("Finding memory...")
        let memories = try await context.client.chat.listMemories()

        let matches = memories.filter {
            $0.id.uuidString.lowercased().hasPrefix(idPrefix.lowercased())
        }

        if matches.isEmpty {
            TerminalUI.printError("No memory found with ID starting with '\(idPrefix)'")
            pendingOperation = nil
            return
        }

        if matches.count > 1 {
            TerminalUI.printWarning("Multiple memories match '\(idPrefix)':")
            for mem in matches.prefix(5) {
                let preview = String(mem.content.prefix(50))
                    .replacingOccurrences(of: "\n", with: " ")
                print("  \(mem.id.uuidString.prefix(8)) - \(preview)...")
            }
            TerminalUI.printInfo("Please provide a longer ID prefix.")
            pendingOperation = nil
            return
        }

        let memory = matches[0]
        pendingOperation = .memory(memory)

        print("")
        print(TerminalUI.bold("⚠️  Dry Run Results:"))
        print(
            "   Would delete memory: \(TerminalUI.cyan(memory.id.uuidString.prefix(8).description))"
        )
        print(
            "   Content: \(String(memory.content.prefix(100)).replacingOccurrences(of: "\n", with: " "))..."
        )
        print("")
        print(TerminalUI.bold("To execute this deletion, run:"))
        print("   /prune confirm")
        print("")
    }

    private func executePendingOperation(context: ChatContext) async throws {
        guard let operation = pendingOperation else {
            TerminalUI.printError("No pending prune operation. Run a prune command first.")
            return
        }

        switch operation {
        case let .memoriesQuery(query):
            TerminalUI.printLoading("Deleting memories...")
            let count = try await context.client.chat.pruneMemories(query: query, dryRun: false)
            TerminalUI.printSuccess("Deleted \(count) memories.")

        case let .memoriesDays(days):
            TerminalUI.printLoading("Deleting memories...")
            let count = try await context.client.chat.pruneMemories(olderThanDays: days, dryRun: false)
            TerminalUI.printSuccess("Deleted \(count) memories.")

        case let .timelines(days):
            TerminalUI.printLoading("Deleting timelines...")
            let currentTimelineId = context.timeline.id
            let count = try await context.client.chat.pruneTimelines(
                olderThanDays: days, excluding: [currentTimelineId], dryRun: false
            )
            TerminalUI.printSuccess("Deleted \(count) timelines.")

        case let .memory(memory):
            TerminalUI.printLoading("Deleting memory...")
            try await context.client.chat.deleteMemory(memory.id)
            TerminalUI.printSuccess("Deleted memory \(memory.id.uuidString.prefix(8)).")
        }

        pendingOperation = nil
    }
}
