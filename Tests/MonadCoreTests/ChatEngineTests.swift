import MonadShared
import MonadPrompt
import OpenAI
import Testing
import Foundation
import Dependencies
@testable import MonadCore

@Suite @MainActor
struct ChatEngineTests {
    
    private let sessionId = UUID()
    
    /// Helper to run a test with standard dependencies
    private func withChatEngineDependencies<T>(_ test: @Sendable (ChatEngine, MockLLMService, MockPersistenceService) async throws -> T) async throws -> T {
        let mockLLM = MockLLMService()
        let mockPersistence = MockPersistenceService()
        
        // Seed a session
        let session = ConversationSession(id: sessionId, title: "Test Session")
        try await mockPersistence.saveSession(session)
        
        return try await withDependencies {
            $0.llmService = mockLLM
            $0.persistenceService = mockPersistence
            $0.sessionManager = SessionManager(workspaceRoot: URL(fileURLWithPath: "/tmp/monad-test"))
        } operation: {
            let engine = ChatEngine()
            return try await test(engine, mockLLM, mockPersistence)
        }
    }
    
    /// Helper to collect events from a stream
    private func collect(_ stream: AsyncThrowingStream<ChatEvent, Error>) async throws -> [ChatEvent] {
        var events: [ChatEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
    
    // MARK: - Group 1: Plain Text Response
    
    @Test("Plain text response emits correct events")
    func plainTextResponse() async throws {
        try await withChatEngineDependencies { engine, mockLLM, _ in
            mockLLM.mockClient.nextResponse = "Hello, world!"
            
            let stream = try await engine.chatStream(
                sessionId: sessionId,
                message: "Hi",
                tools: []
            )
            
            let events = try await collect(stream)
            
            // Should have generationContext, delta, and generationCompleted
            #expect(events.contains(where: { if case .generationContext = $0 { return true }; return false }))
            #expect(events.contains(where: { if case .delta(let text) = $0 { return text == "Hello, world!" }; return false }))
            #expect(events.contains(where: { if case .generationCompleted = $0 { return true }; return false }))
        }
    }
    
    @Test("Response is persisted to the database")
    func responseIsPersisted() async throws {
        try await withChatEngineDependencies { engine, mockLLM, mockPersistence in
            mockLLM.mockClient.nextResponse = "Persisted reply."
            
            let stream = try await engine.chatStream(
                sessionId: sessionId,
                message: "Persistence test",
                tools: []
            )
            
            _ = try await collect(stream)
            
            let messages = try await mockPersistence.fetchMessages(for: sessionId)
            
            // Should contain user message and assistant reply
            #expect(messages.count == 2)
            #expect(messages.contains(where: { $0.role == "user" && $0.content == "Persistence test" }))
            #expect(messages.contains(where: { $0.role == "assistant" && $0.content == "Persisted reply." }))
        }
    }
    
    @Test("Empty message and no tool outputs throws error")
    func emptyMessageThrows() async throws {
        _ = try await withChatEngineDependencies { engine, _, _ in
            await #expect(throws: ToolError.self) {
                _ = try await engine.chatStream(
                    sessionId: sessionId,
                    message: "",
                    tools: []
                )
            }
        }
    }
    
    // MARK: - Group 2: Thinking / Reasoning Tags
    
    @Test("Thinking tags emit thought events")
    func thinkingTagsEmitThoughtEvents() async throws {
        try await withChatEngineDependencies { engine, mockLLM, _ in
            mockLLM.mockClient.nextChunks = [["<think>", "Reasoning...", "</think>", "Answer"]]
            
            let stream = try await engine.chatStream(
                sessionId: sessionId,
                message: "Why?",
                tools: []
            )
            
            let events = try await collect(stream)
            
            // Check sequence: thought, thoughtCompleted, delta
            var foundThought = false
            var foundThoughtCompleted = false
            var foundDelta = false
            
            for event in events {
                if case .thought(let text) = event {
                    if text == "Reasoning..." { foundThought = true }
                } else if case .thoughtCompleted = event {
                    if foundThought { foundThoughtCompleted = true }
                } else if case .delta(let text) = event {
                    if text == "Answer" { foundDelta = true }
                }
            }
            
            #expect(foundThought)
            #expect(foundThoughtCompleted)
            #expect(foundDelta)
        }
    }
    
    // MARK: - Group 3: Structured Tool Calls
    
    struct MockTool: MonadCore.Tool, @unchecked Sendable {
        let id = "mock_tool"
        let name = "mock_tool"
        let description = "A mock tool for testing"
        let requiresPermission = false
        let parametersSchema: [String: Any] = [:]
        
        var result: ToolResult = .success("Tool result")
        var shouldWait: Bool = false
        
        func canExecute() async -> Bool { true }
        
        func execute(parameters: [String: Any]) async throws -> ToolResult {
            if shouldWait { try? await Task.sleep(nanoseconds: 100_000_000) }
            if !result.success && result.error == "client_execution_required" {
                throw ToolError.clientExecutionRequired
            }
            return result
        }
    }
    
    @Test("Server-side tool call is executed and yields events")
    func serverToolCallExecuted() async throws {
        try await withChatEngineDependencies { engine, mockLLM, _ in
            let mockTool = MockTool()
            
            // Set up responses for both turns at once
            mockLLM.mockClient.nextToolCalls = [[["id": "call_1", "function": ["name": "mock_tool", "arguments": "{}"]]]]
            mockLLM.mockClient.nextResponses = ["", "Processed result"]
            
            let stream = try await engine.chatStream(
                sessionId: sessionId,
                message: "Run tool",
                tools: [mockTool.toAnyTool()]
            )
            
            let events = try await collect(stream)
            
            // Should see toolCall delta
            #expect(events.contains(where: { if case .toolCall(let delta) = $0 { return delta.name == "mock_tool" }; return false }))
            
            // Should see tool execution events
            #expect(events.contains(where: { 
                if case .toolExecution(let id, let status) = $0 {
                    if case .attempting = status { return id == "call_1" }
                }
                return false
            }))
            #expect(events.contains(where: { 
                if case .toolExecution(let id, let status) = $0 {
                    if case .success(let result) = status { return id == "call_1" && result.output == "Tool result" }
                }
                return false
            }))
            
            // Final response
            #expect(events.contains(where: { if case .delta(let text) = $0 { return text == "Processed result" }; return false }))
        }
    }
    
    @Test("Sentinel name 'tool_call' is discarded")
    func sentinelToolNameDiscarded() async throws {
        try await withChatEngineDependencies { engine, mockLLM, _ in
            // Emit "tool_call" name which is a sentinel for some models
            mockLLM.mockClient.nextToolCalls = [[["id": "call_1", "function": ["name": "tool_call", "arguments": "{}"]]]]
            mockLLM.mockClient.nextResponses = ["Ignored tool name"]
            
            let stream = try await engine.chatStream(
                sessionId: sessionId,
                message: "Run sentinel",
                tools: [MockTool().toAnyTool()]
            )
            
            let events = try await collect(stream)
            
            // Should NOT have toolExecution events for "tool_call"
            #expect(!events.contains(where: { if case .toolExecution = $0 { return true }; return false }))
            // Should just see the plain text delta
            #expect(events.contains(where: { if case .delta(let text) = $0 { return text == "Ignored tool name" }; return false }))
        }
    }
    
    @Test("Unknown tool name is discarded")
    func unknownToolNameDiscarded() async throws {
        try await withChatEngineDependencies { engine, mockLLM, _ in
            mockLLM.mockClient.nextToolCalls = [[["id": "call_1", "function": ["name": "unknown_tool", "arguments": "{}"]]]]
            mockLLM.mockClient.nextResponses = ["Unknown tool call"]
            
            let stream = try await engine.chatStream(
                sessionId: sessionId,
                message: "Run unknown",
                tools: [MockTool().toAnyTool()]
            )
            
            let events = try await collect(stream)
            
            // Should NOT have toolExecution events
            #expect(!events.contains(where: { if case .toolExecution = $0 { return true }; return false }))
            #expect(events.contains(where: { if case .delta(let text) = $0 { return text == "Unknown tool call" }; return false }))
        }
    }
    
    @Test("Client tool execution pauses the stream")
    func clientToolCallPausesStream() async throws {
        try await withChatEngineDependencies { engine, mockLLM, _ in
            var mockTool = MockTool()
            mockTool.result = .failure("client_execution_required")
            
            mockLLM.mockClient.nextToolCalls = [[["id": "call_1", "function": ["name": "mock_tool", "arguments": "{}"]]]]
            mockLLM.mockClient.nextResponses = ["Pause here"]
            
            let stream = try await engine.chatStream(
                sessionId: sessionId,
                message: "Run client tool",
                tools: [mockTool.toAnyTool()]
            )
            
            let events = try await collect(stream)
            
            // Should emit attempt but NOT success/failure (handled by client)
            #expect(events.contains(where: { 
                if case .toolExecution(let id, let status) = $0 {
                    if case .attempting = status { return id == "call_1" }
                }
                return false
            }))
            
            // Should NOT have success or failure since engine stops
            #expect(!events.contains(where: { 
                if case .toolExecution(_, let status) = $0 {
                    switch status {
                    case .success, .failure: return true
                    default: return false
                    }
                }
                return false
            }))
            
            // Should reach generationCompleted
            #expect(events.contains(where: { if case .generationCompleted = $0 { return true }; return false }))
        }
    }
    
    @Test("Failing tool returns error result to LLM")
    func failingToolReturnsErrorResult() async throws {
        try await withChatEngineDependencies { engine, mockLLM, _ in
            var mockTool = MockTool()
            mockTool.result = .failure("Tool failed")
            
            // Set up responses for both turns
            mockLLM.mockClient.nextToolCalls = [[["id": "call_1", "function": ["name": "mock_tool", "arguments": "{}"]]]]
            mockLLM.mockClient.nextResponses = ["", "It failed."]
            
            let stream = try await engine.chatStream(
                sessionId: sessionId,
                message: "Fail tool",
                tools: [mockTool.toAnyTool()]
            )
            
            let events = try await collect(stream)
            
            #expect(events.contains(where: { 
                if case .toolExecution(let id, let status) = $0 {
                    if case .failure = status { return id == "call_1" }
                }
                return false
            }))
            
            #expect(events.contains(where: { if case .delta(let text) = $0 { return text == "It failed." }; return false }))
        }
    }
    
    // MARK: - Group 4: Fallback XML Parsing
    
    @Test("XML fallback tool call is executed")
    func xmlFallbackToolCallExecuted() async throws {
        try await withChatEngineDependencies { engine, mockLLM, _ in
            let mockTool = MockTool()
            
            // Set up responses for both turns
            mockLLM.mockClient.nextResponses = [
                "<tool_call>{\"name\":\"mock_tool\",\"arguments\":{}}</tool_call>",
                "Fallback worked"
            ]
            
            let stream = try await engine.chatStream(
                sessionId: sessionId,
                message: "Run XML tool",
                tools: [mockTool.toAnyTool()]
            )
            
            let events = try await collect(stream)
            
            // Fallback should yield a .toolCall event for UI
            #expect(events.contains(where: { if case .toolCall(let delta) = $0 { return delta.name == "mock_tool" }; return false }))
            
            // Should see tool execution
            #expect(events.contains(where: { 
                if case .toolExecution(_, let status) = $0 {
                    if case .success(let result) = status { return result.output == "Tool result" }
                }
                return false
            }))
            
            #expect(events.contains(where: { if case .delta(let text) = $0 { return text == "Fallback worked" }; return false }))
        }
    }
    
    // MARK: - Group 5: Multi-Turn & Loop Control
    
    @Test("maxTurns limits the generation loop")
    func maxTurnsLimitsLoop() async throws {
        try await withChatEngineDependencies { engine, mockLLM, _ in
            let mockTool = MockTool()
            // Setup a loop: LLM calls tool, tool returns result, LLM calls tool again...
            mockLLM.mockClient.nextToolCalls = [
                [["id": "c1", "function": ["name": "mock_tool", "arguments": "{}"]]],
                [["id": "c2", "function": ["name": "mock_tool", "arguments": "{}"]]],
                [["id": "c3", "function": ["name": "mock_tool", "arguments": "{}"]]]
            ]
            mockLLM.mockClient.nextResponses = ["", "", ""]
            
            let stream = try await engine.chatStream(
                sessionId: sessionId,
                message: "Infinite tools",
                tools: [mockTool.toAnyTool()],
                maxTurns: 2 // Limit to 2 turns
            )
            
            let events = try await collect(stream)
            
            // Should have executed exactly 2 tools (id c1 and c2)
            let successEvents = events.filter {
                if case .toolExecution(_, let status) = $0, case .success = status { return true }
                return false
            }
            #expect(successEvents.count == 2)
            
            // Should finish cleanly without error
            #expect(events.contains(where: { if case .generationCompleted = $0 { return true }; return false }))
        }
    }
    
    @Test("LLM service errors are propagated through the stream")
    func llmErrorPropagated() async throws {
        try await withChatEngineDependencies { engine, mockLLM, _ in
            mockLLM.mockClient.shouldThrowError = true
            
            let stream = try await engine.chatStream(
                sessionId: sessionId,
                message: "Trigger error",
                tools: []
            )
            
            await #expect(throws: (any Error).self) {
                for try await _ in stream {}
            }
        }
    }
    
    // MARK: - Group 6: Metadata & Context Events
    
    @Test("Generation context event is emitted first")
    func generationContextEventEmittedFirst() async throws {
        try await withChatEngineDependencies { engine, mockLLM, _ in
            mockLLM.mockClient.nextResponse = "Hello"
            
            let stream = try await engine.chatStream(
                sessionId: sessionId,
                message: "Hi",
                tools: []
            )
            
            var firstEvent: ChatEvent? = nil
            for try await event in stream {
                firstEvent = event
                break
            }
            
            if let first = firstEvent {
                if case .generationContext = first {
                    // Success
                } else {
                    #expect(Bool(false), "First event should be generationContext, got \(first)")
                }
            } else {
                #expect(Bool(false), "Stream was empty")
            }
        }
    }
}
