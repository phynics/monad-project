import Foundation
import Logging

/// Policy for vacuuming memories during archival
public enum MemoryVacuumPolicy: Sendable {
    /// Do not run vacuuming.
    case skip
    /// Run vacuuming with the specified threshold.
    case run(threshold: Double)
}

/// Service to archive conversations and index them for semantic recall
public actor ConversationArchiver {
    private let persistence: PersistenceService
    private let llmService: LLMService
    private let contextManager: ContextManager
    private let logger = Logger(label: "com.monad.ConversationArchiver")
    
    public init(persistence: PersistenceService, llmService: LLMService, contextManager: ContextManager) {
        self.persistence = persistence
        self.llmService = llmService
        self.contextManager = contextManager
    }
    
    /// Archive a conversation and index its messages as semantic memories
    @discardableResult
    public func archive(
        messages: [Message], 
        sessionId: UUID?,
        vacuumPolicy: MemoryVacuumPolicy = .run(threshold: 0.95)
    ) async throws -> UUID {
        // 1. Title Generation
        var title = "Archived Conversation"
        if let firstUserMessage = messages.first(where: { $0.role == .user })?.content {
            do {
                title = try await generateTitle(for: firstUserMessage)
            } catch {
                logger.error("Failed to generate descriptive title: \(error.localizedDescription)")
                title = String(firstUserMessage.prefix(40))
            }
        }
        
        // 2. Resolve Session
        let session: ConversationSession
        if let sid = sessionId, let existing = try await persistence.fetchSession(id: sid) {
            var updated = existing
            updated.title = title
            updated.isArchived = true
            updated.updatedAt = Date()
            try await persistence.saveSession(updated)
            session = updated
        } else {
            var newSession = ConversationSession(title: title)
            newSession.isArchived = true
            try await persistence.saveSession(newSession)
            session = newSession
        }
        
        // 3. Index and Save Messages
        for msg in messages {
            var memoryId: UUID?
            
            // Heuristic: Index messages longer than 20 chars as memories
            if msg.content.count > 20 {
                do {
                    let tags = try await llmService.generateTags(for: msg.content)
                    let embedding = try await llmService.embeddingService.generateEmbedding(for: msg.content)
                    
                    let memory = Memory(
                        title: title,
                        content: msg.content,
                        tags: tags,
                        embedding: embedding.map { Double($0) }
                    )
                    // Check similarity to avoid duplicate auto-generated memories
                    memoryId = try await persistence.saveMemory(memory, policy: .preventSimilar(threshold: 0.92))
                } catch {
                    logger.error("Failed to index message as memory: \(error.localizedDescription)")
                }
            }
            
            let conversationMsg = ConversationMessage(
                sessionId: session.id,
                role: .init(rawValue: msg.role.rawValue) ?? .user,
                content: msg.content,
                timestamp: msg.timestamp,
                recalledMemories: "[]",
                memoryId: memoryId,
                parentId: msg.parentId,
                think: msg.think,
                toolCalls: {
                    if let calls = msg.toolCalls, let data = try? JSONEncoder().encode(calls) {
                        return String(data: data, encoding: .utf8) ?? "[]"
                    }
                    return "[]"
                }()
            )
            try await persistence.saveMessage(conversationMsg)
        }
        
        // 4. Update Summary? (Future improvement)
        
        // 5. Memory Vacuum (Cleanup redundancies)
        if case .run(let threshold) = vacuumPolicy {
            _ = try await persistence.vacuumMemories(threshold: threshold)
        }
        
        return session.id
    }
    
    private func generateTitle(for userMessage: String) async throws -> String {
        let utilityClient = await llmService.getUtilityClient()
        let defaultClient = await llmService.getClient()
        guard let client = utilityClient ?? defaultClient else {
            return String(userMessage.prefix(40))
        }
        
        let prompt = """
        Generate a very short, descriptive title (max 5 words) for a conversation that starts with:
        \(userMessage)
        Title:
        """
        
        return try await client.sendMessage(prompt, responseFormat: nil)
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
