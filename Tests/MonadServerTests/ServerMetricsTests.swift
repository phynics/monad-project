import Foundation
import Testing
import Metrics
@testable import MonadServerCore

@Suite struct ServerMetricsTests {
    
    @Test("Test metrics export")
    func testMetricsExport() async {
        let serverMetrics = ServerMetrics()
        
        // Register a counter via the internal registry for testing
        let counter = serverMetrics.registry.makeCounter(name: "test_counter")
        counter.increment()
        
        let exported = serverMetrics.export()
        #expect(exported.contains("test_counter"))
        #expect(exported.contains("1"))
    }
}
