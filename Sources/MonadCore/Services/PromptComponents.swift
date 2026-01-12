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
            The following context notes contain important information about the user, the project, and your persona. Use them to provide accurate and personalized responses.

            \(notesText)
            """
    }

    public var estimatedTokens: Int {
        notes.reduce(0) { $0 + TokenEstimator.estimate(text: $1.content) }
    }
}

/// Relevant memories component (Semantic Context)
public struct MemoriesComponent: PromptSection {
    public let sectionId = "memories"
    public let priority = 85 // Higher than tools, lower than context notes
    public let memories: [Memory]

    public init(memories: [Memory]) {
        self.memories = memories
    }

    public func generateContent() async -> String? {
        if memories.isEmpty {
            return """
                No relevant memories found for this query.
                
                Memories are persistent facts, preferences, or notes about the user and past interactions that are stored in your long-term memory. You can create new memories using the `create_memory` tool or edit existing ones with `edit_memory`. 
                
                When creating or editing memories:
                - Compress the content to be concise but informative.
                - Use "quotes" around specific phrases or terms that might be useful to reference-back later for exact matching or clarity.
                
                Always use these tools to store important information that should be remembered across different chat sessions.
                """
        }

        // Use Memory array extension
        return memories.promptContent
    }

    public var estimatedTokens: Int {
        memories.reduce(0) { $0 + TokenEstimator.estimate(text: $1.content) }
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

/// Loaded documents component
public struct DocumentsComponent: PromptSection {
    public let sectionId = "documents"
    public let priority = 95 // High priority, below system instructions
    public let documents: [DocumentContext]

    public init(documents: [DocumentContext]) {
        self.documents = documents
    }

    public func generateContent() async -> String? {
        guard !documents.isEmpty else { return nil }

        let parts = documents.map { doc in
            """
            DOCUMENT: `\(doc.path)`
            \(doc.visibleContent)
            """
        }

        return """
            === ACTIVE DOCUMENTS ===
            The following documents are loaded into your context. Use document tools to navigate or search them.

            \(parts.joined(separator: "\n\n---\n\n"))
            """
    }

    public var estimatedTokens: Int {
        documents.reduce(0) { $0 + TokenEstimator.estimate(text: $1.visibleContent) }
    }
}

/// Database directory component
public struct DatabaseDirectoryComponent: PromptSection {
    public let sectionId = "database_directory"
    public let priority = 98 // Very high, just below system instructions
    public let tables: [TableDirectoryEntry]

    public init(tables: [TableDirectoryEntry]) {
        self.tables = tables
    }

    public func generateContent() async -> String? {
        guard !tables.isEmpty else { return nil }

        let tableList = tables.map { "- `\($0.name)`\($0.description.isEmpty ? "" : ": \($0.description)")" }.joined(separator: "\n")

        return """
            === DATABASE DIRECTORY ===
            The following tables are available in your local SQLite database. You can manage and query them using `execute_sql`.
            
            \(tableList)
            """
    }

    public var estimatedTokens: Int {
        tables.count * 20 // Rough estimate
    }
}
