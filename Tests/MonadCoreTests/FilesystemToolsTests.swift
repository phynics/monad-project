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
        let tool = ListDirectoryTool(currentDirectory: tempURL.path, jailRoot: tempURL.path)
        let result = try await tool.execute(parameters: ["path": "."])
        
        XCTAssertTrue(result.success, "Tool execution failed: \(result.error ?? "unknown")")
        let content = result.output
        
        XCTAssertTrue(content.contains("file1.txt"))
        XCTAssertTrue(content.contains("file2.md"))
        XCTAssertTrue(content.contains("subdir"))
        // Should NOT contain nested files (shallow list)
        XCTAssertFalse(content.contains("nested.txt"))
    }
    
    func testReadFileTool() async throws {
        let tool = ReadFileTool(currentDirectory: tempURL.path, jailRoot: tempURL.path)
        let result = try await tool.execute(parameters: ["path": "file1.txt"])
        
        XCTAssertTrue(result.success, "Tool execution failed: \(result.error ?? "unknown")")
        XCTAssertEqual(result.output, "Hello World")
    }
    
    func testInspectFileTool() async throws {
        let tool = InspectFileTool(currentDirectory: tempURL.path, jailRoot: tempURL.path)
        let result = try await tool.execute(parameters: ["path": "file2.md"])
        
        XCTAssertTrue(result.success, "Tool execution failed: \(result.error ?? "unknown")")
        let content = result.output
        
        // Output is typically "/path/to/file: ASCII text" or "UTF-8 text"
        XCTAssertTrue(content.contains("file2.md"))
        XCTAssertTrue(content.contains("text")) 
    }
    
    func testFindFileTool() async throws {
        let tool = FindFileTool(currentDirectory: tempURL.path, jailRoot: tempURL.path)
        
        // Search for 'nested.txt'
        let result = try await tool.execute(parameters: ["path": ".", "pattern": "nested"])
        
        XCTAssertTrue(result.success, "Tool execution failed: \(result.error ?? "unknown")")
        let content = result.output
        
        XCTAssertTrue(content.contains("subdir/nested.txt"))
    }
    
    func testSearchFileContentTool() async throws {
        let tool = SearchFileContentTool(currentDirectory: tempURL.path, jailRoot: tempURL.path)
        
        // Search for "Hello"
        // 1. Non-recursive (should find file1.txt only)
        let result1 = try await tool.execute(parameters: ["path": ".", "pattern": "Hello", "recursive": false])
        XCTAssertTrue(result1.success, "Tool execution failed: \(result1.error ?? "unknown")")
        let content1 = result1.output
        
        XCTAssertTrue(content1.contains("file1.txt"))
        XCTAssertFalse(content1.contains("nested.txt"))
        
        // 2. Recursive (should find both)
        let result2 = try await tool.execute(parameters: ["path": ".", "pattern": "Hello", "recursive": true])
        XCTAssertTrue(result2.success, "Tool execution failed: \(result2.error ?? "unknown")")
        let content2 = result2.output
        
        XCTAssertTrue(content2.contains("file1.txt"))
        XCTAssertTrue(content2.contains("nested.txt"))
    }
    
    func testSearchFilesTool() async throws {
        let tool = SearchFilesTool(currentDirectory: tempURL.path, jailRoot: tempURL.path)
        
        // Search for "Hello"
        let result = try await tool.execute(parameters: ["pattern": "Hello"])
        XCTAssertTrue(result.success, "Tool execution failed: \(result.error ?? "unknown")")
        let content = result.output
        
        XCTAssertTrue(content.contains("file1.txt"))
        XCTAssertTrue(content.contains("subdir/nested.txt"))
        
        // Test with include pattern
        let resultInclude = try await tool.execute(parameters: ["pattern": "Hello", "include": "*.txt"])
        XCTAssertTrue(resultInclude.success)
        XCTAssertTrue(resultInclude.output.contains("file1.txt"))
        XCTAssertFalse(resultInclude.output.contains("file2.md"))
    }
    
    func testPathTraversalProtection() async throws {
        let tool = ReadFileTool(currentDirectory: tempURL.path, jailRoot: tempURL.path)
        
        // Attempt to read a file outside the root using ..
        let outsideFile = FileManager.default.temporaryDirectory.appendingPathComponent("outside_\(UUID().uuidString).txt")
        try! "Secret Data".write(to: outsideFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outsideFile) }
        
        let relativePathOutside = "../\(outsideFile.lastPathComponent)"
        
        let result = try await tool.execute(parameters: ["path": relativePathOutside])
        
        // This should fail once we implement protection
        XCTAssertFalse(result.success, "Tool should not allow access outside root: \(result.output)")
        XCTAssertTrue(result.error?.contains("Access denied") ?? false, "Error should mention access denied")
    }
    
    func testJailedRelativePath() async throws {
        let subdir = tempURL.appendingPathComponent("subdir")
        let tool = ListDirectoryTool(currentDirectory: subdir.path, jailRoot: tempURL.path)
        
        // List parent directory from subdir using ..
        let result = try await tool.execute(parameters: ["path": ".."])
        
        // This should SUCCEED because it's still within jailRoot
        XCTAssertTrue(result.success, "Should allow .. if within jail: \(result.error ?? "")")
        XCTAssertTrue(result.output.contains("file1.txt"), "Should see file1.txt in parent")
        
        // Attempt to list outside jailRoot from subdir
        let resultOutside = try await tool.execute(parameters: ["path": "../../.."])
        XCTAssertFalse(resultOutside.success, "Should not allow escaping jailRoot via relative path")
    }
}