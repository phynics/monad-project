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
}

// Default implementations
public extension ContextSection {
    var strategy: CompressionStrategy { .keep }
    var type: ContextSectionType { .text }
}
