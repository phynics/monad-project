import Testing
@testable import MonadShared
import Foundation

@Suite final class ToolErrorSurfacesTests {
    // ToolErrorSurfaceTests already exists in MonadCoreTests but only tests parts of ToolError.
    // Let's create a dedicated one for the custom ToolError enum.
    
    @Test

    
    func testToolErrorDescriptions() {
        let notFound = ToolError.toolNotFound("missing_tool")
        #expect(notFound.errorDescription == "Tool not found: missing_tool")
        
        let clientReq = ToolError.clientToolsDisallowedOnPrivateTimeline
        #expect(clientReq.errorDescription == "Client-side tools cannot be used on private (agent-owned) timelines")
        
        let wNotFound = ToolError.workspaceNotFound(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        #expect(wNotFound.errorDescription == "Workspace not found: 00000000-0000-0000-0000-000000000001")
        
        let cNotConn = ToolError.clientNotConnected
        #expect(cNotConn.errorDescription == "Client is not connected")
        
        let invalid = ToolError.invalidArgument("count", expected: "Int", got: "String")
        #expect(invalid.errorDescription == "Invalid argument 'count': expected Int, got String")
        
        let missing = ToolError.missingArgument("query")
        #expect(missing.errorDescription == "Missing required argument: query")
        
        let failed = ToolError.executionFailed("Timeout")
        #expect(failed.errorDescription == "Tool execution failed: Timeout")
    }
}
