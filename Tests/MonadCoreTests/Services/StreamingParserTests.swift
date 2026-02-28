import XCTest
@testable import MonadCore

final class StreamingParserTests: XCTestCase {
    
    // MARK: - Thinking Tag Parsing
    
    func testStreamingParserNormalText() {
        var parser = StreamingParser()
        parser.process("Hello")
        parser.process(" World")
        
        XCTAssertEqual(parser.content, "Hello World")
        XCTAssertEqual(parser.thinking, "")
        XCTAssertFalse(parser.isThinking)
    }
    
    func testStreamingParserWithThinkingTags() {
        var parser = StreamingParser()
        parser.process("Here is my reasoning: <th")
        XCTAssertEqual(parser.content, "Here is my reasoning: ") // "<th" buffered
        XCTAssertFalse(parser.isThinking) // Still resolving tag
        
        parser.process("ink>This is deep thought.</thi")
        XCTAssertTrue(parser.isThinking) // Inside thought, "</thi" buffered
        
        parser.process("nk>And now the answer.")
        
        XCTAssertEqual(parser.thinking, "This is deep thought.")
        XCTAssertEqual(parser.content, "Here is my reasoning: And now the answer.")
        XCTAssertFalse(parser.isThinking)
    }
    
    func testStreamingParserOrphanedClosingTag() {
        var parser = StreamingParser()
        // DeepSeek and other models sometimes start sending </think> without opening it
        parser.process("Wait, let me think about this...\n</think>\nYes, the answer is 42.")
        
        XCTAssertTrue(parser.hasReclassified)
        XCTAssertEqual(parser.thinking, "Wait, let me think about this...\n")
        XCTAssertEqual(parser.content, "\nYes, the answer is 42.")
    }
    
    func testStreamingParserCodeBlockAvoidance() {
        var parser = StreamingParser()
        parser.process("```xml\n<think>This should NOT be parsed as thinking</think>\n```")
        
        XCTAssertEqual(parser.thinking, "")
        XCTAssertTrue(parser.content.contains("<think>This should NOT be parsed"))
        XCTAssertFalse(parser.isThinking)
    }
    
    // MARK: - Tool Extraction
    
    func testToolExtraction() throws {
        let parser = StreamingParser()
        let response = """
        I will use the tool now.
        ```xml
        <tool_call>
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "get_weather",
          "arguments": {
            "location": "SF"
          }
        }
        </tool_call>
        ```
        And that's it.
        """
        
        let (cleanText, tools) = parser.extractToolCalls(from: response)
        
        // Ensure XML was stripped from text
        XCTAssertFalse(cleanText.contains("<tool_call>"))
        XCTAssertTrue(cleanText.contains("I will use the tool now."))
        XCTAssertTrue(cleanText.contains("And that's it."))
        
        // Ensure tool was extracted
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0].name, "get_weather")
        XCTAssertEqual(tools[0].arguments["location"]?.value as? String, "SF")
        XCTAssertEqual(tools[0].id, UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
    }
    
    func testMultipleToolExtractionsWithoutCodeFences() throws {
        let parser = StreamingParser()
        let response = """
        <tool_call>
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "toolA",
          "arguments": {}
        }
        </tool_call>
        <tool_call>
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "name": "toolB",
          "arguments": {}
        }
        </tool_call>
        """
        
        let (cleanText, tools) = parser.extractToolCalls(from: response)
        XCTAssertEqual(cleanText.trimmingCharacters(in: .whitespacesAndNewlines), "")
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools[0].name, "toolA")
        XCTAssertEqual(tools[1].name, "toolB")
    }
}
