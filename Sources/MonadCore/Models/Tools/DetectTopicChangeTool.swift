import Foundation

/// Tool for the LLM to signal a topic change
public struct DetectTopicChangeTool: Tool, @unchecked Sendable {
    public let id = "mark_topic_change"
    public let name = "Mark Topic Change"
    public let description = "Signal that the conversation topic has changed. Use this when the user shifts focus to a completely new subject."
    public let requiresPermission = false
    
    public var usageExample: String? {
        """
        <tool_call>
        {"name": "mark_topic_change", "arguments": {"new_topic": "SwiftUI Data Flow", "summary": "We discussed Core Data setup and migration strategies...", "reason": "User finished discussing Core Data"}}
        </tool_call>
        """
    }
    
    public init() {}
    
    public func canExecute() async -> Bool {
        return true
    }
    
    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "new_topic": [
                    "type": "string",
                    "description": "The name of the new topic starting now"
                ],
                "summary": [
                    "type": "string",
                    "description": "A brief summary of the previous topic discussion (max 250 words)."
                ],
                "reason": [
                    "type": "string",
                    "description": "Why the topic is considered changed"
                ]
            ],
            "required": ["new_topic", "summary"]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        // This tool is primarily a signal for the system.
        let topic = parameters["new_topic"] as? String ?? "Unknown Topic"
        return .success("Topic change to '\(topic)' noted. Summary recorded.")
    }
}
