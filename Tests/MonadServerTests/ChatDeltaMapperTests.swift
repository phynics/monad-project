import Testing
import Foundation
@testable import MonadServer
import MonadCore
import MonadShared

@Suite struct ChatDeltaMapperTests {

    @Test("Map simple events")
    func testSimpleEvents() {
        // .generationContext
        let metaJson = """
        {"memories":[], "files":[]}
        """.data(using: .utf8)!
        let meta = try! JSONDecoder().decode(ChatMetadata.self, from: metaJson)
        let deltaContext = ChatDeltaMapper.mapEvent(ChatEvent.generationContext(meta))
        #expect(deltaContext.type == StreamEventType.generationContext)

        // .delta
        let deltaContent = ChatDeltaMapper.mapEvent(ChatEvent.delta("Hello"))
        #expect(deltaContent.type == .delta)
        #expect(deltaContent.content == "Hello")

        // .thought
        let deltaThought = ChatDeltaMapper.mapEvent(ChatEvent.thought("Thinking"))
        #expect(deltaThought.type == StreamEventType.thought)
        #expect(deltaThought.thought == "Thinking")

        // .thoughtCompleted
        let deltaThoughtDone = ChatDeltaMapper.mapEvent(ChatEvent.thoughtCompleted)
        #expect(deltaThoughtDone.type == .thoughtCompleted)
    }

    @Test("Map errors")
    func testErrors() {
        // .error generic
        struct DummyError: Error, LocalizedError {
            var errorDescription: String? { "Dummy error text" }
        }
        let deltaError = ChatDeltaMapper.mapEvent(ChatEvent.error(DummyError()))
        #expect(deltaError.type == .error)
        #expect(deltaError.error == "Dummy error text")

        // .error CancellationError
        let deltaCancel = ChatDeltaMapper.mapEvent(ChatEvent.error(CancellationError()))
        #expect(deltaCancel.type == .generationCancelled)
    }

    @Test("Map tool calls and errors")
    func testToolCalls() throws {
        // .toolCall
        let tcJson = """
        {"index":0,"id":"call_1","type":"function","function":{"name":"f1","arguments":"{}"}}
        """.data(using: .utf8)!
        let tc = try JSONDecoder().decode(ToolCallDelta.self, from: tcJson)
        let deltaTC = ChatDeltaMapper.mapEvent(ChatEvent.toolCall(tc))
        #expect(deltaTC.type == StreamEventType.toolCall)
        #expect(deltaTC.toolCalls?.first?.id == "call_1")

        // .toolCallError
        let deltaTCErr = ChatDeltaMapper.mapEvent(ChatEvent.toolCallError(toolCallId: "call_2", name: "f2", error: "Not found"))
        #expect(deltaTCErr.type == .toolCallError)
        #expect(deltaTCErr.toolCallError?.toolCallId == "call_2")
        #expect(deltaTCErr.toolCallError?.name == "f2")
        #expect(deltaTCErr.toolCallError?.error == "Not found")
    }

    @Test("Map tool execution status")
    func testToolExecution() {
        // .attempting (known)
        let attemptKnown = ChatDeltaMapper.mapEvent(ChatEvent.toolExecution(toolCallId: "call_1", status: .attempting(name: "f1", reference: .known("f1"))))
        #expect(attemptKnown.type == .toolExecution)
        #expect(attemptKnown.toolExecution?.status == "attempting")
        #expect(attemptKnown.toolExecution?.target == "server")

        // .attempting (custom)
        let def = WorkspaceToolDefinition(id: "c1", name: "c1", description: "", parametersSchema: [:])
        let attemptCustom = ChatDeltaMapper.mapEvent(ChatEvent.toolExecution(toolCallId: "call_2", status: .attempting(name: "c1", reference: .custom(def))))
        #expect(attemptCustom.toolExecution?.status == "attempting")
        #expect(attemptCustom.toolExecution?.target == "client")

        // .success
        let resSuccess = ToolResult.success("Output")
        let successDelta = ChatDeltaMapper.mapEvent(ChatEvent.toolExecution(toolCallId: "call_3", status: .success(resSuccess)))
        #expect(successDelta.toolExecution?.status == "success")
        #expect(successDelta.toolExecution?.result == "Output")

        // .failed
        let failedDelta = ChatDeltaMapper.mapEvent(ChatEvent.toolExecution(toolCallId: "call_4", status: .failed(reference: .known("f1"), error: "Outer")))
        #expect(failedDelta.toolExecution?.status == "failure")
        #expect(failedDelta.toolExecution?.result == "Error: Outer")

        // .failure
        struct FailError: Error, LocalizedError { var errorDescription: String? { "Crash" } }
        let failureDelta = ChatDeltaMapper.mapEvent(ChatEvent.toolExecution(toolCallId: "call_5", status: .failure(FailError())))
        #expect(failureDelta.toolExecution?.status == "failure")
        #expect(failureDelta.toolExecution?.result == "Crash")
    }

    @Test("Map generation completed")
    func testGenerationCompleted() {
        let meta = APIResponseMetadata(
            model: "gpt-4",
            promptTokens: 10,
            completionTokens: 20,
            totalTokens: 30,
            finishReason: "stop",
            systemFingerprint: "sys_123",
            duration: 1.5,
            tokensPerSecond: 13.3,
            debugSnapshotData: nil
        )

        let msg = Message(content: "Done", role: .assistant)
        let delta = ChatDeltaMapper.mapEvent(ChatEvent.generationCompleted(message: msg, metadata: meta))

        #expect(delta.type == StreamEventType.generationCompleted)
        #expect(delta.responseMetadata?.model == "gpt-4")
        #expect(delta.responseMetadata?.totalTokens == 30)
        #expect(delta.responseMetadata?.duration == 1.5)
    }
}
