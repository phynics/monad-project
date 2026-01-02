import Foundation
import OSLog
import OpenAI

/// Events emitted during the chat conversation loop
public enum ChatEvent: Sendable {
    case streamStart
    case chunk(String) // Content chunk
    case thinking(String) // Thinking chunk
    case toolCall(String) // Tool call details (placeholder, logic handles this)
    case message(Message) // Final message or tool output
    case streamEnd
    case error(String)
}

/// Core engine for managing the conversation loop
public actor ChatEngine {
    private let llmService: LLMService
    private let persistenceService: PersistenceService
    private var logger = Logger(subsystem: "com.monad.core", category: "chat-engine")

    public init(llmService: LLMService, persistenceService: PersistenceService) {
        self.llmService = llmService
        self.persistenceService = persistenceService
    }

    /// Runs the conversation loop.
    /// This replaces `ChatViewModel.runConversationLoop`.
    ///
    /// - Parameters:
    ///   - userPrompt: The initial user prompt.
    ///   - history: The chat history (messages).
    ///   - tools: The list of enabled tools.
    /// - Returns: An async throwing stream of events.
    public func run(
        userPrompt: String,
        history: [Message],
        tools: [Tool]
    ) -> AsyncThrowingStream<ChatEvent, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var currentHistory = history
                    var shouldContinue = true
                    var turnCount = 0

                    // 1. Add user message
                    let contextNotes = try await persistenceService.fetchAlwaysAppendNotes()

                    // Initial prompt logic
                    // We need to get the "raw prompt" (debug info) for the user message
                    let (_, initialRawPrompt) = await llmService.chatStreamWithContext(
                        userQuery: userPrompt,
                        contextNotes: contextNotes,
                        chatHistory: currentHistory,
                        tools: tools
                    )

                    let userMessage = Message(
                        content: userPrompt,
                        role: .user,
                        think: nil,
                        debugInfo: initialRawPrompt.map { .userMessage(rawPrompt: $0) }
                    )
                    currentHistory.append(userMessage)

                    // Emit the user message so UI can display it immediately if not already added
                    // (Actually UI usually adds it optimistically, but let's assume UI handles history provided)
                    // We will emit .message(userMessage) if we want UI to sync, but `ChatViewModel` usually
                    // manages the list. Let's assume this stream emits *updates* to the conversation.

                    while shouldContinue {
                        turnCount += 1
                        if turnCount > 10 {
                            logger.warning("Conversation loop exceeded max turns")
                            shouldContinue = false
                            break
                        }

                        continuation.yield(.streamStart)

                        // 2. Call LLM
                        let (stream, _) = await llmService.chatStreamWithContext(
                            userQuery: "",
                            contextNotes: contextNotes,
                            chatHistory: currentHistory,
                            tools: tools
                        )

                        // We use a local StreamingProcessor to accumulate this turn's response
                        var processor = StreamingProcessor()

                        for try await result in stream {
                            if Task.isCancelled { break }

                            if let delta = result.choices.first?.delta.content {
                                processor.processChunk(delta)
                                // Emit chunk event
                                // We emit raw deltas? Or full state?
                                // `ChatViewModel` expects deltas to feed its `StreamingCoordinator`.
                                // Let's yield deltas.
                                continuation.yield(.chunk(delta))
                            }

                            if let toolCalls = result.choices.first?.delta.toolCalls {
                                processor.processToolCalls(toolCalls)
                                // We might want to yield tool events?
                            }
                        }

                        let assistantMessage = processor.finalize(wasCancelled: Task.isCancelled)
                        continuation.yield(.streamEnd)

                        if Task.isCancelled {
                            shouldContinue = false
                            break
                        }

                        if !assistantMessage.content.isEmpty || assistantMessage.think != nil || assistantMessage.toolCalls != nil {
                            currentHistory.append(assistantMessage)
                            continuation.yield(.message(assistantMessage))

                            // Execute tools
                            if let toolCalls = assistantMessage.toolCalls, !toolCalls.isEmpty {
                                let executor = ToolExecutor(tools: tools)
                                logger.info("Executing \(toolCalls.count) tool calls")
                                let toolResults = await executor.executeAll(toolCalls)

                                for resultMsg in toolResults {
                                    currentHistory.append(resultMsg)
                                    continuation.yield(.message(resultMsg))
                                }
                                shouldContinue = true
                            } else {
                                shouldContinue = false
                            }
                        } else {
                            shouldContinue = false
                        }
                    }

                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
