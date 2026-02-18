import MonadShared
import Foundation
import Logging
import Dependencies

/// Manages conversation sessions, their associated context, and tool execution environments.
///
/// The `SessionManager` is responsible for the lifecycle of `ConversationSession` objects,
/// including their creation, hydration from persistence, and cleanup. It also coordinates
/// session-specific components like `ContextManager` and `ToolExecutor`.
public actor SessionManager {
    /// In-memory cache of active sessions.
    internal var sessions: [UUID: ConversationSession] = [:]
    
    /// Context managers responsible for RAG and context gathering for each session.
    internal var contextManagers: [UUID: ContextManager] = [:]
    
    /// Tool managers handling tool registration and availability for each session.
    internal var toolManagers: [UUID: SessionToolManager] = [:]
    
    /// Tool executors that perform the actual tool calls for each session.
    internal var toolExecutors: [UUID: ToolExecutor] = [:]
    
    /// State management for tool execution context within a session.
    internal var toolContextSessions: [UUID: ToolContextSession] = [:]
    
    /// Snapshots of tool and context state used for debugging chat turns.
    internal var debugSnapshots: [UUID: DebugSnapshot] = [:]

    @Dependency(\.persistenceService) private var _persistenceService
    @Dependency(\.embeddingService) private var _embeddingService
    @Dependency(\.llmService) private var _llmService
    @Dependency(\.agentRegistry) private var _agentRegistry

    internal var persistenceService: any PersistenceServiceProtocol { _persistenceService }
    internal var embeddingService: any EmbeddingServiceProtocol { _embeddingService }
    internal var llmService: any LLMServiceProtocol { _llmService }
    internal var agentRegistry: AgentRegistry { _agentRegistry }

    internal let vectorStore: (any VectorStoreProtocol)?
    internal let workspaceRoot: URL
    internal let connectionManager: (any ClientConnectionManagerProtocol)?

    /// Initializes a new `SessionManager`.
    /// - Parameters:
    ///   - persistenceService: The service used for database persistence.
    ///   - embeddingService: The service used for generating vector embeddings.
    ///   - vectorStore: An optional store for vector embeddings.
    ///   - llmService: The service used for LLM interactions.
    ///   - agentRegistry: Registry for available autonomous agents.
    ///   - workspaceRoot: The root directory where session data is stored.
    ///   - connectionManager: Optional manager for client-side tool connections.
    public init(
        vectorStore: (any VectorStoreProtocol)? = nil,
        workspaceRoot: URL,
        connectionManager: (any ClientConnectionManagerProtocol)? = nil
    ) {
        self.vectorStore = vectorStore
        self.workspaceRoot = workspaceRoot
        self.connectionManager = connectionManager
    }
    
    // MARK: - Component Setup
    /// Initializes and configures the internal components for a conversation session.
    ///
    /// This method sets up the `ContextManager`, `ToolContextSession`, `SessionToolManager`,
    /// and `ToolExecutor` for the given session. It also handles workspace hydration
    /// and registration.
    ///
    /// - Parameters:
    ///   - session: The conversation session to set up components for.
    ///   - workspaceURL: The file system URL for the session's workspace.
    ///   - parentId: An optional parent session ID for context inheritance.
    internal func setupSessionComponents(
        session: ConversationSession,
        workspaceURL: URL,
        parentId: UUID? = nil
    ) async {
        let contextManager = ContextManager(
            persistenceService: persistenceService,
            embeddingService: embeddingService,
            vectorStore: vectorStore,
            workspaceRoot: workspaceURL
        )
        contextManagers[session.id] = contextManager

        let toolContextSession = ToolContextSession()
        toolContextSessions[session.id] = toolContextSession

        let jobQueueContext = JobQueueContext(persistenceService: persistenceService, sessionId: session.id)

        // Setup Tools for session
        let toolManager = await createToolManager(
            for: session, jailRoot: workspaceURL.path,
            toolContextSession: toolContextSession,
            jobQueueContext: jobQueueContext,
            parentId: parentId)
        toolManagers[session.id] = toolManager

        // Hydrate workspaces and register with ToolManager
        if let workspaces = await getWorkspaces(for: session.id) {
            if let primary = workspaces.primary {
                if let ws = try? WorkspaceFactory.create(from: primary, connectionManager: connectionManager) {
                    await toolManager.registerWorkspace(ws)
                }
            }
            for attached in workspaces.attached {
                if let ws = try? WorkspaceFactory.create(from: attached, connectionManager: connectionManager) {
                    await toolManager.registerWorkspace(ws)
                }
            }
        }

        let toolExecutor = ToolExecutor(
            toolManager: toolManager,
            contextSession: toolContextSession,
            jobQueueContext: jobQueueContext
        )
        toolExecutors[session.id] = toolExecutor
    }

    // MARK: - Session Lifecycle

    /// Creates a new conversation session, initializes its workspace, and saves it to persistence.
    /// - Parameters:
    ///   - title: The initial title of the session.
    /// - Returns: The newly created `ConversationSession`.
    public func createSession(title: String = "New Conversation")
        async throws
        -> ConversationSession
    {
        let sessionId = UUID()

        let sessionWorkspaceURL = workspaceRoot.appendingPathComponent(
            "sessions", isDirectory: true
        )
        .appendingPathComponent(sessionId.uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: sessionWorkspaceURL, withIntermediateDirectories: true)

        let notesDir = sessionWorkspaceURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        
        let welcomeNote = "# Welcome to Monad Notes\n\nI should use this space to store long-term memories..."
        try welcomeNote.write(to: notesDir.appendingPathComponent("Welcome.md"), atomically: true, encoding: .utf8)

        let projectNote = "# Project Notes\n\nI should use this file to track the goals and progress..."
        try projectNote.write(to: notesDir.appendingPathComponent("Project.md"), atomically: true, encoding: .utf8)

        let workspace = WorkspaceReference(
            uri: .serverSession(sessionId),
            hostType: .server,
            rootPath: sessionWorkspaceURL.path,
            trustLevel: .full
        )

        try await persistenceService.saveWorkspace(workspace)

        var session = ConversationSession(
            id: sessionId,
            title: title,
            primaryWorkspaceId: workspace.id
        )
        session.workingDirectory = sessionWorkspaceURL.path

        sessions[session.id] = session
        await setupSessionComponents(session: session, workspaceURL: sessionWorkspaceURL)
        try await persistenceService.saveSession(session)

        return session
    }

    /// Retrieves a session by its ID and updates its `updatedAt` timestamp.
    /// - Parameter id: The unique identifier of the session.
    /// - Returns: The `ConversationSession` if found, `nil` otherwise.
    public func getSession(id: UUID) -> ConversationSession? {
        guard var session = sessions[id] else { return nil }
        session.updatedAt = Date()
        sessions[id] = session
        return session
    }

    /// Reconstructs a session and its components from persistence.
    /// - Parameters:
    ///   - id: The session ID to hydrate.
    ///   - parentId: Optional parent job ID for context.
    public func hydrateSession(id: UUID, parentId: UUID? = nil) async throws {
        if toolExecutors[id] != nil { return }
        
        guard let session = try await persistenceService.fetchSession(id: id) else {
            throw SessionError.sessionNotFound
        }
        
        let sessionWorkspaceURL: URL
        if let wd = session.workingDirectory {
            sessionWorkspaceURL = URL(fileURLWithPath: wd)
        } else {
             sessionWorkspaceURL = workspaceRoot.appendingPathComponent(
                "sessions", isDirectory: true
            ).appendingPathComponent(id.uuidString, isDirectory: true)
        }

        sessions[id] = session
        await setupSessionComponents(
            session: session,
            workspaceURL: sessionWorkspaceURL,
            parentId: parentId
        )
    }
    
    /// Updates the title of a specific session.
    /// - Parameters:
    ///   - id: The session ID.
    ///   - title: The new title.
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

    /// Retrieves the context manager for a session if it is active.
    public func getContextManager(for sessionId: UUID) -> ContextManager? {
        return contextManagers[sessionId]
    }

    /// Retrieves the tool executor for a session if it is active.
    public func getToolExecutor(for sessionId: UUID) -> ToolExecutor? {
        return toolExecutors[sessionId]
    }

    /// Retrieves the tool manager for a session if it is active.
    public func getToolManager(for sessionId: UUID) -> SessionToolManager? {
        return toolManagers[sessionId]
    }

    /// Removes a session and its components from memory.
    /// - Note: This does not delete the session from persistence.
    public func deleteSession(id: UUID) {
        sessions.removeValue(forKey: id)
        contextManagers.removeValue(forKey: id)
        toolManagers.removeValue(forKey: id)
        toolExecutors.removeValue(forKey: id)
        toolContextSessions.removeValue(forKey: id)
    }

    /// Fetches the message history for a specific session from persistence.
    public func getHistory(for sessionId: UUID) async throws -> [Message] {
        let conversationMessages = try await persistenceService.fetchMessages(for: sessionId)
        return conversationMessages.map { $0.toMessage() }
    }

    /// Returns the underlying persistence service.
    public func getPersistenceService() -> any PersistenceServiceProtocol {
        return persistenceService
    }

    /// Lists all active (non-archived) sessions from persistence.
    public func listSessions() async throws -> [ConversationSession] {
        return try await persistenceService.fetchAllSessions(includeArchived: false)
    }


    /// Removes active sessions from memory that have not been updated within the specified interval.
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

public enum SessionError: Error {
    case sessionNotFound
}