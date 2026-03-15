import Foundation
import MonadShared

/// Debug command to display the raw context delivered to the LLM
struct DebugCommand: SlashCommand {
    let name = "debug"
    let aliases: [String] = []
    let description = "Show the rendered prompt and raw LLM output for the last exchange"
    let usage = "/debug"
    let category: String? = "Utilities"

    func run(args _: [String], context: ChatContext) async throws {
        guard let snapshot = await context.repl.getLastDebugSnapshot() else {
            TerminalUI.printInfo("No debug data available yet. Please run a chat prompt first.")
            return
        }

        printSnapshotHeader(snapshot)
        printRenderedPrompt(snapshot)
        printRawOutput(snapshot)
        printStructuredContext(snapshot)
        printToolCalls(snapshot)
        printToolResults(snapshot)
        print(TerminalUI.bold("═══════════════════"))
    }

    // MARK: - Section Printers

    private func printSnapshotHeader(_ snapshot: DebugSnapshot) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        print("")
        print(TerminalUI.bold("═══ Debug Snapshot ═══"))
        print(TerminalUI.dim("Timestamp: \(dateFormatter.string(from: snapshot.timestamp))"))
        print(TerminalUI.dim("Model: \(snapshot.model)"))
        print(TerminalUI.dim("Turns: \(snapshot.turnCount)"))
        print("")
    }

    private func printRenderedPrompt(_ snapshot: DebugSnapshot) {
        if let rendered = snapshot.renderedPrompt {
            print(TerminalUI.bold("─── Rendered Prompt ───"))
            print(TerminalUI.dim(rendered))
            print("")
        }
    }

    private func printRawOutput(_ snapshot: DebugSnapshot) {
        if let rawOutput = snapshot.rawOutput, !rawOutput.isEmpty {
            print(TerminalUI.bold("─── Raw Output (Full Stream) ───"))
            print(rawOutput)
            print("")
        }
    }

    private func printStructuredContext(_ snapshot: DebugSnapshot) {
        let sectionOrder = [
            "system_instructions", "context_notes", "memories",
            "tools", "chat_history", "user_query"
        ]

        let sortedKeys = snapshot.structuredContext.keys.sorted { lhs, rhs in
            let lhsIdx = sectionOrder.firstIndex(of: lhs) ?? sectionOrder.count
            let rhsIdx = sectionOrder.firstIndex(of: rhs) ?? sectionOrder.count
            return lhsIdx < rhsIdx
        }

        for key in sortedKeys {
            guard let content = snapshot.structuredContext[key] else { continue }
            let displayName = key.replacingOccurrences(of: "_", with: " ").capitalized
            print(TerminalUI.bold("─── \(displayName) ───"))
            print(content)
            print("")
        }
    }

    private func printToolCalls(_ snapshot: DebugSnapshot) {
        guard !snapshot.toolCalls.isEmpty else { return }

        print(TerminalUI.bold("─── Tool Calls ───"))
        for call in snapshot.toolCalls {
            print(TerminalUI.yellow("  [Turn \(call.turn)] \(call.name)"))
            printPrettyJSON(call.arguments)
        }
        print("")
    }

    private func printToolResults(_ snapshot: DebugSnapshot) {
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

    private func printPrettyJSON(_ jsonString: String) {
        if let data = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(
               withJSONObject: json, options: [.prettyPrinted, .sortedKeys]
           ),
           let prettyStr = String(data: pretty, encoding: .utf8) {
            for line in prettyStr.split(separator: "\n") {
                print(TerminalUI.dim("    \(line)"))
            }
        } else {
            print(TerminalUI.dim("    \(jsonString)"))
        }
    }
}
