import Foundation
import MonadClient

actor PruneSlashCommand: SlashCommand {
    nonisolated let name = "prune"
    nonisolated let description = "Bulk delete data"
    nonisolated let category: String? = "Data Management"
    nonisolated let usage = "/prune [memories|sessions|confirm] <args>"

    private enum PendingOperation {
        case memories(query: String)
        case sessions(days: Int)
    }

    private var pendingOperation: PendingOperation?

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.first ?? "help"

        switch subcommand {
        case "memories", "memory":
            if args.count > 1 {
                let query = args.dropFirst().joined(separator: " ")
                try await planPruneMemories(query: query, context: context)
            } else {
                TerminalUI.printError("Usage: /prune memories <query>")
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

        pendingOperation = .memories(query: query)
        print("")
        print(TerminalUI.bold("⚠️  Dry Run Results:"))
        print("   Would delete \(TerminalUI.cyan("\(count)")) memories matching '\(query)'.")
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

    private func executePendingOperation(context: ChatContext) async throws {
        guard let operation = pendingOperation else {
            TerminalUI.printError("No pending prune operation. Run a prune command first.")
            return
        }

        switch operation {
        case .memories(let query):
            TerminalUI.printLoading("Deleting memories...")
            let count = try await context.client.pruneMemories(query: query, dryRun: false)
            TerminalUI.printSuccess("Deleted \(count) memories.")

        case .sessions(let days):
            TerminalUI.printLoading("Deleting sessions...")
            let currentSessionId = context.session.id
            let count = try await context.client.pruneSessions(
                olderThanDays: days, excluding: [currentSessionId], dryRun: false)
            TerminalUI.printSuccess("Deleted \(count) sessions.")
        }

        pendingOperation = nil
    }
}
