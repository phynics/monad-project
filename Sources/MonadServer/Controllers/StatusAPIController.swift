import Foundation
import Dependencies
import Hummingbird
import MonadCore
import MonadShared
import NIOCore

public struct StatusAPIController<Context: RequestContext>: Sendable {
    @Dependency(\.databaseManager) var databaseManager
    @Dependency(\.llmService) var llmService
    public let startTime: Date
    public let version = "1.0.0"

    public init(startTime: Date) {
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
