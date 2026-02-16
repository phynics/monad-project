import MonadShared
import XCTest
@testable import MonadCore

final class SystemStatusTests: XCTestCase {
    func testStatusResponseSerialization() throws {
        let component = MonadShared.ComponentStatus(status: .ok, details: ["provider": "openai"])
        let response = MonadShared.StatusResponse(
            status: .ok,
            version: "1.0.0",
            uptime: 3600,
            components: ["ai_provider": component]
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MonadShared.StatusResponse.self, from: data)
        
        XCTAssertEqual(decoded.status, .ok)
        XCTAssertEqual(decoded.version, "1.0.0")
        XCTAssertEqual(decoded.uptime, 3600)
        XCTAssertEqual(decoded.components["ai_provider"]?.status, .ok)
        XCTAssertEqual(decoded.components["ai_provider"]?.details?["provider"], "openai")
    }

    func testHealthCheckableProtocol() async throws {
        struct MockService: HealthCheckable {
            func getHealthStatus() async -> MonadCore.HealthStatus { .ok }
            func getHealthDetails() async -> [String: String]? { ["test": "true"] }
            func checkHealth() async -> MonadCore.HealthStatus { .ok }
        }
        
        let service = MockService()
        let status = await service.checkHealth()
        let currentStatus = await service.getHealthStatus()
        let currentDetails = await service.getHealthDetails()
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(currentStatus, .ok)
        XCTAssertEqual(currentDetails?["test"], "true")
    }
}
