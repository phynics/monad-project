import Foundation
import MonadClient

actor PruneSlashCommand: SlashCommand {
    nonisolated let name = "prune"
    nonisolated let description = "Bulk delete data"
    nonisolated let category: String? = "Data Management"
    nonisolated let usage = "/prune [memories|sessions|confirm] <args>"

    private enum PendingOperation {
        case memoriesQuery(String)
        case memoriesDays(Int)
        case sessions(days: Int)
        case memory(Memory)
    }

    private var pendingOperation: PendingOperation?

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.first ?? "help"

        switch subcommand {
        case "memories":
            if args.count > 1 {
                let arg = args.dropFirst().joined(separator: " ")
                if let days = Int(arg) {
                    try await planPruneMemories(days: days, context: context)
                } else {
                    try await planPruneMemories(query: arg, context: context)
                }
            } else {
                TerminalUI.printError("Usage: /prune memories <query|days>")
            }
        case "memory":
            if args.count > 1 {
                if args[1].lowercased() == "olderthan" {
                    if args.count > 2, let days = Int(args[2]) {
                        try await planPruneMemories(days: days, context: context)
                    } else {
                        TerminalUI.printError("Usage: /prune memory olderThan <days>")
                    }
                } else {
                    // ID match
                    let idPrefix = args[1]
                    try await planPruneSingleMemory(idPrefix: idPrefix, context: context)
                }
            } else {
                TerminalUI.printError("Usage: /prune memory <id|olderThan>")
            }
        case "sessions", "session":
            if args.count > 1 {
                let arg = args[1].lowercased()
                let days: Int
                if arg == "all" {
                    days = 0
                } else if let d = Int(arg) {
                    days = d
                } else {
                    TerminalUI.printError("Usage: /prune sessions <older-than-days|all>")
                    return
                }
                try await planPruneSessions(days: days, context: context)
            } else {
                TerminalUI.printError("Usage: /prune sessions <older-than-days|all>")
            }
        case "confirm":
            try await executePendingOperation(context: context)
        default:
            printUsage()
        }
    }

    private func printUsage() {
        print(TerminalUI.bold("Prune Commands:"))
        print("  /prune memories <query>        Plan deletion of memories matching query")
        print("  /prune memory <id>             Plan deletion of a specific memory")
        print("  /prune memory olderThan <days> Plan deletion of memories older than N days")
        print("  /prune sessions <days|all>     Plan deletion of sessions older than N days")
        print("  /prune confirm                 Execute the planned deletion")
    }

    private func planPruneMemories(query: String, context: ChatContext) async throws {
        TerminalUI.printLoading("Checking memories...")
        let count = try await context.client.pruneMemories(query: query, dryRun: true)

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
        let count = try await context.client.pruneMemories(olderThanDays: days, dryRun: true)

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

    private func planPruneSessions(days: Int, context: ChatContext) async throws {
        TerminalUI.printLoading("Checking sessions...")
        // Exclude current session for count accuracy check
        let currentSessionId = context.session.id
        let count = try await context.client.pruneSessions(
            olderThanDays: days, excluding: [currentSessionId], dryRun: true)

        if count == 0 {
            TerminalUI.printInfo("No sessions found to prune.")
            pendingOperation = nil
            return
        }

        pendingOperation = .sessions(days: days)
        let criteria = days == 0 ? "all sessions" : "sessions older than \(days) days"

        print("")
        print(TerminalUI.bold("⚠️  Dry Run Results:"))
        print("   Would delete \(TerminalUI.cyan("\(count)")) sessions matching \(criteria).")
        print("   (Current session will be preserved)")
        print("")
        print(TerminalUI.bold("To execute this deletion, run:"))
        print("   /prune confirm")
        print("")
    }

    private func planPruneSingleMemory(idPrefix: String, context: ChatContext) async throws {
        TerminalUI.printLoading("Finding memory...")
        let memories = try await context.client.listMemories()

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
            for m in matches.prefix(5) {
                print(
                    "  \(m.id.uuidString.prefix(8)) - \(String(m.content.prefix(50)).replacingOccurrences(of: "\n", with: " "))..."
                )
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
        case .memoriesQuery(let query):
            TerminalUI.printLoading("Deleting memories...")
            let count = try await context.client.pruneMemories(query: query, dryRun: false)
            TerminalUI.printSuccess("Deleted \(count) memories.")

        case .memoriesDays(let days):
            TerminalUI.printLoading("Deleting memories...")
            let count = try await context.client.pruneMemories(olderThanDays: days, dryRun: false)
            TerminalUI.printSuccess("Deleted \(count) memories.")

        case .sessions(let days):
            TerminalUI.printLoading("Deleting sessions...")
            let currentSessionId = context.session.id
            let count = try await context.client.pruneSessions(
                olderThanDays: days, excluding: [currentSessionId], dryRun: false)
            TerminalUI.printSuccess("Deleted \(count) sessions.")

        case .memory(let memory):
            TerminalUI.printLoading("Deleting memory...")
            try await context.client.deleteMemory(memory.id)
            TerminalUI.printSuccess("Deleted memory \(memory.id.uuidString.prefix(8)).")
        }

        pendingOperation = nil
    }
}
