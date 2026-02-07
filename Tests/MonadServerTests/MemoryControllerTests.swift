import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServer
import MonadCore
import NIOCore

@Suite struct MemoryControllerTests {

    @Test("Test Memories CRUD")
    func testMemoriesCRUD() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        let sessionManager = SessionManager(
            persistenceService: persistence,
            embeddingService: embedding,
            llmService: llm,
            workspaceRoot: workspaceRoot
        )

        let router = Router()
        let controller = MemoryController<BasicRequestContext>(sessionManager: sessionManager)
        controller.addRoutes(to: router.group("/memories"))

        let app = Application(router: router)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try await app.test(.router) { client in
            // 1. List (Empty)
            try await client.execute(uri: "/memories", method: .get) { response in
                #expect(response.status == .ok)
                let memories = try decoder.decode([Memory].self, from: response.body)
                #expect(memories.isEmpty)
            }

            // 2. Create
            let createReq = CreateMemoryRequest(title: "Test Memory", content: "Test Content", tags: ["test"])
            let createBuffer = ByteBuffer(bytes: try JSONEncoder().encode(createReq))

            try await client.execute(uri: "/memories", method: .post, body: createBuffer) { response in
                #expect(response.status == .created)
                let memory = try decoder.decode(Memory.self, from: response.body)
                #expect(memory.title == "Test Memory")
                #expect(memory.tagArray == ["test"])
            }

            // 3. List (1 item)
            try await client.execute(uri: "/memories", method: .get) { response in
                #expect(response.status == .ok)
                let memories = try decoder.decode([Memory].self, from: response.body)
                #expect(memories.count == 1)
                #expect(memories[0].title == "Test Memory")
            }

            let listResponse = try await client.execute(uri: "/memories", method: .get) { $0 }
            let memoryId = (try decoder.decode([Memory].self, from: listResponse.body))[0].id

            // 4. Delete
            try await client.execute(uri: "/memories/\(memoryId)", method: .delete) { response in
                #expect(response.status == .noContent)
            }

            // 5. List (Empty)
            try await client.execute(uri: "/memories", method: .get) { response in
                let memories = try decoder.decode([Memory].self, from: response.body)
                #expect(memories.isEmpty)
            }
        }
    }
}

public struct CreateMemoryRequest: Codable {
    public let title: String
    public let content: String
    public let tags: [String]?
}
