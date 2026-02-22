import Hummingbird
import MonadShared
import MonadCore
import Foundation
import NIOCore
import HTTPTypes

/// Standard extension to make any Codable & Sendable type a ResponseGenerator
extension ResponseGenerator where Self: Codable & Sendable {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        return try self.response(status: .ok, from: request, context: context)
    }

    public func response(status: HTTPResponse.Status, from request: Request, context: some RequestContext) throws -> Response {
        let data = try SerializationUtils.jsonEncoder.encode(self)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

// Concrete conformances for shared models

extension SessionResponse: ResponseGenerator {}

extension WorkspaceReference: ResponseGenerator {}

extension PaginatedResponse: ResponseGenerator {}

extension ToolReference: ResponseGenerator {}

extension ToolInfo: ResponseGenerator {}

extension Memory: ResponseGenerator {}

extension ClientIdentity: ResponseGenerator {}

extension ClientRegistrationResponse: ResponseGenerator {}

extension Job: ResponseGenerator {}

extension LLMConfiguration: ResponseGenerator {}

extension PruneResponse: ResponseGenerator {}

extension MonadShared.StatusResponse: ResponseGenerator {}

extension ChatResponse: ResponseGenerator {}

extension SessionWorkspacesResponse: ResponseGenerator {}

extension APIErrorResponse: ResponseGenerator {}

extension Message: ResponseGenerator {}
