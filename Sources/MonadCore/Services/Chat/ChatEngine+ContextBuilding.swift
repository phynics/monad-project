import Foundation
import Logging
import MonadShared
import OpenAI

extension ChatEngine {
    func saveConversationSteps(
        timelineId: UUID,
        message: String,
        toolOutputs: [ToolOutputSubmission]?
    ) async throws {
        if let toolOutputs = toolOutputs {
            for output in toolOutputs {
                let msg = ConversationMessage(
                    timelineId: timelineId,
                    role: .tool,
                    content: output.output,
                    toolCallId: output.toolCallId
                )
                try await persistenceService.saveMessage(msg)
            }
        }

        if !message.isEmpty {
            let userMsg = ConversationMessage(timelineId: timelineId, role: .user, content: message)
            try await persistenceService.saveMessage(userMsg)
        } else if toolOutputs?.isEmpty ?? true {
            throw ToolError.invalidArgument("input", expected: "message or toolOutputs", got: "empty")
        }
    }

    func fetchContext(
        contextManager: ContextManager?,
        message: String,
        history: [Message]
    ) async -> ContextData {
        guard let contextManager = contextManager else { return ContextData() }

        do {
            let stream = await contextManager.gatherContext(
                for: message.isEmpty ? (history.last?.content ?? "") : message,
                history: history,
                tagGenerator: { [llmService] query in try await llmService.generateTags(for: query) }
            )

            for try await event in stream {
                if case let .complete(data) = event {
                    return data
                }
            }
        } catch {
            logger.warning("Failed to gather context: \(error)")
        }
        return ContextData()
    }

    func buildPrompt(
        timeline: Timeline?,
        agentInstance: AgentInstance?,
        message: String,
        contextData: ContextData,
        history: [Message],
        availableTools: [AnyTool],
        workspaces: [WorkspaceReference],
        primaryWorkspace: WorkspaceReference?,
        clientName: String?,
        connectedClients: Set<UUID>,
        systemInstructions: String?
    ) async -> (messages: [ChatQuery.ChatCompletionMessageParam], structuredContext: [String: String]) {
        let prompt = await llmService.buildContext(
            userQuery: message,
            contextNotes: contextData.notes,
            memories: contextData.memories.map { $0.memory },
            chatHistory: history,
            tools: availableTools,
            workspaces: workspaces,
            primaryWorkspace: primaryWorkspace,
            clientName: clientName,
            connectedClients: connectedClients,
            systemInstructions: systemInstructions,
            agentInstance: agentInstance,
            timeline: timeline
        )

        // Convert to OpenAI format
        let messages = await prompt.toMessages()
        let structuredContext = await prompt.structuredContext()

        return (messages, structuredContext)
    }
}
