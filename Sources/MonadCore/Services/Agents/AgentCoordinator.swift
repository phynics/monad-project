import Foundation
import Logging
import OpenAI

/// An agent that specializes in coordinating other agents to complete complex tasks
public class AgentCoordinator: BaseAgent, @unchecked Sendable {

    public init(
        llmService: any LLMServiceProtocol,
        persistenceService: any PersistenceServiceProtocol,
        reasoningEngine: ReasoningEngine? = nil
    ) {
        let manifest = AgentManifest(
            id: "coordinator",
            name: "Agent Coordinator",
            description: "Expert at breaking down complex tasks and delegating them to specialized subagents.",
            capabilities: ["coordination", "planning", "delegation"]
        )
        super.init(
            manifest: manifest,
            llmService: llmService,
            persistenceService: persistenceService,
            reasoningEngine: reasoningEngine
        )
    }

    open override var systemInstructions: String {
        """
        You are the Agent Coordinator. Your goal is to complete complex tasks by breaking them down and delegating to specialized subagents.
        
        STRATEGY:
        1. ANALYZE: Understand the high-level goal.
        2. PLAN: Break the goal into discrete, parallelizable sub-tasks.
        3. DELEGATE: Use `launch_subagent` to assign tasks to specialized agents.
        4. MONITOR: Check progress of sub-tasks using available tools.
        5. SYNTHESIZE: Once sub-tasks are complete, combine their results to fulfill the original goal.
        
        IMPORTANT:
        - State 'Job Complete' only when the ENTIRE high-level goal is achieved.
        - If you are waiting for sub-tasks, you can state 'Waiting for sub-tasks' and finish your turn. The job runner will resume you when state changes or after a timeout.
        """
    }
}
