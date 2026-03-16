import Foundation
import MonadPrompt
import MonadShared

/// Pure, stateless prompt assembly — no actor isolation or LLM client required.
public enum PromptBuilder {
    // MARK: - Constants

    public static let maxHistoryTokens = 120_000
    public static let historyTokenBuffer = 4000

    // MARK: - Build Context

    /// Assembles a `Prompt` from a request, optional agent/timeline context, and extension sections.
    public static func buildContext(
        _ request: LLMPromptRequest,
        agentInstance: AgentInstance? = nil,
        timeline: Timeline? = nil,
        extensionSections: [any ContextSection] = []
    ) -> Prompt {
        let instructions = request.systemInstructions ?? DefaultInstructions.system()

        var sections: [any ContextSection] = []

        sections.append(SystemInstructions(instructions))

        if let agent = agentInstance {
            sections.append(AgentContext(agent, timelineTitle: timeline?.title))
        }

        sections.append(ContextNotes(request.contextNotes))
        sections.append(Memories(request.memories))
        sections.append(Tools(request.tools))
        sections.append(WorkspacesContext(
            workspaces: request.workspaces,
            primaryWorkspace: request.primaryWorkspace,
            clientName: request.clientName
        ))

        if let timeline {
            sections.append(TimelineContext(timeline))
        }

        sections.append(ChatHistory(
            optimizeHistory(
                request.chatHistory,
                availableTokens: maxHistoryTokens - historyTokenBuffer
            )
        ))
        sections.append(UserQuery(request.userQuery))
        sections += extensionSections

        return Prompt(sections: sections)
    }

    /// Builds a prompt and converts it to OpenAI message format + raw text.
    public static func buildPrompt(_ request: LLMPromptRequest) async -> LLMPromptResult {
        let prompt = buildContext(request)
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
