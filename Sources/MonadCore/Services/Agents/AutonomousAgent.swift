import Foundation
import Logging
import OpenAI

/// An autonomous agent that executes jobs in the background
public class AutonomousAgent: BaseAgent, @unchecked Sendable {
    
    public override init(
        manifest: AgentManifest,
        llmService: any LLMServiceProtocol,
        persistenceService: any PersistenceServiceProtocol,
        reasoningEngine: ReasoningEngine? = nil
    ) {
        super.init(
            manifest: manifest,
            llmService: llmService,
            persistenceService: persistenceService,
            reasoningEngine: reasoningEngine
        )
    }
    
    public init(
        id: String = "default",
        name: String = "Autonomous Agent",
        description: String = "General purpose autonomous agent",
        llmService: any LLMServiceProtocol,
        persistenceService: any PersistenceServiceProtocol
    ) {
        let manifest = AgentManifest(id: id, name: name, description: description)
        super.init(
            manifest: manifest,
            llmService: llmService,
            persistenceService: persistenceService
        )
    }

    open override var systemInstructions: String {
        "You are an autonomous agent executing a background job. Complete the task."
    }
}
