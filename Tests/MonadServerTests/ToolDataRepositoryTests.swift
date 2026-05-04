import Foundation
import GRDB
import MonadServer
import PKShared
import Testing

@Suite(.serialized)
struct ToolDataRepositoryTests {
    @Test("workspace tool membership is unique per workspace and tool ID")
    func workspaceToolMembership_isUnique() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        let workspaceStore = WorkspaceDataRepository(dbQueue: queue)
        let toolStore = ToolDataRepository(dbQueue: queue)

        let workspaceId = UUID()
        let workspace = WorkspaceReference(
            id: workspaceId,
            uri: .timelineWorkspace(workspaceId),
            location: .runtime
        )
        try await workspaceStore.saveWorkspace(workspace)

        try await toolStore.addToolToWorkspace(workspaceId: workspaceId, tool: .known("bash"))
        try await toolStore.addToolToWorkspace(workspaceId: workspaceId, tool: .known("bash"))

        let tools = try await toolStore.fetchTools(forWorkspaces: [workspaceId])
        #expect(tools == [.known("bash")])
    }
}
