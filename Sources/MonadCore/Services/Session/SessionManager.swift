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
    private var toolContextSessions: [UUID: ToolContextSession] = [:]
    private var debugSnapshots: [UUID: DebugSnapshot] = [:]

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
        let selectedPersonaContent = persona ?? "You are Monad, an intelligent AI assistant."

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
            "# Welcome to Monad Notes\n\nI should use this space to store long-term memories and context notes. I can create new notes here to help me remember important details."
        try welcomeNote.write(
            to: notesDir.appendingPathComponent("Welcome.md"), atomically: true, encoding: .utf8)

        let projectNote =
            "# Project Notes\n\nI should use this file to track the goals and progress of the current session. I will update this file as I learn more about the user's objectives."
        try projectNote.write(
            to: notesDir.appendingPathComponent("Project.md"), atomically: true, encoding: .utf8)

        // 1.2 Create Persona file in Notes
        try selectedPersonaContent.write(
            to: notesDir.appendingPathComponent("Persona.md"), atomically: true, encoding: .utf8)

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
            persona: "Persona.md" // Store filename relative to Notes or just mark it present
        )
        session.workingDirectory = sessionWorkspaceURL.path

        sessions[session.id] = session

        let contextManager = ContextManager(
            persistenceService: persistenceService,
            embeddingService: embeddingService,
            workspaceRoot: sessionWorkspaceURL
        )
        contextManagers[session.id] = contextManager

        let toolContextSession = ToolContextSession()
        toolContextSessions[session.id] = toolContextSession

        let jobQueueContext = JobQueueContext(persistenceService: persistenceService, sessionId: sessionId)

        // Setup Tools for session
        let toolManager = await createToolManager(
            for: session, jailRoot: sessionWorkspaceURL.path,
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
        toolContextSession: ToolContextSession,
        jobQueueContext: JobQueueContext
    ) async -> SessionToolManager {
        let currentWD = session.workingDirectory ?? jailRoot

        let availableTools: [any MonadCore.Tool] = [
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
            // InspectFileTool removed as per user request to remove document workflow tools
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

        // Rehydration: Verify directory exists for Server-hosted sessions
        // We do NOT auto-create here. We let the client/user decide if they want to restore it.
        // The status will be checked in getWorkspaces.
        
        sessions[id] = session
        
        let contextManager = ContextManager(
            persistenceService: persistenceService,
            embeddingService: embeddingService,
            workspaceRoot: sessionWorkspaceURL
        )
        contextManagers[session.id] = contextManager
        
        let toolContextSession = ToolContextSession()
        toolContextSessions[session.id] = toolContextSession
        
        let jobQueueContext = JobQueueContext(persistenceService: persistenceService, sessionId: id)
        
        // Setup Tools
        let toolManager = await createToolManager(
            for: session, jailRoot: sessionWorkspaceURL.path,
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

        // Write content to Notes/Persona.md
        if let workingDirectory = session.workingDirectory {
            let personaPath = URL(fileURLWithPath: workingDirectory)
                .appendingPathComponent("Notes")
                .appendingPathComponent("Persona.md")
            try persona.write(to: personaPath, atomically: true, encoding: .utf8)
        }
        
        // We don't strictly need to update session.persona if it's always "Persona.md", 
        // but we can keep it as a filename reference.
        session.persona = "Persona.md"
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

    public func deleteSession(id: UUID) {
        sessions.removeValue(forKey: id)
        contextManagers.removeValue(forKey: id)
        toolManagers.removeValue(forKey: id)
        toolExecutors.removeValue(forKey: id)
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

    public func getWorkspaces(for sessionId: UUID) async -> (primary: Workspace?, attached: [Workspace])? {
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

        var primary: Workspace?
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

        var attached: [Workspace] = []
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
                
                // If it looks like a session root, add subfolders
                // We can check if path ends in "sessions/<uuid>" or just generic restoration of standard folders
                // For now, let's just ensure the root exists.
                // If it was a session root, we might want Notes/Personas.
                // Let's check if we can infer it.
                // A workspace doesn't explicitly say "I am a session root".
                // But we can check if the workspace URI is .serverSession(id).
                if workspace.uri.host == "monad-server" && workspace.uri.path.hasPrefix("/sessions/") {
                     let notesDir = sessionWorkspaceURL.appendingPathComponent("Notes", isDirectory: true)
                     try? fileManager.createDirectory(at: notesDir, withIntermediateDirectories: true)
                     let personasDir = sessionWorkspaceURL.appendingPathComponent("Personas", isDirectory: true)
                     try? fileManager.createDirectory(at: personasDir, withIntermediateDirectories: true)
                }
            }
        }
    }

    public func getWorkspace(_ id: UUID) async throws -> Workspace? {
        return try await persistenceService.databaseWriter.read { db in
            guard let workspace = try Workspace.fetchOne(db, key: id) else {
                return nil
            }
            
            // Load associated tools from WorkspaceTool table
            let workspaceTools = try WorkspaceTool
                .filter(Column("workspaceId") == id)
                .fetchAll(db)
            
            let toolRefs = workspaceTools.compactMap { try? $0.toToolReference() }
            
            // Create a new workspace with the tools populated
            return Workspace(
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

    /// Retrieve tools associated with a specific client (e.g. from their default workspace)
    public func getClientTools(clientId: UUID) async throws -> [ToolReference] {
        return try await persistenceService.databaseWriter.read { db in
            // Find workspaces owned by this client
            let workspaces = try Workspace
                .filter(Column("ownerId") == clientId)
                .fetchAll(db)
            
            let workspaceIds = workspaces.map { $0.id }
            guard !workspaceIds.isEmpty else { return [] }

            let tools = try WorkspaceTool
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

    // MARK: - Debug Snapshots

    /// Store the debug snapshot for the most recent chat exchange in a session
    public func setDebugSnapshot(_ snapshot: DebugSnapshot, for sessionId: UUID) {
        debugSnapshots[sessionId] = snapshot
    }

    /// Retrieve the debug snapshot for the most recent chat exchange
    public func getDebugSnapshot(for sessionId: UUID) -> DebugSnapshot? {
        return debugSnapshots[sessionId]
    }
}

public enum SessionError: Error {
    case sessionNotFound
}
