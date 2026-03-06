import Hummingbird
import Foundation
import HTTPTypes
import MonadCore
import MonadShared
import Logging
import NIOCore

public struct ErrorMiddleware<Context: RequestContext>: MiddlewareProtocol {
    public init() {}

    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let error as HTTPError {
            let apiError = APIErrorResponse(error: .init(
                code: "http_error",
                message: error.status.reasonPhrase
            ))
            var response = try apiError.response(from: request, context: context)
            response.status = error.status
            return response
        } catch let error as ToolError {
            let status: HTTPResponse.Status
            let code: String
            switch error {
            case .toolNotFound:
                status = .notFound
                code = "tool_not_found"
            case .workspaceNotFound:
                status = .notFound
                code = "workspace_not_found"
            case .missingArgument:
                status = .badRequest
                code = "missing_argument"
            case .invalidArgument:
                status = .badRequest
                code = "invalid_argument"
            case .clientNotConnected:
                status = .serviceUnavailable
                code = "client_not_connected"
            case .executionFailed:
                status = .internalServerError
                code = "execution_failed"
            case .clientExecutionRequired:
                status = .internalServerError
                code = "client_execution_required"
            }

            let apiError = APIErrorResponse(error: .init(
                code: code,
                message: error.localizedDescription
            ))
            var response = try apiError.response(from: request, context: context)
            response.status = status
            return response
        } catch let error as MonadCore.TimelineError {
            let status: HTTPResponse.Status
            let code: String
            switch error {
            case .timelineNotFound:
                status = .notFound
                code = "session_not_found"
            }

            let apiError = APIErrorResponse(error: .init(
                code: code,
                message: error.localizedDescription
            ))
            var response = try apiError.response(from: request, context: context)
            response.status = status
            return response
        } catch {
            Logger.module(named: "server").error("Unhandled error in middleware: \(error)")
            let apiError = APIErrorResponse(error: .init(
                code: "internal_server_error",
                message: "An unexpected error occurred."
            ))
            var response = try apiError.response(from: request, context: context)
            response.status = .internalServerError
            return response
        }
    }
}
