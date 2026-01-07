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
    public var activeMemories: [ActiveMemory] = []
    public var isLoading = false
    public var errorMessage: String?
    
    // Startup Logic
    public var showingStartupChoice = false
    public var lastArchivedSession: ConversationSession?

    public let llmService: LLMService
    public let persistenceManager: PersistenceManager
    public let contextManager: ContextManager
    public let documentManager: DocumentManager

    private var currentTask: Task<Void, Never>?
    private var toolManager: SessionToolManager?

    // Service dependencies
    // These must be preserved!
    public let streamingCoordinator: StreamingCoordinator
    public var toolExecutor: ToolExecutor?
    public let conversationArchiver: ConversationArchiver

    private let logger = Logger.chat
    
    public var injectedMemories: [Memory] {
        let pinned = activeMemories.filter { $0.isPinned }
        let unpinned = activeMemories.filter { !$0.isPinned }
            .sorted { $0.lastAccessed > $1.lastAccessed }
            .prefix(llmService.configuration.memoryContextLimit)
        
        return (pinned + Array(unpinned)).map { $0.memory }
    }
    
    public var injectedDocuments: [DocumentContext] {
        return documentManager.getEffectiveDocuments(limit: llmService.configuration.documentContextLimit)
    }

    public init(llmService: LLMService, persistenceManager: PersistenceManager) {
        self.llmService = llmService
        self.persistenceManager = persistenceManager
        self.contextManager = ContextManager(
            persistenceService: persistenceManager.persistence,
            embeddingService: llmService.embeddingService
        )
        self.documentManager = DocumentManager()
        self.streamingCoordinator = StreamingCoordinator()
        self.conversationArchiver = ConversationArchiver(
            persistenceManager: persistenceManager,
            llmService: llmService,
            contextManager: contextManager
        )
        
        Task {
            await checkStartupState()
        }
    }
    
    // MARK: - Active Context Management
    
    public func toggleMemoryPin(id: UUID) {
        if let index = activeMemories.firstIndex(where: { $0.id == id }) {
            activeMemories[index].isPinned.toggle()
        }
    }
    
    public func removeActiveMemory(id: UUID) {
        activeMemories.removeAll { $0.id == id }
    }
    
    private func updateActiveMemories(with newMemories: [Memory]) {
        for memory in newMemories {
            if let index = activeMemories.firstIndex(where: { $0.id == memory.id }) {
                // Already active, just update access time
                activeMemories[index].lastAccessed = Date()
            } else {
                // Add new active memory
                activeMemories.append(ActiveMemory(memory: memory))
            }
        }
    }
    
    // MARK: - Startup Logic
    
    private func checkStartupState() async {
        do {
            if let last = try await persistenceManager.getLastArchivedSession() {
                self.lastArchivedSession = last
                self.showingStartupChoice = true
            } else {
                // No archived session, just start a new one
                try await persistenceManager.createNewSession()
            }
        } catch {
            logger.error("Failed to check startup state: \(error.localizedDescription)")
        }
    }
    
    public func continueLastSession() {
        guard let session = lastArchivedSession else { return }
        Task {
            do {
                try await persistenceManager.unarchiveSession(session)
                messages = persistenceManager.uiMessages
                showingStartupChoice = false
            } catch {
                errorMessage = "Failed to continue session: \(error.localizedDescription)"
            }
        }
    }
    
    public func startNewSession(deleteOld: Bool) {
        Task {
            do {
                if deleteOld, let session = lastArchivedSession {
                    try await persistenceManager.deleteSession(id: session.id)
                }
                // Just create new, old remains archived if not deleted
                try await persistenceManager.createNewSession()
                messages = []
                activeMemories = [] // Clear active memories on new session
                showingStartupChoice = false
            } catch {
                errorMessage = "Failed to start new session: \(error.localizedDescription)"
            }
        }
    }

    public var tools: SessionToolManager {
        if let existing = toolManager {
            return existing
        }

        let availableTools: [MonadCore.Tool] = [
            SearchArchivedChatsTool(persistenceService: persistenceManager.persistence),
            ViewChatHistoryTool(persistenceService: persistenceManager.persistence, currentSessionProvider: { [weak self] in
                await MainActor.run {
                    return self?.persistenceManager.currentSession?.id
                }
            }),
            SearchMemoriesTool(persistenceService: persistenceManager.persistence, embeddingService: llmService.embeddingService),
            CreateMemoryTool(persistenceService: persistenceManager.persistence, embeddingService: llmService.embeddingService),
            SearchNotesTool(persistenceService: persistenceManager.persistence),
            EditNoteTool(persistenceService: persistenceManager.persistence),
            // Filesystem Tools
            ListDirectoryTool(),
            FindFileTool(),
            SearchFileContentTool(),
            ReadFileTool(),
            // Document Tools
            LoadDocumentTool(documentManager: documentManager),
            UnloadDocumentTool(documentManager: documentManager),
            SwitchDocumentViewTool(documentManager: documentManager),
            EditDocumentSummaryTool(documentManager: documentManager),
            MoveDocumentExcerptTool(documentManager: documentManager),
            LaunchSubagentTool(llmService: llmService, documentManager: documentManager)
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
                
                // 2. Perform an initial call to get the raw prompt for the user message debug info
                let (_, initialRawPrompt) = await llmService.chatStreamWithContext(
                    userQuery: prompt,
                    contextNotes: contextData.notes,
                    documents: contextDocuments,
                    memories: contextMemories,
                    chatHistory: Array(messages.prefix(userMessageIndex)),
                    tools: enabledTools
                )

                // Update debug info for the user message
                messages[userMessageIndex].recalledMemories = contextMemories // Log what was actually injected
                messages[userMessageIndex].debugInfo = .userMessage(
                    rawPrompt: initialRawPrompt, 
                    contextMemories: contextData.memories,
                    generatedTags: contextData.generatedTags,
                    queryVector: contextData.queryVector,
                    augmentedQuery: contextData.augmentedQuery,
                    semanticResults: contextData.semanticResults,
                    tagResults: contextData.tagResults
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
            // Note: This path handles cases where runConversationLoop is called without sendMessage
            // But we mainly use sendMessage.
            // For now, assume this follows similar logic for debug info if needed.
            let userMessage = Message(content: prompt, role: .user)
            messages.append(userMessage)
        }

        var shouldContinue = true
        var turnCount = 0
        
        // Use injected memories which are now stable for this turn unless tools change them?
        // Tools like CreateMemory might add new memories. 
        // Ideally we re-evaluate injectedMemories every iteration if we want dynamic updates,
        // but for consistency within a turn, maybe keep them?
        // Requirement says "memories are collected at chat level". If a tool adds a memory, 
        // we might want it to be immediately available.
        // Let's use `injectedMemories` (computed) each time.

        while shouldContinue {
            turnCount += 1
            if turnCount > 10 {
                logger.warning("Conversation loop exceeded max turns (10). Breaking.")
                shouldContinue = false
                break
            }
            
            let contextNotes = try await persistenceManager.fetchAlwaysAppendNotes()
            let enabledTools = tools.getEnabledTools()
            let contextDocuments = injectedDocuments
            let contextMemories = injectedMemories

            // 2. Call LLM with empty userQuery, relying on chatHistory
            let (stream, _) = await llmService.chatStreamWithContext(
                userQuery: "",
                contextNotes: contextNotes,
                documents: contextDocuments,
                memories: contextMemories,
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
