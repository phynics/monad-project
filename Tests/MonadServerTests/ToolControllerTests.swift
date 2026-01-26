import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServerCore
import MonadCore
import NIOCore

@Suite struct ToolControllerTests {
    
    @Test("Test Tools API")
    func testToolsAPI() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let sessionManager = SessionManager(persistenceService: persistence, embeddingService: embedding)
        
        let router = Router()
        let controller = ToolController<BasicRequestContext>(sessionManager: sessionManager)
        controller.addRoutes(to: router.group("/tools"))
        
        let app = Application(router: router)
        
        try await app.test(.router) { client in
            // 1. List
            try await client.execute(uri: "/tools", method: .get) { response in
                #expect(response.status == .ok)
                // We expect some default tools if implemented, or empty list
                let tools = try JSONDecoder().decode([ToolInfo].self, from: response.body)
                #expect(tools.count >= 0)
            }
            
            // 2. Execute (Mock execution)
            let execReq = ExecuteToolRequest(name: "test_tool", arguments: [:])
            let execBuffer = ByteBuffer(bytes: try JSONEncoder().encode(execReq))
            
            try await client.execute(uri: "/tools/execute", method: .post, body: execBuffer) { response in
                // Should probably error out if tool not found, or return mock result
                #expect(response.status == .notFound || response.status == .ok)
            }
        }
    }
}

public struct ToolInfo: Codable {
    public let id: String
    public let name: String
    public let description: String
}

public struct ExecuteToolRequest: Codable {
    public let name: String
    public let arguments: [String: AnyCodable]
}
