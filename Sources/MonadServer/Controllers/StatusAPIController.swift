import Foundation
import Hummingbird
import MonadCore
import MonadShared
import NIOCore

public struct StatusAPIController<Context: RequestContext>: Sendable {
    public let persistenceService: any PersistenceServiceProtocol
    public let llmService: any LLMServiceProtocol
    public let startTime: Date
    public let version = "1.0.0"

    public init(
        persistenceService: any PersistenceServiceProtocol,
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
    
    @Sendable func getStatus(_ request: Request, context: Context) async throws -> MonadShared.StatusResponse {
        // Run health checks
        let dbHealth = await persistenceService.checkHealth()
        let dbDetails = await persistenceService.getHealthDetails()
        
        let aiHealth = await llmService.checkHealth()
        let aiDetails = await llmService.getHealthDetails()
        
        // Map MonadCore.HealthStatus to MonadShared.HealthStatus
        let mappedDbHealth = MonadShared.HealthStatus(fromCore: dbHealth)
        let mappedAiHealth = MonadShared.HealthStatus(fromCore: aiHealth)
        
        let overallStatus: MonadShared.HealthStatus = (dbHealth == .ok && aiHealth == .ok) ? .ok : .degraded
        
        let uptime = Date().timeIntervalSince(startTime)

        return MonadShared.StatusResponse(
            status: overallStatus,
            version: version,
            uptime: uptime,
            components: [
                "database": MonadShared.ComponentStatus(status: mappedDbHealth, details: dbDetails),
                "ai_provider": MonadShared.ComponentStatus(status: mappedAiHealth, details: aiDetails)
            ]
        )
    }
}

extension MonadShared.StatusResponse: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let data = try JSONEncoder().encode(self)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(bytes: data))
        )
    }
}

extension MonadShared.HealthStatus {
    init(fromCore status: MonadCore.HealthStatus) {
        switch status {
        case .ok: self = .ok
        case .degraded: self = .degraded
        case .down: self = .down
        }
    }
}
