import MonadShared
import Foundation
import Testing
@testable import MonadCore

@Suite @MainActor
struct LoopDetectionTests {

    struct MockTool: Tool, @unchecked Sendable {
        let id = "mock_tool"
        let name = "Mock Tool"
        let description = "A mock tool"
        let requiresPermission = false
        var parametersSchema: [String: Any] { [:] }
        func canExecute() async -> Bool { true }
        func execute(parameters: [String: Any]) async throws -> ToolResult {
            return .success("Executed")
        }
    }

    @Test("Test loop detection triggers after 3 identical calls")
    func testLoopDetection() async throws {
        let tool = MockTool()
        let toolManager = SessionToolManager(availableTools: [tool])
        let executor = ToolExecutor(toolManager: toolManager)

        let toolCall = ToolCall(name: "mock_tool", arguments: ["arg": AnyCodable(1)])

        // Call 1
        let res1 = try await executor.execute(toolCall)
        #expect(res1.content == "Executed")

        // Call 2
        let res2 = try await executor.execute(toolCall)
        #expect(res2.content == "Executed")

        // Call 3 - should trigger loop detection
        let res3 = try await executor.execute(toolCall)
        #expect(res3.content.contains("Loop detected"))
        #expect(res3.role == .tool)
    }

    @Test("Test loop detection reset")
    func testLoopDetectionReset() async throws {
        let tool = MockTool()
        let toolManager = SessionToolManager(availableTools: [tool])
        let executor = ToolExecutor(toolManager: toolManager)

        let toolCall = ToolCall(name: "mock_tool", arguments: ["arg": AnyCodable(1)])

        _ = try await executor.execute(toolCall)
        _ = try await executor.execute(toolCall)

        await executor.reset()

        // Call after reset should be successful
        let res = try await executor.execute(toolCall)
        #expect(res.content == "Executed")
    }

    @Test("Test different arguments do not trigger loop detection")
    func testDifferentArgs() async throws {
        let tool = MockTool()
        let toolManager = SessionToolManager(availableTools: [tool])
        let executor = ToolExecutor(toolManager: toolManager)

        for i in 1...5 {
            let toolCall = ToolCall(name: "mock_tool", arguments: ["arg": AnyCodable(i)])
            let res = try await executor.execute(toolCall)
            #expect(res.content == "Executed")
        }
    }
}
