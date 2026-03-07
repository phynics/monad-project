import XCTest
import MonadShared
import Foundation

final class ChatEventTests: XCTestCase {

    func testChatEventDelta() {
        let event = ChatEvent.delta(event: .generation(text: "Hello"))
        if case .delta(event: .generation(text: let text)) = event {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected delta.generation")
        }
    }

    func testChatEventThinking() {
        let event = ChatEvent.delta(event: .thinking(text: "Thinking..."))
        if case .delta(event: .thinking(text: let text)) = event {
            XCTAssertEqual(text, "Thinking...")
        } else {
            XCTFail("Expected delta.thinking")
        }
    }

    func testChatEventToolCall() {
        let delta = ToolCallDelta(index: 0, id: "call1", name: "test", arguments: "{}")
        let event = ChatEvent.delta(event: .toolCall(delta: delta))
        if case .delta(event: .toolCall(delta: let tc)) = event {
            XCTAssertEqual(tc.id, "call1")
        } else {
            XCTFail("Expected delta.toolCall")
        }
    }

    func testChatEventToolCallError() {
        let event = ChatEvent.error(event: .toolCallError(toolCallId: "call1", name: "test", error: "Not found"))
        if case .error(event: .toolCallError(let id, _, let error)) = event {
            XCTAssertEqual(id, "call1")
            XCTAssertEqual(error, "Not found")
        } else {
            XCTFail("Expected error.toolCallError")
        }
    }

    func testChatEventToolExecution() {
        let ref = ToolReference.known("tool-1")
        let event = ChatEvent.delta(event: .toolExecution(toolCallId: "123", status: .attempting(name: "test", reference: ref)))
        if case .delta(event: .toolExecution(let id, _)) = event {
            XCTAssertEqual(id, "123")
        } else {
            XCTFail("Expected delta.toolExecution")
        }
    }

    func testChatEventGenerationContext() {
        let metadata = ChatMetadata(memories: [UUID()], files: ["README.md"])
        let event = ChatEvent.meta(event: .generationContext(metadata: metadata))
        if case .meta(event: .generationContext(let meta)) = event {
            XCTAssertEqual(meta.files.count, 1)
        } else {
            XCTFail("Expected meta.generationContext")
        }
    }

    func testChatEventGenerationCompleted() {
        let message = Message(content: "Done", role: .assistant)
        let metadata = APIResponseMetadata(model: "test-model", duration: 1.5, tokensPerSecond: 50.0)
        let event = ChatEvent.completion(event: .generationCompleted(message: message, metadata: metadata))
        if case .completion(event: .generationCompleted(let msg, _)) = event {
            XCTAssertEqual(msg.content, "Done")
        } else {
            XCTFail("Expected completion.generationCompleted")
        }
    }

    func testChatEventError() {
        let event = ChatEvent.error(event: .error(message: "Test error"))
        if case .error(event: .error(let msg)) = event {
            XCTAssertEqual(msg, "Test error")
        } else {
            XCTFail("Expected error.error")
        }
    }
}
