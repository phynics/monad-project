import Hummingbird
import MonadCore
import MonadShared
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

extension TimelineResponse: ResponseGenerator {}

extension WorkspaceReference: ResponseGenerator {}

extension PaginatedResponse: ResponseGenerator {}

extension ToolReference: ResponseGenerator {}

extension ToolInfo: ResponseGenerator {}

extension Memory: ResponseGenerator {}

extension ClientIdentity: ResponseGenerator {}

extension ClientRegistrationResponse: ResponseGenerator {}

extension BackgroundJob: ResponseGenerator {}

extension LLMConfiguration: ResponseGenerator {}

extension PruneResponse: ResponseGenerator {}

extension StatusResponse: ResponseGenerator {}

extension ChatResponse: ResponseGenerator {}

extension TimelineWorkspacesResponse: ResponseGenerator {}

extension APIErrorResponse: ResponseGenerator {}

extension Message: ResponseGenerator {}
