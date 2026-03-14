import Foundation
import MonadShared

public extension TimelineManager {
    // MARK: - Workspace Management

    func attachWorkspace(_ workspaceId: UUID, to timelineId: UUID) async throws {
        var timeline: Timeline

        if let memoryTimeline = timelines[timelineId] {
            timeline = memoryTimeline
        } else if let dbTimeline = try await timelineStore.fetchTimeline(id: timelineId) {
            timeline = dbTimeline
        } else {
            throw TimelineError.timelineNotFound
        }

        if !timeline.attachedWorkspaceIds.contains(workspaceId) {
            timeline.attachedWorkspaceIds.append(workspaceId)
        }

        timeline.updatedAt = Date()

        if timelines[timelineId] != nil {
            timelines[timelineId] = timeline
        }
        try await timelineStore.saveTimeline(timeline)

        if let toolManager = toolManagers[timelineId] {
            if let ws = try? await workspaceManager.getWorkspace(id: workspaceId) {
                await toolManager.registerWorkspace(ws)
            }
        }
    }

    func detachWorkspace(_ workspaceId: UUID, from timelineId: UUID) async throws {
        var timeline: Timeline

        if let memoryTimeline = timelines[timelineId] {
            timeline = memoryTimeline
        } else if let dbTimeline = try await timelineStore.fetchTimeline(id: timelineId) {
            timeline = dbTimeline
        } else {
            throw TimelineError.timelineNotFound
        }

        timeline.attachedWorkspaceIds.removeAll { $0 == workspaceId }
        timeline.updatedAt = Date()

        if timelines[timelineId] != nil {
            timelines[timelineId] = timeline
        }

        try await timelineStore.saveTimeline(timeline)

        if let toolManager = toolManagers[timelineId] {
            await toolManager.unregisterWorkspace(workspaceId)
        }
    }

    func getWorkspaces(for timelineId: UUID) async -> (primary: WorkspaceReference?, attached: [WorkspaceReference])? {
        let attachedIds: [UUID]

        if let timeline = timelines[timelineId] {
            attachedIds = timeline.attachedWorkspaceIds
        } else if let timeline = try? await timelineStore.fetchTimeline(id: timelineId) {
            attachedIds = timeline.attachedWorkspaceIds
        } else {
            return nil
        }

        var attached: [WorkspaceReference] = []
        for aid in attachedIds {
            if var ws = try? await getWorkspace(aid) {
                if ws.hostType == .server, let path = ws.rootPath {
                    if !FileManager.default.fileExists(atPath: path) {
                        ws.status = .missing
                    }
                }
                attached.append(ws)
            }
        }

        return (nil, attached)
    }

    func restoreWorkspace(_ id: UUID) async throws {
        guard let workspace = try await getWorkspace(id) else {
            throw TimelineError.timelineNotFound
        }

        if workspace.hostType == .server, let path = workspace.rootPath {
            let timelineWorkspaceURL = URL(fileURLWithPath: path)
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: path) {
                try fileManager.createDirectory(at: timelineWorkspaceURL, withIntermediateDirectories: true)

                if workspace.uri.host == "monad-server", workspace.uri.path.hasPrefix("/timelines/") {
                    let notesDir = timelineWorkspaceURL.appendingPathComponent("Notes", isDirectory: true)
                    try? fileManager.createDirectory(at: notesDir, withIntermediateDirectories: true)
                }
            }
        }
    }

    func getWorkspace(_ id: UUID) async throws -> WorkspaceReference? {
        return try await workspaceStore.fetchWorkspace(id: id, includeTools: true)
    }
}
