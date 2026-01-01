import Foundation
import GRDB
import Shared
import Testing

@testable import MonadAssistant

@Suite(.serialized)
@MainActor
struct EditMemoryToolTests {
    private let persistenceManager: PersistenceManager
    private let tool: EditMemoryTool

    init() async throws {
        // Use an in-memory database for testing
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        let persistence = PersistenceService(dbQueue: queue)
        persistenceManager = PersistenceManager(persistence: persistence)
        tool = EditMemoryTool(persistenceManager: persistenceManager)
    }

    @Test("Test editing title only")
    func editTitle() async throws {
        let memory = Memory(title: "Old Title", content: "Content")
        try await persistenceManager.saveMemory(memory)

        let result = try await tool.execute(parameters: [
            "memory_id": memory.id.uuidString,
            "title": "New Title",
        ])

        #expect(result.success, "Tool execution should succeed")

        let updated = try await persistenceManager.fetchMemory(id: memory.id)
        #expect(updated?.title == "New Title")
        #expect(updated?.content == "Content")
    }

    @Test("Test replacing full content")
    func editContentFull() async throws {
        let memory = Memory(title: "Title", content: "Old Content")
        try await persistenceManager.saveMemory(memory)

        let result = try await tool.execute(parameters: [
            "memory_id": memory.id.uuidString,
            "content": "New Content",
        ])

        #expect(result.success, "Tool execution should succeed")

        let updated = try await persistenceManager.fetchMemory(id: memory.id)
        #expect(updated?.content == "New Content")
    }

    @Test("Test appending line")
    func appendLine() async throws {
        let memory = Memory(title: "Title", content: "Line 1")
        try await persistenceManager.saveMemory(memory)

        let result = try await tool.execute(parameters: [
            "memory_id": memory.id.uuidString,
            "content": "Line 2",
            "line_index": -1,
        ])

        #expect(result.success, "Tool execution should succeed")

        let updated = try await persistenceManager.fetchMemory(id: memory.id)
        #expect(updated?.content == "Line 1\nLine 2")
    }

    @Test("Test replacing specific line")
    func replaceLine() async throws {
        let memory = Memory(title: "Title", content: "Line 1\nLine 2\nLine 3")
        try await persistenceManager.saveMemory(memory)

        let result = try await tool.execute(parameters: [
            "memory_id": memory.id.uuidString,
            "content": "Modified Line 2",
            "line_index": 1,
        ])

        #expect(result.success, "Tool execution should succeed")

        let updated = try await persistenceManager.fetchMemory(id: memory.id)
        #expect(updated?.content == "Line 1\nModified Line 2\nLine 3")
    }

    @Test("Test out of bounds line index")
    func outOfBoundsLine() async throws {
        let memory = Memory(title: "Title", content: "Line 1")
        try await persistenceManager.saveMemory(memory)

        let result = try await tool.execute(parameters: [
            "memory_id": memory.id.uuidString,
            "content": "Too far",
            "line_index": 5,
        ])

        #expect(!result.success, "Expected failure for out of bounds index")
        #expect(result.error?.contains("out of bounds") == true)

        // Ensure no change
        let notUpdated = try await persistenceManager.fetchMemory(id: memory.id)
        #expect(notUpdated?.content == "Line 1")
    }
}
