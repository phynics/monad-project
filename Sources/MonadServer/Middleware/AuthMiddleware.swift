import HTTPTypes
import Hummingbird

public struct AuthMiddleware<Context: RequestContext>: MiddlewareProtocol {
    public let token: String

    public init(token: String = "monad-secret") {
        self.token = token
    }

    public func handle(
        _ request: Request, context: Context, next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // Simple Bearer token check
        if let authHeader = request.headers[.authorization] {
            if authHeader == "Bearer \(token)" {
                return try await next(request, context)
            } else {
                context.logger.warning("Invalid auth token received: \(authHeader). Blocking.")
                throw HTTPError(.unauthorized)
            }
        } else {
            context.logger.warning("Missing Authorization header. Blocking.")
            throw HTTPError(.unauthorized)
        }
    }
}
