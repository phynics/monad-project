import XCTest
import Foundation
@testable import MonadCore
@testable import MonadShared

final class SessionToolManagerTests: XCTestCase {
    
    struct MockTool: MonadShared.Tool, @unchecked Sendable {
        let id: String
        let name: String
        let description = "A mock tool for testing"
        let requiresPermission = false
        var parametersSchema: [String: AnyCodable] { [:] }
        
        func canExecute() async -> Bool { true }
        func execute(parameters: [String: Any]) async throws -> ToolResult {
            return .success("Executed \(name)")
        }
    }
    
    struct MockWorkspace: WorkspaceProtocol, @unchecked Sendable {
        let id: UUID
        let reference: WorkspaceReference
        let toolsToReturn: [ToolReference]
        
        func listTools() async throws -> [ToolReference] { toolsToReturn }
        func executeTool(id: String, parameters: [String: AnyCodable]) async throws -> ToolResult { .success("Workspace tool executed") }
        func readFile(path: String) async throws -> String { "" }
        func writeFile(path: String, content: String) async throws {}
        func listFiles(path: String) async throws -> [String] { [] }
        func deleteFile(path: String) async throws {}
        func healthCheck() async -> Bool { true }
    }
    
    func testInitEnablesAllAvailableTools() async throws {
        let systemTool1 = AnyTool(MockTool(id: "sys1", name: "System 1"))
        let systemTool2 = AnyTool(MockTool(id: "sys2", name: "System 2"))
        
        let manager = SessionToolManager(availableTools: [systemTool1, systemTool2])
        
        let enabled = await manager.enabledTools
        XCTAssertEqual(enabled.count, 2)
        XCTAssertTrue(enabled.contains("sys1"))
        XCTAssertTrue(enabled.contains("sys2"))
        
        let fetchedEnabled = await manager.getEnabledTools()
        XCTAssertEqual(fetchedEnabled.count, 2)
    }
    
    func testUpdateAvailableToolsAutoEnablesNewTools() async throws {
        let systemTool1 = AnyTool(MockTool(id: "sys1", name: "System 1"))
        let manager = SessionToolManager(availableTools: [systemTool1])
        
        // Add a new tool, and simulate one being removed
        let systemTool2 = AnyTool(MockTool(id: "sys2", name: "System 2"))
        await manager.updateAvailableTools([systemTool2])
        
        let enabled = await manager.enabledTools
        XCTAssertEqual(enabled.count, 1) // Only sys2
        XCTAssertTrue(enabled.contains("sys2"))
        XCTAssertFalse(enabled.contains("sys1"))
    }
    
    func testToggleEnableDisableTools() async throws {
        let systemTool1 = AnyTool(MockTool(id: "sys1", name: "System 1"))
        let manager = SessionToolManager(availableTools: [systemTool1])
        
        var enabled = await manager.enabledTools
        XCTAssertTrue(enabled.contains("sys1"))
        
        await manager.disableTool(id: "sys1")
        enabled = await manager.enabledTools
        XCTAssertFalse(enabled.contains("sys1"))
        
        await manager.enableTool(id: "sys1")
        enabled = await manager.enabledTools
        XCTAssertTrue(enabled.contains("sys1"))
        
        await manager.toggleTool("sys1")
        enabled = await manager.enabledTools
        XCTAssertFalse(enabled.contains("sys1"))
    }
    
    func testWorkspaceToolRegistration() async throws {
        let manager = SessionToolManager(availableTools: [])
        
        let workspaceId = UUID()
        let workspaceRef = WorkspaceReference(id: workspaceId, uri: WorkspaceURI(parsing: "monad://test")!, hostType: .server, ownerId: nil)
        
        let def = WorkspaceToolDefinition(
            id: "wsTool1",
            name: "wsTool1",
            description: "A workspace tool",
            parametersSchema: ["type": AnyCodable("object")]
        )
        
        let mockWS = MockWorkspace(
            id: workspaceId,
            reference: workspaceRef,
            toolsToReturn: [.custom(def)]
        )
        
        await manager.registerWorkspace(mockWS)
        
        let available = await manager.getAvailableTools()
        XCTAssertEqual(available.count, 1)
        XCTAssertEqual(available.first?.name, "wsTool1")
        
        // Unregister
        await manager.unregisterWorkspace(workspaceId)
        let availableAfter = await manager.getAvailableTools()
        XCTAssertTrue(availableAfter.isEmpty)
    }
    
    func testGetToolResolvesCorrectly() async throws {
        let systemTool = AnyTool(MockTool(id: "sys1", name: "System 1"))
        let manager = SessionToolManager(availableTools: [systemTool])
        
        let sysResult = await manager.getTool(id: "sys1")
        XCTAssertNotNil(sysResult)
        XCTAssertEqual(sysResult?.name, "System 1")
        
        // Workspace tool resolution
        let workspaceId = UUID()
        let def = WorkspaceToolDefinition(id: "wsTool", name: "wsTool", description: "WS", parametersSchema: [:])
        let mockWS = MockWorkspace(
            id: workspaceId,
            reference: WorkspaceReference(id: workspaceId, uri: WorkspaceURI(parsing: "monad://test")!, hostType: .server, ownerId: nil),
            toolsToReturn: [.custom(def)]
        )
        await manager.registerWorkspace(mockWS)
        
        // The ID of the generic custom workspace tool wrap is something like "\(workspaceId)-\(def.name)"
        // Since we don't know the exact ID format in the test, we can just check getAvailableTools
        let available = await manager.getAvailableTools()
        let wsToolWrapper = available.first(where: { $0.name == "wsTool" })
        XCTAssertNotNil(wsToolWrapper)
        
        if let wsToolId = wsToolWrapper?.id {
            let fetched = await manager.getTool(id: wsToolId)
            XCTAssertNotNil(fetched)
            XCTAssertEqual(fetched?.name, "wsTool")
        }
    }

    func testWorkspaceToolsHaveProvenance() async throws {
        let manager = SessionToolManager(availableTools: [])
        let workspaceId = UUID()
        let uri = WorkspaceURI(parsing: "monad://test-workspace-prov")!
        let workspaceRef = WorkspaceReference(id: workspaceId, uri: uri, hostType: .server, ownerId: nil)

        let def = WorkspaceToolDefinition(id: "provTool", name: "provTool", description: "prov", parametersSchema: [:])
        let mockWS = MockWorkspace(id: workspaceId, reference: workspaceRef, toolsToReturn: [.custom(def)])

        await manager.registerWorkspace(mockWS)

        // Verify the tool has the expected provenance injected
        let available = await manager.getAvailableTools()
        let tool = available.first(where: { $0.name == "provTool" })
        XCTAssertNotNil(tool)
        XCTAssertEqual(tool?.provenance, "Workspace: monad://test-workspace-prov")
        
        let fetched = await manager.getTool(id: tool!.id)
        XCTAssertEqual(fetched?.provenance, "Workspace: monad://test-workspace-prov")
    }

    func testKnownToolRefsResolved() async throws {
        let systemTool = AnyTool(MockTool(id: "cat", name: "cat"))
        let manager = SessionToolManager(availableTools: [systemTool])

        let workspaceId = UUID()
        let uri = WorkspaceURI(parsing: "monad://test-known-tool")!
        let workspaceRef = WorkspaceReference(id: workspaceId, uri: uri, hostType: .server, ownerId: nil)

        // Workspace declares it offers the "cat" known tool
        let mockWS = MockWorkspace(id: workspaceId, reference: workspaceRef, toolsToReturn: [.known(id: "cat")])

        await manager.registerWorkspace(mockWS)

        // The system tool should now have provenance indicating it is tied to the workspace
        let available = await manager.getAvailableTools()
        let tool = available.first(where: { $0.id == "cat" })
        XCTAssertNotNil(tool)
        XCTAssertEqual(tool?.provenance, "Workspace: monad://test-known-tool")

        let fetched = await manager.getTool(id: "cat")
        XCTAssertEqual(fetched?.provenance, "Workspace: monad://test-known-tool")
    }
}
