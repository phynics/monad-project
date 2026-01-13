import Foundation
import Testing
import GRPC
@testable import MonadServerCore
@testable import MonadCore

@Suite struct ServerErrorHandlerTests {
    
    @Test("Test mapping standard errors to gRPC internal error")
    func testMapStandardError() {
        let handler = ServerErrorHandler()
        let error = NSError(domain: "test", code: 123, userInfo: [NSLocalizedDescriptionKey: "Something went wrong"])
        let status = handler.handle(error, context: "test_context")
        
        #expect(status.code == .internalError)
        #expect(status.message == "Something went wrong")
    }
    
    @Test("Test mapping gRPC status directly")
    func testMapGRPCStatus() {
        let handler = ServerErrorHandler()
        let error = GRPCStatus(code: .notFound, message: "Not found")
        let status = handler.handle(error, context: "test_context")
        
        #expect(status.code == .notFound)
        #expect(status.message == "Not found")
    }
}
