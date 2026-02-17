import Foundation

/// Represents a fully assembled prompt consisting of multiple sections
public struct Prompt: Sendable {
    public let sections: [ContextSection]
    
    public init(sections: [ContextSection]) {
        self.sections = sections.sorted(by: { $0.priority > $1.priority })
    }
    
    public init(@ContextBuilder _ content: () -> [ContextSection]) {
        self.init(sections: content())
    }
    
    /// Render the full prompt string, joining sections with standard delimiters
    public func render() async -> String {
        var parts: [String] = []
        for section in sections {
            if let content = await section.render(), !content.isEmpty {
                parts.append(content)
            }
        }
        return parts.joined(separator: "\n\n---\n\n")
    }
    
    /// Generate a structured dictionary of section contents for debugging/logging
    public func structuredContext() async -> [String: String] {
        var context: [String: String] = [:]
        for section in sections {
            if let content = await section.render(), !content.isEmpty {
                context[section.id] = content
            }
        }
        return context
    }
    
    /// Total estimated tokens for all sections
    public var estimatedTokens: Int {
        sections.reduce(0) { $0 + $1.estimatedTokens }
    }
}
