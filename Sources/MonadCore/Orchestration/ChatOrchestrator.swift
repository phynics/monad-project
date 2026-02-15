import Foundation
import Logging
import OpenAI

/// Orchestrates a single chat conversation turn, including context gathering, tool use, and streaming.
public final class ChatOrchestrator: Sendable {
    private let sessionManager: SessionManager
    private let llmService: any LLMServiceProtocol
    private let agentRegistry: AgentRegistry
    private let toolRouter: ToolRouter
    private let logger = Logger(label: "com.monad.core.chat-orchestrator")
    
    public init(
        sessionManager: SessionManager,
        llmService: any LLMServiceProtocol,
        agentRegistry: AgentRegistry,
        toolRouter: ToolRouter
    ) {
        self.sessionManager = sessionManager
        self.llmService = llmService
        self.agentRegistry = agentRegistry
        self.toolRouter = toolRouter
    }
    
    /// Execute a chat request and return a stream of deltas.
    public func chatStream(
        sessionId: UUID,
        message: String,
        clientId: UUID? = nil,
        toolOutputs: [ToolOutputSubmission]? = nil,
        verbose: Bool = false
    ) async throws -> AsyncThrowingStream<ChatDelta, Error> {
        
        // 1. Ensure Session is Hydrated
        try await sessionManager.hydrateSession(id: sessionId)
        
        guard let session = await sessionManager.getSession(id: sessionId) else {
            throw ToolError.toolNotFound("Session \(sessionId)") // Or SessionError
        }
        
        let persistence = await sessionManager.getPersistenceService()
        let contextManager = await sessionManager.getContextManager(for: sessionId)
        
        // 2. Save Tool Outputs
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
        
        // 3. Save User Message
        if !message.isEmpty {
            let userMsg = ConversationMessage(
                sessionId: sessionId, role: .user, content: message)
            try await persistence.saveMessage(userMsg)
        } else if toolOutputs?.isEmpty ?? true {
            throw ToolError.invalidArgument("Message and tool outputs cannot both be empty")
        }
        
        // 4. Fetch History & Context
        let history = try await sessionManager.getHistory(for: sessionId)
        
        var contextData = ContextData()
        if let contextManager = contextManager {
            do {
                let stream = await contextManager.gatherContext(
                    for: message.isEmpty ? (history.last?.content ?? "") : message,
                    history: history,
                    tagGenerator: { [llmService] query in try await llmService.generateTags(for: query) }
                )
                
                for try await event in stream {
                    if case .complete(let data) = event {
                        contextData = data
                    }
                }
            } catch {
                logger.warning("Failed to gather context: \(error)")
            }
        }
        
        guard await llmService.isConfigured else { throw ToolError.executionFailed("LLM Service not configured") }
        
        // 5. Resolve Tools
        var availableTools: [any MonadCore.Tool] = []
        do {
            var references = try await sessionManager.getAggregatedTools(for: sessionId)
            
            if let clientId = clientId {
                let clientTools = try await sessionManager.getClientTools(clientId: clientId)
                references.append(contentsOf: clientTools)
            }
            
            // Deduplicate by ID
            var seenIds = Set<String>()
            references = references.filter { ref in
                if seenIds.contains(ref.toolId) { return false }
                seenIds.insert(ref.toolId)
                return true
            }
            
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
        
        let toolParams = availableTools.map { $0.toToolParam() }
        
        // 6. Load Persona
        var systemInstructions: String? = nil
        if let personaFilename = session.persona, let workingDirectory = session.workingDirectory {
            let personaPath = URL(fileURLWithPath: workingDirectory).appendingPathComponent("Personas").appendingPathComponent(personaFilename)
            if let content = try? String(contentsOf: personaPath, encoding: .utf8) {
                systemInstructions = content
            }
        }
        
        // 7. Build Initial Prompt
        let (initialMessages, _, structuredContext) = await llmService.buildPrompt(
            userQuery: message,
            contextNotes: contextData.notes,
            memories: contextData.memories.map { $0.memory },
            chatHistory: history,
            tools: availableTools,
            systemInstructions: systemInstructions
        )
        
        let modelName = await llmService.configuration.modelName
        
        return AsyncThrowingStream<ChatDelta, Error> { continuation in
            Task { [llmService, sessionManager, persistence, sessionId, availableTools, initialMessages, toolParams, contextData, structuredContext, modelName] in
                var currentMessages = initialMessages
                var turnCount = 0
                let maxTurns = 5
                
                var debugToolCalls: [ToolCallRecord] = []
                var debugToolResults: [ToolResultRecord] = []
                
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
                        
                        if Task.isCancelled { break }
                        
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
                            
                            currentMessages.append(.assistant(.init(content: .textContent(.init(fullResponse)), toolCalls: toolCallsParam)))
                            
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
                                try? await persistence.saveMessage(assistantMsg)
                                
                                let snapshot = DebugSnapshot(structuredContext: structuredContext, toolCalls: debugToolCalls, toolResults: debugToolResults, model: modelName, turnCount: turnCount)
                                await sessionManager.setDebugSnapshot(snapshot, for: sessionId)
                                
                                continuation.yield(ChatDelta(isDone: true))
                                continuation.finish()
                                return
                            }
                            
                            currentMessages.append(contentsOf: executionResults)
                            continue
                        } else {
                            let assistantMsg = ConversationMessage(
                                sessionId: sessionId,
                                role: .assistant,
                                content: fullResponse,
                                recalledMemories: String(decoding: (try? SerializationUtils.jsonEncoder.encode(contextData.memories.map { $0.memory })) ?? Data(), as: UTF8.self)
                            )
                            try? await persistence.saveMessage(assistantMsg)
                            
                            let snapshot = DebugSnapshot(structuredContext: structuredContext, toolCalls: debugToolCalls, toolResults: debugToolResults, model: modelName, turnCount: turnCount)
                            await sessionManager.setDebugSnapshot(snapshot, for: sessionId)
                            
                            continuation.yield(ChatDelta(isDone: true))
                            continuation.finish()
                            return
                        }
                        
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
        }
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
