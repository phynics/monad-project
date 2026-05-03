import Foundation
import HTTPTypes
import Hummingbird
import PositronicKit
import PKShared
import MonadShared
import NIOCore

/// Standard extension to make any Codable & Sendable type a ResponseGenerator
public extension ResponseGenerator where Self: Codable & Sendable {
    func response(from request: Request, context: some RequestContext) throws -> Response {
        return try response(status: .ok, from: request, context: context)
    }

    func response(status: HTTPResponse.Status, from _: Request, context _: some RequestContext) throws -> Response {
        let data = try SerializationUtils.jsonEncoder.encode(self)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data))
        )
    }
}

// Concrete conformances for shared models

extension TimelineResponse: ResponseGenerator {}

extension WorkspaceReference: @retroactive ResponseGenerator {}

extension PaginatedResponse: ResponseGenerator {}

extension ToolReference: @retroactive ResponseGenerator {}

extension ToolInfo: ResponseGenerator {}

extension Memory: @retroactive ResponseGenerator {}

extension RequestOriginIdentity: @retroactive ResponseGenerator {}

extension RequestOriginRegistrationResponse: ResponseGenerator {}

extension LLMConfiguration: @retroactive ResponseGenerator {}

extension PruneResponse: ResponseGenerator {}

extension StatusResponse: ResponseGenerator {}

extension ChatResponse: ResponseGenerator {}

extension TimelineWorkspacesResponse: ResponseGenerator {}

extension APIErrorResponse: ResponseGenerator {}

extension Message: @retroactive ResponseGenerator {}
