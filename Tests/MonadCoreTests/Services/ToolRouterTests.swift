import XCTest
import Foundation
import MonadTestSupport
@testable import MonadCore
@testable import MonadShared
import Dependencies

final class ToolRouterTests: XCTestCase {
    
    struct MockTool: MonadShared.Tool, @unchecked Sendable {
        let id: String
        let name: String
        let description = "A mock tool for testing"
        let requiresPermission = false
        var parametersSchema: [String: AnyCodable] { [:] }
        var result: ToolResult
        
        func canExecute() async -> Bool { true }
        
        func execute(parameters: [String: Any]) async throws -> ToolResult {
            if !result.success, result.error == "client_execution_required" {
                throw ToolError.clientExecutionRequired
            }
            return result
        }
    }
    
    private func setupTimelineManager() async throws -> (TimelineManager, MockPersistenceService) {
        let mockPersistence = MockPersistenceService()
        let timelineManager = try await withDependencies {
            $0.timelinePersistence = mockPersistence
            $0.workspacePersistence = mockPersistence
            $0.memoryStore = mockPersistence
            $0.messageStore = mockPersistence
            $0.msAgentStore = mockPersistence
            $0.backgroundJobStore = mockPersistence
            $0.clientStore = mockPersistence
            $0.toolPersistence = mockPersistence
            $0.agentInstanceStore = mockPersistence
            $0.embeddingService = MockEmbeddingService()
            $0.llmService = MockLLMService()
            $0.msAgentRegistry = MSAgentRegistry()
        } operation: {
            TimelineManager(workspaceRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        }
        return (timelineManager, mockPersistence)
    }
    
    func testExecuteLocally() async throws {
        let (timelineManager, mockPersistence) = try await setupTimelineManager()
        let toolRouter = try await withDependencies {
            $0.timelineManager = timelineManager
        } operation: {
            ToolRouter()
        }
        
        // Setup session and local workspace
        let session = try await timelineManager.createTimeline()
        let workspaceId = UUID()
        let workspaceRef = WorkspaceReference(id: workspaceId, uri: WorkspaceURI(parsing: "monad://local")!, hostType: .server, ownerId: nil)
        
        // Mock persistence expects WorkspaceReference
        try await mockPersistence.saveWorkspace(workspaceRef)
        try await timelineManager.attachWorkspace(workspaceId, to: session.id)
        
        // Setup internal tools by extracting the ToolManager
        let toolManager = await timelineManager.getToolManager(for: session.id)
        XCTAssertNotNil(toolManager)
        
        let toolId = "local_tool"
        let mockTool = MockTool(id: toolId, name: toolId, result: .success("Local success"))
        await toolManager?.updateAvailableTools([mockTool.toAnyTool()])
        
        // The mock persistence doesn't automatically wire tool IDs to workspaces for `findWorkspaceForTool`
        // We simulate `addToolToWorkspace` or just rely on the tool manager falling back to the candidates.
        try await mockPersistence.addToolToWorkspace(workspaceId: workspaceId, tool: .known(toolId))
        
        let toolRef = ToolReference.known(toolId)
        let arguments: [String: AnyCodable] = ["param": AnyCodable("value")]
        
        let result = try await toolRouter.execute(tool: toolRef, arguments: arguments, timelineId: session.id)
        XCTAssertEqual(result, "Local success")
    }
    
    func testExecuteRemotelyThrowsClientExecutionRequired() async throws {
        let (timelineManager, mockPersistence) = try await setupTimelineManager()
        let toolRouter = try await withDependencies {
            $0.timelineManager = timelineManager
        } operation: {
            ToolRouter()
        }
        
        let session = try await timelineManager.createTimeline()
        let workspaceId = UUID()
        
        // Setup remote workspace
        let workspaceRef = WorkspaceReference(id: workspaceId, uri: WorkspaceURI(parsing: "monad://remote")!, hostType: .client, ownerId: UUID())
        try await mockPersistence.saveWorkspace(workspaceRef)
        try await timelineManager.attachWorkspace(workspaceId, to: session.id)
        
        let toolId = "remote_tool"
        try await mockPersistence.addToolToWorkspace(workspaceId: workspaceId, tool: .known(toolId))
        
        let toolRef = ToolReference.known(toolId)
        let arguments: [String: AnyCodable] = [:]
        
        do {
            _ = try await toolRouter.execute(tool: toolRef, arguments: arguments, timelineId: session.id)
            XCTFail("Should have thrown clientExecutionRequired")
        } catch ToolError.clientExecutionRequired {
            // Expected
        } catch {
            XCTFail("Unexpected error thrown: \(error)")
        }
    }
    
    func testExecuteRemotelyWithoutClientThrowsClientNotConnected() async throws {
        let (timelineManager, mockPersistence) = try await setupTimelineManager()
        let toolRouter = try await withDependencies {
            $0.timelineManager = timelineManager
        } operation: {
            ToolRouter()
        }
        
        let session = try await timelineManager.createTimeline()
        let workspaceId = UUID()
        
        // Setup remote workspace missing an ownerId
        let workspaceRef = WorkspaceReference(id: workspaceId, uri: WorkspaceURI(parsing: "monad://remote")!, hostType: .client, ownerId: nil)
        try await mockPersistence.saveWorkspace(workspaceRef)
        try await timelineManager.attachWorkspace(workspaceId, to: session.id)
        
        let toolId = "remote_tool"
        try await mockPersistence.addToolToWorkspace(workspaceId: workspaceId, tool: .known(toolId))
        
        let toolRef = ToolReference.known(toolId)
        let arguments: [String: AnyCodable] = [:]
        
        do {
            _ = try await toolRouter.execute(tool: toolRef, arguments: arguments, timelineId: session.id)
            XCTFail("Should have thrown clientNotConnected")
        } catch ToolError.clientNotConnected {
            // Expected
        } catch {
            XCTFail("Unexpected error thrown: \(error)")
        }
    }
    
    func testExecuteToolNotFound() async throws {
        let (timelineManager, _) = try await setupTimelineManager()
        let toolRouter = try await withDependencies {
            $0.timelineManager = timelineManager
        } operation: {
            ToolRouter()
        }
        
        let session = try await timelineManager.createTimeline()
        let toolRef = ToolReference.known("unknown")
        let arguments: [String: AnyCodable] = [:]
        
        do {
            _ = try await toolRouter.execute(tool: toolRef, arguments: arguments, timelineId: session.id)
            XCTFail("Should have thrown toolNotFound")
        } catch ToolError.toolNotFound {
            // Expected
        } catch {
            XCTFail("Unexpected error thrown: \(error)")
        }
    }
}
