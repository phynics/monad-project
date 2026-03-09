import Testing
import Foundation
import Dependencies
import MonadTestSupport
@testable import MonadCore
@testable import MonadShared

@Suite("Dependency Safety Tests")
struct DependencySafetyTests {
    
    @Test("AgentInstanceManager correctly resolves overridden workspaceRepository")
    func testAgentInstanceManagerDependencyInjection() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let customRepo = WorkspaceRepository(workspaceRoot: tempDir)
        let persistence = MockPersistenceService()
        
        try await withDependencies {
            $0.workspaceRepository = customRepo
            $0.workspacePersistence = persistence
            $0.agentInstanceStore = persistence
            $0.timelinePersistence = persistence
            $0.messageStore = persistence
            $0.agentTemplateStore = persistence
        } operation: {
            // We must also provide a test value for agentInstanceManager if it's not defined
            try await withDependencies {
                $0.agentInstanceManager = AgentInstanceManager(repository: customRepo)
            } operation: {
                @Dependency(\.agentInstanceManager) var manager
                
                let instance = try await manager.createInstance(name: "Test", description: "Test")
                
                @Dependency(\.workspacePersistence) var workspaceStore
                if let workspaceId = instance.primaryWorkspaceId,
                   let workspace = try await workspaceStore.fetchWorkspace(id: workspaceId) {
                    #expect(workspace.rootPath?.contains(tempDir.path) ?? false)
                } else {
                    Issue.record("Workspace not found for created instance")
                }
            }
        }
    }
}
