import Foundation
import MonadPrompt
import MonadShared

/// Pure, stateless prompt assembly — no actor isolation or LLM client required.
public enum PromptBuilder {
    // MARK: - Constants

    public static let maxHistoryTokens = 120_000
    public static let historyTokenBuffer = 4000

    // MARK: - Default Stages

    /// Returns the standard sequence of stages used to assemble a prompt.
    public static func defaultAssemblyStages() -> [any PipelineStage<PromptAssemblyContext, PromptAssemblyEvent>] {
        [
            SystemInstructionsStage(),
            AgentContextStage(),
            ContextNotesStage(),
            MemoriesStage(),
            ToolsStage(),
            WorkspacesContextStage(),
            TimelineContextStage(),
            ChatHistoryStage(),
            UserQueryStage(),
            ExtensionSectionsStage()
        ]
    }

    // MARK: - Build Context

    /// Assembles a `Prompt` from a request, optional agent/timeline context, and extension sections.
    /// Uses the `PromptAssemblyPipeline` to orchestrate assembly.
    public static func buildContext(
        _ request: LLMPromptRequest,
        agentInstance: AgentInstance? = nil,
        timeline: Timeline? = nil,
        extensionSections: [any ContextSection] = []
    ) async throws -> Prompt {
        let assemblyContext = PromptAssemblyContext(
            request: request,
            agentInstance: agentInstance,
            timeline: timeline,
            extensionSections: extensionSections
        )
        
        let pipeline = PromptAssemblyPipeline(stages: defaultAssemblyStages())
        
        // Execute the pipeline and drain the events.
        let stream = pipeline.execute(assemblyContext)
        for try await _ in stream {}
        
        return Prompt(sections: await assemblyContext.sections)
    }

    /// Builds a prompt and converts it to OpenAI message format + raw text.
    public static func buildPrompt(_ request: LLMPromptRequest) async throws -> LLMPromptResult {
        let prompt = try await buildContext(request)
        let messages = await prompt.toMessages()
        let raw = await prompt.render()
        return LLMPromptResult(messages: messages, rawPrompt: raw)
    }

    // MARK: - History Optimization

    /// Truncates history to fit within a token budget, keeping the most recent messages.
    public static func optimizeHistory(
        _ messages: [Message],
        availableTokens: Int
    ) -> [Message] {
        var result: [Message] = []
        var usedTokens = 0

        for message in messages.reversed() {
            let tokens = TokenEstimator.estimate(text: message.content)
            if usedTokens + tokens <= availableTokens {
                result.insert(message, at: 0)
                usedTokens += tokens
            } else {
                if result.count < messages.count {
                    let skippedCount = messages.count - result.count
                    let summary = Message(
                        content: "[System: History truncated. \(skippedCount) earlier messages hidden. " +
                            "Use `view_chat_history` tool to retrieve them.]",
                        role: .system,
                        isSummary: true
                    )
                    result.insert(summary, at: 0)
                }
                break
            }
        }
        return result
    }
}
