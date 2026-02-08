import Foundation
import MonadCore

/// HTTP client for communicating with MonadServer
public actor MonadClient {
    private let configuration: ClientConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let sseReader: SSEStreamReader

    public init(configuration: ClientConfiguration = .fromEnvironment()) {
        self.configuration = configuration

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        self.session = URLSession(configuration: sessionConfig)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        self.sseReader = SSEStreamReader()
    }

    // MARK: - Session API

    /// Create a new chat session
    public func createSession(
        title: String? = nil, persona: String? = nil, workspaceId: UUID? = nil
    ) async throws -> Session {
        var request = try buildRequest(path: "/api/sessions", method: "POST")
        request.httpBody = try encoder.encode(
            CreateSessionRequest(title: title, primaryWorkspaceId: workspaceId, persona: persona))
        return try await perform(request)
    }

    public func listSessions() async throws -> [SessionResponse] {
        let request = try buildRequest(path: "/api/sessions", method: "GET")
        let response: PaginatedResponse<SessionResponse> = try await perform(request)
        return response.items
    }

    /// List available personas
    public func listPersonas() async throws -> [Persona] {
        let request = try buildRequest(path: "/api/sessions/personas", method: "GET")
        return try await perform(request)
    }

    /// Update session persona
    public func updatePersona(_ persona: String, sessionId: UUID) async throws {
        var request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/persona", method: "PATCH")
        request.httpBody = try encoder.encode(UpdatePersonaRequest(persona: persona))
        _ = try await performRaw(request)
    }

    /// Update session title
    public func updateSessionTitle(_ title: String, sessionId: UUID) async throws {
        var request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/title", method: "PATCH")
        request.httpBody = try encoder.encode(UpdateSessionTitleRequest(title: title))
        _ = try await performRaw(request)
    }

    /// Get history for a session
    public func deleteSession(_ id: UUID) async throws {
        let request = try buildRequest(path: "/api/sessions/\(id.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }

    /// Get session history
    public func getHistory(sessionId: UUID) async throws -> [Message] {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/history", method: "GET")
        return try await perform(request)
    }

    // MARK: - Chat API

    /// Send a chat message (non-streaming)
    public func chat(sessionId: UUID, message: String) async throws -> ChatResponse {
        var request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/chat", method: "POST")
        request.httpBody = try encoder.encode(ChatRequest(message: message))
        return try await perform(request)
    }

    /// Send a chat message with streaming response
    public func chatStream(sessionId: UUID, message: String) async throws -> AsyncThrowingStream<
        ChatDelta, Error
    > {
        configuration.logger.debug("chatStream called for session \(sessionId)")
        var request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/chat/stream", method: "POST")
        request.httpBody = try encoder.encode(ChatRequest(message: message))

        configuration.logger.debug(
            "Sending request to \(request.url?.absoluteString ?? "unknown")")
        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            configuration.logger.error("Invalid response type")
            throw MonadClientError.unknown("Invalid response")
        }

        configuration.logger.debug("Response status: \(httpResponse.statusCode)")
        if httpResponse.statusCode != 200 {
            // Read error body if possible
            var message: String?
            do {
                var body = ""
                for try await byte in bytes {
                    body.append(Character(UnicodeScalar(byte)))
                }
                message = body
            } catch {
                configuration.logger.error("Failed to read error body: \(error)")
            }

            switch httpResponse.statusCode {
            case 401:
                configuration.logger.error("HTTP 401 Unauthorized: \(message ?? "")")
                throw MonadClientError.unauthorized
            case 404:
                configuration.logger.error("HTTP 404 Not Found")
                throw MonadClientError.notFound
            default:
                configuration.logger.error("HTTP \(httpResponse.statusCode): \(message ?? "")")
                throw MonadClientError.httpError(
                    statusCode: httpResponse.statusCode, message: message)
            }
        }

        configuration.logger.debug("Starting SSE reader")
        return sseReader.events(from: bytes, logger: configuration.logger)
    }

    // MARK: - Memory API

    /// List all memories
    public func listMemories() async throws -> [Memory] {
        let request = try buildRequest(path: "/api/memories", method: "GET")
        let response: PaginatedResponse<Memory> = try await perform(request)
        return response.items
    }

    /// Search memories
    public func searchMemories(_ query: String, limit: Int? = nil) async throws -> [Memory] {
        var request = try buildRequest(path: "/api/memories/search", method: "POST")
        request.httpBody = try encoder.encode(MemorySearchRequest(query: query, limit: limit))
        return try await perform(request)
    }

    /// Delete a memory
    public func deleteMemory(_ id: UUID) async throws {
        let request = try buildRequest(path: "/api/memories/\(id.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }

    // MARK: - File API

    /// List all files in a workspace
    public func listFiles(workspaceId: UUID) async throws -> [String] {
        let request = try buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/files", method: "GET")
        return try await perform(request)
    }

    /// Get file content
    public func getFileContent(workspaceId: UUID, path: String) async throws -> String {
        // Path might contain slashes, and buildRequest handles relativeTo, but we need to ensure the path is correctly appended.
        // FilesController uses "*" so we just append the path.
        let request = try buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/files/\(path)", method: "GET")
        let (data, _) = try await performRaw(request)
        return String(decoding: data, as: UTF8.self)
    }

    /// Write file content
    public func writeFileContent(workspaceId: UUID, path: String, content: String) async throws {
        var request = try buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/files/\(path)", method: "PUT")
        request.httpBody = content.data(using: .utf8)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        _ = try await performRaw(request)
    }

    /// Delete a file
    public func deleteFile(workspaceId: UUID, path: String) async throws {
        let request = try buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/files/\(path)", method: "DELETE")
        _ = try await performRaw(request)
    }

    // MARK: - Tool API

    /// List all tools available in a session
    public func listTools(sessionId: UUID) async throws -> [Tool] {
        let request = try buildRequest(path: "/api/tools/\(sessionId.uuidString)", method: "GET")
        return try await perform(request)
    }

    /// Enable a tool
    public func enableTool(_ name: String, sessionId: UUID) async throws {
        let request = try buildRequest(
            path: "/api/tools/\(sessionId.uuidString)/\(name)/enable", method: "POST")
        _ = try await performRaw(request)
    }

    /// Disable a tool
    public func disableTool(_ name: String, sessionId: UUID) async throws {
        let request = try buildRequest(
            path: "/api/tools/\(sessionId.uuidString)/\(name)/disable", method: "POST")
        _ = try await performRaw(request)
    }

    // MARK: - Health

    /// Get the detailed health status of the server and its components
    public func getStatus() async throws -> StatusResponse {
        let request = try buildRequest(path: "/status", method: "GET", requiresAuth: false)
        return try await perform(request)
    }

    /// Check if the server is reachable
    public func healthCheck() async throws -> Bool {
        let request = try buildRequest(path: "/health", method: "GET", requiresAuth: false)
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    // MARK: - Configuration API

    /// Get current server configuration
    public func getConfiguration() async throws -> LLMConfiguration {
        let request = try buildRequest(path: "/api/config", method: "GET")
        return try await perform(request)
    }

    /// Update server configuration
    public func updateConfiguration(_ config: LLMConfiguration) async throws {
        var request = try buildRequest(path: "/api/config", method: "PUT")
        request.httpBody = try encoder.encode(config)
        _ = try await performRaw(request)
    }

    // MARK: - Workspace API

    public func createWorkspace(
        uri: WorkspaceURI,
        hostType: WorkspaceHostType,
        ownerId: UUID?,
        rootPath: String?,
        trustLevel: WorkspaceTrustLevel?
    ) async throws -> Workspace {
        var request = try buildRequest(path: "/api/workspaces", method: "POST")
        request.httpBody = try encoder.encode(
            CreateWorkspaceRequest(
                uri: uri.description,
                hostType: hostType,
                ownerId: ownerId,
                rootPath: rootPath,
                trustLevel: trustLevel
            )
        )
        return try await perform(request)
    }

    public func listWorkspaces() async throws -> [Workspace] {
        let request = try buildRequest(path: "/api/workspaces", method: "GET")
        let response: PaginatedResponse<Workspace> = try await perform(request)
        return response.items
    }

    public func getWorkspace(_ id: UUID) async throws -> Workspace {
        let request = try buildRequest(path: "/api/workspaces/\(id.uuidString)", method: "GET")
        return try await perform(request)
    }

    public func deleteWorkspace(_ id: UUID) async throws {
        let request = try buildRequest(path: "/api/workspaces/\(id.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }

    public func attachWorkspace(_ workspaceId: UUID, to sessionId: UUID, isPrimary: Bool)
        async throws
    {
        var request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/workspaces", method: "POST")
        request.httpBody = try encoder.encode(
            AttachWorkspaceRequest(workspaceId: workspaceId, isPrimary: isPrimary)
        )
        _ = try await performRaw(request)
    }

    public func detachWorkspace(_ workspaceId: UUID, from sessionId: UUID) async throws {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/workspaces/\(workspaceId.uuidString)",
            method: "DELETE"
        )
        _ = try await performRaw(request)
    }

    public func listSessionWorkspaces(sessionId: UUID) async throws -> (
        primary: Workspace?, attached: [Workspace]
    ) {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/workspaces", method: "GET")
        let response: SessionWorkspacesResponse = try await perform(request)
        return (response.primaryWorkspace, response.attachedWorkspaces)
    }

    public func restoreWorkspace(sessionId: UUID, workspaceId: UUID) async throws {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/workspaces/\(workspaceId.uuidString)/restore",
            method: "POST"
        )
        _ = try await performRaw(request)
    }

    // MARK: - Prune API

    public func pruneMemories(query: String, dryRun: Bool = false) async throws -> Int {
        var request = try buildRequest(path: "/api/prune/memories", method: "POST")
        request.httpBody = try encoder.encode(PruneMemoriesRequest(query: query, dryRun: dryRun))
        let response: PruneResponse = try await perform(request)
        return response.count
    }

    public func pruneMemories(olderThanDays days: Int, dryRun: Bool = false) async throws -> Int {
        var request = try buildRequest(path: "/api/prune/memories", method: "POST")
        request.httpBody = try encoder.encode(PruneMemoriesRequest(days: days, dryRun: dryRun))
        let response: PruneResponse = try await perform(request)
        return response.count
    }

    public func pruneSessions(olderThanDays days: Int, excluding: [UUID] = [], dryRun: Bool = false)
        async throws -> Int
    {
        var request = try buildRequest(path: "/api/prune/sessions", method: "POST")
        request.httpBody = try encoder.encode(
            PruneSessionRequest(days: days, excludedSessionIds: excluding, dryRun: dryRun))
        let response: PruneResponse = try await perform(request)
        return response.count
    }

    public func pruneMessages(olderThanDays days: Int, dryRun: Bool = false) async throws -> Int {
        var request = try buildRequest(path: "/api/prune/messages", method: "POST")
        request.httpBody = try encoder.encode(PruneMessagesRequest(days: days, dryRun: dryRun))
        let response: PruneResponse = try await perform(request)
        return response.count
    }

    // MARK: - Client API

    public func registerClient(
        hostname: String,
        displayName: String,
        platform: String,
        tools: [ToolReference] = []
    ) async throws -> ClientRegistrationResponse {
        var request = try buildRequest(path: "/api/clients/register", method: "POST")
        request.httpBody = try encoder.encode(
            ClientRegistrationRequest(
                hostname: hostname,
                displayName: displayName,
                platform: platform,
                tools: tools
            )
        )
        return try await perform(request)
    }

    public func listClients() async throws -> [ClientIdentity] {
        let request = try buildRequest(path: "/api/clients", method: "GET")
        return try await perform(request)
    }

    public func deleteClient(_ id: UUID) async throws {
        let request = try buildRequest(path: "/api/clients/\(id.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }

    // MARK: - Job API

    /// Add a new job
    public func addJob(sessionId: UUID, title: String, description: String? = nil, priority: Int = 0) async throws -> Job {
        var request = try buildRequest(path: "/api/sessions/\(sessionId.uuidString)/jobs", method: "POST")
        request.httpBody = try encoder.encode(AddJobRequest(title: title, description: description, priority: priority))
        return try await perform(request)
    }

    /// List jobs for a session
    public func listJobs(sessionId: UUID) async throws -> [Job] {
        let request = try buildRequest(path: "/api/sessions/\(sessionId.uuidString)/jobs", method: "GET")
        return try await perform(request)
    }

    /// Get a specific job
    public func getJob(sessionId: UUID, jobId: UUID) async throws -> Job {
        let request = try buildRequest(path: "/api/sessions/\(sessionId.uuidString)/jobs/\(jobId.uuidString)", method: "GET")
        return try await perform(request)
    }

    /// Delete a job
    public func deleteJob(sessionId: UUID, jobId: UUID) async throws {
        let request = try buildRequest(path: "/api/sessions/\(sessionId.uuidString)/jobs/\(jobId.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }

    // MARK: - Private Helpers

    private func buildRequest(path: String, method: String, requiresAuth: Bool = true) throws
        -> URLRequest
    {
        guard let url = URL(string: path, relativeTo: configuration.baseURL) else {
            throw MonadClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if requiresAuth, let apiKey = configuration.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await performRaw(request)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MonadClientError.decodingError(error)
        }
    }

    private func performRaw(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            configuration.logger.error("Network error: \(error.localizedDescription)")
            throw MonadClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MonadClientError.unknown("Invalid response type")
        }

        let url = request.url?.path ?? "unknown"

        switch httpResponse.statusCode {
        case 200...299:
            return (data, response)
        case 401:
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            configuration.logger.error("HTTP 401 Unauthorized for \(url): \(body)")
            throw MonadClientError.unauthorized
        case 404:
            configuration.logger.warning("HTTP 404 Not Found for \(url)")
            throw MonadClientError.notFound
        default:
            let message = String(data: data, encoding: .utf8)
            configuration.logger.error(
                "HTTP \(httpResponse.statusCode) for \(url): \(message ?? "no body")")
            throw MonadClientError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}
