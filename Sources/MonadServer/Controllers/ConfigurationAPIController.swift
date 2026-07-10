import PKShared
import MonadShared
import Hummingbird
import Foundation
import PositronicKit
import NIOCore
import HTTPTypes

public struct ConfigurationAPIController<Context: RequestContext>: Sendable {
    public let llmService: any LLMStreamClient & LLMConfigStore & LLMUtilityClient

    public init(llmService: any LLMStreamClient & LLMConfigStore & LLMUtilityClient) {
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
