import Foundation
import MonadCore

extension PersistenceManager {
    public func addMessage(
        id: UUID? = nil,
        role: ConversationMessage.MessageRole, 
        content: String, 
        recalledMemories: [Memory]? = nil, 
        memoryId: UUID? = nil,
        parentId: UUID? = nil,
        think: String? = nil,
        toolCalls: [ToolCall]? = nil,
        debugInfo: MessageDebugInfo? = nil
    ) async throws {
        guard let session = currentSession else {
            logger.error("Attempted to add message but no active session")
            throw PersistenceError.noActiveSession
        }
        
        let msgId = id ?? UUID()
        if let info = debugInfo {
            debugInfoCache[msgId] = info
        }

        let memoriesJson: String
        if let memories = recalledMemories,
           let data = try? JSONEncoder().encode(memories),
           let str = String(data: data, encoding: .utf8) {
            memoriesJson = str
        } else {
            memoriesJson = "[]"
        }
        
        let callsJson: String
        if let calls = toolCalls,
           let data = try? JSONEncoder().encode(calls),
           let str = String(data: data, encoding: .utf8) {
            callsJson = str
        } else {
            callsJson = "[]"
        }

        let message = ConversationMessage(
            id: msgId,
            sessionId: session.id,
            role: role,
            content: content,
            timestamp: Date(),
            recalledMemories: memoriesJson,
            memoryId: memoryId,
            parentId: parentId,
            think: think,
            toolCalls: callsJson
        )

        try await persistence.saveMessage(message)

        let flatMessages = try await persistence.fetchMessages(for: session.id).map { [weak self] dbMsg -> Message in
            var msg = dbMsg.toMessage()
            if let self = self, let info = self.debugInfoCache[msg.id] {
                msg.debugInfo = info
            }
            return msg
        }
        currentMessages = .constructForest(from: flatMessages)

        var updatedSession = session
        updatedSession.updatedAt = Date()
        try await persistence.saveSession(updatedSession)
        currentSession = updatedSession
    }
    
    public func replaceMessages(with newMessages: [Message]) async throws {
        guard let session = currentSession else { return }
        logger.info("Replacing messages for session \(session.id) (Compression)")
        
        try await persistence.deleteMessages(for: session.id)
        
        for msg in newMessages {
            let dbMsg = ConversationMessage(
                id: msg.id,
                sessionId: session.id,
                role: .init(rawValue: msg.role.rawValue) ?? .user,
                content: msg.content,
                timestamp: msg.timestamp,
                recalledMemories: {
                    if let memories = msg.recalledMemories, let data = try? JSONEncoder().encode(memories) {
                        return String(data: data, encoding: .utf8) ?? "[]"
                    }
                    return "[]"
                }(),
                memoryId: nil,
                parentId: msg.parentId,
                think: msg.think,
                toolCalls: {
                    if let calls = msg.toolCalls, let data = try? JSONEncoder().encode(calls) {
                        return String(data: data, encoding: .utf8) ?? "[]"
                    }
                    return "[]"
                }()
            )
            try await persistence.saveMessage(dbMsg)
        }
        currentMessages = .constructForest(from: newMessages)
    }
}
