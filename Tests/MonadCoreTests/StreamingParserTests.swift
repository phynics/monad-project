import MonadCore
import MonadShared
import Testing

@Suite struct StreamingParserTests {

    @Test("Test basic content extraction")
    func basicContent() {
        var parser = StreamingParser()
        parser.process("Hello world")
        let thinking: String? = parser.thinking.isEmpty ? nil : parser.thinking
        let content = parser.content
        #expect(content == "Hello world")
        #expect(thinking == nil)
    }

    @Test("Test full thinking block")
    func fullThinkingBlock() {
        var parser = StreamingParser()
        parser.process("<think>Thinking process</think>Actual response")
        let thinking: String? = parser.thinking.isEmpty ? nil : parser.thinking
        let content = parser.content
        #expect(thinking == "Thinking process")
        #expect(content == "Actual response")
    }

    @Test("Test partial thinking block streaming")
    func partialThinkingStreaming() {
        var parser = StreamingParser()

        parser.process("<thi")
        parser.process("nk>Internal")
        parser.process(" thought</think>External")

        let thinking: String? = parser.thinking.isEmpty ? nil : parser.thinking
        let content = parser.content
        #expect(thinking == "Internal thought")
        #expect(content == "External")
    }

    @Test("Test malformed tags")
    func malformedTags() {
        var parser = StreamingParser()
        parser.process("<think>No closing tag")
        parser.process(" still thinking")

        let thinking: String? = parser.thinking.isEmpty ? nil : parser.thinking
        let content = parser.content
        #expect(thinking == "No closing tag still thinking")
        #expect(content == "")
    }

    @Test("Test multiple chunks")
    func multipleChunks() {
        var parser = StreamingParser()
        let chunks = [
            "<", "t", "h", "i", "n", "k", ">", "thought", "<", "/", "t", "h", "i", "n", "k", ">",
            "content"
        ]

        for chunk in chunks {
            parser.process(chunk)
        }

        let thinking: String? = parser.thinking.isEmpty ? nil : parser.thinking
        let content = parser.content
        #expect(thinking == "thought")
        #expect(content == "content")
    }
}
