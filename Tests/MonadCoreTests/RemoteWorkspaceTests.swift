import MonadShared
import XCTest
import MonadCore

// Mock Connection Manager
actor MockConnectionManager: ClientConnectionManagerProtocol {
    var lastMethod: String?
    var lastParams: MonadShared.AnyCodable?
    var lastClientId: UUID?
    var nextResponse: Any?
    var shouldThrow: Error?
    
    func setNextResponse(_ response: Any) {
        self.nextResponse = response
    }
    
    func send<T: Codable & Sendable>(method: String, params: MonadShared.AnyCodable?, expecting: T.Type, to clientId: UUID) async throws -> T {
        lastMethod = method
        lastParams = params
        lastClientId = clientId
        
        if let error = shouldThrow {
            throw error
        }
        
        if let response = nextResponse as? T {
            return response
        }
        
        print("Mock ERROR: Expected \(T.self), got \(type(of: nextResponse)). nextResponse: \(String(describing: nextResponse))")
        fatalError("Mock not configured for return type \(T.self)")
    }
    
    func isConnected(clientId: UUID) async -> Bool {
        return true
    }
}

final class RemoteWorkspaceTests: XCTestCase {
    var workspace: RemoteWorkspace!
    var mockConnection: MockConnectionManager!
    let clientId = UUID()
    
    override func setUp() async throws {
        mockConnection = MockConnectionManager()
        let ref = MonadShared.WorkspaceReference(
            id: UUID(),
            uri: WorkspaceURI(host: "client-host", path: "/remote"),
            hostType: .client,
            ownerId: clientId,
            rootPath: "/remote"
        )
        workspace = try RemoteWorkspace(reference: ref, connectionManager: mockConnection)
    }
    
    func testExecuteTool() async throws {
        // Setup mock response
        let response = ToolExecutionResponse(status: "success", output: "Tool executed")
        await mockConnection.setNextResponse(response)
        
        let result = try await workspace.executeTool(id: "test_tool", parameters: ["arg": MonadShared.AnyCodable("value")])
        
        // Use await to access actor properties if needed, but actor isolation prevents direct access from XCTestCase?
        // Wait, MockConnectionManager is an actor.
        let method = await mockConnection.lastMethod
        let params = await mockConnection.lastParams
        let cid = await mockConnection.lastClientId
        
        XCTAssertEqual(method, "workspace/executeTool")
        XCTAssertEqual(cid, clientId)
        
        // Expected params value is ToolExecutionRequest
        guard let requestObj = params?.value as? ToolExecutionRequest else {
             XCTFail("Invalid parameters type: \(type(of: params?.value))")
             return
        }
        
        XCTAssertEqual(requestObj.toolId, "test_tool")
        
        // requestObj.parameters is [String: MonadShared.AnyCodable]
        XCTAssertEqual(requestObj.parameters["arg"]?.value as? String, "value")
        
        // Check result
        // Check result
        // Check result
        if result.success {
            XCTAssertEqual(result.output, "Tool executed")
        } else {
            XCTFail("Expected success but got error: \(result.error ?? "unknown")")
        }
    }
    
    func testReadFile() async throws {
        let content = "Hello World"
        await mockConnection.setNextResponse(content)
        
        let data = try await workspace.readFile(path: "test.txt")
        // RemoteWorkspace returns String directly
        XCTAssertEqual(data, content)
        
        let method = await mockConnection.lastMethod
        let params = await mockConnection.lastParams
        
        XCTAssertEqual(method, "workspace/readFile")
        
        guard let requestObj = params?.value as? ReadFileRequest else {
            XCTFail("Invalid parameters type: \(type(of: params?.value))")
            return
        }
        XCTAssertEqual(requestObj.path, "test.txt")
    }
}
