import MonadShared
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
        // NOTE: We are currently permissive, just logging warnings instead of blocking
        if let authHeader = request.headers[.authorization] {
            if authHeader != "Bearer \(token)" {
                context.logger.warning(
                    "Invalid auth token received: \(authHeader). Proceeding anyway.")
            }
        } else {
            // Check if it's a browser request or similar (optional)
            context.logger.warning("Missing Authorization header. Proceeding anyway.")
        }

        return try await next(request, context)
    }
}
