import XCTest
@testable import MonadShared
import Foundation

final class ToolErrorSurfacesTests: XCTestCase {
    // ToolErrorSurfaceTests already exists in MonadCoreTests but only tests parts of ToolError.
    // Let's create a dedicated one for the custom ToolError enum.
    
    func testToolErrorDescriptions() {
        let notFound = ToolError.toolNotFound("missing_tool")
        XCTAssertEqual(notFound.errorDescription, "Tool not found: missing_tool")
        
        let clientReq = ToolError.clientExecutionRequired
        XCTAssertEqual(clientReq.errorDescription, "Execution on client required")
        
        let wNotFound = ToolError.workspaceNotFound(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        XCTAssertEqual(wNotFound.errorDescription, "Workspace not found: 00000000-0000-0000-0000-000000000001")
        
        let cNotConn = ToolError.clientNotConnected
        XCTAssertEqual(cNotConn.errorDescription, "Client is not connected")
        
        let invalid = ToolError.invalidArgument("count", expected: "Int", got: "String")
        XCTAssertEqual(invalid.errorDescription, "Invalid argument 'count': expected Int, got String")
        
        let missing = ToolError.missingArgument("query")
        XCTAssertEqual(missing.errorDescription, "Missing required argument: query")
        
        let failed = ToolError.executionFailed("Timeout")
        XCTAssertEqual(failed.errorDescription, "Tool execution failed: Timeout")
    }
}
