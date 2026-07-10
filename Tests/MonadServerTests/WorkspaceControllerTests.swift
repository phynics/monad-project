import Foundation
import GRDB
import Hummingbird
import HummingbirdTesting
@testable import MonadServerCore
import MonadShared
import NIOCore
import PKShared
import PositronicKit
import Testing

@Suite(.serialized)
struct WorkspaceControllerTests {
    /// Builds a workspace API app backed by a real GRDB database (full migrations),
    /// and runs the test closure inside `app.test(.router)`.
    private func withApp(
        _ operation: @escaping @Sendable (
            _ client: any TestClientProtocol,
            _ workspaceStore: WorkspaceDataRepository
        ) async throws -> Void
    ) async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        let workspaceStore = WorkspaceDataRepository(dbQueue: queue)
        let toolStore = ToolDataRepository(dbQueue: queue)

        let router = Router()
        router.add(middleware: ErrorMiddleware())
        let controller = WorkspaceAPIController<BasicRequestContext>(
            workspaceStore: workspaceStore,
            toolStore: toolStore
        )
        controller.addRoutes(to: router.group("/workspaces"))

        let app = Application(router: router)
        try await app.test(.router) { client in
            try await operation(client, workspaceStore)
        }
    }

    private func encodeBody(_ value: some Encodable) throws -> ByteBuffer {
        try ByteBuffer(bytes: JSONEncoder().encode(value))
    }

    private func decodeWorkspace(_ buffer: ByteBuffer) throws -> WorkspaceReference {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkspaceReference.self, from: buffer)
    }

    @Test("Create persists contextInjection and creation-time tools")
    func create_persistsContextInjectionAndTools() async throws {
        try await withApp { client, workspaceStore in
            let timelineId = UUID()
            let request = CreateWorkspaceRequest(
                uri: WorkspaceURI.timelineWorkspace(timelineId).description,
                location: .runtime,
                originId: nil,
                rootPath: "/tmp/ws",
                trustLevel: .restricted,
                tools: [.known("bash")],
                contextInjection: "Always answer in haiku."
            )

            var createdId: UUID?
            try await client.execute(
                uri: "/workspaces", method: .post, body: encodeBody(request)
            ) { response in
                #expect(response.status == .created)
                let workspace = try decodeWorkspace(response.body)
                #expect(workspace.contextInjection == "Always answer in haiku.")
                createdId = workspace.id
            }

            // Verify the real GRDB round-trip, not just the response echo.
            let id = try #require(createdId)
            let persisted = try #require(
                try await workspaceStore.fetchWorkspace(id: id, includeTools: true)
            )
            #expect(persisted.contextInjection == "Always answer in haiku.")
            #expect(persisted.rootPath == "/tmp/ws")
            #expect(persisted.trustLevel == .restricted)
            #expect(persisted.tools == [.known("bash")])
        }
    }

    @Test("Create without contextInjection behaves as before (nil)")
    func create_withoutContextInjection_defaultsToNil() async throws {
        try await withApp { client, workspaceStore in
            let timelineId = UUID()
            // Omit the new fields entirely from the JSON payload.
            let json = """
            {"uri": "\(WorkspaceURI.timelineWorkspace(timelineId).description)",
             "location": "runtime", "tools": []}
            """
            var createdId: UUID?
            try await client.execute(
                uri: "/workspaces", method: .post, body: ByteBuffer(string: json)
            ) { response in
                #expect(response.status == .created)
                createdId = try decodeWorkspace(response.body).id
            }
            let id = try #require(createdId)
            let persisted = try #require(
                try await workspaceStore.fetchWorkspace(id: id, includeTools: false)
            )
            #expect(persisted.contextInjection == nil)
        }
    }

    @Test("Update sets contextInjection without clobbering unrelated fields")
    func update_setsContextInjection_preservesOtherFields() async throws {
        try await withApp { client, workspaceStore in
            let workspaceId = UUID()
            let workspace = WorkspaceReference(
                id: workspaceId,
                uri: .timelineWorkspace(workspaceId),
                location: .runtime,
                rootPath: "/tmp/original",
                trustLevel: .readOnly
            )
            try await workspaceStore.saveWorkspace(workspace)

            let patch = UpdateWorkspaceRequest(contextInjection: "Injected context")
            try await client.execute(
                uri: "/workspaces/\(workspaceId.uuidString)", method: .patch,
                body: encodeBody(patch)
            ) { response in
                #expect(response.status == .ok)
                let updated = try decodeWorkspace(response.body)
                #expect(updated.contextInjection == "Injected context")
                #expect(updated.rootPath == "/tmp/original")
                #expect(updated.trustLevel == .readOnly)
            }

            let persisted = try #require(
                try await workspaceStore.fetchWorkspace(id: workspaceId, includeTools: false)
            )
            #expect(persisted.contextInjection == "Injected context")
            #expect(persisted.rootPath == "/tmp/original")
            #expect(persisted.trustLevel == .readOnly)
        }
    }

    @Test("Update omitting contextInjection leaves existing value unchanged")
    func update_omittedContextInjection_isUnchanged() async throws {
        try await withApp { client, workspaceStore in
            let workspaceId = UUID()
            let workspace = WorkspaceReference(
                id: workspaceId,
                uri: .timelineWorkspace(workspaceId),
                location: .runtime,
                contextInjection: "Keep me"
            )
            try await workspaceStore.saveWorkspace(workspace)

            // Patch only rootPath; contextInjection is absent from the JSON.
            try await client.execute(
                uri: "/workspaces/\(workspaceId.uuidString)", method: .patch,
                body: ByteBuffer(string: #"{"rootPath": "/tmp/moved"}"#)
            ) { response in
                #expect(response.status == .ok)
            }

            let persisted = try #require(
                try await workspaceStore.fetchWorkspace(id: workspaceId, includeTools: false)
            )
            #expect(persisted.contextInjection == "Keep me")
            #expect(persisted.rootPath == "/tmp/moved")
        }
    }

    @Test("Update with clearContextInjection clears the value")
    func update_clearContextInjection_clearsValue() async throws {
        try await withApp { client, workspaceStore in
            let workspaceId = UUID()
            let workspace = WorkspaceReference(
                id: workspaceId,
                uri: .timelineWorkspace(workspaceId),
                location: .runtime,
                rootPath: "/tmp/keep",
                contextInjection: "Remove me"
            )
            try await workspaceStore.saveWorkspace(workspace)

            let patch = UpdateWorkspaceRequest(clearContextInjection: true)
            try await client.execute(
                uri: "/workspaces/\(workspaceId.uuidString)", method: .patch,
                body: encodeBody(patch)
            ) { response in
                #expect(response.status == .ok)
                let updated = try decodeWorkspace(response.body)
                #expect(updated.contextInjection == nil)
                #expect(updated.rootPath == "/tmp/keep")
            }

            let persisted = try #require(
                try await workspaceStore.fetchWorkspace(id: workspaceId, includeTools: false)
            )
            #expect(persisted.contextInjection == nil)
            #expect(persisted.rootPath == "/tmp/keep")
        }
    }
}
