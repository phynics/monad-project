import Foundation
import MonadShared

/// Debug command to display the turn snapshot for the last exchange
struct DebugCommand: SlashCommand {
    let name = "debug"
    let aliases: [String] = []
    let description = "Show the rendered prompt and raw LLM output for the last exchange"
    let usage = "/debug"
    let category: String? = "Utilities"

    func run(args _: [String], context: ChatContext) async throws {
        guard let snapshot = await context.repl.getLastTurnSnapshot() else {
            TerminalUI.printInfo("No debug data available yet. Please run a chat prompt first.")
            return
        }

        printSnapshotHeader(snapshot)
        printRenderedPrompt(snapshot)
        printRawOutput(snapshot)
        printContextSummary(snapshot)
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

    private func printRenderedPrompt(_ snapshot: TurnSnapshot) {
        if let rendered = snapshot.renderedPrompt {
            print(TerminalUI.bold("─── Rendered Prompt ───"))
            print(TerminalUI.dim(rendered))
            print("")
        }
    }

    private func printRawOutput(_ snapshot: TurnSnapshot) {
        if !snapshot.rawOutput.isEmpty {
            print(TerminalUI.bold("─── Raw Output (Full Stream) ───"))
            print(snapshot.rawOutput)
            print("")
        }
    }

    private func printContextSummary(_ snapshot: TurnSnapshot) {
        if let instructions = snapshot.systemInstructions {
            print(TerminalUI.bold("─── System Instructions ───"))
            let preview = instructions.count > 200 ? String(instructions.prefix(200)) + "…" : instructions
            print(TerminalUI.dim(preview))
            print("")
        }
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
