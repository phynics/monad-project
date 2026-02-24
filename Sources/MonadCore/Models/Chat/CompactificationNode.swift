import Foundation

/// Type of compactification node
public enum CompactificationType: String, Codable, Sendable {
    /// Single tool call + response pair
    case toolExecution
    /// Group of consecutive tool executions (UI grouping)
    case toolLoop
    /// Meta-summary when token threshold exceeded
    case broad
}

/// A node that compacts multiple messages into a summary for context purposes
public struct CompactificationNode: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var type: CompactificationType

    /// Compact summary for LLM context
    public var summary: String

    /// Display hint for UI (more verbose)
    public var displayHint: String

    /// IDs of grouped messages (or other compactification nodes)
    public var childIds: [UUID]

    /// Additional metadata (e.g., tool name, topic)
    public var metadata: [String: String]

    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        type: CompactificationType,
        summary: String,
        displayHint: String? = nil,
        childIds: [UUID],
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.summary = summary
        self.displayHint = displayHint ?? summary
        self.childIds = childIds
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

// MARK: - Factory Methods

extension CompactificationNode {
    /// Create a tool execution summary from a tool call and its result
    public static func toolExecution(
        toolName: String,
        arguments: [String: Any],
        resultSummary: String,
        callMessageId: UUID,
        responseMessageId: UUID
    ) -> CompactificationNode {
        let argsSummary = arguments.keys.sorted().prefix(3).joined(separator: ", ")
        let summary = "[\(toolName)(\(argsSummary))] → \(resultSummary.prefix(100))"

        return CompactificationNode(
            type: .toolExecution,
            summary: summary,
            displayHint: "[\(toolName)] \(resultSummary.prefix(200))",
            childIds: [callMessageId, responseMessageId],
            metadata: ["tool": toolName]
        )
    }

    /// Create a tool loop grouping from consecutive executions
    public static func toolLoop(
        executionNodes: [CompactificationNode]
    ) -> CompactificationNode {
        let summaries = executionNodes.map { $0.summary }.joined(separator: "\n")
        let toolCount = executionNodes.count
        let tools = executionNodes.compactMap { $0.metadata["tool"] }.joined(separator: ", ")

        return CompactificationNode(
            type: .toolLoop,
            summary: summaries,
            displayHint: "📦 Tool Loop (\(toolCount) tools): \(tools)",
            childIds: executionNodes.map { $0.id },
            metadata: ["count": String(toolCount)]
        )
    }

    /// Create a broad summary from LLM-generated content
    public static func broad(
        summary: String,
        compactedNodeIds: [UUID]
    ) -> CompactificationNode {
        return CompactificationNode(
            type: .broad,
            summary: summary,
            displayHint: "📋 Conversation Summary",
            childIds: compactedNodeIds,
            metadata: [:]
        )
    }
}
