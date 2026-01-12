import Foundation
import MonadCore
import OSLog

extension ChatViewModel {
    internal func runConversationLoop(
        userPrompt: String?,
        parentId: UUID?,
        contextData: ContextData
    ) async throws {
        // 1. Add user message to history if provided (legacy path, usually nil)
        if let prompt = userPrompt {
            do {
                try await persistenceManager.addMessage(role: .user, content: prompt)
                messages = persistenceManager.uiMessages
            } catch {
                Logger.chat.error("Failed to save user message (loop): \(error.localizedDescription)")
            }
        }

        var shouldContinue = true
        var turnCount = 0
        var currentParentId = parentId
        var currentContextData = contextData

        while shouldContinue {
            turnCount += 1
            if turnCount > 10 {
                Logger.chat.warning("Conversation loop exceeded max turns (10). Breaking.")
                shouldContinue = false
                break
            }

            let contextNotes = try await persistenceManager.fetchAllNotes()
            let enabledTools = toolManager.getEnabledTools()
            let contextDocuments = injectedDocuments

            // 2. Call LLM with empty userQuery, relying on chatHistory
            let (stream, rawPrompt, structuredContext) = await llmService.chatStreamWithContext(
                userQuery: "",
                contextNotes: contextNotes,
                documents: contextDocuments,
                memories: currentContextData.memories.map { $0.memory },
                chatHistory: messages,
                tools: enabledTools
            )

            streamingCoordinator.startStreaming()
            isLoading = false

            do {
                Logger.chat.debug("Starting stream consumption for turn \(turnCount)")
                var chunkCount = 0
                for try await result in stream {
                    if Task.isCancelled { break }
                    chunkCount += 1

                    streamingCoordinator.updateMetadata(from: result)

                    if let delta = result.choices.first?.delta.content {
                        streamingCoordinator.processChunk(delta)
                    }

                    if let toolCalls = result.choices.first?.delta.toolCalls {
                        streamingCoordinator.processToolCalls(toolCalls)
                    }
                }
                Logger.chat.debug("Stream consumption finished for turn \(turnCount). Total chunks: \(chunkCount)")
            } catch {
                Logger.chat.error("Stream error in turn \(turnCount): \(error.localizedDescription)")
                throw error
            }

            let assistantMessage = streamingCoordinator.finalize(
                wasCancelled: Task.isCancelled,
                rawPrompt: rawPrompt,
                structuredContext: structuredContext
            )

            // Record performance
            if let speed = assistantMessage.stats?.tokensPerSecond {
                performanceMetrics.recordSpeed(speed)
                if messages.count >= 5 && performanceMetrics.isSlow {
                    Logger.chat.warning("Performance drop detected (\(speed) t/s).")
                }
            }

            if Task.isCancelled {
                streamingCoordinator.stopStreaming()
                shouldContinue = false
                break
            }

            if !assistantMessage.content.isEmpty || assistantMessage.think != nil || assistantMessage.toolCalls != nil {
                messages.append(assistantMessage)
                streamingCoordinator.stopStreaming()

                do {
                    try await persistenceManager.addMessage(
                        id: assistantMessage.id,
                        role: .assistant,
                        content: assistantMessage.content,
                        parentId: currentParentId,
                        think: assistantMessage.think,
                        toolCalls: assistantMessage.toolCalls,
                        debugInfo: assistantMessage.debugInfo
                    )
                    messages = persistenceManager.uiMessages
                } catch {
                    Logger.chat.error("Failed to save assistant message: \(error.localizedDescription)")
                    errorMessage = "Failed to save message. It is shown locally but may be lost on restart."
                }

                let assistantMsgId = assistantMessage.id
                generateTitleIfNeeded()

                // Execute tool calls if present
                if let toolCalls = assistantMessage.toolCalls, !toolCalls.isEmpty {
                    isExecutingTools = true
                    let topicChange = try await toolOrchestrator.handleToolCalls(
                        toolCalls, 
                        assistantMsgId: assistantMsgId
                    )
                    isExecutingTools = false

                    messages = persistenceManager.uiMessages

                    if topicChange {
                        Logger.chat.info("Topic change detected via tool call. Triggering compression.")
                        await compressContext()
                        // Reset context data after topic change to ensure fresh retrieval if needed
                        currentContextData = ContextData()
                    }

                    currentParentId = assistantMsgId
                    shouldContinue = true
                } else {
                    // No more tool calls - check for auto-dequeue
                    if autoDequeueEnabled, let syntheticUserMsg = toolOrchestrator.autoDequeueNextJob() {
                        messages.append(syntheticUserMsg)

                        // For auto-dequeued jobs, we should probably gather fresh context 
                        // as it might be a completely different task.
                        currentContextData = try await contextManager.gatherContext(
                            for: syntheticUserMsg.content,
                            history: messages
                        )

                        do {
                            try await persistenceManager.addMessage(
                                id: syntheticUserMsg.id,
                                role: .user,
                                content: syntheticUserMsg.content
                            )
                            messages = persistenceManager.uiMessages
                        } catch {
                            Logger.chat.error("Failed to save auto-dequeued message: \(error.localizedDescription)")
                        }

                        currentParentId = syntheticUserMsg.id
                        shouldContinue = true
                    } else {
                        shouldContinue = false
                    }
                }
            } else {
                streamingCoordinator.stopStreaming()
                Logger.chat.warning("Assistant returned an empty response")
                errorMessage = "The model returned an empty response. You might want to try again."
                shouldContinue = false
            }
        }

        currentTask = nil
        isLoading = false
    }

    internal func handleCancellation() {
        Logger.chat.notice("Generation cancelled by user")
        if !streamingCoordinator.streamingContent.isEmpty {
            let assistantMessage = Message(
                content: streamingCoordinator.streamingContent + "\n\n[Generation cancelled]",
                role: .assistant,
                think: streamingCoordinator.streamingThinking.isEmpty ? nil : streamingCoordinator.streamingThinking
            )
            messages.append(assistantMessage)
        }
        streamingCoordinator.stopStreaming()
        currentTask = nil
        isLoading = false
    }

    public func cancelGeneration() {
        currentTask?.cancel()
        currentTask = nil
    }
}
