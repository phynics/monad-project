import Foundation
import MonadCore
import OSLog

extension ChatViewModel {
    public func sendMessage() {
        // Input Validation
        let cleanedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedInput.isEmpty else { return }

        let prompt = cleanedInput
        inputText = ""
        isLoading = true
        errorMessage = nil
        Logger.chat.debug("Starting message generation for prompt length: \(prompt.count)")

        // Add user message immediately to track progress in UI
        let userMessage = Message(content: prompt, role: .user, gatheringProgress: .augmenting)
        messages.append(userMessage)
        let userMsgId = userMessage.id

        currentTask = Task {
            do {
                guard await llmService.isConfigured else {
                    errorMessage = "LLM Service is not configured."
                    isLoading = false
                    return
                }

                // Basic sanity check for extremely long input
                if prompt.count > 100_000 {
                    errorMessage = "Input is too long (\(prompt.count) characters). Please shorten your message."
                    isLoading = false
                    return
                }

                // Reset loop detection for the new interaction
                await toolExecutor.reset()

                // 1. Gather Context via ContextManager
                let service = llmService
                let tagGenerator: @Sendable (String) async throws -> [String] = { text in
                    try await service.generateTags(for: text)
                }

                let memoryLimit = await llmService.configuration.memoryContextLimit
                let contextData = try await contextManager.gatherContext(
                    for: prompt,
                    history: messages,
                    limit: memoryLimit,
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

                // 2. Build the prompt for debug info without starting a stream
                let enabledTools = await toolManager.getEnabledTools()
                let (_, _, _) = await llmService.buildPrompt(
                    userQuery: prompt,
                    contextNotes: contextData.notes,
                    documents: injectedDocuments,
                    memories: injectedMemories,
                    chatHistory: messages,
                    tools: enabledTools
                )

                // Persist the user message now that we have context data (memories)
                var userMessageSaved = false
                do {
                    try await persistenceManager.addMessage(
                        id: userMsgId,
                        role: .user,
                        content: prompt,
                        recalledMemories: contextData.memories.map { $0.memory }
                    )
                    messages = persistenceManager.uiMessages
                    userMessageSaved = true
                } catch {
                    Logger.chat.error("Failed to save user message: \(error.localizedDescription)")
                    errorMessage = "Failed to save message. It is shown locally but may be lost on restart."
                }

                // 3. Start the conversation loop
                try await runConversationLoop(
                    userPrompt: nil,
                    parentId: userMessageSaved ? userMsgId : nil,
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
}