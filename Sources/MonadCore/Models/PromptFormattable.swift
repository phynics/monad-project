import Foundation

/// Protocol for models that can be formatted for inclusion in LLM prompts
public protocol PromptFormattable {
    /// Formatted string for inclusion in prompt
    var promptString: String { get }
}
