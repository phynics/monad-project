import Foundation
import Hummingbird
import MonadCore
import NIOCore

public struct StatusAPIController<Context: RequestContext>: Sendable {
    public let persistenceService: any HealthCheckable
    public let llmService: any LLMServiceProtocol
    public let startTime: Date
    public let version = "1.0.0"

    public init(
        persistenceService: any HealthCheckable,
        llmService: any LLMServiceProtocol,
        startTime: Date
    ) {
        self.persistenceService = persistenceService
        self.llmService = llmService
        self.startTime = startTime
    }

    public func addRoutes(to router: Router<Context>) {
        router.get("/status", use: getStatus)
    }

    @Sendable func getStatus(_ request: Request, context: Context) async throws -> StatusResponse {
        // Run health checks
        let dbHealth = await persistenceService.checkHealth()
        let dbDetails = await persistenceService.getHealthDetails()

        let aiHealth = await llmService.checkHealth()
        let aiDetails = await llmService.getHealthDetails()

        // Map MonadCore.HealthStatus to HealthStatus
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
    init(fromCore status: MonadCore.HealthStatus) {
        switch status {
        case .ok: self = .ok
        case .degraded: self = .degraded
        case .down: self = .down
        }
    }
}
