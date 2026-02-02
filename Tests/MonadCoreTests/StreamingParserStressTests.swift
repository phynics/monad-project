import Foundation
import Testing

@testable import MonadCore

@Suite struct StreamingParserStressTests {

    // MARK: - Code Block Protection

    @Test("Think tag inside code block should be treated as text")
    func testThinkTagInsideCodeBlock() {
        let parser = StreamingParser()
        // Input: ```\n<think>\n```
        // Expected: All content, no thinking.

        _ = parser.process("```\n")
        _ = parser.process("<think>\n")
        _ = parser.process("```")

        let (thinking, content) = parser.finalize()

        #expect(thinking == nil)
        #expect(content.contains("<think>") == true)
    }

    @Test("Closing think tag inside code block (nested in thinking) should be preserved")
    func testClosingThinkTagInsideCodeBlockInThinking() {
        let parser = StreamingParser()
        // Input: <think>\nHere is code:\n```\nprint(\"</think>")\n```\n</think>
        // Expected: Thinking contains the code block with the tag literal.

        let chunks = [
            "<think>\n",
            "Here is code:\n",
            "```\n",
            "print(\\\"<\\/think>\\\")\\n",
            "```\\n",
            "</think>",
        ]

        for chunk in chunks {
            _ = parser.process(chunk)
        }

        let (thinking, content) = parser.finalize()

        #expect(thinking != nil)
        #expect(thinking?.contains("print(\\\"<\\/think>\\\")") == true)
        #expect(content.isEmpty == true)
    }

    // MARK: - Partial Delimiters

    @Test("Partial code block delimiters across chunks")
    func testPartialBackticks() {
        let parser = StreamingParser()
        // Sequence: "Start", "`", "`", "`", "Code", "`", "`", "`", "End"
        // Should detect block.

        _ = parser.process("Start ")
        _ = parser.process("`")
        _ = parser.process("`")
        _ = parser.process("`")
        _ = parser.process("Code")
        _ = parser.process("`")
        _ = parser.process("`")
        _ = parser.process("`")
        _ = parser.process(" End")

        let (_, _) = parser.finalize()

        // "```" are stripped or preserved?
        // In `extractNextSegment`, it returns "```" as text.
        // So they should be in the output.
        // But the *state* `insideCodeBlock` should have toggled correctly to protect content if it had tags.
        // Let's test with a tag inside.

        parser.reset()
        _ = parser.process("`")
        _ = parser.process("`")
        _ = parser.process("`")
        _ = parser.process("<think>")  // Should be ignored as tag
        _ = parser.process("`")
        _ = parser.process("`")
        _ = parser.process("`")

        let (thinking, content2) = parser.finalize()
        #expect(thinking == nil)
        #expect(content2.contains("<think>"))
    }

    @Test("Partial tag delimiters across chunks")
    func testPartialTags() {
        let parser = StreamingParser()
        // < t h i n k >

        let input = "<think>Inner</think>"
        for char in input {
            _ = parser.process(String(char))
        }

        let (thinking, content) = parser.finalize()
        #expect(thinking == "Inner")
        #expect(content.isEmpty == true)
    }

    // MARK: - Edge Cases

    @Test("Orphaned closing tag triggers reclassification")
    func testOrphanedClosingTag() {
        let parser = StreamingParser()

        _ = parser.process("Some content that ")
        _ = parser.process("was actually thinking </think>")
        _ = parser.process(" Real content")

        let (thinking, content) = parser.finalize()

        // The parser logic: if </think> found without <think>, it treats everything before as thinking.
        #expect(thinking?.contains("Some content that was actually thinking") == true)
        #expect(content.contains("Real content") == true)
    }

    @Test("Empty buffer handling")
    func testEmptyProcessing() {
        let parser = StreamingParser()
        _ = parser.process("")
        let (thinking, content) = parser.finalize()
        #expect(thinking == nil)
        #expect(content == "")
    }

    @Test("Interleaved partials")
    func testInterleavedPartials() {
        let parser = StreamingParser()
        // `<` then `think>`
        _ = parser.process("<")
        // Verify intermediate state didn't crash or output garbage
        _ = parser.process("think>Content")

        let (thinking, _) = parser.finalize()
        #expect(thinking == "Content")
    }

    // MARK: - Stress Test

    @Test("Complex interleaved stream")
    func testComplexStream() {
        let parser = StreamingParser()
        let chunks = [
            "Start ",
            "<thi", "nk>",
            "Reasoning...\n",
            "Here is a code block in thinking:\n",
            "```swift\n",
            "if x < 10 { print('hi') }\n",
            "```\n",
            "End of reasoning.",
            "</", "think>",
            "\nFinal Answer.",
        ]

        for chunk in chunks {
            _ = parser.process(chunk)
        }

        let (thinking, content) = parser.finalize()

        #expect(thinking?.contains("Reasoning...") == true)
        #expect(thinking?.contains("if x < 10") == true)
        #expect(content.contains("Final Answer") == true)
        #expect(content.contains("Start") == true)  // "Start " was before <think>
    }
}
