import Hummingbird
import Foundation
import HTTPTypes
import NIOCore
import MonadCore

public struct SessionController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager
    
    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }
    
    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/", use: create)
    }
    
    @Sendable func create(_ request: Request, context: Context) async throws -> Response {
        let session = try await sessionManager.createSession()
        let data = try SerializationUtils.jsonEncoder.encode(session)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .created, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}
