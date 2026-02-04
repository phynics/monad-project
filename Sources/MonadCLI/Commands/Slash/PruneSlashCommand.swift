import Foundation
import MonadClient

struct PruneSlashCommand: SlashCommand {
    let name = "prune"
    let description = "Bulk delete data"
    let category: String? = "Data Management"
    let usage = "/prune [memories|sessions] <args>"

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.first ?? "help"

        switch subcommand {
        case "memories", "memory":
            if args.count > 1 {
                let query = args.dropFirst().joined(separator: " ")
                try await pruneMemories(query: query, context: context)
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
                try await pruneSessions(days: days, context: context)
            } else {
                TerminalUI.printError("Usage: /prune sessions <older-than-days|all>")
            }
        default:
            printUsage()
        }
    }

    private func printUsage() {
        print(TerminalUI.bold("Prune Commands:"))
        print("  /prune memories <query>        Delete memories matching query")
        print(
            "  /prune sessions <days|all>     Delete sessions older than N days (excludes current)")
    }

    private func pruneMemories(query: String, context: ChatContext) async throws {
        print(
            "Are you sure you want to delete memories matching '\(query)'? (y/n): ", terminator: "")
        guard let response = readLine(), response.lowercased() == "y" else {
            TerminalUI.printInfo("Aborted.")
            return
        }

        let count = try await context.client.pruneMemories(query: query)
        TerminalUI.printSuccess("Deleted \(count) memories.")
    }

    private func pruneSessions(days: Int, context: ChatContext) async throws {
        let msg = days == 0 ? "all sessions" : "sessions older than \(days) days"
        print(
            "Are you sure you want to delete \(msg)? (Current session will be preserved) (y/n): ",
            terminator: "")
        guard let response = readLine(), response.lowercased() == "y" else {
            TerminalUI.printInfo("Aborted.")
            return
        }

        // Exclude current session
        let currentSessionId = context.session.id
        let count = try await context.client.pruneSessions(
            olderThanDays: days, excluding: [currentSessionId])
        TerminalUI.printSuccess("Deleted \(count) sessions.")
    }
}
