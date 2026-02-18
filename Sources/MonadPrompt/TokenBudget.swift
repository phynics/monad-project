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
        
        // We need to cut tokens.
        // Allocation strategy:
        // 1. Sort sections by priority (Highest first).
        // 2. Allocate budget to high priority sections.
        // 3. If a section doesn't fit:
        //    - If .keep: Allocate anyway (blow budget? or consume remaining?)
        //      -> We'll assume .keep MUST be kept. If it exceeds budget, we just go over.
        //    - If .truncate: Give it remaining budget.
        //    - If .drop: Drop it.
        //    - If .summarize: Treat as drop for now (unless we have async summary size est, which we don't efficiently).
        
        // Map original index to section for stability
        let indexedSections = sections.enumerated().map { (index: $0.offset, section: $0.element) }
        let sortedByPriority = indexedSections.sorted { $0.section.priority > $1.section.priority }
        
        var decisions: [Int: SectionDecision] = [:]
        var remainingBudget = available
        
        // First pass: Allocate .keep sections regardless of budget (they are mandatory-ish)
        // Wait, if we have 8000 tokens, and System (Keep, 1000) + User (Keep, 100) -> 1100.
        // If we prioritize strict budget, we might need to error out if Keep exceeds budget?
        // Let's assume .keep sections consume budget first.
        
        // Revised Allocation:
        // Iterate Priority High -> Low.
        
        for (index, section) in sortedByPriority {
            let size = section.estimatedTokens
            
            if size <= remainingBudget {
                // It fits
                decisions[index] = .keepOriginal
                remainingBudget -= size
            } else {
                // Doesn't fit completely
                switch section.strategy {
                case .keep:
                    // Must keep. We go into debt if needed (or consume all remaining)
                    // We'll consume all remaining and technically go over budget, 
                    // as we can't truncate .keep
                    decisions[index] = .keepOriginal
                    remainingBudget -= size
                    
                case .truncate:
                    if remainingBudget > 0 {
                        // Squeeze it in
                        decisions[index] = .constrain(limit: remainingBudget)
                        remainingBudget = 0
                    } else {
                        // No budget left
                        decisions[index] = .drop
                    }
                    
                case .summarize:
                    // If we had a compressor and logic to "summarize to X", we'd use it.
                    // For now, if full content doesn't fit, we drop.
                    decisions[index] = .drop
                    
                case .drop:
                    decisions[index] = .drop
                }
            }
        }
        
        // Second pass: Reconstruct in original order
        var result: [ContextSection] = []
        for (index, section) in indexedSections {
            guard let decision = decisions[index] else {
                // Should not happen, but default to drop if missing
                continue
            }
            
            switch decision {
            case .keepOriginal:
                result.append(section)
            case .constrain(let limit):
                result.append(section.constrained(to: limit))
            case .drop:
                break // Skip
            }
        }
        
        return result
    }
    
    private enum SectionDecision {
        case keepOriginal
        case constrain(limit: Int)
        case drop
    }
}
