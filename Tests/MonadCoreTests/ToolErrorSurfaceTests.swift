import Testing
import Foundation
import Dependencies
@testable import MonadCore
import OpenAI

@Suite("Tool Error Surfacing Tests")
struct ToolErrorSurfaceTests {
    
    @Test("ChatEngine emits error event when tool fails")
    func testToolErrorEmission() async throws {
        let mockPersistence = MockPersistenceService()
        let mockLLM = MockLLMService()
        
        // 1. Setup a tool that always fails
        struct FailingTool: Tool {
            let id = "fail_tool"
            let name = "fail_tool" // name must match tool call
            let description = "Always fails"
            let requiresPermission = false
            var parametersSchema: [String: AnyCodable] { ToolParameterSchema.object { _ in }.schema }
            func canExecute() async -> Bool { true }
            func execute(parameters: [String: Any]) async throws -> ToolResult {
                return .failure("Execution failed intentionally")
            }
        }
        
        let tool = FailingTool()
        let chatEngine = ChatEngine()
        
        // 2. Mock LLM to call this tool
        let toolCall = ToolCall(name: "fail_tool", arguments: [:])
        let jsonDict: [String: Any] = [
            "id": "mock",
            "object": "chat.completion.chunk",
            "created": Date().timeIntervalSince1970,
            "model": "mock-model",
            "choices": [
                [
                    "index": 0,
                    "delta": [
                        "role": "assistant",
                        "tool_calls": [[
                            "index": 0,
                            "id": "call_123",
                            "function": ["name": "fail_tool", "arguments": "{}"]
                        ]]
                    ],
                    "finish_reason": "tool_calls"
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: jsonDict)
        let result = try JSONDecoder().decode(ChatStreamResult.self, from: data)
        
        mockLLM.stubbedStream = AsyncThrowingStream { continuation in
            continuation.yield(result)
            continuation.finish()
        }
        
        // 3. Execute chat turn with dependencies
        let events = try await withDependencies {
            $0.persistenceService = mockPersistence
            $0.llmService = mockLLM
            $0.sessionManager = SessionManager(workspaceRoot: FileManager.default.temporaryDirectory)
        } operation: {
            let stream = try await chatEngine.chatStream(
                sessionId: UUID(),
                message: "Trigger tool",
                tools: [AnyTool(tool)]
            )
            return try await stream.collect()
        }
        
        // 4. Verify error event was emitted
        let hasError = events.contains { event in
            if case .toolExecution(_, let status) = event,
               case .failed(_, let error) = status {
                return error == "Execution failed intentionally"
            }
            return false
        }
        
        #expect(hasError, "Expected .toolExecution(.failed) event but none was found")
    }
}