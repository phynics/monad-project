import Foundation
import GRDB

/// Context note injected into prompts
///
/// Notes are text blocks that provide context to the LLM. They can be:
/// - Always appended to every prompt (alwaysAppend = true)
/// - Selectively included based on search/relevance
/// - Read-only for system/protected notes
/// - Searchable by name, description, and content
public struct Note: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord, Sendable {
    public var id: UUID

    /// Display name of the note
    public var name: String

    /// Brief description of what this note contains
    public var description: String

    /// The actual content to inject into context
    public var content: String

    /// If true, note cannot be edited or deleted (for system notes)
    public var isReadonly: Bool

    /// If true, always append to every prompt (for critical context)
    public var alwaysAppend: Bool

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        content: String,
        isReadonly: Bool = false,
        alwaysAppend: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.content = content
        self.isReadonly = isReadonly
        self.alwaysAppend = alwaysAppend
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Search

extension Note {
    /// Check if note matches search query
    /// - Parameter query: Search string to match against name, description, or content
    /// - Returns: True if note matches query
    public func matches(query: String) -> Bool {
        guard !query.isEmpty else { return true }

        let lowercased = query.lowercased()
        return name.lowercased().contains(lowercased)
            || description.lowercased().contains(lowercased)
            || content.lowercased().contains(lowercased)
    }
}

// MARK: - Prompt Formatting

extension Note: PromptFormattable {
    /// Formatted content for inclusion in LLM prompt
    public var promptString: String {
        var parts: [String] = []

        // Title
        parts.append("# \(name)")

        // Description (if present)
        if !description.isEmpty {
            parts.append(description)
        }

        // Content
        parts.append(content)

        return parts.joined(separator: "\n")
    }
}

extension Array where Element == Note {
    /// Format multiple notes for prompt inclusion
    public var promptContent: String {
        guard !isEmpty else { return "" }

        return """
            These notes that are marked 'always append'.

            \(map { $0.promptString }.joined(separator: "\n\n"))
            """
    }
}
