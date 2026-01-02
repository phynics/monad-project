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

    public let llmServiceViewModel: LLMServiceViewModel
    public let persistenceManager: PersistenceManager

    private var currentTask: Task<Void, Never>?
    private var toolManager: SessionToolManager?

    // Service dependencies
    // These must be preserved!
    public let streamingCoordinator: StreamingCoordinator
    public var toolExecutor: ToolExecutor?
    public let conversationArchiver: ConversationArchiver

    // Core Engine
    private let chatEngine: ChatEngine

    private let logger = Logger.chat

    public init(llmServiceViewModel: LLMServiceViewModel, persistenceManager: PersistenceManager) {
        self.llmServiceViewModel = llmServiceViewModel
        self.persistenceManager = persistenceManager
        self.streamingCoordinator = StreamingCoordinator()
        self.conversationArchiver = ConversationArchiver(persistenceManager: persistenceManager)

        // Initialize ChatEngine
        // Note: ChatEngine is an actor.
        self.chatEngine = ChatEngine(
            llmService: llmServiceViewModel.coreService,
            persistenceService: persistenceManager.persistence
        )
    }

    public var tools: SessionToolManager {
        if let existing = toolManager {
            return existing
        }

        // Initialize tools with PersistenceService from PersistenceManager
        let persistenceService = persistenceManager.persistence

        let availableTools: [Tool] = [
            SearchArchivedChatsTool(persistenceService: persistenceService),
            SearchMemoriesTool(persistenceService: persistenceService),
            CreateMemoryTool(persistenceService: persistenceService),
            EditMemoryTool(persistenceService: persistenceService),
            SearchNotesTool(persistenceService: persistenceService),
            EditNoteTool(persistenceService: persistenceService),
        ]
        let manager = SessionToolManager(availableTools: availableTools)
        self.toolManager = manager
        // ToolExecutor is now in Core and transiently used by ChatEngine,
        // but we keep it here if UI needs it or for legacy reasons?
        // Actually ChatViewModel previously used it.
        // We can create one for local use if needed, but ChatEngine handles execution now.
        // We'll keep the property as optional but maybe unused.
        self.toolExecutor = ToolExecutor(tools: availableTools)
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
        guard !inputText.isEmpty, llmServiceViewModel.isConfigured else { return }

        let prompt = inputText
        inputText = ""
        isLoading = true
        errorMessage = nil
        logger.debug("Starting message generation for prompt length: \(prompt.count)")

        // Ensure tools are initialized
        let enabledTools = tools.getEnabledTools()

        currentTask = Task {
            do {
                let stream = await chatEngine.run(
                    userPrompt: prompt,
                    history: messages,
                    tools: enabledTools
                )

                // Add user message optimistically?
                // ChatEngine adds it to history internally but we need to update UI.
                // We'll construct it here for UI.
                // Wait, ChatEngine emits messages. We should wait for that?
                // But we want immediate feedback.
                let userMsg = Message(content: prompt, role: .user)
                messages.append(userMsg)

                for try await event in stream {
                    switch event {
                    case .streamStart:
                        streamingCoordinator.startStreaming()
                        isLoading = false // It's streaming now

                    case .chunk(let delta):
                        streamingCoordinator.processChunk(delta)

                    case .thinking(let delta):
                        // StreamingCoordinator handles parsing tags, but if ChatEngine emits explicit thinking...
                        // Our ChatEngine implementation currently only emits .chunk from delta.
                        // So we just rely on .chunk handling in coordinator.
                        break

                    case .toolCall:
                        // Logic handled inside engine/coordinator mostly
                        break

                    case .streamEnd:
                        streamingCoordinator.stopStreaming()

                    case .message(let message):
                        messages.append(message)

                    case .error(let msg):
                        errorMessage = msg
                    }
                }

                isLoading = false
                currentTask = nil

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
