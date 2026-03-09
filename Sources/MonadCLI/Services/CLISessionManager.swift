import ArgumentParser
import Foundation
import MonadClient
import MonadShared

struct CLITimelineManager {
    let client: MonadClient

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

        print("")
        TerminalUI.printInfo("Found previously attached client-side workspaces:")
        for (uri, _) in workspaces {
            print("  - \(uri)")
        }

        print("")
        print("Re-attach these workspaces? (y/n) [y]: ", terminator: "")
        let response = readLine()?.lowercased().trimmingCharacters(in: .whitespaces) ?? "y"
        guard response == "y" || response == "" else { return }

        let allWorkspaces = (try? await client.workspace.listWorkspaces()) ?? []
        var updatedWorkspaces = workspaces

        for (uri, _) in workspaces {
            do {
                // Find workspace by URI or recreate it — never attach by stale ID
                let wsId: UUID
                if let existing = allWorkspaces.first(where: { $0.uri.description == uri }) {
                    wsId = existing.id
                } else {
                    guard let workspaceURI = WorkspaceURI(parsing: uri) else { continue }
                    let rootPath = URL(string: uri).map { $0.path }
                    let newWs = try await client.workspace.createWorkspace(
                        uri: workspaceURI,
                        hostType: .client,
                        ownerId: clientId,
                        rootPath: rootPath,
                        trustLevel: .readOnly
                    )
                    wsId = newWs.id
                }

                try await client.workspace.attachWorkspace(wsId, to: timeline.id, isPrimary: false)
                try await client.workspace.syncWorkspaceTools(
                    ClientConstants.readOnlyToolReferences, workspaceId: wsId
                )
                updatedWorkspaces[uri] = wsId.uuidString
                TerminalUI.printSuccess("Attached \(uri)")
            } catch {
                TerminalUI.printError("Failed to re-attach \(uri): \(error.localizedDescription)")
                updatedWorkspaces.removeValue(forKey: uri)
            }
        }

        LocalConfigManager.shared.updateClientWorkspaces(updatedWorkspaces)
    }
}
