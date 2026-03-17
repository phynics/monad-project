import Foundation
import OpenAI
import Testing
@testable import MonadCore

@Suite
struct ChatEngineRenderingTests {
    @Test
    func testRenderSingleMessage() {
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .user(.init(content: .string("Hello")))
        ]
        let output = ChatEngine.renderMessagesStatic(messages)
        let expected = "─── [USER] ───\nHello\n\n"
        #expect(output == expected)
    }

    @Test
    func testRenderMultipleMessages() {
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .user(.init(content: .string("Hello"))),
            .assistant(.init(content: .textContent("Hi there")))
        ]
        let output = ChatEngine.renderMessagesStatic(messages)
        let expected = "─── [USER] ───\nHello\n\n─── [ASSISTANT] ───\nHi there\n\n"
        #expect(output == expected)
    }

    @Test
    func testRenderMessageWithTrailingNewlines() {
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .assistant(.init(content: .textContent("Done.\n\n")))
        ]
        let output = ChatEngine.renderMessagesStatic(messages)
        // Standardized behavior: trimmed content + exactly \n\n
        let expected = "─── [ASSISTANT] ───\nDone.\n\n"
        #expect(output == expected)
    }

    @Test
    func testRenderEmptyMessage() {
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .system(.init(content: .textContent("")))
        ]
        let output = ChatEngine.renderMessagesStatic(messages)
        // Header + \n\n
        let expected = "─── [SYSTEM] ───\n\n"
        #expect(output == expected)
    }
}
