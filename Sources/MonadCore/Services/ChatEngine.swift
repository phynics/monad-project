import MonadShared
import Foundation
import Logging
import OpenAI
import Dependencies
import MonadPrompt

/// Unified chat engine that handles both interactive chat and autonomous agent execution.
/// Returns `AsyncThrowingStream<ChatEvent>` for all use cases — callers decide how to consume.
///
/// - Interactive chat (MonadServer): streams deltas to the client via SSE.
/// - Autonomous agents (AgentExecutor): consumes the stream internally for state tracking.
///
/// Tool resolution is the caller's responsibility. The engine accepts pre-resolved tools.
/// Session hydration is also the caller's responsibility for autonomous use cases.
public final class ChatEngine: @unchecked Sendable {
    @Dependency(\.sessionManager) private var sessionManager
    @Dependency(\.persistenceService) private var persistenceService
    @Dependency(\.llmService) private var llmService
    
    private let logger = Logger(label: "com.monad.chat-engine")
    
    public init() {}
    
    /// Execute a chat turn and return a stream of deltas.
    /// - Parameters:
    ///   - sessionId: The unique identifier for the chat session.
    ///   - message: The user's input message.
    ///   - tools: Pre-resolved tools available for this turn.
    ///   - toolOutputs: Optional list of tool outputs to be processed from a previous turn.
    ///   - contextManager: Optional context manager for RAG. If nil, no context is gathered.
    ///   - systemInstructions: Optional system instructions to override the default.
    ///   - maxTurns: Maximum number of LLM turns before stopping. Defaults to 5.
    /// - Returns: An asynchronous stream of chat events.
    public func chatStream(
        sessionId: UUID,
        message: String,
        tools: [AnyTool],
        toolOutputs: [ToolOutputSubmission]? = nil,
        contextManager: ContextManager? = nil,
        systemInstructions: String? = nil,
        maxTurns: Int = 5
    ) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        
        // Save conversation steps (user message + any tool outputs from previous turn)
        try await saveConversationSteps(sessionId: sessionId, message: message, toolOutputs: toolOutputs)
        
        // Fetch history
        let history = try await sessionManager.getHistory(for: sessionId)
        
        // Gather context (RAG)
        let contextData = await fetchContext(contextManager: contextManager, message: message, history: history)
        
        guard await llmService.isConfigured else { throw ToolError.executionFailed("LLM Service not configured") }
        
        let toolParams = tools.map { $0.toToolParam() }
        
        // Build prompt
        let session = await sessionManager.getSession(id: sessionId)
        let (initialMessages, structuredContext) = await buildPrompt(
            session: session,
            message: message,
            contextData: contextData,
            history: history,
            availableTools: tools,
            systemInstructions: systemInstructions
        )
        
        let modelName = await llmService.configuration.modelName
        
        return AsyncThrowingStream<ChatEvent, Error> { continuation in
            Task {
                await self.runChatLoop(
                    continuation: continuation,
                    sessionId: sessionId,
                    initialMessages: initialMessages,
                    toolParams: toolParams,
                    availableTools: tools,
                    contextData: contextData,
                    structuredContext: structuredContext,
                    modelName: modelName,
                    maxTurns: maxTurns
                )
            }
        }
    }

    // MARK: - Core Loop

    private enum TurnResult {
        case `continue`(newMessages: [ChatQuery.ChatCompletionMessageParam])
        case finish
    }

    private func runChatLoop(
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation,
        sessionId: UUID,
        initialMessages: [ChatQuery.ChatCompletionMessageParam],
        toolParams: [ChatQuery.ChatCompletionToolParam],
        availableTools: [AnyTool],
        contextData: ContextData,
        structuredContext: [String: String],
        modelName: String,
        maxTurns: Int
    ) async {
        var currentMessages = initialMessages
        var turnCount = 0
        
        // Emit Metadata Event
        let metadata = ChatMetadata(
            memories: contextData.memories.map { $0.memory.id },
            files: contextData.notes.map { $0.name }
        )
        continuation.yield(.generationContext(metadata))
        
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
        availableTools: [AnyTool],
        contextData: ContextData,
        structuredContext: [String: String],
        modelName: String,
        turnCount: Int,
        sessionId: UUID,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async throws -> TurnResult {
        var debugToolCalls: [ToolCallRecord] = []
        var debugToolResults: [ToolResultRecord] = []
        
        let streamData = await llmService.chatStream(
            messages: currentMessages,
            tools: toolParams.isEmpty ? nil : toolParams,
            responseFormat: nil
        )
        
        var fullResponse = ""
        var fullThinking = ""
        var toolCallAccumulators: [Int: (id: String, name: String, args: String)] = [:]
        
        let parser = StreamingParser()
        var hasEmittedThought = false
        
        // Bug 1: Track timing and token usage
        let turnStartTime = Date()
        var streamUsage: ChatResult.CompletionUsage? = nil
        
        for try await result in streamData {
            if Task.isCancelled { break }
            
            // Capture usage stats (sent in final chunk when includeUsage: true)
            if let usage = result.usage { streamUsage = usage }
            
            // Forward Content and Thinking
            if let delta = result.choices.first?.delta.content {
                let parseResult = parser.process(delta)
                
                if let thinkingChunk = parseResult.thinking, !thinkingChunk.isEmpty {
                    fullThinking += thinkingChunk
                    hasEmittedThought = true
                    continuation.yield(.thought(thinkingChunk))
                }
                
                if let contentChunk = parseResult.content, !contentChunk.isEmpty {
                    if hasEmittedThought {
                        continuation.yield(.thoughtCompleted)
                        hasEmittedThought = false
                    }
                    fullResponse += contentChunk
                    continuation.yield(.delta(contentChunk))
                }
            }
            
            // Forward separate reasoning_content if model supports it out of band
            // OpenAI type doesn't officially wrap reasoning_content locally yet unless we mapped it, 
            // but for now StreamingParser handles standard <think> tags locally.
            
            // Accumulate Tool Calls
            if let calls = result.choices.first?.delta.toolCalls {
                if hasEmittedThought {
                    continuation.yield(.thoughtCompleted)
                    hasEmittedThought = false
                }
                
                for call in calls {
                    guard let index = call.index else { continue }
                    var acc = toolCallAccumulators[index] ?? ("", "", "")
                    if let id = call.id { acc.id = id }
                    if let name = call.function?.name { acc.name += name }
                    if let args = call.function?.arguments { acc.args += args }
                    toolCallAccumulators[index] = acc
                    
                    continuation.yield(.toolCall(ToolCallDelta(
                        index: index,
                        id: call.id,
                        name: call.function?.name,
                        arguments: call.function?.arguments
                    )))
                }
            }
        }
        
        // Flush Any Pending Text
        let pending = parser.flush()
        if let thinkingChunk = pending.thinking, !thinkingChunk.isEmpty {
            fullThinking += thinkingChunk
            hasEmittedThought = true
            continuation.yield(.thought(thinkingChunk))
        }
        if hasEmittedThought {
            continuation.yield(.thoughtCompleted)
            hasEmittedThought = false
        }
        if let contentChunk = pending.content, !contentChunk.isEmpty {
            fullResponse += contentChunk
            continuation.yield(.delta(contentChunk))
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
                
                for (index, value) in finalToolCalls.sorted(by: { $0.key < $1.key }) {
                    continuation.yield(.toolCall(ToolCallDelta(index: index, id: value.id, name: value.name, arguments: value.args)))
                }
            }
        }
        
        // Bug 1: Compute timing and token metadata after the stream loop
        let turnDuration = Date().timeIntervalSince(turnStartTime)
        let completionTokens = streamUsage?.completionTokens
            ?? TokenEstimator.estimate(text: fullResponse + fullThinking)
        let tokensPerSecond: Double? = turnDuration > 0
            ? Double(completionTokens) / turnDuration : nil
        
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
                turnCount: turnCount,
                continuation: continuation
            )
            debugToolResults.append(contentsOf: newDebugRecords)
            
            if requiresClientExecution {
                let callsForDB = toolCallsParam.compactMap { param -> ToolCall? in
                    let argsData = param.function.arguments.data(using: .utf8) ?? Data()
                    let args = (try? JSONDecoder().decode([String: AnyCodable].self, from: argsData)) ?? [:]
                    return ToolCall(name: param.function.name, arguments: args)
                }
                let callsJSON = (try? SerializationUtils.jsonEncoder.encode(callsForDB)).flatMap { String(decoding: $0, as: UTF8.self) } ?? "[]"
                
                let assistantMsg = ConversationMessage(sessionId: sessionId, role: .assistant, content: fullResponse, think: fullThinking.isEmpty ? nil : fullThinking, toolCalls: callsJSON)
                try? await persistenceService.saveMessage(assistantMsg)
                
                let snapshot = DebugSnapshot(structuredContext: structuredContext, toolCalls: debugToolCalls, toolResults: debugToolResults, model: modelName, turnCount: turnCount)
                await sessionManager.setDebugSnapshot(snapshot, for: sessionId)
                
                let snapshotData = try? SerializationUtils.jsonEncoder.encode(snapshot)
                continuation.yield(.generationCompleted(
                    message: assistantMsg.toMessage(),
                    metadata: APIResponseMetadata(
                        model: modelName,
                        promptTokens: streamUsage?.promptTokens,
                        completionTokens: streamUsage?.completionTokens,
                        totalTokens: streamUsage?.totalTokens,
                        duration: turnDuration,
                        tokensPerSecond: tokensPerSecond,
                        debugSnapshotData: snapshotData
                    )
                ))
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
                recalledMemories: String(decoding: (try? SerializationUtils.jsonEncoder.encode(contextData.memories.map { $0.memory })) ?? Data(), as: UTF8.self),
                think: fullThinking.isEmpty ? nil : fullThinking
            )
            try? await persistenceService.saveMessage(assistantMsg)
            
            let snapshot = DebugSnapshot(structuredContext: structuredContext, toolCalls: debugToolCalls, toolResults: debugToolResults, model: modelName, turnCount: turnCount)
            await sessionManager.setDebugSnapshot(snapshot, for: sessionId)
            
            let snapshotData = try? SerializationUtils.jsonEncoder.encode(snapshot)
            continuation.yield(.generationCompleted(
                message: assistantMsg.toMessage(),
                metadata: APIResponseMetadata(
                    model: modelName,
                    promptTokens: streamUsage?.promptTokens,
                    completionTokens: streamUsage?.completionTokens,
                    totalTokens: streamUsage?.totalTokens,
                    duration: turnDuration,
                    tokensPerSecond: tokensPerSecond,
                    debugSnapshotData: snapshotData
                )
            ))
            return .finish
        }
    }

    // MARK: - Helper Methods

    private func saveConversationSteps(
        sessionId: UUID,
        message: String,
        toolOutputs: [ToolOutputSubmission]?
    ) async throws {
        if let toolOutputs = toolOutputs {
            for output in toolOutputs {
                let msg = ConversationMessage(
                    sessionId: sessionId,
                    role: .tool,
                    content: output.output,
                    toolCallId: output.toolCallId
                )
                try await persistenceService.saveMessage(msg)
            }
        }
        
        if !message.isEmpty {
            let userMsg = ConversationMessage(sessionId: sessionId, role: .user, content: message)
            try await persistenceService.saveMessage(userMsg)
        } else if toolOutputs?.isEmpty ?? true {
            throw ToolError.invalidArgument("Message and tool outputs cannot both be empty")
        }
    }

    private func fetchContext(
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
                if case .complete(let data) = event {
                    return data
                }
            }
        } catch {
            logger.warning("Failed to gather context: \(error)")
        }
        return ContextData()
    }

    private func buildPrompt(
        session: ConversationSession?,
        message: String,
        contextData: ContextData,
        history: [Message],
        availableTools: [AnyTool],
        systemInstructions: String?
    ) async -> (messages: [ChatQuery.ChatCompletionMessageParam], structuredContext: [String: String]) {
        let prompt = await llmService.buildContext(
            userQuery: message,
            contextNotes: contextData.notes,
            memories: contextData.memories.map { $0.memory },
            chatHistory: history,
            tools: availableTools,
            systemInstructions: systemInstructions
        )
        
        // Convert to OpenAI format
        let messages = await prompt.toMessages()
        let structuredContext = await prompt.structuredContext()
        
        return (messages, structuredContext)
    }

    private func executeTools(
        calls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam],
        availableTools: [AnyTool],
        turnCount: Int,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async -> (results: [ChatQuery.ChatCompletionMessageParam], requiresClientExecution: Bool, debugRecords: [ToolResultRecord]) {
        var executionResults: [ChatQuery.ChatCompletionMessageParam] = []
        var requiresClientExecution = false
        var debugRecords: [ToolResultRecord] = []
        
        for call in calls {
            guard let tool = availableTools.first(where: { $0.name == call.function.name }) else {
                executionResults.append(.tool(.init(content: .textContent(.init("Error: Tool not found")), toolCallId: call.id)))
                continuation.yield(.toolExecution(toolCallId: call.id, status: .failure(ToolError.executionFailed("Tool not found: \(call.function.name)"))))
                continue
            }
            
            // Bug 2: Emit attempting event so the CLI can show tool progress
            let toolRef = tool.toolReference
            continuation.yield(.toolExecution(toolCallId: call.id, status: .attempting(name: tool.name, reference: toolRef)))
            
            let argsData = call.function.arguments.data(using: .utf8) ?? Data()
            let argsDict = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]

            do {
                let result = try await tool.execute(parameters: argsDict)
                debugRecords.append(ToolResultRecord(toolCallId: call.id, name: call.function.name, output: result.output, turn: turnCount))
                continuation.yield(.toolExecution(toolCallId: call.id, status: .success(result)))
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
