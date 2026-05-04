import Foundation
import MonadClient
import MonadShared
import PKShared

// MARK: - Core Commands

struct HelpCommand: SlashCommand {
    let name = "help"
    let aliases = ["h", "?"]
    let description = "Show available commands"
    let category: String? = "Chat Commands"
    let registry: SlashCommandRegistry

    func run(args _: [String], context _: ChatContext) async throws {
        let commands = await registry.allCommands

        // Group by category
        var grouped: [String: [SlashCommand]] = [:]
        for cmd in commands {
            let cat = cmd.category ?? "General"
            grouped[cat, default: []].append(cmd)
        }

        let sortedCategories = grouped.keys.sorted {
            // "General" first/last? Let's generic sort, but maybe put General first or last.
            // Let's use specific order if possible, or just strict alphabetical.
            // Custom order: Core/General, Chat, Filesystem, Tools, Data, CONFIG
            if $0 == "General" { return true }
            if $1 == "General" { return false }
            return $0 < $1
        }

        print("\n" + TerminalUI.bold("Available Commands:") + "\n")

        for cat in sortedCategories {
            guard let cmds = grouped[cat], !cmds.isEmpty else { continue }
            print(TerminalUI.bold(cat) + ":")

            for cmd in cmds {
                let aliasesStr =
                    cmd.aliases.isEmpty ? "" : " (\(cmd.aliases.joined(separator: ", ")))"
                let namePart = "/\(cmd.name)\(aliasesStr)".padding(
                    toLength: 30, withPad: " ", startingAt: 0
                )
                print("  \(TerminalUI.cyan(namePart)) \(cmd.description)")
            }
            print("")
        }
    }
}

struct QuitCommand: SlashCommand {
    let name = "quit"
    let aliases = ["q", "exit"]
    let description = "Exit the chat"
    let category: String? = "Chat Commands"

    func run(args _: [String], context: ChatContext) async throws {
        await context.repl.stop()
        TerminalUI.printInfo("Goodbye!")
    }
}

struct NewTimelineCommand: SlashCommand {
    let name = "new"
    let description = "Start a new chat timeline"
    let category: String? = "Timeline Management"

    func run(args _: [String], context: ChatContext) async throws {
        do {
            let currentAgent = await context.repl.getCurrentAgent()
            let manager = CLITimelineManager(client: context.client)
            let timeline = try await manager.createNewTimelineFlow()
            if let agent = currentAgent {
                try? await context.client.chat.attachAgent(agentId: agent.id, to: timeline.id)
            }
            await context.repl.switchTimeline(timeline)
            if let agent = currentAgent {
                await context.repl.setAgent(agent)
            }
            TerminalUI.printSuccess("Started new timeline \(timeline.id.uuidString.prefix(8))")
        } catch {
            TerminalUI.printError("Failed to create timeline: \(error.localizedDescription)")
        }
    }
}

// MARK: - Specialized Commands

struct TimelineCommand: SlashCommand {
    let name = "timeline"
    let aliases = ["timelines"]
    let description = "Manage timelines"
    let category: String? = "Timeline Management"
    let usage = "/timeline [info|list|create|delete|rename|switch|log] [args]"

    func run(args: [String], context: ChatContext) async throws {
        let subcommand = args.first ?? "info"

        switch subcommand {
        case "info":
            try await showInfo(context: context)
        case "list", "ls":
            try await listTimelines(context: context)
        case "delete", "rm":
            if args.count > 1 {
                try await deleteTimeline(args[1], context: context)
            } else {
                TerminalUI.printError("Usage: /timeline delete <timeline-id>")
            }
        case "create", "new":
            let title = args.dropFirst().dropFirst().joined(separator: " ")
            try await createTimeline(title.isEmpty ? nil : title, context: context)
        case "rename", "name":
            if args.count > 1 {
                let newTitle = args.dropFirst().joined(separator: " ")
                try await renameTimeline(newTitle, context: context)
            } else {
                TerminalUI.printError("Usage: /timeline rename <new-name>")
            }
        case "switch", "use":
            if args.count > 1 {
                try await switchTimeline(args[1], context: context)
            } else {
                // Interactive TUI switch
                try await interactiveSwitch(context: context)
            }
        case "log", "history":
            try await showHistory(context: context)
        default:
            try await showInfo(context: context)
        }
    }

    private func showInfo(context: ChatContext) async throws {
        let timeline = context.timeline
        let messages = try await context.client.chat.getHistory(timelineId: timeline.id)
        let timelineWS = try await context.client.workspace.listTimelineWorkspaces(timelineId: timeline.id)

        print("")
        print(TerminalUI.bold("Current Timeline"))
        print("")
        print("  Title:    \(timeline.title ?? "Untitled")")
        print("  ID:       \(timeline.id.uuidString)")
        print("  Created:  \(TerminalUI.formatDate(timeline.createdAt))")
        print("  Messages: \(messages.count)")

        // Workspaces
        var wsDesc: [String] = []
        if let primary = timelineWS.primary {
            wsDesc.append("\(primary.uri.description) (★)")
        }
        for workspace in timelineWS.attached.prefix(2) {
            wsDesc.append("\(workspace.uri.description) (●)")
        }
        if timelineWS.attached.count > 2 {
            wsDesc.append("+\(timelineWS.attached.count - 2) more")
        }

        if !wsDesc.isEmpty {
            print("")
            print("  Workspaces: \(wsDesc.joined(separator: ", "))")
        }

        print("")
        print(TerminalUI.dim("Use '/timeline list' for all timelines, '/timeline switch' to change."))
        print("")
    }

    private func interactiveSwitch(context: ChatContext) async throws {
        let manager = CLITimelineManager(client: context.client)
        guard let selected = try await manager.showPublicTimelineSelector(
            currentTimelineId: context.timeline.id,
            allowCancel: true
        ) else {
            TerminalUI.printInfo("Cancelled.")
            return
        }

        if selected.id == context.timeline.id {
            TerminalUI.printInfo("Already in this timeline.")
            return
        }

        try await switchToTimeline(selected, context: context)
    }

    private func showHistory(context: ChatContext) async throws {
        let manager = CLITimelineManager(client: context.client)
        try await manager.browseTimeline(
            timelineId: context.timeline.id,
            title: context.timeline.title ?? "Untitled",
            kindLabel: "public"
        )
    }

    private func listTimelines(context: ChatContext) async throws {
        let timelines = CLITimelineCatalog.sortedPublicTimelines(
            try await context.client.chat.listTimelines()
        )
        if timelines.isEmpty {
            TerminalUI.printInfo("No timelines found.")
            return
        }

        print("\n" + TerminalUI.bold("Timelines:") + "\n")
        let currentId = context.timeline.id

        for timeline in timelines {
            let title = timeline.title ?? "Untitled"
            let dateStr = TerminalUI.formatDate(timeline.createdAt)
            let isCurrent = timeline.id == currentId
            let marker = isCurrent ? TerminalUI.green(" ●") : ""
            let idStr = timeline.id.uuidString.prefix(8)

            print(
                "  \(TerminalUI.dim(String(idStr)))  \(title)  \(TerminalUI.dim(dateStr))\(marker)"
            )
        }
        print("")
    }

    private func deleteTimeline(_ idStr: String, context: ChatContext) async throws {
        if context.timeline.id.uuidString.hasPrefix(idStr) {
            TerminalUI.printError("Switch to another timeline before deleting the current one.")
            return
        }

        if let uuid = UUID(uuidString: idStr) {
            try await context.client.chat.deleteTimeline(uuid)
            TerminalUI.printSuccess("Deleted timeline \(uuid.uuidString.prefix(8))")
            return
        }

        // Partial match
        let timelines = try await context.client.chat.listTimelines()
        if let match = timelines.first(where: {
            $0.id.uuidString.hasPrefix(idStr) || $0.id.uuidString.hasPrefix(idStr.uppercased())
        }) {
            if match.id == context.timeline.id {
                TerminalUI.printError("Switch to another timeline before deleting the current one.")
                return
            }
            try await context.client.chat.deleteTimeline(match.id)
            TerminalUI.printSuccess("Deleted timeline \(match.id.uuidString.prefix(8))")
        } else {
            TerminalUI.printError("Invalid timeline ID or no match: \(idStr)")
        }
    }

    private func renameTimeline(_ title: String, context: ChatContext) async throws {
        try await context.client.chat.updateTimelineTitle(title, timelineId: context.timeline.id)
        TerminalUI.printSuccess("Renamed timeline to: \(title)")
    }

    private func switchTimeline(_ idStr: String, context: ChatContext) async throws {
        let timelines = CLITimelineCatalog.sortedPublicTimelines(
            try await context.client.chat.listTimelines()
        )
        if let match = timelines.first(where: { $0.id.uuidString.hasPrefix(idStr) }) {
            try await switchToTimeline(match, context: context)
        } else {
            TerminalUI.printError("No timeline found matching: \(idStr)")
        }
    }

    private func createTimeline(_ title: String?, context: ChatContext) async throws {
        let manager = CLITimelineManager(client: context.client)
        let timeline = try await manager.createNewTimelineFlow(title: title)
        let currentAgent = await context.repl.getCurrentAgent()
        await context.repl.switchTimeline(timeline)
        if let currentAgent {
            try? await context.client.chat.attachAgent(agentId: currentAgent.id, to: timeline.id)
            await context.repl.setAgent(currentAgent)
        }
        TerminalUI.printSuccess("Switched to timeline: \(timeline.title ?? timeline.id.uuidString)")
    }

    private func switchToTimeline(_ timeline: TimelineResponse, context: ChatContext) async throws {
        let agent = try await attachedAgent(for: timeline, context: context)
        await context.repl.switchTimeline(timeline)
        await context.repl.setAgent(agent)
        TerminalUI.printSuccess("Switched to timeline: \(timeline.title ?? timeline.id.uuidString)")
    }

    private func attachedAgent(
        for timeline: TimelineResponse,
        context: ChatContext
    ) async throws -> AgentInstance? {
        guard let agentId = timeline.attachedAgentInstanceId else { return nil }
        return try await context.client.chat.getAgentInstance(id: agentId)
    }
}
