import Foundation

/// Protocol for models that can be formatted for inclusion in LLM prompts
protocol PromptFormattable {
    /// Formatted string for inclusion in prompt
    var promptString: String { get }
}
