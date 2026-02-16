import MonadShared
import Foundation
import Logging
import OpenAI
import Dependencies

/// An engine that implements autonomous reasoning loops (e.g. ReAct)
public final class ReasoningEngine: @unchecked Sendable {
    @Dependency(\.llmService) private var defaultLLMService
    @Dependency(\.persistenceService) private var defaultPersistenceService
    
    private let explicitLLMService: (any LLMServiceProtocol)?
    private let explicitPersistenceService: (any PersistenceServiceProtocol)?

    public var llmService: any LLMServiceProtocol { explicitLLMService ?? defaultLLMService }
    public var persistenceService: any PersistenceServiceProtocol { explicitPersistenceService ?? defaultPersistenceService }
    
    private let logger = Logger(label: "com.monad.reasoning-engine")

    public init(
        llmService: (any LLMServiceProtocol)? = nil,
        persistenceService: (any PersistenceServiceProtocol)? = nil
    ) {
        self.explicitLLMService = llmService
        self.explicitPersistenceService = persistenceService
    }

    /// Result of an autonomous execution turn
    public enum StepResult {
        case continueLoop
        case complete(String)
        case needInformation(String)
        case error(String)
    }

    /// Run an autonomous loop to complete a job
    public func runLoop(
        job: Job,
        session: ConversationSession,
        toolExecutor: ToolExecutor,
        contextManager: ContextManager?,
        systemInstructions: String,
        maxTurns: Int = 10
    ) async throws -> StepResult {
        var turnCount = 0

        while turnCount < maxTurns {
            // Check for cancellation
            if Task.isCancelled {
                return .error("Cancelled")
            }

            turnCount += 1
            
            // 1. Fetch History
            let latestHistory = (try? await persistenceService.fetchMessages(for: session.id))?.map { $0.toMessage() } ?? []
            
            // 2. Resolve Tools
            let availableTools = await toolExecutor.getAvailableTools()
            
            // 3. Gather Context (RAG)
            var contextNotes: [ContextFile] = []
            var contextMemories: [Memory] = []

            if let contextManager = contextManager {
                let query = latestHistory.last(where: { $0.role == .user })?.content ?? job.description ?? job.title
                do {
                    let stream = await contextManager.gatherContext(for: query, history: latestHistory, limit: 5)
                    for try await event in stream {
                        if case .complete(let data) = event {
                            contextNotes = data.notes
                            contextMemories = data.memories.map { $0.memory }
                        }
                    }
                } catch {
                    logger.warning("Failed to gather context: \(error)")
                }
            }

            // 4. Build Prompt
            let (messages, _, _) = await llmService.buildPrompt(
                userQuery: "Continue execution",
                contextNotes: contextNotes,
                memories: contextMemories,
                chatHistory: latestHistory, 
                tools: availableTools,
                systemInstructions: systemInstructions
            )
            
            // 5. LLM Turn
            var assistantContent = ""
            var toolCallAccumulators: [Int: (id: String, name: String, args: String)] = [:]
            
            do {
                let stream = await llmService.chatStream(
                  messages: messages,
                  tools: availableTools.map { $0.toToolParam() },
                  responseFormat: nil
                )
                
                for try await result in stream {
                    if Task.isCancelled { throw CancellationError() }

                    if let content = result.choices.first?.delta.content {
                        assistantContent += content
                    }
                    
                    if let calls = result.choices.first?.delta.toolCalls {
                        for call in calls {
                            guard let index = call.index else { continue }
                            var acc = toolCallAccumulators[index] ?? ("", "", "")
                            if let id = call.id { acc.id = id }
                            if let name = call.function?.name { acc.name += name }
                            if let args = call.function?.arguments { acc.args += args }
                            toolCallAccumulators[index] = acc
                        }
                    }
                }
                
                // 6. Process Assistant Message & Tools
                var toolCalls: [MonadCore.ToolCall] = []
                if !toolCallAccumulators.isEmpty {
                    toolCalls = toolCallAccumulators.sorted(by: { $0.key < $1.key }).compactMap { _, value in
                        guard !value.name.isEmpty else { return nil }
                        let argsData = value.args.data(using: .utf8) ?? Data()
                        let args = (try? JSONDecoder().decode([String: AnyCodable].self, from: argsData)) ?? [:]
                        return MonadCore.ToolCall(name: value.name, arguments: args)
                    }
                } else {
                    let fallbackCalls = ToolOutputParser.parse(from: assistantContent)
                    toolCalls = fallbackCalls.compactMap { MonadCore.ToolCall(name: $0.name, arguments: $0.arguments) }
                }
                
                let toolCallsJSON = (try? SerializationUtils.jsonEncoder.encode(toolCalls)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                let assistantMsg = ConversationMessage(
                    sessionId: session.id, role: .assistant, content: assistantContent, timestamp: Date(), toolCalls: toolCallsJSON
                )
                try await persistenceService.saveMessage(assistantMsg)
                
                if !toolCalls.isEmpty {
                    for toolCall in toolCalls {
                        if Task.isCancelled { throw CancellationError() }

                        let result: String
                        if let tool = availableTools.first(where: { $0.name == toolCall.name }) {
                            do {
                                let args = toolCall.arguments.mapValues { $0.value }
                                let toolResult = try await tool.execute(parameters: args)
                                result = toolResult.output
                            } catch {
                                result = "Error: \(error.localizedDescription)"
                            }
                        } else {
                            result = "Error: Tool '\(toolCall.name)' not found"
                        }
                        
                        let toolMsg = ConversationMessage(
                            sessionId: session.id, role: .tool, content: result, timestamp: Date(), toolCallId: toolCall.id.uuidString
                        )
                        try await persistenceService.saveMessage(toolMsg)
                    }
                } else {
                    // Completion detection
                    if assistantContent.lowercased().contains("job complete") {
                        return .complete(assistantContent)
                    } else if assistantContent.lowercased().contains("i need more information") {
                        return .needInformation(assistantContent)
                    }
                }
            } catch is CancellationError {
                return .error("Cancelled")
            } catch {
                return .error(error.localizedDescription)
            }
        }
        
        return .error("Max turns reached")
    }
}
