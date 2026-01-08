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
        let userNode = MessageNode(message: userMessage)
        // Note: For now we still show flat messages in the VM for simple UI binding if needed, 
        // but let's try to transition to the forest as the source of truth for UI as well if we can.
        // If we want UI to remain same, we can just use the flattened view.
        
        // For simplicity during transition, I will keep 'messages' as [Message] in the VM
        // but derived from the forest in PersistenceManager.
        
        // Let's modify runConversationLoop to handle parent IDs.
        let userMsgId = userMessage.id

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
                    history: messages, // History before this message
                    limit: llmService.configuration.memoryContextLimit,
                    tagGenerator: tagGenerator,
                    onProgress: { [weak self] progress in
                        guard let self = self else { return }
                        Task { @MainActor in
                            if let index = self.messages.firstIndex(where: { $0.id == userMsgId }) {
                                self.messages[index].gatheringProgress = progress
                            }
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
                    chatHistory: messages,
                    tools: enabledTools
                )

                // Persist the user message now that we have context data (memories)
                try? await persistenceManager.addMessage(
                    role: .user,
                    content: prompt,
                    recalledMemories: contextData.memories.map { $0.memory }
                )
                
                // Sync UI messages from forest
                messages = persistenceManager.uiMessages

                // 3. Start the conversation loop
                try await runConversationLoop(
                    userPrompt: nil, // Already added and persisted
                    parentId: userMsgId,
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
        parentId: UUID?,
        contextData: ContextData
    ) async throws {
        // 1. Add user message to history if provided
        if let prompt = userPrompt {
            try? await persistenceManager.addMessage(role: .user, content: prompt)
            messages = persistenceManager.uiMessages
        }

        var shouldContinue = true
        var turnCount = 0
        var currentParentId = parentId
        
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
            let (stream, rawPrompt, structuredContext) = await llmService.chatStreamWithContext(
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

            let assistantMessage = streamingCoordinator.finalize(
                wasCancelled: Task.isCancelled,
                rawPrompt: rawPrompt,
                structuredContext: structuredContext
            )
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
                // Persist assistant message under currentParentId
                try? await persistenceManager.addMessage(
                    role: .assistant,
                    content: assistantMessage.content,
                    parentId: currentParentId
                )
                
                // Update local UI from persisted forest
                messages = persistenceManager.uiMessages
                
                // Get the assistant message ID for nesting tool results
                // Since it's the last assistant message in flat view too
                let assistantMsgId = messages.last { $0.role == .assistant }?.id

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
                    
                    // Persist tool results under assistant message
                    for var toolResult in toolResults {
                        try? await persistenceManager.addMessage(
                            role: .tool,
                            content: toolResult.content,
                            parentId: assistantMsgId
                        )
                    }
                    
                    messages = persistenceManager.uiMessages

                    // Continue loop to send tool results back to LLM
                    // Next assistant message should probably also be under user message 
                    // OR under the last assistant message.
                    // Requirement: "tool call loops are placed under the assistant message"
                    // This implies the assistant message is the parent of tools.
                    // If assistant continues after tools, it's a sibling of the tools?
                    // Or child of previous assistant?
                    // Let's keep subsequent assistant messages as siblings of tools (children of assistantMsgId).
                    // Actually, if we want User -> Assistant -> [Tools], then next Assistant 
                    // should probably be a child of Assistant too if it's responding to tools.
                    currentParentId = assistantMsgId
                    
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
                
                let lastUserMessage = messages[lastUserMessageIndex]
                
                try await runConversationLoop(
                    userPrompt: nil,
                    parentId: lastUserMessage.id,
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
