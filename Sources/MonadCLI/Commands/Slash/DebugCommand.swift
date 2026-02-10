import Foundation
import MonadClient

/// Debug command to display the raw context delivered to the LLM
struct DebugCommand: SlashCommand {
    let name = "debug"
    let aliases: [String] = []
    let description = "Show the raw context delivered to the LLM for the last exchange"
    let usage = "/debug"
    let category: String? = "Utilities"

    func run(args: [String], context: ChatContext) async throws {
        do {
            let snapshot = try await context.client.getDebugSnapshot(sessionId: context.session.id)

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium

            print("")
            print(TerminalUI.bold("═══ Debug Snapshot ═══"))
            print(TerminalUI.dim("Timestamp: \(dateFormatter.string(from: snapshot.timestamp))"))
            print(TerminalUI.dim("Model: \(snapshot.model)"))
            print(TerminalUI.dim("Turns: \(snapshot.turnCount)"))
            print("")

            // Display structured context sections
            // Sort keys for consistent ordering
            let sectionOrder = [
                "system_instructions", "context_notes", "memories",
                "tools", "chat_history", "user_query",
            ]

            let sortedKeys = snapshot.structuredContext.keys.sorted { a, b in
                let aIdx = sectionOrder.firstIndex(of: a) ?? sectionOrder.count
                let bIdx = sectionOrder.firstIndex(of: b) ?? sectionOrder.count
                return aIdx < bIdx
            }

            for key in sortedKeys {
                guard let content = snapshot.structuredContext[key] else { continue }
                let displayName = key.replacingOccurrences(of: "_", with: " ").capitalized
                print(TerminalUI.bold("─── \(displayName) ───"))
                print(content)
                print("")
            }

            // Tool calls
            if !snapshot.toolCalls.isEmpty {
                print(TerminalUI.bold("─── Tool Calls ───"))
                for call in snapshot.toolCalls {
                    print(TerminalUI.yellow("  [Turn \(call.turn)] \(call.name)"))
                    // Pretty-print JSON arguments
                    if let data = call.arguments.data(using: .utf8),
                        let json = try? JSONSerialization.jsonObject(with: data),
                        let pretty = try? JSONSerialization.data(
                            withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
                        let prettyStr = String(data: pretty, encoding: .utf8)
                    {
                        for line in prettyStr.split(separator: "\n") {
                            print(TerminalUI.dim("    \(line)"))
                        }
                    } else {
                        print(TerminalUI.dim("    \(call.arguments)"))
                    }
                }
                print("")
            }

            // Tool results
            if !snapshot.toolResults.isEmpty {
                print(TerminalUI.bold("─── Tool Results ───"))
                for result in snapshot.toolResults {
                    print(TerminalUI.green("  [Turn \(result.turn)] \(result.name)"))
                    for line in result.output.split(separator: "\n", omittingEmptySubsequences: false) {
                        print(TerminalUI.dim("    \(line)"))
                    }
                }
                print("")
            }

            print(TerminalUI.bold("═══════════════════"))

        } catch {
            TerminalUI.printInfo("No debug data available for this session.")
        }
    }
}
