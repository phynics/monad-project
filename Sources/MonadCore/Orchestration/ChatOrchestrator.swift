import Foundation
import Logging
import OpenAI
import Dependencies

/// Orchestrates a single chat conversation turn, including context gathering, tool use, and streaming.
public final class ChatOrchestrator: @unchecked Sendable {
    @Dependency(\.sessionManager) private var sessionManager
    @Dependency(\.persistenceService) private var persistenceService
    @Dependency(\.llmService) private var llmService
    @Dependency(\.agentRegistry) private var agentRegistry
    @Dependency(\.toolRouter) private var toolRouter
    
    private let logger = Logger(label: "com.monad.core.chat-orchestrator")
    
    public init() {}
    
    /// Execute a chat request and return a stream of deltas.
    /// - Parameters:
    ///   - sessionId: The unique identifier for the chat session.
    ///   - message: The user's input message.
    ///   - clientId: Optional client identifier for scoping tools and context.
    ///   - toolOutputs: Optional list of tool outputs to be processed from a previous turn.
    /// - Returns: An asynchronous stream of chat deltas.
    public func chatStream(
        sessionId: UUID,
        message: String,
        clientId: UUID? = nil,
        toolOutputs: [ToolOutputSubmission]? = nil
    ) async throws -> AsyncThrowingStream<ChatDelta, Error> {
        
        // 3. Ensure Session is Hydrated
        try await sessionManager.hydrateSession(id: sessionId)
        
        guard let session = await sessionManager.getSession(id: sessionId) else {
            throw ToolError.toolNotFound("Session \(sessionId)")
        }

        // 4. Save Conversation Steps
        try await saveConversationSteps(sessionId: sessionId, message: message, toolOutputs: toolOutputs, persistence: persistenceService)
        
        // 4. Fetch History & Context
        let history = try await sessionManager.getHistory(for: sessionId)
        
        // 5. Fetch History & Context
        let contextData = await fetchContext(sessionId: sessionId, message: message, history: history)
        
        guard await llmService.isConfigured else { throw ToolError.executionFailed("LLM Service not configured") }
        
        // 5. Resolve Tools
        let availableTools = await resolveTools(sessionId: sessionId, clientId: clientId)
        
        let toolParams = availableTools.map { $0.toToolParam() }
        
        // 6. Build Prompt
        let (initialMessages, structuredContext) = await buildPrompt(
            session: session,
            message: message,
            contextData: contextData,
            history: history,
            availableTools: availableTools
        )
        
        let modelName = await llmService.configuration.modelName
        
        return AsyncThrowingStream<ChatDelta, Error> { continuation in
            Task {
                await self.runChatLoop(
                    continuation: continuation,
                    sessionId: sessionId,
                    initialMessages: initialMessages,
                    toolParams: toolParams,
                    availableTools: availableTools,
                    contextData: contextData,
                    structuredContext: structuredContext,
                    modelName: modelName
                )
            }
        }
    }

    private enum TurnResult {
        case `continue`(newMessages: [ChatQuery.ChatCompletionMessageParam])
        case finish
    }

    private func runChatLoop(
        continuation: AsyncThrowingStream<ChatDelta, Error>.Continuation,
        sessionId: UUID,
        initialMessages: [ChatQuery.ChatCompletionMessageParam],
        toolParams: [ChatQuery.ChatCompletionToolParam],
        availableTools: [any MonadCore.Tool],
        contextData: ContextData,
        structuredContext: [String: String],
        modelName: String
    ) async {
        var currentMessages = initialMessages
        var turnCount = 0
        let maxTurns = 5
        
        // A. Emit Metadata Event
        let metadata = ChatMetadata(
            memories: contextData.memories.map { $0.memory.id },
            files: contextData.notes.map { $0.name }
        )
        continuation.yield(ChatDelta(metadata: metadata))
        
        while turnCount < maxTurns {
            turnCount += 1
            
            if Task.isCancelled { break }
            
            do {
                let result = try await processTurn(
                    currentMessages: currentMessages,
                    toolParams: toolParams,
                    availableTools: availableTools,
                    contextData: contextData,
                    structuredContext: structuredContext,
                    modelName: modelName,
                    turnCount: turnCount,
                    sessionId: sessionId,
                    continuation: continuation
                )
                
                switch result {
                case .continue(let newMessages):
                    currentMessages.append(contentsOf: newMessages)
                case .finish:
                    continuation.finish()
                    return
                }
            } catch {
                logger.error("Error in chat loop turn \(turnCount): \(error)")
                continuation.finish(throwing: error)
                return
            }
        }
        continuation.finish()
    }
    
    private func processTurn(
        currentMessages: [ChatQuery.ChatCompletionMessageParam],
        toolParams: [ChatQuery.ChatCompletionToolParam],
        availableTools: [any MonadCore.Tool],
        contextData: ContextData,
        structuredContext: [String: String],
        modelName: String,
        turnCount: Int,
        sessionId: UUID,
        continuation: AsyncThrowingStream<ChatDelta, Error>.Continuation
    ) async throws -> TurnResult {
        var debugToolCalls: [ToolCallRecord] = []
        var debugToolResults: [ToolResultRecord] = []
        
        let streamData = await llmService.chatStream(
            messages: currentMessages,
            tools: toolParams.isEmpty ? nil : toolParams,
            responseFormat: nil
        )
        
        var fullResponse = ""
        var toolCallAccumulators: [Int: (id: String, name: String, args: String)] = [:]
        
        for try await result in streamData {
            if Task.isCancelled { break }
            
            // Forward Content
            if let delta = result.choices.first?.delta.content {
                fullResponse += delta
                continuation.yield(ChatDelta(content: delta))
            }
            
            // Accumulate Tool Calls
            if let calls = result.choices.first?.delta.toolCalls {
                var toolDeltas: [ToolCallDelta] = []
                for call in calls {
                    guard let index = call.index else { continue }
                    var acc = toolCallAccumulators[index] ?? ("", "", "")
                    if let id = call.id { acc.id = id }
                    if let name = call.function?.name { acc.name += name }
                    if let args = call.function?.arguments { acc.args += args }
                    toolCallAccumulators[index] = acc
                    
                    toolDeltas.append(ToolCallDelta(
                        index: index,
                        id: call.id,
                        name: call.function?.name,
                        arguments: call.function?.arguments
                    ))
                }
                
                if !toolDeltas.isEmpty {
                    continuation.yield(ChatDelta(toolCalls: toolDeltas))
                }
            }
        }
        
        if Task.isCancelled { return .finish }
        
        var finalToolCalls = toolCallAccumulators
        
        // Parse fallback calls if needed
        if finalToolCalls.isEmpty {
            let fallbackCalls = ToolOutputParser.parse(from: fullResponse)
            if !fallbackCalls.isEmpty {
                for (index, call) in fallbackCalls.enumerated() {
                    let argsJson = (try? SerializationUtils.jsonEncoder.encode(call.arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    finalToolCalls[index] = (id: UUID().uuidString, name: call.name, args: argsJson)
                }
                
                let toolDeltas = finalToolCalls.sorted(by: { $0.key < $1.key }).map { index, value in
                    ToolCallDelta(index: index, id: value.id, name: value.name, arguments: value.args)
                }
                continuation.yield(ChatDelta(toolCalls: toolDeltas))
            }
        }
        
        if !finalToolCalls.isEmpty {
            let sortedCalls = finalToolCalls.sorted(by: { $0.key < $1.key })
            let toolCallsParam: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam] = sortedCalls.map { _, value in
                .init(id: value.id, function: .init(arguments: value.args, name: value.name))
            }
            
            for (_, value) in sortedCalls {
                debugToolCalls.append(ToolCallRecord(name: value.name, arguments: value.args, turn: turnCount))
            }
            
            let assistantMessage = ChatQuery.ChatCompletionMessageParam.assistant(.init(content: .textContent(.init(fullResponse)), toolCalls: toolCallsParam))
            
            let (executionResults, requiresClientExecution, newDebugRecords) = await executeTools(
                calls: toolCallsParam,
                availableTools: availableTools,
                turnCount: turnCount
            )
            debugToolResults.append(contentsOf: newDebugRecords)
            
            if requiresClientExecution {
                let callsForDB = toolCallsParam.compactMap { param -> ToolCall? in
                    let argsData = param.function.arguments.data(using: .utf8) ?? Data()
                    let args = (try? JSONDecoder().decode([String: AnyCodable].self, from: argsData)) ?? [:]
                    return ToolCall(name: param.function.name, arguments: args)
                }
                let callsJSON = (try? SerializationUtils.jsonEncoder.encode(callsForDB)).flatMap { String(decoding: $0, as: UTF8.self) } ?? "[]"
                
                let assistantMsg = ConversationMessage(sessionId: sessionId, role: .assistant, content: fullResponse, toolCalls: callsJSON)
                try? await persistenceService.saveMessage(assistantMsg)
                
                let snapshot = DebugSnapshot(structuredContext: structuredContext, toolCalls: debugToolCalls, toolResults: debugToolResults, model: modelName, turnCount: turnCount)
                await sessionManager.setDebugSnapshot(snapshot, for: sessionId)
                
                continuation.yield(ChatDelta(isDone: true))
                return .finish
            }
            
            var newMessages: [ChatQuery.ChatCompletionMessageParam] = [assistantMessage]
            newMessages.append(contentsOf: executionResults)
            return .continue(newMessages: newMessages)
            
        } else {
            let assistantMsg = ConversationMessage(
                sessionId: sessionId,
                role: .assistant,
                content: fullResponse,
                recalledMemories: String(decoding: (try? SerializationUtils.jsonEncoder.encode(contextData.memories.map { $0.memory })) ?? Data(), as: UTF8.self)
            )
            try? await persistenceService.saveMessage(assistantMsg)
            
            let snapshot = DebugSnapshot(structuredContext: structuredContext, toolCalls: debugToolCalls, toolResults: debugToolResults, model: modelName, turnCount: turnCount)
            await sessionManager.setDebugSnapshot(snapshot, for: sessionId)
            
            continuation.yield(ChatDelta(isDone: true))
            return .finish
        }
    }
    
    /// Executes the provided tool calls by matching them against available tools.
    /// - Parameters:
    ///   - calls: The collection of tool calls to process.
    ///   - availableTools: The list of registered tools.
    ///   - turnCount: The current turn count for logging.
    // MARK: - Helper Methods

    private func saveConversationSteps(
        sessionId: UUID,
        message: String,
        toolOutputs: [ToolOutputSubmission]?,
        persistence: any PersistenceServiceProtocol
    ) async throws {
        if let toolOutputs = toolOutputs {
            for output in toolOutputs {
                let msg = ConversationMessage(
                    sessionId: sessionId,
                    role: .tool,
                    content: output.output,
                    toolCallId: output.toolCallId
                )
                try await persistence.saveMessage(msg)
            }
        }
        
        if !message.isEmpty {
            let userMsg = ConversationMessage(
                sessionId: sessionId, role: .user, content: message)
            try await persistence.saveMessage(userMsg)
        } else if toolOutputs?.isEmpty ?? true {
            throw ToolError.invalidArgument("Message and tool outputs cannot both be empty")
        }
    }

    private func fetchContext(
        sessionId: UUID,
        message: String,
        history: [Message]
    ) async -> ContextData {
        guard let contextManager = await sessionManager.getContextManager(for: sessionId) else { return ContextData() }
        
        do {
            let stream = await contextManager.gatherContext(
                for: message.isEmpty ? (history.last?.content ?? "") : message,
                history: history,
                tagGenerator: { [llmService] query in try await llmService.generateTags(for: query) }
            )
            
            for try await event in stream {
                if case .complete(let data) = event {
                    return data
                }
            }
        } catch {
            logger.warning("Failed to gather context: \(error)")
        }
        return ContextData()
    }

    private func resolveTools(sessionId: UUID, clientId: UUID?) async -> [any MonadCore.Tool] {
        var availableTools: [any MonadCore.Tool] = []
        do {
            let references = try await sessionManager.getAllToolReferences(sessionId: sessionId, clientId: clientId)
            
            availableTools = references.compactMap { (ref: ToolReference) -> (any MonadCore.Tool)? in
                var def: WorkspaceToolDefinition?
                switch ref {
                case .known(let id): def = SystemToolRegistry.shared.getDefinition(for: id)
                case .custom(let definition): def = definition
                }
                guard let d = def else { return nil }
                return DelegatingTool(
                    ref: ref,
                    router: toolRouter,
                    sessionId: sessionId,
                    resolvedDefinition: d
                )
            }
        } catch {
            logger.warning("Failed to fetch tools: \(error)")
        }
        return availableTools
    }

    private func buildPrompt(
        session: ConversationSession,
        message: String,
        contextData: ContextData,
        history: [Message],
        availableTools: [any MonadCore.Tool]
    ) async -> (messages: [ChatQuery.ChatCompletionMessageParam], structuredContext: [String: String]) {
        let systemInstructions: String? = nil
        
        let (initialMessages, _, structuredContext) = await llmService.buildPrompt(
            userQuery: message,
            contextNotes: contextData.notes,
            memories: contextData.memories.map { $0.memory },
            chatHistory: history,
            tools: availableTools,
            systemInstructions: systemInstructions
        )
        return (initialMessages, structuredContext)
    }

    private func executeTools(
        calls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam],
        availableTools: [any MonadCore.Tool],
        turnCount: Int
    ) async -> (results: [ChatQuery.ChatCompletionMessageParam], requiresClientExecution: Bool, debugRecords: [ToolResultRecord]) {
        var executionResults: [ChatQuery.ChatCompletionMessageParam] = []
        var requiresClientExecution = false
        var debugRecords: [ToolResultRecord] = []
        
        for call in calls {
            guard let tool = availableTools.first(where: { $0.name == call.function.name }) else {
                executionResults.append(.tool(.init(content: .textContent(.init("Error: Tool not found")), toolCallId: call.id)))
                continue
            }
            
            let argsData = call.function.arguments.data(using: .utf8) ?? Data()
            let argsDict = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
            
            do {
                let result = try await tool.execute(parameters: argsDict)
                debugRecords.append(ToolResultRecord(toolCallId: call.id, name: call.function.name, output: result.output, turn: turnCount))
                executionResults.append(.tool(.init(content: .textContent(.init(result.output)), toolCallId: call.id)))
            } catch let error as ToolError {
                if case .clientExecutionRequired = error {
                    requiresClientExecution = true
                    break
                }
                executionResults.append(.tool(.init(content: .textContent(.init("Error: \(error.localizedDescription)")), toolCallId: call.id)))
            } catch {
                executionResults.append(.tool(.init(content: .textContent(.init("Error: \(error.localizedDescription)")), toolCallId: call.id)))
            }
        }
        return (executionResults, requiresClientExecution, debugRecords)
    }
}
