import XCTest
@testable import MonadCore

final class SubagentTests: XCTestCase {
    
    func testDocumentContextMetadataView() {
        let content = "Hello World"
        let doc = DocumentContext(path: "test.txt", content: content, viewMode: .metadata)
        
        XCTAssertTrue(doc.visibleContent.contains("Content not loaded"))
        XCTAssertTrue(doc.visibleContent.contains("Size:"))
    }
    
    func testDocumentsComponentMetadata() async {
        let content = String(repeating: "A", count: 100)
        let doc = DocumentContext(path: "test.txt", content: content, viewMode: .metadata)
        let component = DocumentsComponent(documents: [doc])
        
        let output = await component.generateContent()
        XCTAssertNotNil(output)
        XCTAssertTrue(output!.contains("Metadata Only"))
        XCTAssertTrue(output!.contains("100 bytes"))
        XCTAssertFalse(output!.contains(content)) // Should not show content
    }
    
    // We can't easily test LaunchSubagentTool execution fully without mocking the entire LLMService/Client stack
    // which is complex due to actor isolation. However, we can verify the tool schema and initialization.
    
    func testLaunchSubagentToolSchema() async {
        let llmService = await LLMService()
        let docManager = await DocumentManager()
        let tool = LaunchSubagentTool(llmService: llmService, documentManager: docManager)
        
        XCTAssertEqual(tool.name, "Launch Subagent")
        
        let schema = tool.parametersSchema
        let props = schema["properties"] as? [String: Any]
        XCTAssertNotNil(props?["prompt"])
        XCTAssertNotNil(props?["documents"])
    }
}