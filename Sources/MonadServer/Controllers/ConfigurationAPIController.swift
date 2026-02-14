import Hummingbird
import Foundation
import MonadCore
import NIOCore
import HTTPTypes

public struct ConfigurationAPIController<Context: RequestContext>: Sendable {
    public let llmService: any LLMServiceProtocol
    
    public init(llmService: any LLMServiceProtocol) {
        self.llmService = llmService
    }
    
    public func addRoutes(to group: RouterGroup<Context>) {
        group.get("/", use: getConfiguration)
        group.put("/", use: updateConfiguration)
        group.delete("/", use: clearConfiguration)
    }
    
    @Sendable func getConfiguration(_ request: Request, context: Context) async throws -> LLMConfiguration {
        return await llmService.configuration
    }
    
    @Sendable func updateConfiguration(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        let config = try await request.decode(as: LLMConfiguration.self, context: context)
        try await llmService.updateConfiguration(config)
        return .ok
    }
    
    @Sendable func clearConfiguration(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        await llmService.clearConfiguration()
        return .noContent
    }
}

extension LLMConfiguration: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let data = try SerializationUtils.jsonEncoder.encode(self)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}