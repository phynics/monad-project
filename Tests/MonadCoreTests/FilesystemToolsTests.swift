import XCTest
@testable import MonadCore

final class FilesystemToolsTests: XCTestCase {
    var tempURL: URL!
    
    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        
        // Structure:
        // /root
        //   - file1.txt ("Hello World")
        //   - file2.md ("Markdown content")
        //   - /subdir
        //     - nested.txt ("Nested Hello")
        
        try! "Hello World".write(to: tempURL.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
        try! "Markdown content".write(to: tempURL.appendingPathComponent("file2.md"), atomically: true, encoding: .utf8)
        
        let subdir = tempURL.appendingPathComponent("subdir")
        try! FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try! "Nested Hello".write(to: subdir.appendingPathComponent("nested.txt"), atomically: true, encoding: .utf8)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }
    
    func testListDirectoryTool() async throws {
        let tool = ListDirectoryTool()
        let result = try await tool.execute(parameters: ["path": tempURL.path])
        
        XCTAssertTrue(result.success, "Tool execution failed: \(result.error ?? "unknown")")
        let content = result.output
        
        XCTAssertTrue(content.contains("file1.txt"))
        XCTAssertTrue(content.contains("file2.md"))
        XCTAssertTrue(content.contains("subdir"))
        // Should NOT contain nested files (shallow list)
        XCTAssertFalse(content.contains("nested.txt"))
    }
    
    func testReadFileTool() async throws {
        let tool = ReadFileTool()
        let result = try await tool.execute(parameters: ["path": tempURL.appendingPathComponent("file1.txt").path])
        
        XCTAssertTrue(result.success, "Tool execution failed: \(result.error ?? "unknown")")
        XCTAssertEqual(result.output, "Hello World")
    }
    
    func testInspectFileTool() async throws {
        let tool = InspectFileTool()
        let result = try await tool.execute(parameters: ["path": tempURL.appendingPathComponent("file2.md").path])
        
        XCTAssertTrue(result.success, "Tool execution failed: \(result.error ?? "unknown")")
        let content = result.output
        
        // Output is typically "/path/to/file: ASCII text" or "UTF-8 text"
        XCTAssertTrue(content.contains("file2.md"))
        XCTAssertTrue(content.contains("text")) 
    }
    
    func testFindFileTool() async throws {
        let tool = FindFileTool()
        
        // Search for 'nested.txt'
        let result = try await tool.execute(parameters: ["path": tempURL.path, "pattern": "nested"])
        
        XCTAssertTrue(result.success, "Tool execution failed: \(result.error ?? "unknown")")
        let content = result.output
        
        XCTAssertTrue(content.contains("subdir/nested.txt"))
    }
    
    func testSearchFileContentTool() async throws {
        let tool = SearchFileContentTool()
        
        // Search for "Hello"
        // 1. Non-recursive (should find file1.txt only)
        let result1 = try await tool.execute(parameters: ["path": tempURL.path, "pattern": "Hello", "recursive": false])
        XCTAssertTrue(result1.success, "Tool execution failed: \(result1.error ?? "unknown")")
        let content1 = result1.output
        
        XCTAssertTrue(content1.contains("file1.txt"))
        XCTAssertFalse(content1.contains("nested.txt"))
        
        // 2. Recursive (should find both)
        let result2 = try await tool.execute(parameters: ["path": tempURL.path, "pattern": "Hello", "recursive": true])
        XCTAssertTrue(result2.success, "Tool execution failed: \(result2.error ?? "unknown")")
        let content2 = result2.output
        
        XCTAssertTrue(content2.contains("file1.txt"))
        XCTAssertTrue(content2.contains("nested.txt"))
    }
}