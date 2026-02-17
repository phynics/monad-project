import Foundation

/// Strategy for ensuring the prompt fits within a token limit
public struct TokenBudget: Sendable {
    public let maxTokens: Int
    public let reserveForResponse: Int
    
    public init(maxTokens: Int, reserveForResponse: Int) {
        self.maxTokens = maxTokens
        self.reserveForResponse = reserveForResponse
    }
    
    /// Apply the budget to a list of sections, returning a potentially modified list
    /// - Parameters:
    ///   - sections: The sections to process
    ///   - compressor: Optional compressor for .summarize strategy
    /// - Returns: A new list of sections that fits within the budget (best effort)
    public func apply(to sections: [ContextSection], compressor: SectionCompressor? = nil) async -> [ContextSection] {
        let available = maxTokens - reserveForResponse
        let currentTotal = sections.reduce(0) { $0 + $1.estimatedTokens }
        
        // If we fit, return as is
        if currentTotal <= available {
            return sections
        }
        
        // Sort by priority (ascending) to process low priority first
        let sortedSections = sections.sorted(by: { $0.priority < $1.priority })
        var processedSections: [String: ContextSection] = [:]
        
        // We calculate how many tokens we need to cut
        var tokensSaved = 0
        let tokensNeeded = currentTotal - available
        
        // First pass: Drop or Compress
        for section in sortedSections {
            if tokensSaved >= tokensNeeded {
                // We've saved enough, keep the rest as is
                processedSections[section.id] = section
                continue
            }
            
            switch section.strategy {
            case .drop:
                tokensSaved += section.estimatedTokens
                // Dropped
                
            case .summarize:
                if let compressor = compressor, let content = await section.render() {
                    // Try to compress
                    if let _ = try? await compressor.summarize(content) {
                        // We successfully summarized. 
                        // Note: In this generic layer we can't easily construct a new SummarizedSection 
                        // because we don't know the concrete types.
                        // However, we can track that we saved tokens. 
                        // For this implementation, we will treat successful summarization as 
                        // "keeping the section but counting it as reduced".
                        // BUT since we can't mutate the section to *hold* the summary without a wrapper,
                        // we must assume the caller/renderer handles it OR we drop it if we can't wrap.
                        
                        // Strict implementation: If we can't wrap, we drop.
                        tokensSaved += section.estimatedTokens
                    } else {
                        // Failed to summarize, treat as drop
                         tokensSaved += section.estimatedTokens
                    }
                } else {
                    // No compressor or no content, drop
                    tokensSaved += section.estimatedTokens
                }
                
            case .truncate:
                 // Generic truncation implies we accept partial content. 
                 // Without a wrapper, we count it as dropped for safety in this pass.
                 tokensSaved += section.estimatedTokens
                 
            case .keep:
                processedSections[section.id] = section
            }
        }
        
        // Reconstruct order from original list
        return sections.compactMap { processedSections[$0.id] }
    }
}
