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
    public let notes: [Note]

    public init(notes: [Note]) {
        self.notes = notes
    }

    public func generateContent() async -> String? {
        guard !notes.isEmpty else { return nil }

        // Use Note's promptString (PromptFormattable protocol)
        let notesText = notes.map { $0.promptString }.joined(separator: "\n\n")

        return """
            _These are notes that you use keep track of important information. These context notes are the ones that are marked "Always Append", there could be more notes you could use to tools to search. You can also edit these notes using edit_note tool. Make sure to use notes for their purpose, and be brief in what you put in your notes. 'Human' note should only include information about the user, 'Persona' block should include information about yourself, etc. This self-editing function will help you grow recursively._

            \(notesText)
            """
    }

    public var estimatedTokens: Int {
        notes.reduce(0) { $0 + TokenEstimator.estimate(text: $1.content) }
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
        messages.reduce(0) { $0 + TokenEstimator.estimate(text: $1.content) }
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
