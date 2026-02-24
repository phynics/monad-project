import Foundation
import Logging

/// A tool wrapper that allows an Agent definition to be called as a tool by another agent or chat session.
/// Executing this tool results in a background Job being queued for the target agent.
public struct AgentAsTool: Tool, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let requiresPermission: Bool

    private let agentId: String
    private let agentName: String
    private let jobQueueContext: JobQueueContext

    public init(agent: Agent, jobQueueContext: JobQueueContext) {
        self.agentId = agent.id.uuidString
        self.agentName = agent.name
        self.jobQueueContext = jobQueueContext

        // Tool ID is the agent ID
        self.id = agent.id.uuidString
        self.name = agent.name

        // Tool description uses the agent's description but emphasizes background execution
        self.description = "\(agent.description) (Launches a background task)"

        // Delegation usually requires permission in this framework
        self.requiresPermission = true
    }

    public var parametersSchema: [String: AnyCodable] {
        ToolParameterSchema.object { b in
            b.string("task_title", description: "A short, descriptive title for the task.", required: true)
            b.string("task_description", description: "A detailed description of what the agent should do.", required: true)
            b.integer("priority", description: "Priority of the task (0-10, higher is more urgent).")
        }.schema
    }

    public func canExecute() async -> Bool {
        return true
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let params = ToolParameters(parameters)
        let title: String
        let taskDescription: String
        
        do {
            title = try params.require("task_title", as: String.self)
            taskDescription = try params.require("task_description", as: String.self)
        } catch {
            return .failure(error.localizedDescription)
        }

        let priority = params.optional("priority", as: Int.self) ?? 0

        let request = AddJobRequest(
            title: title,
            description: taskDescription,
            priority: priority,
            agentId: agentId
        )

        do {
            let job = try await jobQueueContext.launchSubagent(request: request)
            return .success("Task delegated to '\(agentName)'. Background Job ID: \(job.id.uuidString.prefix(8))")
        } catch {
            return .failure("Failed to delegate task: \(error.localizedDescription)")
        }
    }

    public func summarize(parameters: [String: Any], result: ToolResult) -> String {
        let title = parameters["task_title"] as? String ?? "untitled"
        return "[\(id)] → \(title) (\(result.success ? "Delegated" : "Failed"))"
    }
}