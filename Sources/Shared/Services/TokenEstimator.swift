import Foundation

/// Utility for rough token estimation (rough mapping of chars to tokens)
public enum TokenEstimator {
    /// Estimate tokens for a string (standard roughly 4 chars per token)
    public static func estimate(text: String) -> Int {
        text.count / 4
    }

    /// Estimate tokens for multiple components
    public static func estimate(parts: [String]) -> Int {
        parts.reduce(0) { $0 + estimate(text: $1) }
    }
}
