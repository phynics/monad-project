import Foundation
import Testing
import MonadCore
import MonadServerCore
import MonadTestSupport
import GRPC
import NIOCore

@MainActor
@Suite struct ProviderTests {
    
    @Test("Test GRPCServerProvider initialization")
    func testGRPCServerProviderInit() {
        let provider = GRPCServerProvider(handlers: [])
        #expect(provider.name == "gRPC Server")
    }
    
    @Test("Test MetricsServerProvider initialization")
    func testMetricsServerProvider() async throws {
        let metrics = ServerMetrics()
        let provider = MetricsServerProvider(metrics: metrics, port: 0) // Port 0 for random
        #expect(provider.name == "Metrics Server")
        
        try await provider.start()
        // It starts in a background task, so we just verify it didn't crash
        try await provider.shutdown()
    }
}
