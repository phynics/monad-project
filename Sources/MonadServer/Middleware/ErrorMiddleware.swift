import Hummingbird
import Foundation
import HTTPTypes
import MonadCore

public struct ErrorMiddleware<Context: RequestContext>: MiddlewareProtocol {
    public init() {}
    
    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let error as HTTPError {
            return Response(status: error.status)
        } catch let error as MonadCore.ToolError {
            switch error {
            case .toolNotFound, .workspaceNotFound:
                return Response(status: .notFound)
            case .missingArgument, .invalidArgument:
                return Response(status: .badRequest)
            case .clientNotConnected:
                return Response(status: .serviceUnavailable)
            case .executionFailed, .clientExecutionRequired:
                return Response(status: .internalServerError)
            }
        } catch let error as MonadCore.SessionError {
            switch error {
            case .sessionNotFound:
                return Response(status: .notFound)
            }
        } catch {
            return Response(status: .internalServerError)
        }
    }
}