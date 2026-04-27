import Foundation
import PKShared

/// Debug command to display the turn snapshot for the last exchange
struct DebugCommand: SlashCommand {
    let name = "debug"
    let aliases: [String] = []
    let description = "Show turn metadata, tool activity, and metrics for the last exchange"
    let usage = "/debug"
    let category: String? = "Utilities"

    private let maxContentPreview = 300

    func run(args _: [String], context: ChatContext) async throws {
        guard let snapshot = await context.repl.getLastTurnSnapshot() else {
            TerminalUI.printInfo("No debug data available yet. Please run a chat prompt first.")
            return
        }

        printSnapshotHeader(snapshot)
        printBuiltPrompt(snapshot)
        printContextRetrieval(snapshot)
        printToolCalls(snapshot)
        printToolResults(snapshot)
        printMetrics(snapshot)
        print(TerminalUI.bold("═══════════════════"))
    }

    // MARK: - Section Printers

    private func printSnapshotHeader(_ snapshot: TurnSnapshot) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        print("")
        print(TerminalUI.bold("═══ Turn Snapshot ═══"))
        print(TerminalUI.dim("Timestamp: \(dateFormatter.string(from: snapshot.timestamp))"))
        print(TerminalUI.dim("Model: \(snapshot.modelName)"))
        print(TerminalUI.dim("Turn: \(snapshot.turnCount)/\(snapshot.maxTurns)"))
        if let agentId = snapshot.agentInstanceId {
            print(TerminalUI.dim("Agent: \(agentId.uuidString.prefix(8))"))
        }
        if !snapshot.availableToolIds.isEmpty {
            print(TerminalUI.dim("Tools: \(snapshot.availableToolIds.joined(separator: ", "))"))
        }
        print("")
    }

    private func printBuiltPrompt(_ snapshot: TurnSnapshot) {
        guard let ctx = snapshot.contextSnapshot, !ctx.promptMessages.isEmpty else { return }

        let totalTokens = ctx.promptMessages.reduce(0) { $0 + $1.tokenCount }
        print(TerminalUI.bold("─── Built Prompt (\(ctx.promptMessages.count) messages, ~\(totalTokens) tokens) ───"))

        for (index, msg) in ctx.promptMessages.enumerated() {
            let roleLabel = formatRole(msg.role)
            let tokenLabel = TerminalUI.dim(" [\(msg.tokenCount) tok]")
            print("  \(TerminalUI.bold("\(index + 1). \(roleLabel)"))\(tokenLabel)")

            let preview = truncate(msg.content, to: maxContentPreview)
            for line in preview.split(separator: "\n", omittingEmptySubsequences: false).prefix(8) {
                print(TerminalUI.dim("     \(line)"))
            }
            if msg.content.count > maxContentPreview ||
                msg.content.split(separator: "\n", omittingEmptySubsequences: false).count > 8
            {
                print(TerminalUI.dim("     …(\(msg.content.count) chars total)"))
            }
        }
        print("")
    }

    private func printContextRetrieval(_ snapshot: TurnSnapshot) {
        guard let ctx = snapshot.contextSnapshot else { return }
        let hasData = !ctx.memories.isEmpty || !ctx.files.isEmpty
            || !ctx.generatedTags.isEmpty || ctx.augmentedQuery != nil
        guard hasData else { return }

        print(TerminalUI.bold("─── Context Retrieval (\(String(format: "%.3fs", ctx.executionTime))) ───"))
        if let query = ctx.augmentedQuery {
            let preview = query.count > 120 ? String(query.prefix(120)) + "…" : query
            print(TerminalUI.dim("  Query: \(preview)"))
        }
        if !ctx.generatedTags.isEmpty {
            print(TerminalUI.dim("  Tags: \(ctx.generatedTags.joined(separator: ", "))"))
        }
        if !ctx.memories.isEmpty {
            print(TerminalUI.dim("  Memories (\(ctx.memories.count)):"))
            for memory in ctx.memories {
                let sim = memory.similarity.map { String(format: " (%.2f)", $0) } ?? ""
                let preview = String(memory.content.prefix(80)).replacingOccurrences(of: "\n", with: " ")
                print(TerminalUI.dim("    • \(memory.id.uuidString.prefix(8))\(sim) \(preview)"))
            }
        }
        if !ctx.files.isEmpty {
            print(TerminalUI.dim("  Files (\(ctx.files.count)):"))
            for file in ctx.files {
                print(TerminalUI.dim("    • \(file.name) ← \(file.source)"))
            }
        }
        print("")
    }

    private func printToolCalls(_ snapshot: TurnSnapshot) {
        guard !snapshot.toolCalls.isEmpty else { return }

        print(TerminalUI.bold("─── Tool Calls ───"))
        for call in snapshot.toolCalls {
            print(TerminalUI.yellow("  [Turn \(call.turn)] \(call.name)"))
            printPrettyJSON(call.arguments)
        }
        print("")
    }

    private func printToolResults(_ snapshot: TurnSnapshot) {
        guard !snapshot.toolResults.isEmpty else { return }

        print(TerminalUI.bold("─── Tool Results ───"))
        for result in snapshot.toolResults {
            print(TerminalUI.green("  [Turn \(result.turn)] \(result.name)"))
            for line in result.output.split(separator: "\n", omittingEmptySubsequences: false) {
                print(TerminalUI.dim("    \(line)"))
            }
        }
        print("")
    }

    private func printMetrics(_ snapshot: TurnSnapshot) {
        print(TerminalUI.bold("─── Metrics ───"))
        print(TerminalUI.dim("  Duration: \(String(format: "%.2fs", snapshot.turnDuration))"))
        if let tps = snapshot.tokensPerSecond {
            print(TerminalUI.dim("  Tokens/sec: \(String(format: "%.1f", tps))"))
        }
        if let prompt = snapshot.promptTokens {
            print(TerminalUI.dim("  Prompt tokens: \(prompt)"))
        }
        if let completion = snapshot.completionTokens {
            print(TerminalUI.dim("  Completion tokens: \(completion)"))
        }
        if let total = snapshot.totalTokens {
            print(TerminalUI.dim("  Total tokens: \(total)"))
        }
        print("")
    }

    // MARK: - Helpers

    private func formatRole(_ role: String) -> String {
        switch role {
        case "system": return "SYSTEM"
        case "user": return "USER"
        case "assistant": return "ASSISTANT"
        case "tool": return "TOOL"
        case "developer": return "DEVELOPER"
        default: return role.uppercased()
        }
    }

    private func truncate(_ text: String, to limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit))
    }

    private func printPrettyJSON(_ jsonString: String) {
        if let data = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(
               withJSONObject: json, options: [.prettyPrinted, .sortedKeys]
           ),
           let prettyStr = String(data: pretty, encoding: .utf8)
        {
            for line in prettyStr.split(separator: "\n") {
                print(TerminalUI.dim("    \(line)"))
            }
        } else {
            print(TerminalUI.dim("    \(jsonString)"))
        }
    }
}
