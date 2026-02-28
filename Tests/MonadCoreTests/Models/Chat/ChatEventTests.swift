import XCTest
@testable import MonadCore
import Foundation

final class ChatEventTests: XCTestCase {
    
    func testChatEventDelta() {
        let event = ChatEvent.delta("Hello")
        XCTAssertEqual(event.delta, "Hello")
        XCTAssertNil(event.generationContext)
        XCTAssertFalse(event.isError)
    }
    
    func testChatEventThought() {
        let event = ChatEvent.thought("Thinking...")
        XCTAssertEqual(event.thought, "Thinking...")
        XCTAssertFalse(event.isThoughtCompleted)
    }
    
    func testChatEventThoughtCompleted() {
        let event = ChatEvent.thoughtCompleted
        XCTAssertTrue(event.isThoughtCompleted)
        XCTAssertNil(event.thought)
    }
    
    func testChatEventToolCall() {
        let delta = ToolCallDelta(index: 0, id: "call1", name: "test", arguments: "{}")
        let event = ChatEvent.toolCall(delta)
        XCTAssertNotNil(event.toolCall)
        XCTAssertEqual(event.toolCall?.id, "call1")
    }
    
    func testChatEventToolCallError() {
        let event = ChatEvent.toolCallError(toolCallId: "call1", name: "test", error: "Not found")
        XCTAssertNotNil(event.toolCallError)
        XCTAssertEqual(event.toolCallError?.toolCallId, "call1")
        XCTAssertEqual(event.toolCallError?.error, "Not found")
    }
    
    func testChatEventToolExecution() {
        let ref = ToolReference.known("tool-1")
        let event = ChatEvent.toolExecution(toolCallId: "123", status: .attempting(name: "test", reference: ref))
        
        XCTAssertNotNil(event.toolExecution)
        XCTAssertEqual(event.toolExecution?.toolCallId, "123")
    }
    
    func testChatEventGenerationContext() {
        let metadata = ChatMetadata(memories: [UUID()], files: ["README.md"])
        let event = ChatEvent.generationContext(metadata)
        XCTAssertNotNil(event.generationContext)
        XCTAssertEqual(event.generationContext?.files.count, 1)
    }
    
    func testChatEventGenerationCompleted() {
        let message = Message(content: "Done", role: .assistant)
        let metadata = APIResponseMetadata(model: "test-model", duration: 1.5, tokensPerSecond: 50.0)
        let event = ChatEvent.generationCompleted(message: message, metadata: metadata)
        
        XCTAssertNotNil(event.generationCompleted)
        XCTAssertEqual(event.generationCompleted?.message.content, "Done")
    }
    
    func testChatEventError() {
        struct MockError: Error, Equatable {}
        let event = ChatEvent.error(MockError())
        XCTAssertTrue(event.isError)
        XCTAssertNotNil(event.error)
    }
}
