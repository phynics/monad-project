import Foundation
import MonadCore
import OSLog

extension ChatViewModel {
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

        // Remove everything after this user message
        messages = Array(messages.prefix(through: lastUserMessageIndex))

        currentTask = Task {
            do {
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

                let enabledTools = await toolManager.getEnabledTools()
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