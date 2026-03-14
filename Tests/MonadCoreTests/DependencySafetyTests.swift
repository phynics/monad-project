import Dependencies
import Foundation
@testable import MonadCore
@testable import MonadShared
import MonadTestSupport
import Testing

@Suite("Dependency Safety Tests")
struct DependencySafetyTests {
    @Test("AgentInstanceManager correctly resolves overridden agentWorkspaceService")
    func agentInstanceManagerDependencyInjection() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let customRepo = AgentWorkspaceService(workspaceRoot: tempDir)
        let persistence = MockPersistenceService()

        try await withDependencies {
            $0.agentWorkspaceService = customRepo
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
                   let workspace = try await workspaceStore.fetchWorkspace(id: workspaceId)
                {
                    #expect(workspace.rootPath?.contains(tempDir.path) ?? false)
                } else {
                    Issue.record("Workspace not found for created instance")
                }
            }
        }
    }
}
