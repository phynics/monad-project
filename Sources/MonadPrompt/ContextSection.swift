import Foundation

/// Defines how a section should be handled when the token budget is exceeded
public enum CompressionStrategy: Sendable {
    /// Never compress this section (e.g. system instructions, critical context)
    case keep
    
    /// Truncate the section if needed
    /// - tail: if true, cut from the end. if false, cut from the beginning.
    case truncate(tail: Bool)
    
    /// Summarize the section content (requires external compressor logic)
    case summarize
    
    /// Omit the section entirely if it doesn't fit
    case drop
}

/// The structural type of the section, used for formatting hints
public enum ContextSectionType: Sendable {
    /// A single block of text
    case text
    
    /// A list of items (e.g. chat messages, search results)
    case list(items: [String])
}

/// A generic section of the prompt context
public protocol ContextSection: Sendable {
    /// Unique identifier for this section type (e.g. "system", "history")
    var id: String { get }
    
    /// Priority for ordering (higher = earlier in prompt/more important)
    var priority: Int { get }
    
    /// Estimated token count for this section
    var estimatedTokens: Int { get }
    
    /// Strategy for handling token budget constraints
    var strategy: CompressionStrategy { get }
    
    /// The type of content this section represents
    var type: ContextSectionType { get }
    
    /// Render the section into a string for the prompt
    func render() async -> String?
    
    /// Render the section, optionally constrained to a specific token limit
    /// - Parameter tokens: Maximum tokens allowed. If nil, no limit.
    /// - Returns: Rendered string, potentially truncated/summarized.
    func render(constrainedTo tokens: Int?) async -> String?
    
    /// Create a version of this section constrained to a token limit
    /// - Parameter tokens: The token limit
    /// - Returns: A new section (either self, a modified copy, or a generic wrapper)
    func constrained(to tokens: Int) -> ContextSection
}

// Default implementations
public extension ContextSection {
    var strategy: CompressionStrategy { .keep }
    var type: ContextSectionType { .text }
    
    func render(constrainedTo tokens: Int?) async -> String? {
        // Default: Ignore limit and render normally
        await render()
    }
    
    func constrained(to tokens: Int) -> ContextSection {
        ConstrainedSection(wrapped: self, limit: tokens)
    }
}

/// A generic wrapper that enforces a token limit on rendering
public struct ConstrainedSection: ContextSection {
    public let wrapped: ContextSection
    public let limit: Int
    
    public var id: String { wrapped.id }
    public var priority: Int { wrapped.priority }
    public var estimatedTokens: Int { min(wrapped.estimatedTokens, limit) }
    public var strategy: CompressionStrategy { wrapped.strategy }
    public var type: ContextSectionType { wrapped.type }
    
    public init(wrapped: ContextSection, limit: Int) {
        self.wrapped = wrapped
        self.limit = limit
    }
    
    public func render() async -> String? {
        await wrapped.render(constrainedTo: limit)
    }
    
    public func render(constrainedTo tokens: Int?) async -> String? {
        let effectiveLimit = tokens.map { min($0, limit) } ?? limit
        return await wrapped.render(constrainedTo: effectiveLimit)
    }
    
    // Recursive update if constrained again
    public func constrained(to tokens: Int) -> ContextSection {
        ConstrainedSection(wrapped: wrapped, limit: min(limit, tokens))
    }
}
