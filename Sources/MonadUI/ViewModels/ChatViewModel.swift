import OSLog
import Observation
import OpenAI
import SwiftUI
import MonadCore

@MainActor
@Observable
public final class ChatViewModel {
    public var inputText: String = ""
    public var messages: [Message] = []
    public var isLoading = false
    public var errorMessage: String?

    public let llmService: LLMService
    public let persistenceManager: PersistenceManager
    public let contextManager: ContextManager

    private var currentTask: Task<Void, Never>?
    private var toolManager: SessionToolManager?

    // Service dependencies
    // These must be preserved!
    public let streamingCoordinator: StreamingCoordinator
    public var toolExecutor: ToolExecutor?
    public let conversationArchiver: ConversationArchiver

    private let logger = Logger.chat

    public init(llmService: LLMService, persistenceManager: PersistenceManager) {
        self.llmService = llmService
        self.persistenceManager = persistenceManager
        self.contextManager = ContextManager(
            persistenceService: persistenceManager.persistence,
            embeddingService: llmService.embeddingService
        )
        self.streamingCoordinator = StreamingCoordinator()
        self.conversationArchiver = ConversationArchiver(persistenceManager: persistenceManager)
    }

    public var tools: SessionToolManager {
        if let existing = toolManager {
            return existing
        }

        let availableTools: [MonadCore.Tool] = [
            SearchArchivedChatsTool(persistenceService: persistenceManager.persistence),
            SearchMemoriesTool(persistenceService: persistenceManager.persistence, embeddingService: llmService.embeddingService),
            CreateMemoryTool(persistenceService: persistenceManager.persistence, embeddingService: llmService.embeddingService),
            SearchNotesTool(persistenceService: persistenceManager.persistence),
            EditNoteTool(persistenceService: persistenceManager.persistence),
        ]
        let manager = SessionToolManager(availableTools: availableTools)
        self.toolManager = manager
        self.toolExecutor = ToolExecutor(toolManager: manager)
        return manager
    }

    // Expose streaming state
    public var streamingThinking: String {
        streamingCoordinator.streamingThinking
    }

    public var streamingContent: String {
        streamingCoordinator.streamingContent
    }

    public var isStreaming: Bool {
        streamingCoordinator.isStreaming
    }

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
        logger.debug("Starting message generation for prompt length: \(prompt.count)")
        
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
                
                let contextData = try await contextManager.gatherContext(for: prompt, tagGenerator: tagGenerator)
                let enabledTools = tools.getEnabledTools()
                
                // 2. Perform an initial call to get the raw prompt for the user message debug info
                let (_, initialRawPrompt) = await llmService.chatStreamWithContext(
                    userQuery: prompt,
                    contextNotes: contextData.notes,
                    memories: contextData.memories.map { $0.memory },
                    chatHistory: messages,
                    tools: enabledTools
                )

                // 3. Start the conversation loop
                try await runConversationLoop(
                    userPrompt: prompt, 
                    initialRawPrompt: initialRawPrompt,
                    contextData: contextData
                )

            } catch is CancellationError {
                handleCancellation()
            } catch {
                let msg = "Failed to get response: \(error.localizedDescription)"
                logger.error("\(msg)")
                errorMessage = msg
                streamingCoordinator.stopStreaming()
                isLoading = false
                currentTask = nil
            }
        }
    }

    // Removed fetchRelevantMemories as it is now in ContextManager

    private func runConversationLoop(
        userPrompt: String?, 
        initialRawPrompt: String?,
        contextData: ContextData
    ) async throws {
        // 1. Add user message to history if provided
        if let prompt = userPrompt {
            let userMessage = Message(
                content: prompt,
                role: .user,
                think: nil,
                debugInfo: initialRawPrompt.map { 
                    .userMessage(
                        rawPrompt: $0, 
                        contextMemories: contextData.memories,
                        generatedTags: contextData.generatedTags,
                        queryVector: contextData.queryVector
                    ) 
                }
            )
            messages.append(userMessage)
        }

        var shouldContinue = true
        var turnCount = 0
        let currentMemories = contextData.memories.map { $0.memory }

        while shouldContinue {
            turnCount += 1
            if turnCount > 10 {
                logger.warning("Conversation loop exceeded max turns (10). Breaking.")
                shouldContinue = false
                break
            }

            // Re-fetch context notes if they might have changed (optional optimization: only fetch once if not expecting changes)
            // But since tools might edit notes, it's safer to fetch.
            // However, ContextManager is designed for the initial user query context.
            // For subsequent turns in the loop (tool outputs), we might want to re-evaluate context or stick to the initial one.
            // For now, let's keep fetching "Always Append" notes as they are "system prompts" essentially.
            
            // We can reuse ContextManager to fetch notes only, or expose a method.
            // Since we don't have a query for tool outputs, semantic search for memories is harder.
            // We'll stick to the initial memories for the whole turn for now, or accummulate.
            // NOTE: The previous implementation re-fetched contextNotes every loop iteration.
            
            let contextNotes = try await persistenceManager.fetchAlwaysAppendNotes()
            let enabledTools = tools.getEnabledTools()

            // 2. Call LLM with empty userQuery, relying on chatHistory (which now includes the user message)
            let (stream, _) = await llmService.chatStreamWithContext(
                userQuery: "",
                contextNotes: contextNotes,
                memories: currentMemories,
                chatHistory: messages,
                tools: enabledTools
            )

            streamingCoordinator.startStreaming()
            isLoading = false

            for try await result in stream {
                if Task.isCancelled { break }

                streamingCoordinator.updateMetadata(from: result)

                if let delta = result.choices.first?.delta.content {
                    streamingCoordinator.processChunk(delta)
                }

                // Process tool calls from delta
                if let toolCalls = result.choices.first?.delta.toolCalls {
                    streamingCoordinator.processToolCalls(toolCalls)
                }
            }

            let assistantMessage = streamingCoordinator.finalize(wasCancelled: Task.isCancelled)
            streamingCoordinator.stopStreaming()

            if Task.isCancelled {
                shouldContinue = false
                break
            }

            if !assistantMessage.content.isEmpty || assistantMessage.think != nil
                || assistantMessage.toolCalls != nil
            {
                messages.append(assistantMessage)

                // Execute tool calls if present
                if let toolCalls = assistantMessage.toolCalls, !toolCalls.isEmpty,
                    let executor = toolExecutor
                {
                    logger.info("Executing \(toolCalls.count) tool calls")
                    let toolResults = await executor.executeAll(toolCalls)
                    messages.append(contentsOf: toolResults)

                    // Continue loop to send tool results back to LLM
                    shouldContinue = true
                } else {
                    // No more tool calls, we are done
                    shouldContinue = false
                }
            } else {
                shouldContinue = false
            }
        }

        currentTask = nil
        isLoading = false
    }

    private func handleCancellation() {
        logger.notice("Generation cancelled by user")
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

    public func archiveConversation(confirmationDismiss: @escaping () -> Void) {
        Task {
            do {
                try await conversationArchiver.archive(messages: messages)
                logger.info("Conversation archived")
                messages = []
                errorMessage = nil
                confirmationDismiss()
            } catch {
                let msg = "Failed to archive: \(error.localizedDescription)"
                logger.error("\(msg)")
                errorMessage = msg
            }
        }
    }

    public func clearConversation() {
        logger.debug("Clearing conversation")
        messages = []
        errorMessage = nil
    }
}
