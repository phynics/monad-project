import Foundation
import GRDB
import Logging
import MonadCore

public actor SessionManager {
    private var sessions: [UUID: ConversationSession] = [:]
    private var contextManagers: [UUID: ContextManager] = [:]
    private var toolManagers: [UUID: SessionToolManager] = [:]
    private var toolExecutors: [UUID: ToolExecutor] = [:]
    private var documentManagers: [UUID: DocumentManager] = [:]
    private var toolContextSessions: [UUID: ToolContextSession] = [:]

    private let persistenceService: any PersistenceServiceProtocol
    private let embeddingService: any EmbeddingService
    private let llmService: any LLMServiceProtocol
    private let workspaceRoot: URL

    public init(
        persistenceService: any PersistenceServiceProtocol,
        embeddingService: any EmbeddingService,
        llmService: any LLMServiceProtocol,
        workspaceRoot: URL
    ) {
        self.persistenceService = persistenceService
        self.embeddingService = embeddingService
        self.llmService = llmService
        self.workspaceRoot = workspaceRoot
    }

    public func createSession(title: String = "New Conversation") async throws
        -> ConversationSession
    {
        let sessionId = UUID()
        
        // 1. Create Workspace
        let sessionWorkspaceURL = workspaceRoot.appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(sessionId.uuidString, isDirectory: true)
        
        try FileManager.default.createDirectory(at: sessionWorkspaceURL, withIntermediateDirectories: true)
        
        let workspace = Workspace(
            uri: .serverSession(sessionId),
            hostType: .server,
            rootPath: sessionWorkspaceURL.path,
            trustLevel: .full
        )
        
        try await persistenceService.databaseWriter.write { db in
            try workspace.insert(db)
        }

        // 2. Create Session
        var session = ConversationSession(
            id: sessionId, 
            title: title,
            primaryWorkspaceId: workspace.id
        )
        session.workingDirectory = sessionWorkspaceURL.path
        
        sessions[session.id] = session

        let contextManager = ContextManager(
            persistenceService: persistenceService, 
            embeddingService: embeddingService,
            workspaceRoot: sessionWorkspaceURL
        )
        contextManagers[session.id] = contextManager

        let documentManager = DocumentManager()
        documentManagers[session.id] = documentManager

        let toolContextSession = ToolContextSession()
        toolContextSessions[session.id] = toolContextSession

        let jobQueueContext = JobQueueContext(persistenceService: persistenceService)

        // Setup Tools for session
        let toolManager = await createToolManager(
            for: session, jailRoot: sessionWorkspaceURL.path, documentManager: documentManager, toolContextSession: toolContextSession,
            jobQueueContext: jobQueueContext)
        toolManagers[session.id] = toolManager

        let toolExecutor = ToolExecutor(
            toolManager: toolManager,
            contextSession: toolContextSession,
            jobQueueContext: jobQueueContext
        )
        toolExecutors[session.id] = toolExecutor

        // Ensure session exists in database for foreign key constraints
        try await persistenceService.saveSession(session)

        return session
    }

    private func createToolManager(
        for session: ConversationSession,
        jailRoot: String,
        documentManager: DocumentManager,
        toolContextSession: ToolContextSession,
        jobQueueContext: JobQueueContext
    ) async -> SessionToolManager {
        let currentWD = session.workingDirectory ?? jailRoot

        let availableTools: [any MonadCore.Tool] = [
            ExecuteSQLTool(persistenceService: persistenceService),
            // Filesystem Tools
            ChangeDirectoryTool(
                currentPath: currentWD,
                root: jailRoot,
                onChange: { newPath in
                    // Update working directory logic would need a way to communicate back to SessionManager
                    // For now, in Server we might want to handle this differently or just let it be.
                }),
            ListDirectoryTool(currentDirectory: currentWD, jailRoot: jailRoot),
            FindFileTool(currentDirectory: currentWD, jailRoot: jailRoot),
            SearchFileContentTool(currentDirectory: currentWD, jailRoot: jailRoot),
            SearchFilesTool(currentDirectory: currentWD, jailRoot: jailRoot),
            ReadFileTool(currentDirectory: currentWD, jailRoot: jailRoot),
            InspectFileTool(currentDirectory: currentWD, jailRoot: jailRoot),
            // Document Tools
            LoadDocumentTool(documentManager: documentManager),
            UnloadDocumentTool(documentManager: documentManager),
            SwitchDocumentViewTool(documentManager: documentManager),
            FindExcerptsTool(llmService: llmService, documentManager: documentManager),
            EditDocumentSummaryTool(documentManager: documentManager),
            MoveDocumentExcerptTool(documentManager: documentManager),
            LaunchSubagentTool(llmService: llmService, documentManager: documentManager),
            // Job Queue Gateway
            JobQueueGatewayTool(context: jobQueueContext, contextSession: toolContextSession),
        ]

        return SessionToolManager(
            availableTools: availableTools, contextSession: toolContextSession)
    }

    public func getSession(id: UUID) -> ConversationSession? {
        guard var session = sessions[id] else { return nil }
        session.updatedAt = Date()
        sessions[id] = session
        return session
    }

    public func getContextManager(for sessionId: UUID) -> ContextManager? {
        return contextManagers[sessionId]
    }

    public func getToolExecutor(for sessionId: UUID) -> ToolExecutor? {
        return toolExecutors[sessionId]
    }

    public func getToolManager(for sessionId: UUID) -> SessionToolManager? {
        return toolManagers[sessionId]
    }

    public func getDocumentManager(for sessionId: UUID) -> DocumentManager? {
        return documentManagers[sessionId]
    }

    public func deleteSession(id: UUID) {
        sessions.removeValue(forKey: id)
        contextManagers.removeValue(forKey: id)
        toolManagers.removeValue(forKey: id)
        toolExecutors.removeValue(forKey: id)
        documentManagers.removeValue(forKey: id)
        toolContextSessions.removeValue(forKey: id)
    }

    public func getHistory(for sessionId: UUID) async throws -> [Message] {
        let conversationMessages = try await persistenceService.fetchMessages(for: sessionId)
        return conversationMessages.map { $0.toMessage() }
    }

    public func getPersistenceService() -> any PersistenceServiceProtocol {
        return persistenceService
    }

    public func listSessions() async throws -> [ConversationSession] {
        return try await persistenceService.fetchAllSessions(includeArchived: false)
    }

    public func cleanupStaleSessions(maxAge: TimeInterval) {
        let now = Date()
        let staleIds = sessions.values.filter { session in
            return now.timeIntervalSince(session.updatedAt) > maxAge
        }.map { $0.id }

        for id in staleIds {
            deleteSession(id: id)
        }
    }

    // MARK: - Workspace Management

    public func attachWorkspace(_ workspaceId: UUID, to sessionId: UUID, isPrimary: Bool = false)
        async throws
    {
        guard var session = sessions[sessionId] else {
            // Try enabling recovery from DB if not in memory?
            // For now, assume session must be active/loaded. Or load it.
            // If we fetch from DB, we should cache it.
            // But existing getSession loads from memory.
            // Let's rely on memory first, if checking implementation, createSession puts in memory.
            throw SessionError.sessionNotFound  // Simple error for now
        }

        if isPrimary {
            session.primaryWorkspaceId = workspaceId
        } else {
            // Add to attached if not already there and not primary
            if session.primaryWorkspaceId != workspaceId {
                var currentAttached = session.attachedWorkspaces
                if !currentAttached.contains(workspaceId) {
                    currentAttached.append(workspaceId)
                    // Update the JSON string backing via init or setter?
                    // ConversationSession properties are var, but attachedWorkspaces is computed.
                    // I access attachedWorkspaceIds directly or use a helper?
                    // In ConversationSession, I added `attachedWorkspaceIds: String`.
                    // helper `attachedWorkspaces` is GET only.
                    // I need to update `attachedWorkspaceIds` string manually.
                    if let data = try? JSONEncoder().encode(currentAttached),
                        let str = String(data: data, encoding: .utf8)
                    {
                        session.attachedWorkspaceIds = str
                    }
                }
            }
        }

        session.updatedAt = Date()
        sessions[sessionId] = session
        try await persistenceService.saveSession(session)
    }

    public func detachWorkspace(_ workspaceId: UUID, from sessionId: UUID) async throws {
        guard var session = sessions[sessionId] else {
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
        sessions[sessionId] = session
        try await persistenceService.saveSession(session)
    }

    public func getWorkspaces(for sessionId: UUID) -> (primary: UUID?, attached: [UUID])? {
        guard let session = sessions[sessionId] else { return nil }
        return (session.primaryWorkspaceId, session.attachedWorkspaces)
    }

    public func getWorkspace(_ id: UUID) async throws -> Workspace? {
        return try await persistenceService.databaseWriter.read { db in
            try Workspace.fetchOne(db, key: id)
        }
    }

    public func findWorkspaceForTool(_ tool: ToolReference, in workspaceIds: [UUID]) async throws
        -> UUID?
    {
        return try await persistenceService.databaseWriter.read { db in
            // Identify tool ID
            let toolId = tool.toolId

            // Find which workspace in the list contains this tool
            // We use SQL because constructing a complex filter with GRDB for "IN" clause and "toolId" is easier this way or using filter.

            // SELECT workspaceId FROM workspaceTool WHERE toolId = ? AND workspaceId IN (?, ?, ...)
            let exists =
                try WorkspaceTool
                .filter(Column("toolId") == toolId)
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchOne(db)

            return exists?.workspaceId
        }
    }

    public func getAggregatedTools(for sessionId: UUID) async throws -> [ToolReference] {
        guard let session = sessions[sessionId] else { return [] }

        var ids: [UUID] = []
        if let p = session.primaryWorkspaceId { ids.append(p) }
        ids.append(contentsOf: session.attachedWorkspaces)

        let workspaceIds = ids

        guard !workspaceIds.isEmpty else { return [] }

        return try await persistenceService.databaseWriter.read { db in
            let tools =
                try WorkspaceTool
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchAll(db)

            return try tools.map { try $0.toToolReference() }
        }
    }
}

public enum SessionError: Error {
    case sessionNotFound
}
