import Foundation

/// Represents a fully assembled LLM prompt consisting of multiple ordered sections.
/// Sections are automatically sorted based on their cache policy and priority upon initialization.
public struct Prompt: Sendable {
    /// The ordered collection of sections that make up the prompt.
    public let sections: [ContextSection]

    /// Initializes a new prompt from an array of sections.
    /// - Parameter sections: The raw sections to include. They will be sorted for optimal prompt construction.
    public init(sections: [ContextSection]) {
        self.sections = sections.sorted {
            if $0.cachePolicy != $1.cachePolicy {
                return $0.cachePolicy < $1.cachePolicy // stable < semiStable < volatile
            }
            return $0.priority > $1.priority
        }
    }

    /// Initializes a new prompt using a declarative `@ContextBuilder` block.
    /// - Parameter content: A closure that returns an array of sections.
    public init(@ContextBuilder _ content: () -> [ContextSection]) {
        self.init(sections: content())
    }

    /// Renders the full prompt string by joining all non-empty sections with delimiters.
    /// - Returns: The final rendered prompt string.
    public func render() async -> String {
        var parts: [String] = []
        for section in sections {
            if let content = await section.render(), !content.isEmpty {
                parts.append(content)
            }
        }
        return parts.joined(separator: "\n\n---\n\n")
    }

    /// Generates a structured representation of the prompt sections for logging or analysis.
    /// - Returns: A dictionary mapping section IDs to their rendered content.
    public func structuredContext() async -> [String: String] {
        var context: [String: String] = [:]
        for section in sections {
            if let content = await section.render(), !content.isEmpty {
                context[section.id] = content
            }
        }
        return context
    }

    /// An estimate of the total number of tokens for all sections in the prompt.
    public var estimatedTokens: Int {
        sections.reduce(0) { $0 + $1.estimatedTokens }
    }
}
