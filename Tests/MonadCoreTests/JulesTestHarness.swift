import Testing
import Foundation
import GRDB
@testable import MonadCore

@Suite("Jules Integration Harness")
@MainActor
struct JulesTestHarness {

    // MARK: - Mocks

    struct MockTool: Tool {
        let id: String
        let name: String
        let description: String
        let requiresPermission: Bool
        let executionBlock: ([String: Any]) async throws -> ToolResult

        var parametersSchema: [String: Any] { [:] }

        func canExecute() async -> Bool { true }

        func execute(parameters: [String: Any]) async throws -> ToolResult {
            try await executionBlock(parameters)
        }
    }

    // MARK: - Persistence Integration Tests

    @Test("Persistence: Complete Session Lifecycle")
    func persistenceLifecycle() async throws {
        // Setup in-memory DB
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)
        let persistence = PersistenceService(dbQueue: queue)

        // 1. Create Session
        let session = ConversationSession(title: "Jules Test Session")
        try await persistence.saveSession(session)

        let fetchedSession = try await persistence.fetchSession(id: session.id)
        #expect(fetchedSession != nil)
        #expect(fetchedSession?.title == "Jules Test Session")

        // 2. Add Messages
        let msg1 = ConversationMessage(sessionId: session.id, role: .user, content: "Hello")
        try await persistence.saveMessage(msg1)

        let msg2 = ConversationMessage(sessionId: session.id, role: .assistant, content: "Hi there")
        try await persistence.saveMessage(msg2)

        let messages = try await persistence.fetchMessages(for: session.id)
        #expect(messages.count == 2)
        #expect(messages.contains { $0.content == "Hello" })
        #expect(messages.contains { $0.content == "Hi there" })

        // 3. Archive Session
        var sessionToArchive = fetchedSession!
        sessionToArchive.isArchived = true
        try await persistence.saveSession(sessionToArchive)

        let archivedSessions = try await persistence.fetchAllSessions(includeArchived: true)
        #expect(archivedSessions.first { $0.id == session.id }?.isArchived == true)

        // 4. Verify Immutability (Delete should fail)
        await #expect(throws: Error.self) {
            try await persistence.deleteSession(id: session.id)
        }
    }

    // MARK: - Tool Execution Integration Tests

    @Test("Tool Execution: Chained Execution")
    func toolExecutionChain() async throws {
        // Setup Tools
        let tool1 = MockTool(
            id: "step1",
            name: "Step 1",
            description: "First step",
            requiresPermission: false
        ) { params in
            return .success("Step 1 Complete")
        }

        let tool2 = MockTool(
            id: "step2",
            name: "Step 2",
            description: "Second step",
            requiresPermission: true
        ) { params in
            return .success("Step 2 Complete")
        }

        let manager = await SessionToolManager(availableTools: [tool1, tool2])
        let executor = await ToolExecutor(toolManager: manager)

        // Execute Tool 1
        let call1 = ToolCall(name: "step1", arguments: [:])
        let result1 = try await executor.execute(call1)
        #expect(result1.role == .tool)
        #expect(result1.content == "Step 1 Complete")

        // Execute Tool 2
        let call2 = ToolCall(name: "step2", arguments: [:])
        let result2 = try await executor.execute(call2)
        #expect(result2.role == .tool)
        #expect(result2.content == "Step 2 Complete")

        // Batch Execution
        let results = await executor.executeAll([call1, call2])
        #expect(results.count == 2)
        #expect(results.map { $0.content }.sorted() == ["Step 1 Complete", "Step 2 Complete"])
    }

    // MARK: - Streaming Coordination Tests

    @Test("Streaming: Complex Thinking and Tool Calls")
    func streamingComplexFlow() async {
        let coordinator = StreamingCoordinator()
        coordinator.startStreaming()

        // simulate chunks
        // 1. Thinking
        coordinator.processChunk("<think>Planning")
        coordinator.processChunk(" the next step</think>")

        // 2. Content
        coordinator.processChunk("I will now call the tool.")

        // 3. Native Tool Call Simulation
        // We use structs that mirror the expected structure for reflection
        struct MockToolCall {
            let index: Int
            let id: String?
            let function: MockFunction?
        }
        struct MockFunction {
            let name: String?
            let arguments: String?
        }

        let toolChunk1 = MockToolCall(index: 0, id: "call_123", function: MockFunction(name: "weather", arguments: ""))
        let toolChunk2 = MockToolCall(index: 0, id: nil, function: MockFunction(name: nil, arguments: "{\"loc"))
        let toolChunk3 = MockToolCall(index: 0, id: nil, function: MockFunction(name: nil, arguments: "ation\": \"NYC\"}"))

        coordinator.processToolCalls([toolChunk1])
        coordinator.processToolCalls([toolChunk2])
        coordinator.processToolCalls([toolChunk3])

        let message = coordinator.finalize()

        #expect(message.role == .assistant)
        #expect(message.think == "Planning the next step")
        #expect(message.content == "I will now call the tool.")

        // Verify tool calls
        #expect(message.toolCalls?.count == 1)
        let toolCall = message.toolCalls?.first
        #expect(toolCall?.name == "weather")

        let args = toolCall?.arguments
        #expect(args?["location"]?.value as? String == "NYC")
    }
}
