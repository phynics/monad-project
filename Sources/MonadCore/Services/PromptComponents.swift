import Foundation

/// Protocol for prompt components that can be added to the prompt builder
public protocol PromptSection: Sendable {
    /// The section identifier
    var sectionId: String { get }

    /// Priority for ordering (higher = earlier in prompt)
    var priority: Int { get }

    /// Generate the text content for this component
    func generateContent() async -> String?

    /// Estimated tokens for this component
    var estimatedTokens: Int { get }
}

/// System instructions component
public struct SystemInstructionsComponent: PromptSection {
    public let sectionId = "system"
    public let priority = 100
    public let instructions: String

    public init(instructions: String) {
        self.instructions = instructions
    }

    public func generateContent() async -> String? {
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

/// Context notes component
public struct ContextNotesComponent: PromptSection {
    public let sectionId = "context_notes"
    public let priority = 90
    public let notes: [ContextFile]

    public init(notes: [ContextFile]) {
        self.notes = notes
    }

    public func generateContent() async -> String? {
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
            Examples:
            You can edit or create new files in the `Notes/` directory to store long-term information.

            \(notesText)
            """
    }

    public var estimatedTokens: Int {
        TokenEstimator.estimate(parts: notes.map(\.content))
    }
}

/// Relevant memories component (Semantic Context)
public struct MemoriesComponent: PromptSection {
    public let sectionId = "memories"
    public let priority = 85  // Higher than tools, lower than context notes
    public let memories: [Memory]
    public let summarizedContent: String?

    public init(memories: [Memory], summarizedContent: String? = nil) {
        self.memories = memories
        self.summarizedContent = summarizedContent
    }

    public func generateContent() async -> String? {
        if let summary = summarizedContent {
            return """
            === MEMORY CONTEXT (SUMMARIZED) ===
            \(summary)
            """
        }

        if memories.isEmpty {
            return nil
        }

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

/// Available tools component
public struct ToolsComponent: PromptSection {
    public let sectionId = "tools"
    public let priority = 80
    public let tools: [Tool]

    public init(tools: [Tool]) {
        self.tools = tools
    }

    public func generateContent() async -> String? {
        guard !tools.isEmpty else { return nil }

        // Use Tool's formatToolsForPrompt function
        return await formatToolsForPrompt(tools)
    }

    public var estimatedTokens: Int {
        tools.count * 50  // Rough estimate
    }
}

/// Chat history component
public struct ChatHistoryComponent: PromptSection {
    public let sectionId = "chat_history"
    public let priority = 70
    public let messages: [Message]

    public init(messages: [Message]) {
        self.messages = messages
    }

    public func generateContent() async -> String? {
        // History is handled separately in message array
        return nil
    }

    public var estimatedTokens: Int {
        TokenEstimator.estimate(parts: messages.map(\.content))
    }
}

/// User query component
public struct UserQueryComponent: PromptSection {
    public let sectionId = "user_query"
    public let priority = 10
    public let query: String

    public init(query: String) {
        self.query = query
    }

    public func generateContent() async -> String? {
        guard !query.isEmpty else { return nil }
        return query
    }

    public var estimatedTokens: Int {
        TokenEstimator.estimate(text: query)
    }
}
