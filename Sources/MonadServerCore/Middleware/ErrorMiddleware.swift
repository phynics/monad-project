import Hummingbird
import Foundation
import HTTPTypes

public struct ErrorMiddleware<Context: RequestContext>: MiddlewareProtocol {
    public init() {}
    
    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let error as HTTPError {
            return Response(status: error.status)
        } catch {
            return Response(status: .internalServerError)
        }
    }
}