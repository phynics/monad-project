import Testing
import Foundation
@testable import MonadServer
import MonadCore
import MonadShared

@Suite struct ChatDeltaMapperTests {

    @Test("Map simple events")
    func testSimpleEvents() {
        // .meta(.generationContext)
        let metaJson = """
        {"memories":[], "files":[]}
        """.data(using: .utf8)!
        let meta = try! JSONDecoder().decode(ChatMetadata.self, from: metaJson)
        let deltaContext = ChatDeltaMapper.mapEvent(.meta(.generationContext(meta)))
        #expect(deltaContext.type == StreamEventType.generationContext)

        // .delta(.generation)
        let deltaContent = ChatDeltaMapper.mapEvent(.delta(.generation("Hello")))
        #expect(deltaContent.type == .delta)
        #expect(deltaContent.content == "Hello")

        // .delta(.thinking)
        let deltaThought = ChatDeltaMapper.mapEvent(.delta(.thinking("Thinking")))
        #expect(deltaThought.type == StreamEventType.thought)
        #expect(deltaThought.thought == "Thinking")


    }

    @Test("Map errors")
    func testErrors() {
        // .error(.error) generic
        struct DummyError: Error, LocalizedError {
            var errorDescription: String? { "Dummy error text" }
        }
        let deltaError = ChatDeltaMapper.mapEvent(.error(.error(DummyError())))
        #expect(deltaError.type == .error)
        #expect(deltaError.error == "Dummy error text")

        // .error(.error) CancellationError
        let deltaCancel = ChatDeltaMapper.mapEvent(.error(.error(CancellationError())))
        #expect(deltaCancel.type == .generationCancelled)
    }

    @Test("Map tool calls and errors")
    func testToolCalls() throws {
        // .delta(.toolCall)
        let tcJson = """
        {"index":0,"id":"call_1","type":"function","function":{"name":"f1","arguments":"{}"}}
        """.data(using: .utf8)!
        let tc = try JSONDecoder().decode(ToolCallDelta.self, from: tcJson)
        let deltaTC = ChatDeltaMapper.mapEvent(.delta(.toolCall(tc)))
        #expect(deltaTC.type == StreamEventType.toolCall)
        #expect(deltaTC.toolCalls?.first?.id == "call_1")

        // .error(.toolCallError)
        let deltaTCErr = ChatDeltaMapper.mapEvent(.error(.toolCallError(toolCallId: "call_2", name: "f2", error: "Not found")))
        #expect(deltaTCErr.type == .toolCallError)
        #expect(deltaTCErr.toolCallError?.toolCallId == "call_2")
        #expect(deltaTCErr.toolCallError?.name == "f2")
        #expect(deltaTCErr.toolCallError?.error == "Not found")
    }

    @Test("Map tool execution status")
    func testToolExecution() {
        // .delta(.toolExecution) attempting (known)
        let attemptKnown = ChatDeltaMapper.mapEvent(.delta(.toolExecution(toolCallId: "call_1", status: .attempting(name: "f1", reference: .known("f1")))))
        #expect(attemptKnown.type == .toolExecution)
        #expect(attemptKnown.toolExecution?.status == "attempting")
        #expect(attemptKnown.toolExecution?.target == "server")

        // .delta(.toolExecution) attempting (custom)
        let def = WorkspaceToolDefinition(id: "c1", name: "c1", description: "", parametersSchema: [:])
        let attemptCustom = ChatDeltaMapper.mapEvent(.delta(.toolExecution(toolCallId: "call_2", status: .attempting(name: "c1", reference: .custom(def)))))
        #expect(attemptCustom.toolExecution?.status == "attempting")
        #expect(attemptCustom.toolExecution?.target == "client")

        // .completion(.toolExecution) success
        let resSuccess = ToolResult.success("Output")
        let successDelta = ChatDeltaMapper.mapEvent(.completion(.toolExecution(toolCallId: "call_3", status: .success(resSuccess))))
        #expect(successDelta.toolExecution?.status == "success")
        #expect(successDelta.toolExecution?.result == "Output")

        // .completion(.toolExecution) failed
        let failedDelta = ChatDeltaMapper.mapEvent(.completion(.toolExecution(toolCallId: "call_4", status: .failed(reference: .known("f1"), error: "Outer"))))
        #expect(failedDelta.toolExecution?.status == "failure")
        #expect(failedDelta.toolExecution?.result == "Error: Outer")

        // .completion(.toolExecution) failure
        struct FailError: Error, LocalizedError { var errorDescription: String? { "Crash" } }
        let failureDelta = ChatDeltaMapper.mapEvent(.completion(.toolExecution(toolCallId: "call_5", status: .failure(FailError()))))
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
        let delta = ChatDeltaMapper.mapEvent(.completion(.generationCompleted(message: msg, metadata: meta)))

        #expect(delta.type == StreamEventType.generationCompleted)
        #expect(delta.responseMetadata?.model == "gpt-4")
        #expect(delta.responseMetadata?.totalTokens == 30)
        #expect(delta.responseMetadata?.duration == 1.5)
    }
}
