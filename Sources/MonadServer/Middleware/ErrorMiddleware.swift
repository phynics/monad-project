import MonadShared
import Hummingbird
import Foundation
import HTTPTypes
import MonadCore
import Logging
import NIOCore

extension APIErrorResponse: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let data = try SerializationUtils.jsonEncoder.encode(self)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        // Note: The status code should be set by the caller if it's not .ok
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

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
        } catch let error as MonadCore.ToolError {
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
        } catch let error as MonadCore.SessionError {
            let status: HTTPResponse.Status
            let code: String
            switch error {
            case .sessionNotFound:
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
            Logger.server.error("Unhandled error in middleware: \(error)")
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