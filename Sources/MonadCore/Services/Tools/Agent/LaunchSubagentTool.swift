import Foundation
import Logging
import OpenAI

/// Tool that allows an agent to launch a sub-task using another agent
public struct LaunchSubagentTool: Tool, Sendable {
    public let id = "launch_subagent"
    public let name = "Launch Subagent"
    public let description = "Delegate a specific task to another agent. This task will run in the background."
    public let requiresPermission = true

    private let persistenceService: any PersistenceServiceProtocol
    private let sessionId: UUID
    private let parentId: UUID?
    private let agentRegistry: AgentRegistry

    public init(
        persistenceService: any PersistenceServiceProtocol,
        sessionId: UUID,
        parentId: UUID? = nil,
        agentRegistry: AgentRegistry
    ) {
        self.persistenceService = persistenceService
        self.sessionId = sessionId
        self.parentId = parentId
        self.agentRegistry = agentRegistry
    }

    public var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "agent_id": [
                    "type": "string",
                    "description": "The ID of the agent to launch (e.g. 'default', 'researcher', 'coder')."
                ],
                "task_title": [
                    "type": "string",
                    "description": "A short, descriptive title for the task."
                ],
                "task_description": [
                    "type": "string",
                    "description": "A detailed description of what the subagent should do."
                ],
                "priority": [
                    "type": "integer",
                    "description": "Priority of the task (0-10, higher is more urgent).",
                    "default": 0
                ],
                "parent_id": [
                    "type": "string",
                    "description": "Optional parent job ID. If not provided, it defaults to the current job ID if applicable."
                ]
            ],
            "required": ["agent_id", "task_title", "task_description"]
        ]
    }

    public func canExecute() async -> Bool {
        return true
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let agentId = parameters["agent_id"] as? String else {
            return .failure("Missing 'agent_id'")
        }
        guard let title = parameters["task_title"] as? String else {
            return .failure("Missing 'task_title'")
        }
        guard let taskDescription = parameters["task_description"] as? String else {
            return .failure("Missing 'task_description'")
        }
        
        let priority = (parameters["priority"] as? Int) ?? 0
        
        var resolvedParentId = parentId
        if let explicitParentIdString = parameters["parent_id"] as? String,
           let explicitParentId = UUID(uuidString: explicitParentIdString) {
            resolvedParentId = explicitParentId
        }

        // Verify agent exists
        guard await agentRegistry.hasAgent(id: agentId) else {
            let available = await agentRegistry.listAgents().map { "\($0.id) (\($0.name))" }.joined(separator: ", ")
            return .failure("Agent '\(agentId)' not found. Available agents: \(available)")
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
