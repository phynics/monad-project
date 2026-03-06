import XCTest
@testable import MonadCore
@testable import MonadShared

final class ToolOutputParserTests: XCTestCase {

    // MARK: - Pipe-Delimited Format (Qwen-style)

    func testParsePipeDelimitedSingleCall() {
        let content = """
        <|tool_calls_section_begin|>
        <|tool_call_begin|>
        functions.list_workspaces:0
        <|tool_call_argument_begin|>
        {}
        <|tool_call_end|>
        <|tool_calls_section_end|>
        """

        let calls = ToolOutputParser.parse(from: content)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "list_workspaces")
    }

    func testParsePipeDelimitedWithArguments() {
        let content = """
        <|tool_call_begin|>
        functions.read_file:0
        <|tool_call_argument_begin|>
        {"path": "/tmp/test.txt"}
        <|tool_call_end|>
        """

        let calls = ToolOutputParser.parse(from: content)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "read_file")
        XCTAssertNotNil(calls.first?.arguments["path"])
    }

    // MARK: - XML Format (existing)

    func testParseXMLToolCall() {
        let content = """
        Let me check that for you.
        <tool_call>{"tool": "list_files", "args": {"directory": "/"}}
        </tool_call>
        """

        let calls = ToolOutputParser.parse(from: content)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "list_files")
    }

    // MARK: - No Matches

    func testParseNoToolCalls() {
        let content = "Just a regular response with no tool calls."
        let calls = ToolOutputParser.parse(from: content)
        XCTAssertTrue(calls.isEmpty)
    }
}
