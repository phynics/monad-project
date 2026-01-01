import Foundation

/// Protocol for prompt components that can be added to the prompt builder
protocol PromptSection: Sendable {
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
struct SystemInstructionsComponent: PromptSection {
    let sectionId = "system"
    let priority = 100
    let instructions: String

    func generateContent() async -> String? {
        guard !instructions.isEmpty else { return nil }
        return """
            # System Instructions

            \(instructions)
            """
    }

    var estimatedTokens: Int {
        TokenEstimator.estimate(text: instructions)
    }
}

/// Context notes component
struct ContextNotesComponent: PromptSection {
    let sectionId = "context_notes"
    let priority = 90
    let notes: [Note]

    func generateContent() async -> String? {
        guard !notes.isEmpty else { return nil }

        // Use Note's promptString (PromptFormattable protocol)
        let notesText = notes.map { $0.promptString }.joined(separator: "\n\n")

        return """
            # Context Notes

            \(notesText)
            """
    }

    var estimatedTokens: Int {
        notes.reduce(0) { $0 + TokenEstimator.estimate(text: $1.content) }
    }
}

/// Available tools component
struct ToolsComponent: PromptSection {
    let sectionId = "tools"
    let priority = 80
    let tools: [Tool]

    func generateContent() async -> String? {
        guard !tools.isEmpty else { return nil }

        // Use Tool's formatToolsForPrompt function
        return await formatToolsForPrompt(tools)
    }

    var estimatedTokens: Int {
        tools.count * 50  // Rough estimate
    }
}

/// Chat history component
struct ChatHistoryComponent: PromptSection {
    let sectionId = "chat_history"
    let priority = 70
    let messages: [Message]

    func generateContent() async -> String? {
        // History is handled separately in message array
        return nil
    }

    var estimatedTokens: Int {
        messages.reduce(0) { $0 + TokenEstimator.estimate(text: $1.content) }
    }
}

/// User query component
struct UserQueryComponent: PromptSection {
    let sectionId = "user_query"
    let priority = 10
    let query: String

    func generateContent() async -> String? {
        guard !query.isEmpty else { return nil }
        return query
    }

    var estimatedTokens: Int {
        TokenEstimator.estimate(text: query)
    }
}
