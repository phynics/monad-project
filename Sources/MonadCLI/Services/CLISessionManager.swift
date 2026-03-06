import Foundation
import ArgumentParser
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
                print("  [\(idx+1)] \(title) (\(timeline.id.uuidString.prefix(8))) - \(date)")
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

        print("")
        TerminalUI.printInfo("Found previously attached client-side workspaces:")

        for (uri, _) in workspaces {
            print("  - \(uri)")
        }

        print("")
        print("Re-attach these workspaces? (y/n) [y]: ", terminator: "")
        let response = readLine()?.lowercased().trimmingCharacters(in: .whitespaces) ?? "y"

        if response == "y" || response == "" {
            for (uri, wsIdStr) in workspaces {
                guard let wsId = UUID(uuidString: wsIdStr) else { continue }

                do {
                    // Verify workspace exists on server and is linked to this client
                    // Actually, we can just attempt to attach. If it fails, it might be gone.
                    try await client.workspace.attachWorkspace(wsId, to: timeline.id, isPrimary: false)
                    TerminalUI.printSuccess("Attached \(uri)")
                } catch {
                    TerminalUI.printError("Failed to re-attach \(uri): \(error.localizedDescription)")
                }
            }
        }
    }
}
