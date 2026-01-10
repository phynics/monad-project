import Foundation

/// Gateway tool that activates the JobQueueContext
///
/// When executed, this tool activates the job queue context and makes
/// job management tools available. Calling any non-context tool will
/// automatically exit the job queue context.
public final class JobQueueGatewayTool: ContextGatewayTool, @unchecked Sendable {
    public typealias Context = JobQueueContext

    public let id = "manage_jobs"
    public let name = "Manage Jobs"
    public let description = "Enter job queue management mode to add, remove, and prioritize jobs"
    public let requiresPermission = false

    public let context: JobQueueContext
    public let contextSession: ToolContextSession

    public init(context: JobQueueContext, contextSession: ToolContextSession) {
        self.context = context
        self.contextSession = contextSession
    }

    public func canExecute() async -> Bool { true }

    public var parametersSchema: [String: Any] {
        ["type": "object", "properties": [:]]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        // Activate the context
        await contextSession.activate(context)

        // Return welcome message
        let message = await context.welcomeMessage()
        return .success(message)
    }
}
