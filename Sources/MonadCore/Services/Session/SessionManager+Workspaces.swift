import Foundation
import GRDB

extension SessionManager {
    // MARK: - Workspace Management

    public func attachWorkspace(_ workspaceId: UUID, to sessionId: UUID, isPrimary: Bool = false)
        async throws
    {
        var session: ConversationSession

        if let memorySession = sessions[sessionId] {
            session = memorySession
        } else if let dbSession = try await persistenceService.fetchSession(id: sessionId) {
            session = dbSession
        } else {
            throw SessionError.sessionNotFound
        }

        if isPrimary {
            session.primaryWorkspaceId = workspaceId
        } else {
            // Add to attached if not already there and not primary
            if session.primaryWorkspaceId != workspaceId {
                var currentAttached = session.attachedWorkspaces
                if !currentAttached.contains(workspaceId) {
                    currentAttached.append(workspaceId)
                    if let data = try? JSONEncoder().encode(currentAttached),
                        let str = String(data: data, encoding: .utf8)
                    {
                        session.attachedWorkspaceIds = str
                    }
                }
            }
        }

        session.updatedAt = Date()

        // Update in-memory if present
        if sessions[sessionId] != nil {
            sessions[sessionId] = session
        }
        // Always save to DB
        try await persistenceService.saveSession(session)
        
        // Update ToolManager
        if let toolManager = toolManagers[sessionId] {
             if let wsRef = try? await getWorkspace(workspaceId) {
                  if let ws = try? WorkspaceFactory.create(from: wsRef, connectionManager: connectionManager) {
                      await toolManager.registerWorkspace(ws)
                  }
             }
        }
    }

    public func detachWorkspace(_ workspaceId: UUID, from sessionId: UUID) async throws {
        var session: ConversationSession

        if let memorySession = sessions[sessionId] {
            session = memorySession
        } else if let dbSession = try await persistenceService.fetchSession(id: sessionId) {
            session = dbSession
        } else {
            throw SessionError.sessionNotFound
        }

        if session.primaryWorkspaceId == workspaceId {
            session.primaryWorkspaceId = nil
        } else {
            var currentAttached = session.attachedWorkspaces
            if let index = currentAttached.firstIndex(of: workspaceId) {
                currentAttached.remove(at: index)

                if let data = try? JSONEncoder().encode(currentAttached),
                    let str = String(data: data, encoding: .utf8)
                {
                    session.attachedWorkspaceIds = str
                }
            }
        }

        session.updatedAt = Date()

        // Update in-memory if present
        if sessions[sessionId] != nil {
            sessions[sessionId] = session
        }

        try await persistenceService.saveSession(session)
        
        // Update ToolManager
        if let toolManager = toolManagers[sessionId] {
             await toolManager.unregisterWorkspace(workspaceId)
        }
    }

    public func getWorkspaces(for sessionId: UUID) async -> (primary: WorkspaceReference?, attached: [WorkspaceReference])? {
        var primaryId: UUID?
        var attachedIds: [UUID] = []

        if let session = sessions[sessionId] {
            primaryId = session.primaryWorkspaceId
            attachedIds = session.attachedWorkspaces
        } else if let session = try? await persistenceService.fetchSession(id: sessionId) {
            primaryId = session.primaryWorkspaceId
            attachedIds = session.attachedWorkspaces
        } else {
            return nil
        }

        var primary: WorkspaceReference?
        if let pid = primaryId {
            if var p = try? await getWorkspace(pid) {
                if p.hostType == .server, let path = p.rootPath {
                   if !FileManager.default.fileExists(atPath: path) {
                       p.status = .missing
                   }
                }
                primary = p
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
            throw SessionError.sessionNotFound // Or workspaceNotFound
        }

        if workspace.hostType == .server, let path = workspace.rootPath {
            let sessionWorkspaceURL = URL(fileURLWithPath: path)
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: path) {
                try fileManager.createDirectory(at: sessionWorkspaceURL, withIntermediateDirectories: true)
                
                if workspace.uri.host == "monad-server" && workspace.uri.path.hasPrefix("/sessions/") {
                     let notesDir = sessionWorkspaceURL.appendingPathComponent("Notes", isDirectory: true)
                     try? fileManager.createDirectory(at: notesDir, withIntermediateDirectories: true)
                     let personasDir = sessionWorkspaceURL.appendingPathComponent("Personas", isDirectory: true)
                     try? fileManager.createDirectory(at: personasDir, withIntermediateDirectories: true)
                }
            }
        }
    }

    public func getWorkspace(_ id: UUID) async throws -> WorkspaceReference? {
        return try await persistenceService.databaseWriter.read { db in
            guard let workspace = try WorkspaceReference.fetchOne(db, key: id) else {
                return nil
            }
            
            // Load associated tools from WorkspaceTool table
            let workspaceTools = try WorkspaceTool
                .filter(Column("workspaceId") == id)
                .fetchAll(db)
            
            let toolRefs = workspaceTools.compactMap { try? $0.toToolReference() }
            
            // Create a new workspace with the tools populated
            return WorkspaceReference(
                id: workspace.id,
                uri: workspace.uri,
                hostType: workspace.hostType,
                ownerId: workspace.ownerId,
                tools: toolRefs,
                rootPath: workspace.rootPath,
                trustLevel: workspace.trustLevel,
                lastModifiedBy: workspace.lastModifiedBy,
                status: workspace.status,
                createdAt: workspace.createdAt
            )
        }
    }
}
