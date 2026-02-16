import MonadShared
import MonadCore
import Testing

@Suite struct StreamingParserTests {

    @Test("Test basic content extraction")
    func basicContent() {
        let parser = StreamingParser()
        _ = parser.process("Hello world")
        let (thinking, content) = parser.finalize()
        #expect(content == "Hello world")
        #expect(thinking == nil)
    }

    @Test("Test full thinking block")
    func fullThinkingBlock() {
        let parser = StreamingParser()
        _ = parser.process("<think>Thinking process</think>Actual response")
        let (thinking, content) = parser.finalize()
        #expect(thinking == "Thinking process")
        #expect(content == "Actual response")
    }

    @Test("Test partial thinking block streaming")
    func partialThinkingStreaming() {
        let parser = StreamingParser()

        _ = parser.process("<thi")
        _ = parser.process("nk>Internal")
        _ = parser.process(" thought</think>External")

        let (thinking, content) = parser.finalize()
        #expect(thinking == "Internal thought")
        #expect(content == "External")
    }

    @Test("Test malformed tags")
    func malformedTags() {
        let parser = StreamingParser()
        _ = parser.process("<think>No closing tag")
        _ = parser.process(" still thinking")

        let (thinking, content) = parser.finalize()
        #expect(thinking == "No closing tag still thinking")
        #expect(content == "")
    }

    @Test("Test multiple chunks")
    func multipleChunks() {
        let parser = StreamingParser()
        let chunks = [
            "<", "t", "h", "i", "n", "k", ">", "thought", "<", "/", "t", "h", "i", "n", "k", ">",
            "content"
        ]

        for chunk in chunks {
            _ = parser.process(chunk)
        }

        let (thinking, content) = parser.finalize()
        #expect(thinking == "thought")
        #expect(content == "content")
    }
}
