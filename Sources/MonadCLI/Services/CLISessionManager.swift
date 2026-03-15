import ArgumentParser
import Foundation
import Logging
import MonadClient
import MonadShared

struct CLITimelineManager {
    let client: MonadClient
    private let logger = Logger.module(named: "timeline-manager")

    /// Resolves which timeline to use (Resume or New)
    func resolveTimeline(
        explicitId: String?,
        localConfig: LocalConfig
    ) async throws -> Timeline {
        // 1. Try to resume from flag
        if let timelineId = explicitId, let uuid = UUID(uuidString: timelineId) {
            do {
                _ = try await client.chat.getHistory(timelineId: uuid)
                TerminalUI.printInfo("Resuming timeline \(uuid.uuidString.prefix(8))...")
                return Timeline(id: uuid, title: nil)
            } catch {
                TerminalUI.printError("Timeline not found: \(timelineId)")
                throw ExitCode.failure
            }
        }

        // 2. Try to resume from config (automatic)
        if let lastId = localConfig.lastSessionId, let uuid = UUID(uuidString: lastId) {
            do {
                _ = try await client.chat.getHistory(timelineId: uuid)
                TerminalUI.printInfo("Resumed timeline \(uuid.uuidString.prefix(8))")
                return Timeline(id: uuid, title: nil)
            } catch {
                // Stale config, ignore and proceed to menu
                logger.debug("Stale session in local config: \(uuid.uuidString). Proceeding to menu.")
            }
        }

        // 3. Interactive Menu
        return try await showTimelineMenu()
    }

    private func showTimelineMenu() async throws -> Timeline {
        print("")
        print(TerminalUI.bold("No active timeline found."))
        print("  [1] Create New Timeline")
        print("  [2] List Existing Timelines")
        print("")
        print("Select an option [1]: ", terminator: "")

        let choice = readLine()?.trimmingCharacters(in: .whitespaces) ?? "1"

        if choice == "2" {
            let timelines = try await client.chat.listTimelines()
            if timelines.isEmpty {
                print("No timelines found. Creating new one.")
                return try await createNewTimelineFlow()
            }

            print("")
            for (idx, timeline) in timelines.enumerated() {
                let title = timeline.title ?? "Untitled"
                let date = TerminalUI.formatDate(timeline.updatedAt)
                print("  [\(idx + 1)] \(title) (\(timeline.id.uuidString.prefix(8))) - \(date)")
            }
            print("")
            print("Select a timeline [1]: ", terminator: "")
            let indexStr = readLine()?.trimmingCharacters(in: .whitespaces) ?? "1"
            let index = (Int(indexStr) ?? 1) - 1

            if index >= 0 && index < timelines.count {
                let timeline = timelines[index]
                return Timeline(id: timeline.id, title: timeline.title)
            } else {
                TerminalUI.printError("Invalid selection.")
                throw ExitCode.failure
            }
        } else {
            return try await createNewTimelineFlow()
        }
    }

    private func createNewTimelineFlow() async throws -> Timeline {
        let timeline = try await client.chat.createTimeline()
        TerminalUI.printSuccess("Created new timeline \(timeline.id.uuidString.prefix(8))")
        return timeline
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
        let response = readLine()?.lowercased().trimmingCharacters(in: .whitespaces) ?? "y"
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
            hostType: .client,
            ownerId: clientId,
            rootPath: rootPath,
            trustLevel: .readOnly
        )
        return newWs.id
    }
}
