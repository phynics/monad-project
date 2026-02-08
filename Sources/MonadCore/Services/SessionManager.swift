import Foundation
import GRDB
import Logging
import GRDB
import Logging

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

    public func createSession(title: String = "New Conversation", persona: String? = nil)
        async throws
        -> ConversationSession
    {
        let sessionId = UUID()
        // Default persona logic
        let selectedPersona = persona ?? "Default.md"

        // 1. Create Workspace
        let sessionWorkspaceURL = workspaceRoot.appendingPathComponent(
            "sessions", isDirectory: true
        )
        .appendingPathComponent(sessionId.uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: sessionWorkspaceURL, withIntermediateDirectories: true)

        // 1.1 Create Notes directory and default note
        let notesDir = sessionWorkspaceURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        let welcomeNote =
            "# Welcome to Monad Notes\n\nThis is your personal notes space. You can create new notes and they will be part of the context."
        try welcomeNote.write(
            to: notesDir.appendingPathComponent("Welcome.md"), atomically: true, encoding: .utf8)

        let projectNote =
            "# Project Notes\n\nThis note is automatically generated to track the goals and progress of the current session. The agent will fill this in based on your requests."
        try projectNote.write(
            to: notesDir.appendingPathComponent("Project.md"), atomically: true, encoding: .utf8)

        // 1.2 Create Personas directory and default personas
        let personasDir = sessionWorkspaceURL.appendingPathComponent("Personas", isDirectory: true)
        try FileManager.default.createDirectory(at: personasDir, withIntermediateDirectories: true)

        let defaultPersonaContent = "You are Monad, an intelligent AI assistant."
        try defaultPersonaContent.write(
            to: personasDir.appendingPathComponent("Default.md"), atomically: true, encoding: .utf8)

        let productPersonaContent =
            "You are an expert AI Product Manager. You specialize in defining requirements, user stories, and product strategy."
        try productPersonaContent.write(
            to: personasDir.appendingPathComponent("ProductManager.md"), atomically: true,
            encoding: .utf8)

        let architectPersonaContent =
            "You are a Senior Software Architect. You focus on system design, scalability, and clean architecture."
        try architectPersonaContent.write(
            to: personasDir.appendingPathComponent("Architect.md"), atomically: true,
            encoding: .utf8)

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
            primaryWorkspaceId: workspace.id,
            persona: selectedPersona
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

        let jobQueueContext = JobQueueContext(persistenceService: persistenceService, sessionId: sessionId)

        // Setup Tools for session
        let toolManager = await createToolManager(
            for: session, jailRoot: sessionWorkspaceURL.path, documentManager: documentManager,
            toolContextSession: toolContextSession,
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
            CreateMemoryEdgeTool(persistenceService: persistenceService),
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

    public func hydrateSession(id: UUID) async throws {
        // If already hydrated (has tool executor), skip
        if toolExecutors[id] != nil { return }
        
        guard let session = try await persistenceService.fetchSession(id: id) else {
            throw SessionError.sessionNotFound
        }
        
        // Check if path exists
        let sessionWorkspaceURL: URL
        if let wd = session.workingDirectory {
            sessionWorkspaceURL = URL(fileURLWithPath: wd)
        } else {
             sessionWorkspaceURL = workspaceRoot.appendingPathComponent(
                "sessions", isDirectory: true
            ).appendingPathComponent(id.uuidString, isDirectory: true)
        }
        
        sessions[id] = session
        
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
        
        let jobQueueContext = JobQueueContext(persistenceService: persistenceService, sessionId: id)
        
        // Setup Tools
        let toolManager = await createToolManager(
            for: session, jailRoot: sessionWorkspaceURL.path, documentManager: documentManager,
            toolContextSession: toolContextSession,
            jobQueueContext: jobQueueContext)
        toolManagers[session.id] = toolManager
        
        let toolExecutor = ToolExecutor(
            toolManager: toolManager,
            contextSession: toolContextSession,
            jobQueueContext: jobQueueContext
        )
        toolExecutors[session.id] = toolExecutor
    }
    
    public func updateSessionPersona(id: UUID, persona: String) async throws {
        var session: ConversationSession
        if let memorySession = sessions[id] {
            session = memorySession
        } else if let dbSession = try await persistenceService.fetchSession(id: id) {
            session = dbSession
        } else {
            throw SessionError.sessionNotFound
        }

        session.persona = persona
        session.updatedAt = Date()

        if sessions[id] != nil {
            sessions[id] = session
        }
        try await persistenceService.saveSession(session)
    }

    public func updateSessionTitle(id: UUID, title: String) async throws {
        var session: ConversationSession
        if let memorySession = sessions[id] {
            session = memorySession
        } else if let dbSession = try await persistenceService.fetchSession(id: id) {
            session = dbSession
        } else {
            throw SessionError.sessionNotFound
        }

        session.title = title
        session.updatedAt = Date()

        if sessions[id] != nil {
            sessions[id] = session
        }
        try await persistenceService.saveSession(session)
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

    public func listPersonas() -> [Persona] {
        return [
            Persona(id: "Default.md", content: "You are Monad, an intelligent AI assistant."),
            Persona(
                id: "ProductManager.md",
                content:
                    "You are an expert AI Product Manager. You specialize in defining requirements, user stories, and product strategy."
            ),
            Persona(
                id: "Architect.md",
                content:
                    "You are a Senior Software Architect. You focus on system design, scalability, and clean architecture."
            ),
        ]
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

        // Update in-memory if present
        if sessions[sessionId] != nil {
            sessions[sessionId] = session
        }
        // Always save to DB
        try await persistenceService.saveSession(session)
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
    }

    public func getWorkspaces(for sessionId: UUID) async -> (primary: UUID?, attached: [UUID])? {
        if let session = sessions[sessionId] {
            return (session.primaryWorkspaceId, session.attachedWorkspaces)
        }

        // Fallback: Try to fetch from database
        if let session = try? await persistenceService.fetchSession(id: sessionId) {
            // We do NOT add to in-memory `sessions` here to avoid partial state
            // (missing ContextManager, etc.) unless we want to fully support lazy loading.
            // For now, just returning the data is enough to satisfy the API.
            return (session.primaryWorkspaceId, session.attachedWorkspaces)
        }

        return nil
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

    public func getToolSource(toolId: String, for sessionId: UUID) async -> String? {
        guard let session = sessions[sessionId] else { return nil }

        // 1. Check System Tools
        if let toolManager = toolManagers[sessionId] {
            let systemTools = await toolManager.availableTools
            if systemTools.contains(where: { $0.id == toolId }) {
                return "System"
            }
        }

        // 2. Check Workspaces
        // 2. Check Workspaces
        var ids: [UUID] = []
        if let p = session.primaryWorkspaceId { ids.append(p) }
        ids.append(contentsOf: session.attachedWorkspaces)

        let workspaceIds = ids

        if workspaceIds.isEmpty { return nil }

        return try? await persistenceService.databaseWriter.read { db in
            // Find which workspace has this tool
            if let toolRecord =
                try WorkspaceTool
                .filter(Column("toolId") == toolId)
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchOne(db),
                let ws = try Workspace.fetchOne(db, key: toolRecord.workspaceId)
            {

                if ws.hostType == .client {
                    // Try to find client info
                    if let owner = ws.ownerId,
                        let client = try? ClientIdentity.fetchOne(db, key: owner)
                    {
                        return "Client: \(client.hostname)"
                    }
                    return "Client Workspace"
                } else if session.primaryWorkspaceId == ws.id {
                    return "Primary Workspace"
                } else {
                    return "Workspace: \(ws.uri.description)"
                }
            }
            return nil
        }
    }
}

public enum SessionError: Error {
    case sessionNotFound
}
