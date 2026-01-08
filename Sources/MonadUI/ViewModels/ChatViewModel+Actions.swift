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
                do {
                    try await persistenceManager.addMessage(
                        id: userMsgId, // Use the same ID
                        role: .user,
                        content: prompt,
                        recalledMemories: contextData.memories.map { $0.memory }
                    )
                    // Sync UI messages from forest only on success
                    messages = persistenceManager.uiMessages
                } catch {
                    Logger.chat.error("Failed to save user message: \(error.localizedDescription)")
                    errorMessage = "Failed to save message. It is shown locally but may be lost on restart."
                }

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
        
        while shouldContinue {
            // ... (rest of loop setup) ...
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
                streamingCoordinator.stopStreaming()
                shouldContinue = false
                break
            }

            if !assistantMessage.content.isEmpty || assistantMessage.think != nil
                || assistantMessage.toolCalls != nil
            {
                // OPTIMISTIC UPDATE:
                // 1. Append the finalized message to the UI immediately
                messages.append(assistantMessage)
                
                // 2. Stop streaming (removes the "Streaming..." bubble)
                streamingCoordinator.stopStreaming()
                
                // 3. Persist to DB using the SAME ID so the eventual consistency update matches
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
                    
                    // 4. Sync from forest only on success
                    messages = persistenceManager.uiMessages
                } catch {
                    Logger.chat.error("Failed to save assistant message: \(error.localizedDescription)")
                    errorMessage = "Failed to save message. It is shown locally but may be lost on restart."
                }
                
                // Get the assistant message ID for nesting tool results
                // Since it's the last assistant message in flat view too
                let assistantMsgId = assistantMessage.id

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
                        do {
                            try await persistenceManager.addMessage(
                                role: .tool,
                                content: toolResult.content,
                                parentId: assistantMsgId
                            )
                        } catch {
                            Logger.chat.error("Failed to save tool result: \(error.localizedDescription)")
                        }
                    }
                    
                    // Sync again
                    messages = persistenceManager.uiMessages
                    
                    // Check for topic change signal and compress if needed
                    if toolCalls.contains(where: { $0.name == "mark_topic_change" }) {
                        Logger.chat.info("Topic change detected via tool call. Triggering compression.")
                        await compressContext()
                    }

                    // Continue loop to send tool results back to LLM
                    currentParentId = assistantMsgId
                    
                    shouldContinue = true
                } else {
                    // No more tool calls, we are done
                    shouldContinue = false
                }
            } else {
                streamingCoordinator.stopStreaming()
                Logger.chat.warning("Assistant returned an empty response (no content, no thinking, no tool calls)")
                errorMessage = "The model returned an empty response. You might want to try again."
                shouldContinue = false
            }
        }

        currentTask = nil
        isLoading = false
    }
    
    public func compressContext(scope: CompressionScope = .topic) async {
        Logger.chat.info("Attempting context compression (scope: \(scope))...")
        do {
            let compressed = try await contextCompressor.compress(messages: messages, scope: scope)
            
            // If the compressed array is different (shorter) than original, update persistence
            if compressed.count < messages.count || (scope == .broad && compressed.contains(where: { $0.summaryType == .broad })) {
                Logger.chat.notice("Compression successful. Replacing \(self.messages.count) messages with \(compressed.count).")
                try await persistenceManager.replaceMessages(with: compressed)
                messages = persistenceManager.uiMessages
            } else {
                Logger.chat.debug("Compression yielded no reduction.")
            }
        } catch {
            Logger.chat.error("Context compression failed: \(error.localizedDescription)")
        }
    }
    
    public func triggerMemoryVacuum() async {
        do {
            let count = try await persistenceManager.vacuumMemories()
            Logger.chat.info("Memory vacuum pruned \(count) memories.")
        } catch {
            Logger.chat.error("Memory vacuum failed: \(error.localizedDescription)")
        }
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
