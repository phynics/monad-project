import Foundation
import MonadCore

/// Manages conversation archiving to database
@MainActor
public final class ConversationArchiver {
    private let persistenceManager: PersistenceManager
    private let llmService: LLMService
    private let contextManager: ContextManager

    public init(
        persistenceManager: PersistenceManager,
        llmService: LLMService,
        contextManager: ContextManager
    ) {
        self.persistenceManager = persistenceManager
        self.llmService = llmService
        self.contextManager = contextManager
    }

    /// Archive current conversation to database
    public func archive(messages: [Message]) async throws {
        guard !messages.isEmpty else { return }

        // 1. Performance Evaluation & Embedding Adjustment
        await evaluateAndAdjustEmbeddings(from: messages)

        // 2. Create session if needed
        if persistenceManager.currentSession == nil {
            let title = generateTitle(from: messages)
            try await persistenceManager.createNewSession(title: title)
        }

        // 3. Save and index all messages
        for message in messages {
            // Index user and assistant messages into memories for future semantic retrieval
            var memoryId: UUID? = nil
            if message.role == .user || message.role == .assistant {
                do {
                    let tags = try await llmService.generateTags(for: message.content)
                    let embedding = try await llmService.embeddingService.generateEmbedding(for: message.content)
                    
                    let memory = Memory(
                        title: generateMessageTitle(from: message.content),
                        content: message.content,
                        tags: tags,
                        embedding: embedding
                    )
                    try await persistenceManager.saveMemory(memory)
                    memoryId = memory.id
                } catch {
                    print("Failed to index message as memory: \(error)")
                }
            }

            try await persistenceManager.addMessage(
                role: ConversationMessage.MessageRole(rawValue: message.role.rawValue) ?? .user,
                content: message.content,
                recalledMemories: message.recalledMemories,
                memoryId: memoryId
            )
        }

        // 4. Archive the session
        try await persistenceManager.archiveCurrentSession()
    }

    /// Generate a short title for a message memory
    private func generateMessageTitle(from content: String) -> String {
        let words = content.split(separator: " ").prefix(5)
        return words.joined(separator: " ") + (words.count < 5 ? "" : "...")
    }

    private func evaluateAndAdjustEmbeddings(from messages: [Message]) async {
        // Collect all recalled memories and query vectors from debug info
        var allRecalledMemories: [Memory] = []
        var queryVectors: [[Double]] = []
        var transcriptParts: [String] = []
        
        for msg in messages {
            transcriptParts.append("[\(msg.role.rawValue.uppercased())] \(msg.content)")
            
            if let debug = msg.debugInfo {
                if let memories = debug.contextMemories {
                    for result in memories {
                        if !allRecalledMemories.contains(where: { $0.id == result.memory.id }) {
                            allRecalledMemories.append(result.memory)
                        }
                    }
                }
                if let vector = debug.queryVector, !vector.isEmpty {
                    queryVectors.append(vector)
                }
            }
        }
        
        guard !allRecalledMemories.isEmpty else { return }
        
        let transcript = transcriptParts.joined(separator: "\n\n")
        
        do {
            // Evaluate helpfulness via LLM
            let evaluations = try await llmService.evaluateRecallPerformance(
                transcript: transcript,
                recalledMemories: allRecalledMemories
            )
            
            // Adjust embeddings based on evaluations
            try await contextManager.adjustEmbeddings(
                evaluations: evaluations,
                queryVectors: queryVectors
            )
        } catch {
            print("Failed to evaluate and adjust embeddings: \(error)")
        }
    }

    /// Generate conversation title from messages
    private func generateTitle(from messages: [Message]) -> String {
        if let firstMessage = messages.first(where: { $0.role == .user }) {
            let words = firstMessage.content.split(separator: " ").prefix(6)
            return words.joined(separator: " ") + (words.count < 6 ? "" : "...")
        }
        return "Conversation at \(Date().formatted(date: .abbreviated, time: .shortened))"
    }
}
