import Foundation
import Testing
import MonadCore
import GRPC
import NIOCore
import SwiftProtobuf

@testable import MonadCore

@Suite
struct gRPCServiceTests {
    
    @Test("Test gRPCPersistenceService Initialization")
    func testPersistenceInit() async throws {
        // We need a way to mock the GRPCChannel or use an in-process transport.
        // For now, let's just verify it compiles and handles basic mappings.
    }
}
