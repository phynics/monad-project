import Foundation
import MonadShared
import Logging
import OpenAI

/// Tool that allows an agent to launch a sub-task using another agent
public struct LaunchSubagentTool: MonadShared.Tool, Sendable {
    public let id = "launch_subagent"
    public let name = "Launch Subagent"
    public let description = "Delegate a specific task to another agent. This task will run in the background."
    public let requiresPermission = true

    private let persistenceService: any JobStoreProtocol
    private let sessionId: UUID
    private let parentId: UUID?
    private let msAgentRegistry: MSAgentRegistry

    public init(
        persistenceService: any JobStoreProtocol,
        sessionId: UUID,
        parentId: UUID? = nil,
        msAgentRegistry: MSAgentRegistry
    ) {
        self.persistenceService = persistenceService
        self.sessionId = sessionId
        self.parentId = parentId
        self.msAgentRegistry = msAgentRegistry
    }

    public var parametersSchema: [String: AnyCodable] {
        ToolParameterSchema.object { builder in
            builder.string("agent_id", description: "The ID of the agent to launch (e.g. 'default', 'researcher', 'coder').", required: true)
            builder.string("task_title", description: "A short, descriptive title for the task.", required: true)
            builder.string("task_description", description: "A detailed description of what the subagent should do.", required: true)
            builder.integer("priority", description: "Priority of the task (0-10, higher is more urgent).")
            builder.string("parent_id", description: "Optional parent job ID. If not provided, it defaults to the current job ID if applicable.")
        }.schema
    }

    public func canExecute() async -> Bool {
        return true
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let params = ToolParameters(parameters)
        let agentId: String
        let title: String
        let taskDescription: String

        do {
            agentId = try params.require("agent_id", as: String.self)
            title = try params.require("task_title", as: String.self)
            taskDescription = try params.require("task_description", as: String.self)
        } catch {
            return .failure(error.localizedDescription)
        }

        let priority = params.optional("priority", as: Int.self) ?? 0

        var resolvedParentId = parentId
        if let explicitParentIdString = params.optional("parent_id", as: String.self),
           let explicitParentId = UUID(uuidString: explicitParentIdString) {
            resolvedParentId = explicitParentId
        }

        // Verify agent exists
        guard await msAgentRegistry.hasMSAgent(id: agentId) else {
            let available = await msAgentRegistry.listMSAgents().map { "\($0.id) (\($0.name))" }.joined(separator: ", ")
            return .failure("MSAgent '\(agentId)' not found. Available msAgents: \(available)")
        }

        // Create the job
        let job = Job(
            sessionId: sessionId,
            parentId: resolvedParentId,
            title: title,
            description: taskDescription,
            priority: priority,
            agentId: agentId
        )

        do {
            try await persistenceService.saveJob(job)
            return .success("Launched subagent '\(agentId)' for task: '\(title)'. Job ID: \(job.id)")
        } catch {
            return .failure("Failed to create job: \(error.localizedDescription)")
        }
    }

    public func summarize(parameters: [String: Any], result: ToolResult) -> String {
        let agentId = parameters["agent_id"] as? String ?? "unknown"
        let title = parameters["task_title"] as? String ?? "untitled task"
        return "[launch_subagent(\(agentId))] → \(title) (\(result.success ? "Success" : "Failed"))"
    }
}
