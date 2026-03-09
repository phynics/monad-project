import Testing
import Foundation
@testable import MonadCore
@testable import MonadShared

@Suite final class ToolOutputParserTests {

    // MARK: - Pipe-Delimited Format (Qwen-style)

    @Test


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
        #expect(calls.count == 1)
        #expect(calls.first?.name == "list_workspaces")
    }

    @Test
    func testParsePipeDelimitedWithArguments() throws {
        let content = """
        <|tool_call_begin|>
        functions.read_file:0
        <|tool_call_argument_begin|>
        {"path": "/tmp/test.txt"}
        <|tool_call_end|>
        """

        let calls = ToolOutputParser.parse(from: content)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "read_file")
        try #require(calls.first?.arguments["path"] != nil)
    }

    // MARK: - XML Format (existing)

    @Test


    func testParseXMLToolCall() {
        let content = """
        Let me check that for you.
        <tool_call>{"tool": "list_files", "args": {"directory": "/"}}
        </tool_call>
        """

        let calls = ToolOutputParser.parse(from: content)
        #expect(calls.count == 1)
        #expect(calls.first?.name == "list_files")
    }

    // MARK: - No Matches

    @Test


    func testParseNoToolCalls() {
        let content = "Just a regular response with no tool calls."
        let calls = ToolOutputParser.parse(from: content)
        #expect(calls.isEmpty)
    }
}
