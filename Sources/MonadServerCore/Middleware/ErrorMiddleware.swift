import Hummingbird
import Foundation
import HTTPTypes

public struct ErrorMiddleware<Context: RequestContext>: MiddlewareProtocol {
    public init() {}
    
    public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        do {
            return try await next(request, context)
        } catch let error as HTTPError {
            return errorResponse(status: error.status, message: error.body ?? "Unknown Error")
        } catch {
            return errorResponse(status: .internalServerError, message: error.localizedDescription)
        }
    }
    
    private func errorResponse(status: HTTPResponse.Status, message: String) -> Response {
        let errorBody = ErrorResponse(error: .init(message: message))
        guard let data = try? JSONEncoder().encode(errorBody) else {
            return Response(status: status, body: .init(byteBuffer: ByteBuffer(string: "{\"error\":{\"message\":\"\(message)\"}}")))
        }
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

struct ErrorResponse: Codable {
    struct ErrorDetail: Codable {
        let message: String
    }
    let error: ErrorDetail
}

