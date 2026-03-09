import Foundation
import Logging
import MonadShared
import OpenAI

/// Tool that allows an agent to launch a sub-task using another agent
public struct LaunchSubagentTool: MonadShared.Tool, Sendable {
    public let id = "launch_subagent"
    public let name = "Launch Subagent"
    public let description = "Delegate a specific task to another agent. This task will run in the background."
    public let requiresPermission = true

    private let backgroundJobStore: any BackgroundJobStoreProtocol
    private let messageStore: any MessageStoreProtocol
    private let agentTemplateStore: any AgentTemplateStoreProtocol
    private let timelineId: UUID
    private let parentId: UUID?

    public init(
        backgroundJobStore: any BackgroundJobStoreProtocol,
        messageStore: any MessageStoreProtocol,
        agentTemplateStore: any AgentTemplateStoreProtocol,
        timelineId: UUID,
        parentId: UUID? = nil
    ) {
        self.backgroundJobStore = backgroundJobStore
        self.messageStore = messageStore
        self.agentTemplateStore = agentTemplateStore
        self.timelineId = timelineId
        self.parentId = parentId
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
        guard await agentTemplateStore.hasAgentTemplate(id: agentId) else {
            let available = (try? await agentTemplateStore.fetchAllAgentTemplates())?.map { "\($0.id) (\($0.name))" }.joined(separator: ", ") ?? ""
            return .failure("AgentTemplate '\(agentId)' not found. Available agentTemplates: \(available)")
        }

        // Create the job
        let job = BackgroundJob(
            timelineId: timelineId,
            parentId: resolvedParentId,
            title: title,
            description: taskDescription,
            priority: priority,
            agentId: agentId
        )

        do {
            try await backgroundJobStore.saveJob(job)
            return .success("Launched subagent '\(agentId)' for task: '\(title)'. BackgroundJob ID: \(job.id)")
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
