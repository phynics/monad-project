import Foundation

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
    public func createSession() async throws -> Session {
        let request = try buildRequest(path: "/api/sessions", method: "POST")
        return try await perform(request)
    }

    /// List all sessions
    public func listSessions() async throws -> [Session] {
        let request = try buildRequest(path: "/api/sessions", method: "GET")
        return try await perform(request)
    }

    /// Delete a session
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
        var request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/chat/stream", method: "POST")
        request.httpBody = try encoder.encode(ChatRequest(message: message))

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MonadClientError.unknown("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            throw MonadClientError.httpError(statusCode: httpResponse.statusCode, message: nil)
        }

        return sseReader.events(from: bytes)
    }

    // MARK: - Memory API

    /// List all memories
    public func listMemories() async throws -> [Memory] {
        let request = try buildRequest(path: "/api/memories", method: "GET")
        return try await perform(request)
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

    // MARK: - Note API

    /// List all notes
    public func listNotes() async throws -> [Note] {
        let request = try buildRequest(path: "/api/notes", method: "GET")
        return try await perform(request)
    }

    /// Get a note by ID
    public func getNote(_ id: UUID) async throws -> Note {
        let request = try buildRequest(path: "/api/notes/\(id.uuidString)", method: "GET")
        return try await perform(request)
    }

    /// Create a new note
    public func createNote(title: String, content: String) async throws -> Note {
        var request = try buildRequest(path: "/api/notes", method: "POST")
        request.httpBody = try encoder.encode(CreateNoteRequest(title: title, content: content))
        return try await perform(request)
    }

    /// Update a note
    public func updateNote(_ id: UUID, title: String? = nil, content: String? = nil) async throws
        -> Note
    {
        var request = try buildRequest(path: "/api/notes/\(id.uuidString)", method: "PATCH")
        request.httpBody = try encoder.encode(UpdateNoteRequest(title: title, content: content))
        return try await perform(request)
    }

    /// Delete a note
    public func deleteNote(_ id: UUID) async throws {
        let request = try buildRequest(path: "/api/notes/\(id.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }

    // MARK: - Tool API

    /// List all tools
    public func listTools() async throws -> [Tool] {
        let request = try buildRequest(path: "/api/tools", method: "GET")
        return try await perform(request)
    }

    /// Enable a tool
    public func enableTool(_ name: String) async throws {
        let request = try buildRequest(path: "/api/tools/\(name)/enable", method: "POST")
        _ = try await performRaw(request)
    }

    /// Disable a tool
    public func disableTool(_ name: String) async throws {
        let request = try buildRequest(path: "/api/tools/\(name)/disable", method: "POST")
        _ = try await performRaw(request)
    }

    // MARK: - Health

    /// Check if the server is reachable
    public func healthCheck() async throws -> Bool {
        let request = try buildRequest(path: "/health", method: "GET", requiresAuth: false)
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
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
            throw MonadClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MonadClientError.unknown("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return (data, response)
        case 401:
            throw MonadClientError.unauthorized
        case 404:
            throw MonadClientError.notFound
        default:
            let message = String(data: data, encoding: .utf8)
            throw MonadClientError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}
