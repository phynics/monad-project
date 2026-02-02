import Foundation
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

    public init(
        persistenceService: any PersistenceServiceProtocol, embeddingService: any EmbeddingService,
        llmService: any LLMServiceProtocol
    ) {
        self.persistenceService = persistenceService
        self.embeddingService = embeddingService
        self.llmService = llmService
    }

    public func createSession(title: String = "New Conversation") async throws
        -> ConversationSession
    {
        let session = ConversationSession(id: UUID(), title: title)
        sessions[session.id] = session

        let contextManager = ContextManager(
            persistenceService: persistenceService, embeddingService: embeddingService)
        contextManagers[session.id] = contextManager

        let documentManager = DocumentManager()
        documentManagers[session.id] = documentManager

        let toolContextSession = ToolContextSession()
        toolContextSessions[session.id] = toolContextSession

        let jobQueueContext = JobQueueContext(persistenceService: persistenceService)

        // Setup Tools for session
        let toolManager = await createToolManager(
            for: session, documentManager: documentManager, toolContextSession: toolContextSession,
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
        documentManager: DocumentManager,
        toolContextSession: ToolContextSession,
        jobQueueContext: JobQueueContext
    ) async -> SessionToolManager {
        let currentWD = session.workingDirectory ?? FileManager.default.currentDirectoryPath

        let availableTools: [any MonadCore.Tool] = [
            ExecuteSQLTool(persistenceService: persistenceService),
            // Filesystem Tools
            ChangeDirectoryTool(
                currentPath: currentWD,
                onChange: { [weak self] newPath in
                    guard let self = self else { return }
                    // Update working directory logic would need a way to communicate back to SessionManager
                    // For now, in Server we might want to handle this differently or just let it be.
                }),
            ListDirectoryTool(root: currentWD),
            FindFileTool(root: currentWD),
            SearchFileContentTool(root: currentWD),
            ReadFileTool(root: currentWD),
            InspectFileTool(root: currentWD),
            // Document Tools
            LoadDocumentTool(documentManager: documentManager),
            UnloadDocumentTool(documentManager: documentManager),
            SwitchDocumentViewTool(documentManager: documentManager),
            FindExcerptsTool(llmService: llmService, documentManager: documentManager),
            EditDocumentSummaryTool(documentManager: documentManager),
            MoveDocumentExcerptTool(documentManager: documentManager),
            LaunchSubagentTool(llmService: llmService, documentManager: documentManager),
            DetectTopicChangeTool(),
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
}
