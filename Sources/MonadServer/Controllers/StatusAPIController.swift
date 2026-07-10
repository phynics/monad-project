import Foundation
import Hummingbird
import PositronicKit
import PKShared
import MonadShared
import NIOCore

public struct StatusAPIController<Context: RequestContext>: Sendable {
    private struct NoOpDatabaseHealth: HealthCheckable {
        func getHealthStatus() async -> HealthStatus { .ok }
        func getHealthDetails() async -> [String: String]? { nil }
        func checkHealth() async -> HealthStatus { .ok }
    }

    private let databaseManager: any HealthCheckable
    private let llmService: any LLMStreamClient & LLMConfigStore & LLMUtilityClient & HealthCheckable
    public let startTime: Date
    public let version = "1.0.0"

    public init(
        databaseManager: any HealthCheckable,
        llmService: any LLMStreamClient & LLMConfigStore & LLMUtilityClient & HealthCheckable,
        startTime: Date
    ) {
        self.databaseManager = databaseManager
        self.llmService = llmService
        self.startTime = startTime
    }

    public func addRoutes(to router: Router<Context>) {
        router.get("/status", use: getStatus)
    }

    @Sendable func getStatus(_ request: Request, context: Context) async throws -> StatusResponse {
        // Run health checks
        let dbHealth = await databaseManager.checkHealth()
        let dbDetails = await databaseManager.getHealthDetails()

        let aiHealth = await llmService.checkHealth()
        let aiDetails = await llmService.getHealthDetails()

        // Map HealthStatus to HealthStatus
        let mappedDbHealth = HealthStatus(fromCore: dbHealth)
        let mappedAiHealth = HealthStatus(fromCore: aiHealth)

        let overallStatus: HealthStatus = (dbHealth == .ok && aiHealth == .ok) ? .ok : .degraded

        let uptime = Date().timeIntervalSince(startTime)

        return StatusResponse(
            status: overallStatus,
            version: version,
            uptime: uptime,
            components: [
                "database": ComponentStatus(status: mappedDbHealth, details: dbDetails),
                "ai_provider": ComponentStatus(status: mappedAiHealth, details: aiDetails)
            ]
        )
    }
}

extension HealthStatus {
    init(fromCore status: HealthStatus) {
        switch status {
        case .ok: self = .ok
        case .degraded: self = .degraded
        case .down: self = .down
        }
    }
}
