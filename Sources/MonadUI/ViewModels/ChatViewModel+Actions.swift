import Foundation
import OSLog
import MonadCore

extension ChatViewModel {
    public func sendMessage() {
        // Input Validation
        let cleanedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedInput.isEmpty else { return }
        
        guard llmService.isConfigured else {
            errorMessage = "LLM Service is not configured."
            return
        }
        
        // Basic sanity check for extremely long input to prevent accidental massive pastes hanging the UI
        if cleanedInput.count > 100_000 {
            errorMessage = "Input is too long (\(cleanedInput.count) characters). Please shorten your message."
            return
        }

        let prompt = cleanedInput
        inputText = ""
        isLoading = true
        errorMessage = nil
        Logger.chat.debug("Starting message generation for prompt length: \(prompt.count)")
        
        // Add user message immediately to track progress in UI
        let userMessage = Message(content: prompt, role: .user, gatheringProgress: .augmenting)
        messages.append(userMessage)
        let userMessageIndex = messages.count - 1

        // Reset loop detection for the new interaction
        toolExecutor?.reset()

        currentTask = Task {
            do {
                // 1. Gather Context via ContextManager
                // Define tag generator closure
                let service = llmService
                let tagGenerator: @Sendable (String) async throws -> [String] = { text in
                    try await service.generateTags(for: text)
                }
                
                let contextData = try await contextManager.gatherContext(
                    for: prompt, 
                    history: Array(messages.prefix(userMessageIndex)), // History before this message
                    limit: llmService.configuration.memoryContextLimit,
                    tagGenerator: tagGenerator,
                    onProgress: { [weak self] progress in
                        guard let self = self else { return }
                        Task { @MainActor in
                            self.messages[userMessageIndex].gatheringProgress = progress
                        }
                    }
                )
                
                // Merge found memories into chat-level active memories
                updateActiveMemories(with: contextData.memories.map { $0.memory })
                
                let enabledTools = tools.getEnabledTools()
                
                // Use computed properties for injection
                let contextDocuments = injectedDocuments
                let contextMemories = injectedMemories
                
                // 2. Build the prompt for debug info without starting a stream
                let (_, initialRawPrompt, structuredContext) = await llmService.buildPrompt(
                    userQuery: prompt,
                    contextNotes: contextData.notes,
                    documents: contextDocuments,
                    memories: contextMemories,
                    chatHistory: Array(messages.prefix(userMessageIndex)),
                    tools: enabledTools
                )

                // Update debug info for the user message
                messages[userMessageIndex].recalledMemories = contextMemories // Log what was actually injected
                messages[userMessageIndex].recalledDocuments = contextDocuments
                messages[userMessageIndex].debugInfo = .userMessage(
                    rawPrompt: initialRawPrompt, 
                    contextMemories: contextData.memories,
                    generatedTags: contextData.generatedTags,
                    queryVector: contextData.queryVector,
                    augmentedQuery: contextData.augmentedQuery,
                    semanticResults: contextData.semanticResults,
                    tagResults: contextData.tagResults,
                    structuredContext: structuredContext
                )
                
                // Persist the user message now that we have context data (memories)
                try? await persistenceManager.addMessage(
                    role: .user,
                    content: prompt,
                    recalledMemories: contextData.memories.map { $0.memory }
                )

                // 3. Start the conversation loop
                try await runConversationLoop(
                    userPrompt: nil, // Already added
                    initialRawPrompt: nil,
                    contextData: contextData
                )

            } catch is CancellationError {
                handleCancellation()
            } catch {
                let msg = "Failed to get response: \(error.localizedDescription)"
                Logger.chat.error("\(msg)")
                errorMessage = msg
                streamingCoordinator.stopStreaming()
                isLoading = false
                currentTask = nil
            }
        }
    }

    internal func runConversationLoop(
        userPrompt: String?,
        initialRawPrompt: String?,
        contextData: ContextData
    ) async throws {
        // 1. Add user message to history if provided
        if let prompt = userPrompt {
            // Note: This path handles cases where runConversationLoop is called without sendMessage
            // But we mainly use sendMessage.
            // For now, assume this follows similar logic for debug info if needed.
            let userMessage = Message(content: prompt, role: .user)
            messages.append(userMessage)
        }

        var shouldContinue = true
        var turnCount = 0
        
        while shouldContinue {
            turnCount += 1
            if turnCount > 10 {
                Logger.chat.warning("Conversation loop exceeded max turns (10). Breaking.")
                shouldContinue = false
                break
            }
            
            let contextNotes = try await persistenceManager.fetchAlwaysAppendNotes()
            let enabledTools = tools.getEnabledTools()
            let contextDocuments = injectedDocuments
            let contextMemories = injectedMemories

            // 2. Call LLM with empty userQuery, relying on chatHistory
            let (stream, _, _) = await llmService.chatStreamWithContext(
                userQuery: "",
                contextNotes: contextNotes,
                documents: contextDocuments,
                memories: contextMemories,
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
                        Logger.chat.debug("RAW STREAM CHUNK: '\(delta)'")
                        streamingCoordinator.processChunk(delta)
                    }

                    // Process tool calls from delta
                    if let toolCalls = result.choices.first?.delta.toolCalls {
                        Logger.chat.debug("RAW TOOL CALL DELTA: \(toolCalls.count) items")
                        streamingCoordinator.processToolCalls(toolCalls)
                    }
                }
                Logger.chat.debug("Stream consumption finished for turn \(turnCount). Total chunks: \(chunkCount)")
            } catch {
                Logger.chat.error("Stream error in turn \(turnCount): \(error.localizedDescription)")
                throw error
            }

            let assistantMessage = streamingCoordinator.finalize(wasCancelled: Task.isCancelled)
            streamingCoordinator.stopStreaming()
            
            // Record performance
            if let speed = assistantMessage.stats?.tokensPerSecond {
                performanceMetrics.recordSpeed(speed)
                
                // Trigger logic: after 5 messages, if speed < 75% of average
                if messages.count >= 5 && performanceMetrics.isSlow {
                    Logger.chat.warning("Performance drop detected (\(speed) t/s). Injecting long context for next turn.")
                    shouldInjectLongContext = true
                }
            }

            if Task.isCancelled {
                shouldContinue = false
                break
            }

            if !assistantMessage.content.isEmpty || assistantMessage.think != nil
                || assistantMessage.toolCalls != nil
            {
                messages.append(assistantMessage)
                
                // Persist assistant message
                try? await persistenceManager.addMessage(
                    role: .assistant,
                    content: assistantMessage.content
                )
                
                // Check if we need to auto-generate a title
                generateTitleIfNeeded()

                // Execute tool calls if present
                if let toolCalls = assistantMessage.toolCalls, !toolCalls.isEmpty,
                    let executor = toolExecutor
                {
                    Logger.chat.info("Executing \(toolCalls.count) tool calls")
                    isExecutingTools = true
                    let toolResults = await executor.executeAll(toolCalls)
                    isExecutingTools = false
                    messages.append(contentsOf: toolResults)
                    
                    // Note: We currently don't persist tool outputs as ConversationMessage doesn't support .tool role yet.

                    // Continue loop to send tool results back to LLM
                    shouldContinue = true
                } else {
                    // No more tool calls, we are done
                    shouldContinue = false
                }
            } else {
                Logger.chat.warning("Assistant returned an empty response (no content, no thinking, no tool calls)")
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
                think: streamingCoordinator.streamingThinking.isEmpty
                    ? nil
                    : streamingCoordinator.streamingThinking
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

    public func retry() {
        guard errorMessage != nil else { return }
        
        // Find last user message
        guard let lastUserMessageIndex = messages.lastIndex(where: { $0.role == .user }) else { 
            errorMessage = "Nothing to retry."
            return
        }
        
        let prompt = messages[lastUserMessageIndex].content
        errorMessage = nil
        isLoading = true
        
        // Remove everything after this user message (including any failed assistant/tool messages)
        messages = Array(messages.prefix(through: lastUserMessageIndex))
        
        currentTask = Task {
            do {
                // Define tag generator closure
                let service = llmService
                let tagGenerator: @Sendable (String) async throws -> [String] = { text in
                    try await service.generateTags(for: text)
                }
                
                // Re-gather context
                let contextData = try await contextManager.gatherContext(
                    for: prompt,
                    history: Array(messages.prefix(lastUserMessageIndex)),
                    limit: llmService.configuration.memoryContextLimit,
                    tagGenerator: tagGenerator,
                    onProgress: { [weak self] progress in
                        guard let self = self else { return }
                        Task { @MainActor in
                            self.messages[lastUserMessageIndex].gatheringProgress = progress
                        }
                    }
                )
                
                updateActiveMemories(with: contextData.memories.map { $0.memory })
                
                let enabledTools = tools.getEnabledTools()
                let contextDocuments = injectedDocuments
                let contextMemories = injectedMemories
                
                // Refresh debug info
                let (_, rawPrompt, structuredContext) = await llmService.chatStreamWithContext(
                    userQuery: prompt,
                    contextNotes: contextData.notes,
                    documents: contextDocuments,
                    memories: contextMemories,
                    chatHistory: Array(messages.prefix(lastUserMessageIndex)),
                    tools: enabledTools
                )
                
                messages[lastUserMessageIndex].recalledMemories = contextMemories
                messages[lastUserMessageIndex].recalledDocuments = contextDocuments
                messages[lastUserMessageIndex].debugInfo = .userMessage(
                    rawPrompt: rawPrompt,
                    contextMemories: contextData.memories,
                    generatedTags: contextData.generatedTags,
                    queryVector: contextData.queryVector,
                    augmentedQuery: contextData.augmentedQuery,
                    semanticResults: contextData.semanticResults,
                    tagResults: contextData.tagResults,
                    structuredContext: structuredContext
                )
                
                try await runConversationLoop(
                    userPrompt: nil,
                    initialRawPrompt: nil,
                    contextData: contextData
                )
            } catch is CancellationError {
                handleCancellation()
            } catch {
                let msg = "Failed to retry: \(error.localizedDescription)"
                Logger.chat.error("\(msg)")
                errorMessage = msg
                streamingCoordinator.stopStreaming()
                isLoading = false
                currentTask = nil
            }
        }
    }
}
