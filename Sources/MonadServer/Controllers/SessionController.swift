import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import NIOCore

public struct SessionController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/", use: create)
        group.get("/", use: list)
        group.get("/{id}", use: get)
        group.patch("/{id}", use: update)
        group.delete("/{id}", use: delete)
        
        // Messages
        group.get("/{id}/messages", use: getMessages)
        group.get("/{id}/history", use: getMessages) // Legacy alias

        group.get("/personas", use: listPersonas)

        // Workspace routes
        group.post("/{id}/workspaces", use: attachWorkspace)
        group.delete("/{id}/workspaces/{wsId}", use: detachWorkspace)
        group.get("/{id}/workspaces", use: listWorkspaces)
    }

    @Sendable func create(_ request: Request, context: Context) async throws -> Response {
        let input = try? await request.decode(as: CreateSessionRequest.self, context: context)
        let session = try await sessionManager.createSession(
            title: input?.title ?? "New Conversation",
            persona: input?.persona
        )
        let response = SessionResponse(
            id: session.id,
            title: session.title,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            isArchived: session.isArchived,
            tags: session.tagArray,
            workingDirectory: session.workingDirectory,
            persona: session.persona,
            primaryWorkspaceId: session.primaryWorkspaceId,
            attachedWorkspaceIds: session.attachedWorkspaces
        )
        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .created, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func list(_ request: Request, context: Context) async throws -> Response {
        // Parse pagination query params manually until we have a proper binder
        let uri = request.uri
        // Basic query parsing
        let components = URLComponents(string: uri.description)
        let page = components?.queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init) ?? 1
        let perPage = components?.queryItems?.first(where: { $0.name == "perPage" })?.value.flatMap(Int.init) ?? 20

        let sessions = try await sessionManager.listSessions()
        
        // In-memory pagination
        let total = sessions.count
        let start = (page - 1) * perPage
        let paginatedSessions: [ConversationSession]
        if start < total {
            let end = min(start + perPage, total)
            paginatedSessions = Array(sessions[start..<end])
        } else {
            paginatedSessions = []
        }

        let sessionResponses = paginatedSessions.map { session in
            SessionResponse(
                id: session.id,
                title: session.title,
                createdAt: session.createdAt,
                updatedAt: session.updatedAt,
                isArchived: session.isArchived,
                tags: session.tagArray,
                workingDirectory: session.workingDirectory,
                persona: session.persona,
                primaryWorkspaceId: session.primaryWorkspaceId,
                attachedWorkspaceIds: session.attachedWorkspaces
            )
        }
        
        let metadata = PaginationMetadata(page: page, perPage: perPage, totalItems: total)
        let response = PaginatedResponse(items: sessionResponses, metadata: metadata)

        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
    
    @Sendable func get(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }
        
        guard let session = await sessionManager.getSession(id: id) else {
             // Try DB fallback via fetchSession checks in manager or direct
             // SessionManager.getSession calls internal map. 
             // Ideally SessionManager should check DB too if not in memory.
             // But existing getSession returns from map.
             // We can use list logic or trust SessionManager. 
             // But let's check basic list for now or rely on manager improvements.
             // Actually, SessionManager.attachWorkspace does check DB.
             // Let's rely on a get-or-fetch pattern if not present.
             // For now, assume if not in manager it might be gone or not loaded.
             // Wait, SessionManager.listSessions fetches from DB.
             // We should improve SessionManager.getSession or just fetch from DB here?
             // Accessing persistence service from here.
             let persistence = await sessionManager.getPersistenceService()
             if let dbSession = try? await persistence.fetchSession(id: id) {
                 let response = SessionResponse(
                     id: dbSession.id,
                     title: dbSession.title,
                     createdAt: dbSession.createdAt,
                     updatedAt: dbSession.updatedAt,
                     isArchived: dbSession.isArchived,
                     tags: dbSession.tagArray,
                     workingDirectory: dbSession.workingDirectory,
                     persona: dbSession.persona,
                     primaryWorkspaceId: dbSession.primaryWorkspaceId,
                     attachedWorkspaceIds: dbSession.attachedWorkspaces
                 )
                 let data = try SerializationUtils.jsonEncoder.encode(response)
                 var headers = HTTPFields()
                 headers[.contentType] = "application/json"
                 return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
             }
             throw HTTPError(.notFound)
        }

        let response = SessionResponse(
            id: session.id,
            title: session.title,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            isArchived: session.isArchived,
            tags: session.tagArray,
            workingDirectory: session.workingDirectory,
            persona: session.persona,
            primaryWorkspaceId: session.primaryWorkspaceId,
            attachedWorkspaceIds: session.attachedWorkspaces
        )
        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
    
    @Sendable func update(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }
        
        let input = try await request.decode(as: UpdateSessionRequest.self, context: context)
        
        if let title = input.title {
            try await sessionManager.updateSessionTitle(id: id, title: title)
        }
        if let persona = input.persona {
            try await sessionManager.updateSessionPersona(id: id, persona: persona)
        }
        
        return try await get(request, context: context)
    }
    
    @Sendable func delete(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }
        
        // Remove from memory
        await sessionManager.deleteSession(id: id)
        
        // Remove from DB
        let persistence = await sessionManager.getPersistenceService()
        try await persistence.deleteSession(id: id)
        
        return Response(status: .noContent)
    }

    @Sendable func listPersonas(_ request: Request, context: Context) async throws -> Response {
        let personas = await sessionManager.listPersonas()
        let data = try SerializationUtils.jsonEncoder.encode(personas)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func getMessages(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }
        
        let uri = request.uri
        let components = URLComponents(string: uri.description)
        let page = components?.queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init) ?? 1
        let perPage = components?.queryItems?.first(where: { $0.name == "perPage" })?.value.flatMap(Int.init) ?? 50 // Higher default for messages

        let messages = try await sessionManager.getHistory(for: id)
        
        // In-memory pagination
        let total = messages.count
        let start = (page - 1) * perPage
        let paginatedMessages: [Message]
        if start < total {
            let end = min(start + perPage, total)
            paginatedMessages = Array(messages[start..<end])
        } else {
            paginatedMessages = []
        }
        
        let metadata = PaginationMetadata(page: page, perPage: perPage, totalItems: total)
        let response = PaginatedResponse(items: paginatedMessages, metadata: metadata)
        
        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    // MARK: - Workspace Endpoints

    @Sendable func attachWorkspace(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        // Decode request body
        let input = try await request.decode(as: AttachWorkspaceRequest.self, context: context)

        try await sessionManager.attachWorkspace(
            input.workspaceId, to: id, isPrimary: input.isPrimary)

        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers)
    }

    @Sendable func detachWorkspace(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        let wsIdString = try context.parameters.require("wsId")

        guard let id = UUID(uuidString: idString), let wsId = UUID(uuidString: wsIdString) else {
            throw HTTPError(.badRequest)
        }

        try await sessionManager.detachWorkspace(wsId, from: id)
        return Response(status: .noContent)
    }

    @Sendable func listWorkspaces(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        guard let workspaces = await sessionManager.getWorkspaces(for: id) else {
            throw HTTPError(.notFound)
        }

        let response = SessionWorkspacesResponse(
            primaryWorkspaceId: workspaces.primary,
            attachedWorkspaceIds: workspaces.attached
        )

        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}
