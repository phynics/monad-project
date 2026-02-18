import Foundation
import MonadShared
import MonadPrompt

/// System instructions wrapper
public struct SystemInstructions: ContextSection {
    public let id = "system"
    public let priority = 100
    public let strategy: CompressionStrategy = .keep
    public let type: ContextSectionType = .text
    public let instructions: String
    
    public init(_ instructions: String) {
        self.instructions = instructions
    }
    
    public func render() async -> String? {
        guard !instructions.isEmpty else { return nil }
        return """
            # System Instructions
            
            \(instructions)
            """
    }
    
    public var estimatedTokens: Int {
        TokenEstimator.estimate(text: instructions)
    }
}



/// Memories wrapper
public struct Memories: ContextSection {
    public let id = "memories"
    public let priority = 85
    public let strategy: CompressionStrategy = .summarize
    public let type: ContextSectionType = .list(items: [])
    public let memories: [Memory]
    public let summarizedContent: String?
    
    public init(_ memories: [Memory], summarizedContent: String? = nil) {
        self.memories = memories
        self.summarizedContent = summarizedContent
    }
    
    public func render() async -> String? {
        if let summary = summarizedContent {
            return """
            === MEMORY CONTEXT (SUMMARIZED) ===
            \(summary)
            """
        }
        
        if memories.isEmpty { return nil }
        
        return """
            Found \(memories.count) relevant memories:
            
            \(memories.promptContent)
            """
    }
    
    public var estimatedTokens: Int {
        if let summary = summarizedContent {
            return TokenEstimator.estimate(text: summary)
        }
        return TokenEstimator.estimate(parts: memories.map(\.content))
    }
}

/// Tools wrapper
public struct Tools: ContextSection {
    public let id = "tools"
    public let priority = 80
    public let strategy: CompressionStrategy = .keep 
    public let type: ContextSectionType = .list(items: [])
    public let tools: [AnyTool]
    
    public init(_ tools: [AnyTool]) {
        self.tools = tools
    }
    
    public func render() async -> String? {
        guard !tools.isEmpty else { return nil }
        return await formatToolsForPrompt(tools)
    }
    
    public var estimatedTokens: Int {
        tools.count * 50 // Rough estimate
    }
}

/// Chat History wrapper
public struct ChatHistory: ContextSection {
    public let id = "chat_history"
    public let priority = 70
    public let strategy: CompressionStrategy = .truncate(tail: false) // Crop from start (oldest)
    public let type: ContextSectionType = .list(items: [])
    public let messages: [Message]
    
    public init(_ messages: [Message]) {
        self.messages = messages
    }
    
    public func render() async -> String? {
        // Special case: History isn't rendered into system prompt text usually, 
        // it's handled as messages array. But for debug or raw prompt, we render it.
        // For actual LLM calls, LLMService handles message conversion.
        return nil
    }
    
    public var estimatedTokens: Int {
        TokenEstimator.estimate(parts: messages.map(\.content))
    }
    
    public func constrained(to tokens: Int) -> ContextSection {
        guard estimatedTokens > tokens else { return self }
        
        var accumulated = 0
        var keepCount = 0
        
        // Keep newest messages first (iterate backwards)
        for message in messages.reversed() {
            // Rough estimate per message including overhead
            let count = TokenEstimator.estimate(text: message.content) + 10 
            if accumulated + count > tokens {
                break
            }
            accumulated += count
            keepCount += 1
        }
        
        // If we can't keep any messages but limit is > 0, keep at least the very last one if possible?
        // Or just return empty. 
        // Strict adherence to budget means return what fits.
        // If query is huge, history might be 0.
        
        let subset = Array(messages.suffix(keepCount))
        return ChatHistory(subset)
    }
}

public struct ContextNotes: ContextSection {
    public let id = "context_notes"
    public let priority = 90
    public let strategy: CompressionStrategy = .truncate(tail: true)
    public let type: ContextSectionType = .list(items: []) 
    public let notes: [ContextFile]
    
    public init(_ notes: [ContextFile]) {
        self.notes = notes
    }
    
    public func render() async -> String? {
        guard !notes.isEmpty else { return nil }
        
        let notesText = notes.map { note in
            """
            [File: \(note.name) (\(note.source))]
            \(note.content)
            """
        }.joined(separator: "\n\n")
        
        return """
            The following context files contain important information about the user, the project, and your persona. Use them to provide accurate and personalized responses.
            
            You can edit or create new files in the `Notes/` directory to store long-term information.
            
            \(notesText)
            """
    }
    
    public func render(constrainedTo tokens: Int?) async -> String? {
        guard let tokens = tokens else { return await render() }
        guard var fullText = await render() else { return nil }
        
        let estimated = TokenEstimator.estimate(text: fullText)
        if estimated <= tokens { return fullText }
        
        // Truncate
        // Simple char approximation: tokens * 4
        let charLimit = tokens * 4
        if fullText.count > charLimit {
            fullText = String(fullText.prefix(charLimit)) + "\n... [Truncated]"
        }
        return fullText
    }
    
    public var estimatedTokens: Int {
        TokenEstimator.estimate(parts: notes.map(\.content))
    }
}

/// User Query wrapper
public struct UserQuery: ContextSection {
    public let id = "user_query"
    public let priority = 10
    public let strategy: CompressionStrategy = .keep
    public let type: ContextSectionType = .text
    public let query: String
    
    public init(_ query: String) {
        self.query = query
    }
    
    public func render() async -> String? {
        guard !query.isEmpty else { return nil }
        return query
    }
    
    public var estimatedTokens: Int {
        TokenEstimator.estimate(text: query)
    }
}
