import XCTest
@testable import MonadCore
import Foundation

final class ChatEventTests: XCTestCase {

    func testChatEventDelta() {
        let event = ChatEvent.delta(.generation("Hello"))
        if case .delta(.generation(let text)) = event {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected delta.generation")
        }
    }

    func testChatEventThinking() {
        let event = ChatEvent.delta(.thinking("Thinking..."))
        if case .delta(.thinking(let text)) = event {
            XCTAssertEqual(text, "Thinking...")
        } else {
            XCTFail("Expected delta.thinking")
        }
    }

    func testChatEventToolCall() {
        let delta = ToolCallDelta(index: 0, id: "call1", name: "test", arguments: "{}")
        let event = ChatEvent.delta(.toolCall(delta))
        if case .delta(.toolCall(let tc)) = event {
            XCTAssertEqual(tc.id, "call1")
        } else {
            XCTFail("Expected delta.toolCall")
        }
    }

    func testChatEventToolCallError() {
        let event = ChatEvent.error(.toolCallError(toolCallId: "call1", name: "test", error: "Not found"))
        if case .error(.toolCallError(let id, _, let error)) = event {
            XCTAssertEqual(id, "call1")
            XCTAssertEqual(error, "Not found")
        } else {
            XCTFail("Expected error.toolCallError")
        }
    }

    func testChatEventToolExecution() {
        let ref = ToolReference.known("tool-1")
        let event = ChatEvent.delta(.toolExecution(toolCallId: "123", status: .attempting(name: "test", reference: ref)))
        if case .delta(.toolExecution(let id, _)) = event {
            XCTAssertEqual(id, "123")
        } else {
            XCTFail("Expected delta.toolExecution")
        }
    }

    func testChatEventGenerationContext() {
        let metadata = ChatMetadata(memories: [UUID()], files: ["README.md"])
        let event = ChatEvent.meta(.generationContext(metadata))
        if case .meta(.generationContext(let meta)) = event {
            XCTAssertEqual(meta.files.count, 1)
        } else {
            XCTFail("Expected meta.generationContext")
        }
    }

    func testChatEventGenerationCompleted() {
        let message = Message(content: "Done", role: .assistant)
        let metadata = APIResponseMetadata(model: "test-model", duration: 1.5, tokensPerSecond: 50.0)
        let event = ChatEvent.completion(.generationCompleted(message: message, metadata: metadata))
        if case .completion(.generationCompleted(let msg, _)) = event {
            XCTAssertEqual(msg.content, "Done")
        } else {
            XCTFail("Expected completion.generationCompleted")
        }
    }

    func testChatEventError() {
        struct MockError: Error, Equatable {}
        let event = ChatEvent.error(.error(MockError()))
        if case .error(.error) = event {
            // pass
        } else {
            XCTFail("Expected error.error")
        }
    }
}
