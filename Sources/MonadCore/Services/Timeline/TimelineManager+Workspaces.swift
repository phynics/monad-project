import MonadShared
import Foundation

extension TimelineManager {
    // MARK: - Workspace Management

    public func attachWorkspace(_ workspaceId: UUID, to timelineId: UUID, isPrimary: Bool = false)
        async throws {
        var timeline: Timeline

        if let memoryTimeline = timelines[timelineId] {
            timeline = memoryTimeline
        } else if let dbTimeline = try await timelineStore.fetchTimeline(id: timelineId) {
            timeline = dbTimeline
        } else {
            throw TimelineError.timelineNotFound
        }

        if isPrimary {
            timeline.primaryWorkspaceId = workspaceId
        } else {
            // Add to attached if not already there and not primary
            if timeline.primaryWorkspaceId != workspaceId {
                var currentAttached = timeline.attachedWorkspaces
                if !currentAttached.contains(workspaceId) {
                    currentAttached.append(workspaceId)
                    if let data = try? JSONEncoder().encode(currentAttached),
                        let str = String(data: data, encoding: .utf8) {
                        timeline.attachedWorkspaceIds = str
                    }
                }
            }
        }

        timeline.updatedAt = Date()

        // Update in-memory if present
        if timelines[timelineId] != nil {
            timelines[timelineId] = timeline
        }
        // Always save to DB
        try await timelineStore.saveTimeline(timeline)

        // Update ToolManager
        if let toolManager = toolManagers[timelineId] {
            if let ws = try? await workspaceManager.getWorkspace(id: workspaceId) {
                await toolManager.registerWorkspace(ws)
            }
        }

    }

    public func detachWorkspace(_ workspaceId: UUID, from timelineId: UUID) async throws {
        var timeline: Timeline

        if let memoryTimeline = timelines[timelineId] {
            timeline = memoryTimeline
        } else if let dbTimeline = try await timelineStore.fetchTimeline(id: timelineId) {
            timeline = dbTimeline
        } else {
            throw TimelineError.timelineNotFound
        }

        if timeline.primaryWorkspaceId == workspaceId {
            timeline.primaryWorkspaceId = nil
        } else {
            var currentAttached = timeline.attachedWorkspaces
            if let index = currentAttached.firstIndex(of: workspaceId) {
                currentAttached.remove(at: index)

                if let data = try? JSONEncoder().encode(currentAttached),
                    let str = String(data: data, encoding: .utf8) {
                    timeline.attachedWorkspaceIds = str
                }
            }
        }

        timeline.updatedAt = Date()

        // Update in-memory if present
        if timelines[timelineId] != nil {
            timelines[timelineId] = timeline
        }

        try await timelineStore.saveTimeline(timeline)

        // Update ToolManager
        if let toolManager = toolManagers[timelineId] {
             await toolManager.unregisterWorkspace(workspaceId)
        }
    }

    public func getWorkspaces(for timelineId: UUID) async -> (primary: WorkspaceReference?, attached: [WorkspaceReference])? {
        var primaryId: UUID?
        var attachedIds: [UUID] = []

        if let timeline = timelines[timelineId] {
            primaryId = timeline.primaryWorkspaceId
            attachedIds = timeline.attachedWorkspaces
        } else if let timeline = try? await timelineStore.fetchTimeline(id: timelineId) {
            primaryId = timeline.primaryWorkspaceId
            attachedIds = timeline.attachedWorkspaces
        } else {
            return nil
        }

        var primary: WorkspaceReference?
        if let pid = primaryId {
            if var primaryWorkspace = try? await getWorkspace(pid) {
                if primaryWorkspace.hostType == .server, let path = primaryWorkspace.rootPath {
                   if !FileManager.default.fileExists(atPath: path) {
                       primaryWorkspace.status = .missing
                   }
                }
                primary = primaryWorkspace
            }
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

        return (primary, attached)
    }

    public func restoreWorkspace(_ id: UUID) async throws {
        guard let workspace = try await getWorkspace(id) else {
            throw TimelineError.timelineNotFound // Or workspaceNotFound
        }

        if workspace.hostType == .server, let path = workspace.rootPath {
            let timelineWorkspaceURL = URL(fileURLWithPath: path)
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: path) {
                try fileManager.createDirectory(at: timelineWorkspaceURL, withIntermediateDirectories: true)

                if workspace.uri.host == "monad-server" && workspace.uri.path.hasPrefix("/timelines/") {
                     let notesDir = timelineWorkspaceURL.appendingPathComponent("Notes", isDirectory: true)
                     try? fileManager.createDirectory(at: notesDir, withIntermediateDirectories: true)
                }
            }
        }
    }

    public func getWorkspace(_ id: UUID) async throws -> WorkspaceReference? {
        return try await workspaceStore.fetchWorkspace(id: id, includeTools: true)
    }
}
