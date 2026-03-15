import Foundation
import HTTPTypes
import Hummingbird
import Logging
import MonadCore
import MonadShared
import NIOCore

public struct ErrorMiddleware<Context: RequestContext>: MiddlewareProtocol {
    public init() {}

    public func handle(
        _ request: Request, context: Context, next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let error as HTTPError {
            return try buildErrorResponse(
                code: "http_error",
                message: error.status.reasonPhrase,
                status: error.status,
                request: request,
                context: context
            )
        } catch let error as ToolError {
            let classification = classifyToolError(error)
            return try buildErrorResponse(
                code: classification.code,
                message: error.localizedDescription,
                status: classification.status,
                request: request,
                context: context
            )
        } catch let error as MonadCore.TimelineError {
            let classification = classifyTimelineError(error)
            return try buildErrorResponse(
                code: classification.code,
                message: error.localizedDescription,
                status: classification.status,
                request: request,
                context: context
            )
        } catch {
            Logger.module(named: "server").error("Unhandled error in middleware: \(error)")
            return try buildErrorResponse(
                code: "internal_server_error",
                message: "An unexpected error occurred.",
                status: .internalServerError,
                request: request,
                context: context
            )
        }
    }

    // MARK: - Error Classification

    private struct ErrorClassification {
        let status: HTTPResponse.Status
        let code: String
    }

    private func classifyToolError(_ error: ToolError) -> ErrorClassification {
        switch error {
        case .toolNotFound:
            return ErrorClassification(status: .notFound, code: "tool_not_found")
        case .workspaceNotFound:
            return ErrorClassification(status: .notFound, code: "workspace_not_found")
        case .missingArgument:
            return ErrorClassification(status: .badRequest, code: "missing_argument")
        case .invalidArgument:
            return ErrorClassification(status: .badRequest, code: "invalid_argument")
        case .clientNotConnected:
            return ErrorClassification(status: .serviceUnavailable, code: "client_not_connected")
        case .executionFailed:
            return ErrorClassification(status: .internalServerError, code: "execution_failed")
        case .clientToolsDisallowedOnPrivateTimeline:
            return ErrorClassification(status: .forbidden, code: "client_tools_disallowed_on_private_timeline")
        }
    }

    private func classifyTimelineError(_ error: MonadCore.TimelineError) -> ErrorClassification {
        switch error {
        case .timelineNotFound:
            return ErrorClassification(status: .notFound, code: "session_not_found")
        }
    }

    private func buildErrorResponse(
        code: String,
        message: String,
        status: HTTPResponse.Status,
        request: Request,
        context: Context
    ) throws -> Response {
        let apiError = APIErrorResponse(error: .init(code: code, message: message))
        var response = try apiError.response(from: request, context: context)
        response.status = status
        return response
    }
}
