import ArgumentParser
import Foundation
import Logging
import MonadClient
import PKShared
import MonadShared

struct CLITimelineManager {
    let client: MonadClient
    private let input: @Sendable () -> String?
    private let logger = Logger.module(named: "timeline-manager")

    init(
        client: MonadClient,
        input: @escaping @Sendable () -> String? = { readLine() }
    ) {
        self.client = client
        self.input = input
    }

    /// Resolves which timeline to use (Resume or New)
    func resolveTimeline(
        explicitId: String?,
        localConfig: LocalConfig
    ) async throws -> Timeline {
        if let timelineId = explicitId, let uuid = UUID(uuidString: timelineId) {
            do {
                let timeline = try await client.chat.getTimeline(id: uuid)
                TerminalUI.printInfo("Resuming timeline \(uuid.uuidString.prefix(8))...")
                return timeline
            } catch {
                TerminalUI.printError("Timeline not found: \(timelineId)")
                throw ExitCode.failure
            }
        }

        if let lastId = localConfig.lastSessionId, let uuid = UUID(uuidString: lastId) {
            do {
                let timeline = try await client.chat.getTimeline(id: uuid)
                TerminalUI.printInfo("Resumed timeline \(uuid.uuidString.prefix(8))")
                return timeline
            } catch {
                logger.debug("Stale session in local config: \(uuid.uuidString). Proceeding to menu.")
            }
        }

        return try await showTimelineMenu()
    }

    private func showTimelineMenu() async throws -> Timeline {
        print("")
        print(TerminalUI.bold("Choose a public timeline to start."))
        guard let timeline = try await showPublicTimelineSelector(
            currentTimelineId: nil,
            allowCancel: true
        ) else {
            throw ExitCode.failure
        }
        return timeline
    }

    func createNewTimelineFlow(title: String? = nil) async throws -> Timeline {
        let timeline = try await client.chat.createTimeline(title: title)
        TerminalUI.printSuccess("Created new timeline \(timeline.id.uuidString.prefix(8))")
        return timeline
    }

    func showPublicTimelineSelector(
        currentTimelineId: UUID?,
        allowCancel: Bool
    ) async throws -> Timeline? {
        while true {
            let timelines = CLITimelineCatalog.sortedPublicTimelines(try await client.chat.listTimelines())

            if timelines.isEmpty {
                TerminalUI.printInfo("No public timelines found. Creating one.")
                return try await createNewTimelineFlow()
            }

            print("")
            print(TerminalUI.bold("Public Timelines"))
            print("")

            for (idx, timeline) in timelines.enumerated() {
                let title = timeline.title ?? "Untitled"
                let marker = timeline.id == currentTimelineId ? TerminalUI.green("●") : " "
                let id = timeline.id.uuidString.prefix(8)
                let date = TerminalUI.formatDate(timeline.updatedAt)
                print("  \(idx + 1). \(marker) \(title)  \(TerminalUI.dim("#\(id) • \(date)"))")
            }

            print("")
            print("Actions: <number> switch, p <number> peek, d <number> delete, c create\(allowCancel ? ", q cancel" : "")")
            print("Select action: ", terminator: "")

            let response = input()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if response.isEmpty, let first = timelines.first {
                return first
            }
            if allowCancel, response.lowercased() == "q" {
                return nil
            }
            if response.lowercased() == "c" {
                return try await createTimelineWithPrompt()
            }

            let parts = response.split(separator: " ", maxSplits: 1).map(String.init)
            if let selected = resolveIndexedTimelineSelection(parts, timelines: timelines) {
                switch parts.first?.lowercased() {
                case "p":
                    try await browseTimeline(
                        timelineId: selected.id,
                        title: selected.title ?? "Untitled",
                        kindLabel: "public"
                    )
                    continue
                case "d":
                    try await deleteTimelineWithConfirmation(
                        selected,
                        currentTimelineId: currentTimelineId
                    )
                    continue
                default:
                    return selected
                }
            }

            TerminalUI.printError("Invalid selection.")
        }
    }

    func browseTimeline(
        timelineId: UUID,
        title: String,
        kindLabel: String,
        pageSize: Int = 10
    ) async throws {
        let messages = try await client.chat.getHistory(timelineId: timelineId)
        if messages.isEmpty {
            TerminalUI.printInfo("No messages in this \(kindLabel) timeline yet.")
            return
        }

        var page = 0
        let totalPages = max(1, Int(ceil(Double(messages.count) / Double(pageSize))))

        while true {
            let start = page * pageSize
            let end = min(start + pageSize, messages.count)

            print("")
            print(TerminalUI.bold(title) + TerminalUI.dim("  [\(kindLabel) #\(timelineId.uuidString.prefix(8))]"))
            print(TerminalUI.dim("Messages \(start + 1)-\(end) of \(messages.count) • page \(page + 1)/\(totalPages)"))
            print("")

            for message in messages[start ..< end] {
                render(message: message)
                print("")
            }

            print("Peek actions: n next, p previous, q quit [q]: ", terminator: "")
            let choice = input()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "q"
            switch choice {
            case "n" where page + 1 < totalPages:
                page += 1
            case "p" where page > 0:
                page -= 1
            case "q", "":
                return
            default:
                TerminalUI.printError("Invalid selection.")
            }
        }
    }

    /// Handles re-attachment of client-side workspaces
    func handleWorkspaceReattachment(timeline: Timeline, localConfig: LocalConfig) async {
        guard let workspaces = localConfig.clientWorkspaces, !workspaces.isEmpty else { return }
        guard let clientId = RegistrationManager.shared.getIdentity()?.clientId else { return }
        guard promptForReattachment(workspaces: workspaces) else { return }

        let allWorkspaces = await fetchAllWorkspaces()
        let updatedWorkspaces = await reattachWorkspaces(
            workspaces, allWorkspaces: allWorkspaces, clientId: clientId, timelineId: timeline.id
        )

        LocalConfigManager.shared.updateClientWorkspaces(updatedWorkspaces)
    }

    private func promptForReattachment(workspaces: [String: String]) -> Bool {
        print("")
        TerminalUI.printInfo("Found previously attached client-side workspaces:")
        for (uri, _) in workspaces {
            print("  - \(uri)")
        }

        print("")
        print("Re-attach these workspaces? (y/n) [y]: ", terminator: "")
        let response = input()?.lowercased().trimmingCharacters(in: .whitespaces) ?? "y"
        return response == "y" || response == ""
    }

    private func fetchAllWorkspaces() async -> [WorkspaceReference] {
        do {
            return try await client.workspace.listWorkspaces()
        } catch {
            logger.error("Failed to list workspaces during re-attachment: \(error)")
            return []
        }
    }

    private func reattachWorkspaces(
        _ workspaces: [String: String],
        allWorkspaces: [WorkspaceReference],
        clientId: UUID,
        timelineId: UUID
    ) async -> [String: String] {
        var updatedWorkspaces = workspaces

        for (uri, _) in workspaces {
            do {
                let wsId = try await resolveOrCreateWorkspace(
                    uri: uri, allWorkspaces: allWorkspaces, clientId: clientId
                )
                try await client.workspace.attachWorkspace(wsId, to: timelineId)
                try await client.workspace.syncWorkspaceTools(
                    ClientConstants.readOnlyToolReferences, workspaceId: wsId
                )
                updatedWorkspaces[uri] = wsId.uuidString
                TerminalUI.printSuccess("Attached \(uri)")
            } catch {
                logger.error("Failed to re-attach workspace \(uri): \(error)")
                TerminalUI.printError("Failed to re-attach \(uri): \(error.localizedDescription)")
                updatedWorkspaces.removeValue(forKey: uri)
            }
        }

        return updatedWorkspaces
    }

    private func resolveOrCreateWorkspace(
        uri: String,
        allWorkspaces: [WorkspaceReference],
        clientId: UUID
    ) async throws -> UUID {
        if let existing = allWorkspaces.first(where: { $0.uri.description == uri }) {
            return existing.id
        }
        guard let workspaceURI = WorkspaceURI(parsing: uri) else {
            throw MonadClientError.unknown("Failed to parse URI for re-attachment: \(uri)")
        }
        let rootPath = workspaceURI.path
        let newWs = try await client.workspace.createWorkspace(
            uri: workspaceURI,
            location: .attached,
            originId: clientId,
            rootPath: rootPath,
            trustLevel: .readOnly
        )
        return newWs.id
    }

    private func createTimelineWithPrompt() async throws -> Timeline {
        print("Title (optional): ", terminator: "")
        let title = input()?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await createNewTimelineFlow(title: title?.isEmpty == true ? nil : title)
    }

    private func resolveIndexedTimelineSelection(
        _ parts: [String],
        timelines: [TimelineResponse]
    ) -> TimelineResponse? {
        let selectionToken: String
        if let first = parts.first?.lowercased(), ["p", "d"].contains(first) {
            guard parts.count == 2 else { return nil }
            selectionToken = parts[1]
        } else if let first = parts.first {
            selectionToken = first
        } else {
            return nil
        }

        guard let index = Int(selectionToken), index > 0, index <= timelines.count else {
            return nil
        }
        return timelines[index - 1]
    }

    private func deleteTimelineWithConfirmation(
        _ timeline: TimelineResponse,
        currentTimelineId: UUID?
    ) async throws {
        if timeline.id == currentTimelineId {
            TerminalUI.printError("Switch to another timeline before deleting the current one.")
            return
        }

        let title = timeline.title ?? "Untitled"
        print("Delete \"\(title)\"? (y/N): ", terminator: "")
        let confirmation = input()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "n"
        guard confirmation == "y" else {
            TerminalUI.printInfo("Deletion cancelled.")
            return
        }

        try await client.chat.deleteTimeline(timeline.id)
        TerminalUI.printSuccess("Deleted timeline \(timeline.id.uuidString.prefix(8))")
    }

    private func render(message: Message) {
        switch message.role {
        case .user:
            print("\(TerminalUI.userColor("You:"))")
            print(message.content)
        case .assistant:
            print("\(TerminalUI.assistantColor("Assistant:"))")
            print(message.content)
        case .system:
            print("\(TerminalUI.systemColor("System:"))")
            print(message.content)
        case .tool:
            print("\(TerminalUI.toolColor("Tool:"))")
            print(message.content)
        case .summary:
            print("\(TerminalUI.dim("Summary:"))")
            print(message.content)
        }
    }
}
