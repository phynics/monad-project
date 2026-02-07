import Foundation
import Hummingbird
import MonadCore
import NIOCore

public struct StatusController<Context: RequestContext>: Sendable {
    public let persistenceService: any PersistenceServiceProtocol
    public let llmService: any LLMServiceProtocol
    
    public init(
        persistenceService: any PersistenceServiceProtocol,
        llmService: any LLMServiceProtocol
    ) {
        self.persistenceService = persistenceService
        self.llmService = llmService
    }
    
    public func addRoutes(to router: Router<Context>) {
        router.get("/status", use: getStatus)
    }
    
    @Sendable func getStatus(_ request: Request, context: Context) async throws -> StatusResponse {
        // Run health checks
        let dbHealth = await persistenceService.checkHealth()
        let dbDetails = await persistenceService.healthDetails
        
        let aiHealth = await llmService.checkHealth()
        let aiDetails = await llmService.healthDetails
        
        let overallStatus: HealthStatus = (dbHealth == .ok && aiHealth == .ok) ? .ok : .degraded
        
        return StatusResponse(
            status: overallStatus,
            version: "1.0.0", // TODO: Pull from config or build info
            uptime: 0, // TODO: Implement uptime tracking
            components: [
                "database": ComponentStatus(status: dbHealth, details: dbDetails),
                "ai_provider": ComponentStatus(status: aiHealth, details: aiDetails)
            ]
        )
    }
}

extension StatusResponse: ResponseGenerator {
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
