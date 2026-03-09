import ErrorKit
import Foundation
import Logging
import MonadShared
import OpenAI

/// Errors thrown by `ChatEngine` during setup and execution.
public enum ChatEngineError: Throwable {
    case llmServiceNotConfigured
    case missingInput

    public var userFriendlyMessage: String {
        switch self {
        case .llmServiceNotConfigured:
            return "The LLM service is not configured. Please set up your API endpoint and key."
        case .missingInput:
            return "A message or tool outputs must be provided to start a chat turn."
        }
    }
}

/// Input for `buildTurnInitialState`, grouping the per-turn setup parameters.
struct TurnInitInput {
    let timelineId: UUID
    let message: String
    let tools: [AnyTool]
    let contextData: ContextData
    let history: [Message]
    let agentInstanceId: UUID?
    let systemInstructions: String?
}

/// Input parameters for building the LLM prompt in a chat turn.
struct BuildPromptParams {
    let timeline: Timeline?
    let agentInstance: AgentInstance?
    let message: String
    let contextData: ContextData
    let history: [Message]
    let availableTools: [AnyTool]
    let workspaces: [WorkspaceReference]
    let primaryWorkspace: WorkspaceReference?
    let clientName: String?
    let connectedClients: Set<UUID>
    let systemInstructions: String?
}

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
                try await messageStore.saveMessage(msg)
            }
        }

        if !message.isEmpty {
            let userMsg = ConversationMessage(timelineId: timelineId, role: .user, content: message)
            try await messageStore.saveMessage(userMsg)
        } else if toolOutputs?.isEmpty ?? true {
            throw ChatEngineError.missingInput
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

    func buildTurnInitialState(
        input: TurnInitInput
    ) async throws -> (messages: [ChatQuery.ChatCompletionMessageParam], structuredContext: [String: String]) {
        let timeline = await timelineManager.getTimeline(id: input.timelineId)
        let workspaces = await timelineManager.getWorkspaces(for: input.timelineId)
        let attachedWorkspaces = workspaces?.attached ?? []

        let agentInstance: AgentInstance? = input.agentInstanceId != nil
            ? try? await agentInstanceStore.fetchAgentInstance(id: input.agentInstanceId!)
            : nil

        var clientName: String?
        if let ownerId = workspaces?.primary?.ownerId,
           let client = try? await clientStore.fetchClient(id: ownerId)
        {
            clientName = client.displayName
        }

        let params = BuildPromptParams(
            timeline: timeline,
            agentInstance: agentInstance,
            message: input.message,
            contextData: input.contextData,
            history: input.history,
            availableTools: input.tools,
            workspaces: attachedWorkspaces,
            primaryWorkspace: workspaces?.primary,
            clientName: clientName,
            connectedClients: Set<UUID>(),
            systemInstructions: input.systemInstructions
        )
        return await buildPrompt(params)
    }

    func buildPrompt(
        _ params: BuildPromptParams
    ) async -> (messages: [ChatQuery.ChatCompletionMessageParam], structuredContext: [String: String]) {
        let prompt = await llmService.buildContext(
            userQuery: params.message,
            contextNotes: params.contextData.notes,
            memories: params.contextData.memories.map { $0.memory },
            chatHistory: params.history,
            tools: params.availableTools,
            workspaces: params.workspaces,
            primaryWorkspace: params.primaryWorkspace,
            clientName: params.clientName,
            connectedClients: params.connectedClients,
            systemInstructions: params.systemInstructions,
            agentInstance: params.agentInstance,
            timeline: params.timeline
        )

        let messages = await prompt.toMessages()
        let structuredContext = await prompt.structuredContext()

        return (messages, structuredContext)
    }
}
