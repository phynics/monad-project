import MonadShared
import MonadCore
@testable import MonadServer
import Testing
import Foundation

// MockConnectionManager brings in all needed MonadCore protocols via MonadCore import.
// The implementation is identical to the one in MonadCoreTests – kept here since RemoteWorkspace
// now lives in MonadServer (which imports MonadCore).
actor MockConnectionManagerForRemote: ClientConnectionManagerProtocol {
    var lastMethod: String?
    var lastParams: AnyCodable?
    var lastClientId: UUID?
    var nextResponse: Any?
    var shouldThrow: Error?

    func setNextResponse(_ response: Any) {
        self.nextResponse = response
    }

    func send<T: Codable & Sendable>(method: String, params: AnyCodable?, expecting: T.Type, to clientId: UUID) async throws -> T {
        lastMethod = method
        lastParams = params
        lastClientId = clientId

        if let error = shouldThrow {
            throw error
        }

        if let response = nextResponse as? T {
            return response
        }

        fatalError("Mock not configured for return type \(T.self)")
    }

    func isConnected(clientId: UUID) async -> Bool {
        return true
    }
}

@Suite final class RemoteWorkspaceTests {
    var workspace: RemoteWorkspace!
    var mockConnection: MockConnectionManagerForRemote!
    let clientId = UUID()

    init() async throws {
        mockConnection = MockConnectionManagerForRemote()
        let ref = WorkspaceReference(
            id: UUID(),
            uri: WorkspaceURI(host: "client-host", path: "/remote"),
            hostType: .client,
            ownerId: clientId,
            rootPath: "/remote"
        )
        workspace = try RemoteWorkspace(reference: ref, connectionManager: mockConnection)
    }

    @Test


    func testExecuteTool() async throws {
        let response = ToolExecutionResponse(status: "success", output: "Tool executed")
        await mockConnection.setNextResponse(response)

        let result = try await workspace.executeTool(id: "test_tool", parameters: ["arg": AnyCodable("value")])

        let method = await mockConnection.lastMethod
        let params = await mockConnection.lastParams
        let cid = await mockConnection.lastClientId

        #expect(method == "workspace/executeTool")
        #expect(cid == clientId)

        guard let requestDict = params?.value as? [String: Any] else {
             Issue.record("Invalid parameters type: \(type(of: params?.value))")
             return
        }

        #expect(requestDict["toolId"] as? String == "test_tool")

        guard let parametersDict = requestDict["parameters"] as? [String: Any] else {
            Issue.record("Missing parameters dictionary")
            return
        }
        #expect(parametersDict["arg"] as? String == "value")

        if result.success {
            #expect(result.output == "Tool executed")
        } else {
            Issue.record("Expected success but got error: \(result)")
        }
    }

    @Test


    func testReadFile() async throws {
        let content = "Hello World"
        await mockConnection.setNextResponse(content)

        let data = try await workspace.readFile(path: "test.txt")
        #expect(data == content)

        let method = await mockConnection.lastMethod
        let params = await mockConnection.lastParams

        #expect(method == "workspace/readFile")

        guard let requestDict = params?.value as? [String: Any] else {
            Issue.record("Invalid parameters type: \(type(of: params?.value))")
            return
        }
        #expect(requestDict["path"] as? String == "test.txt")
    }
}
