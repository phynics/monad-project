import MonadShared
import Hummingbird
import Logging
import Foundation

public struct LogMiddleware<Context: RequestContext>: MiddlewareProtocol {
    public init() {}
    
    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        let start = DispatchTime.now()
        context.logger.info("Request: \(request.method) \(request.uri.path)")
        
        do {
            let response = try await next(request, context)
            let end = DispatchTime.now()
            let duration = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            
            context.logger.info("Response: \(response.status.code) (\(String(format: "%.3fs", duration)))")
            return response
        } catch {
            let end = DispatchTime.now()
            let duration = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            
            context.logger.error("Error: \(error) (\(String(format: "%.3fs", duration)))")
            throw error
        }
    }
}
