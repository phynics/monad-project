import Hummingbird
import HTTPTypes

public struct AuthMiddleware<Context: RequestContext>: MiddlewareProtocol {
    public let token: String
    
    public init(token: String = "monad-secret") {
        self.token = token
    }

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        // Simple Bearer token check
        guard let authHeader = request.headers[.authorization] else {
            throw HTTPError(.unauthorized, message: "Missing Authorization header")
        }
        
        guard authHeader == "Bearer \(token)" else {
            throw HTTPError(.forbidden, message: "Invalid token")
        }
        
        return try await next(request, context)
    }
}
