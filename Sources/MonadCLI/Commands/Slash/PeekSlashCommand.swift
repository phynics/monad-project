import Foundation
import MonadClient
import MonadShared

struct PeekSlashCommand: SlashCommand {
    let name = "peek"
    let aliases: [String] = []
    let description = "Peek into another timeline without switching"
    let category: String? = "Timeline Management"
    let usage = "/peek timeline [timeline #|timeline title|private]"

    func run(args: [String], context: ChatContext) async throws {
        guard args.dropFirst().first == "timeline" else {
            TerminalUI.printError("Usage: \(usage)")
            return
        }

        let queryParts = Array(args.dropFirst(2))
        let query = queryParts.isEmpty ? nil : queryParts.joined(separator: " ")
        let publicTimelines = try await context.client.chat.listTimelines()
        let currentAgent = await context.repl.getCurrentAgent()
        let resolution = CLITimelineCatalog.resolvePeekTarget(
            query: query,
            publicTimelines: publicTimelines,
            currentAgent: currentAgent
        )
        let manager = CLITimelineManager(client: context.client)

        switch resolution {
        case .publicTimeline(let timeline):
            try await manager.browseTimeline(
                timelineId: timeline.id,
                title: timeline.title ?? "Untitled",
                kindLabel: "public"
            )
        case .privateTimeline(let timelineId):
            let timeline = try await context.client.chat.getTimeline(id: timelineId)
            try await manager.browseTimeline(
                timelineId: timelineId,
                title: timeline.title ?? "Agent Private",
                kindLabel: "agent private"
            )
        case .ambiguous(let matches):
            guard let selected = promptForDisambiguation(matches: matches) else {
                TerminalUI.printInfo("Cancelled.")
                return
            }
            try await manager.browseTimeline(
                timelineId: selected.id,
                title: selected.title ?? "Untitled",
                kindLabel: "public"
            )
        case .privateTimelineUnavailable:
            TerminalUI.printError("No agent is attached to the current timeline.")
        case .notFound:
            TerminalUI.printError("No public timeline matched that query.")
        }
    }

    private func promptForDisambiguation(matches: [TimelineResponse]) -> TimelineResponse? {
        let sortedMatches = CLITimelineCatalog.sortedPublicTimelines(matches)

        print("")
        print(TerminalUI.bold("Multiple timelines matched:"))
        for (index, timeline) in sortedMatches.enumerated() {
            let title = timeline.title ?? "Untitled"
            let date = TerminalUI.formatDate(timeline.updatedAt)
            print("  \(index + 1). \(title)  \(TerminalUI.dim("#\(timeline.id.uuidString.prefix(8)) • \(date)"))")
        }
        print("")
        print("Choose a timeline to peek [q]: ", terminator: "")

        let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "q"
        guard response != "q", !response.isEmpty else { return nil }
        guard let index = Int(response), index > 0, index <= sortedMatches.count else {
            TerminalUI.printError("Invalid selection.")
            return nil
        }
        return sortedMatches[index - 1]
    }
}
