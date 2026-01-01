import Observation
import OpenAI
import SwiftUI
import os.log

@MainActor
@Observable
class ChatViewModel {
    var inputText: String = ""
    var messages: [Message] = []
    var isLoading = false
    var errorMessage: String?

    let llmService: LLMService
    let persistenceManager: PersistenceManager

    private var currentTask: Task<Void, Never>?
    private var toolManager: SessionToolManager?

    // Service dependencies
    // These must be preserved!
    let streamingCoordinator: StreamingCoordinator
    var toolExecutor: ToolExecutor?
    let conversationArchiver: ConversationArchiver

    private let logger = Logger.chat

    init(llmService: LLMService, persistenceManager: PersistenceManager) {
        self.llmService = llmService
        self.persistenceManager = persistenceManager
        self.streamingCoordinator = StreamingCoordinator()
        self.conversationArchiver = ConversationArchiver(persistenceManager: persistenceManager)
    }

    var tools: SessionToolManager {
        if let existing = toolManager {
            return existing
        }

        let availableTools: [Tool] = [
            SearchArchivedChatsTool(persistenceManager: persistenceManager),
            SearchMemoriesTool(persistenceManager: persistenceManager),
            CreateMemoryTool(persistenceManager: persistenceManager),
            EditMemoryTool(persistenceManager: persistenceManager),
            SearchNotesTool(persistenceManager: persistenceManager),
            EditNoteTool(persistenceManager: persistenceManager),
        ]
        let manager = SessionToolManager(availableTools: availableTools)
        self.toolManager = manager
        self.toolExecutor = ToolExecutor(toolManager: manager)
        return manager
    }

    // Expose streaming state
    var streamingThinking: String {
        streamingCoordinator.streamingThinking
    }

    var streamingContent: String {
        streamingCoordinator.streamingContent
    }

    var isStreaming: Bool {
        streamingCoordinator.isStreaming
    }

    func sendMessage() {
        guard !inputText.isEmpty, llmService.isConfigured else { return }

        let prompt = inputText
        inputText = ""
        isLoading = true
        errorMessage = nil
        logger.debug("Starting message generation for prompt length: \(prompt.count)")

        currentTask = Task {
            do {
                // For the very first turn, we need to get the raw prompt to attach to the user message.
                // Subsequent turns in the loop will use the chat history.
                let contextNotes = try await persistenceManager.fetchAlwaysAppendNotes()
                let enabledTools = tools.getEnabledTools()

                // Perform an initial call to get the raw prompt for the user message debug info
                // This stream won't be processed, it's just to get the raw prompt builder output
                let (_, initialRawPrompt) = await llmService.chatStreamWithContext(
                    userQuery: prompt,
                    contextNotes: contextNotes,
                    chatHistory: messages,
                    tools: enabledTools
                )

                // Start the conversation loop
                try await runConversationLoop(
                    userPrompt: prompt, initialRawPrompt: initialRawPrompt)

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

    private func runConversationLoop(userPrompt: String?, initialRawPrompt: String?) async throws {
        // 1. Add user message to history if provided
        if let prompt = userPrompt {
            let userMessage = Message(
                content: prompt,
                role: .user,
                think: nil,
                debugInfo: initialRawPrompt.map { .userMessage(rawPrompt: $0) }
            )
            messages.append(userMessage)
        }

        var shouldContinue = true
        var turnCount = 0

        while shouldContinue {
            turnCount += 1
            if turnCount > 10 {
                logger.warning("Conversation loop exceeded max turns (10). Breaking.")
                shouldContinue = false
                break
            }

            let contextNotes = try await persistenceManager.fetchAlwaysAppendNotes()
            let enabledTools = tools.getEnabledTools()

            // 2. Call LLM with empty userQuery, relying on chatHistory (which now includes the user message)
            let (stream, _) = await llmService.chatStreamWithContext(
                userQuery: "",
                contextNotes: contextNotes,
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

    func cancelGeneration() {
        currentTask?.cancel()
        currentTask = nil
    }

    func archiveConversation(confirmationDismiss: @escaping () -> Void) {
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

    func clearConversation() {
        logger.debug("Clearing conversation")
        messages = []
        errorMessage = nil
    }
}
