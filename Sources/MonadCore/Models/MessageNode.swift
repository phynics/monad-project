import Foundation

/// Content of a message node - either a message or a compactification
public enum NodeContent: Sendable, Equatable {
    case message(Message)
    case compaction(CompactificationNode)

    public var id: UUID {
        switch self {
        case .message(let msg): return msg.id
        case .compaction(let node): return node.id
        }
    }
}

/// A node in the message forest (tree structure)
public struct MessageNode: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var content: NodeContent
    public var children: [MessageNode]

    // MARK: - Initializers

    public init(content: NodeContent, children: [MessageNode] = []) {
        self.id = content.id
        self.content = content
        self.children = children
    }

    /// Convenience initializer for message content
    public init(message: Message, children: [MessageNode] = []) {
        self.id = message.id
        self.content = .message(message)
        self.children = children
    }

    /// Convenience initializer for compaction content
    public init(compaction: CompactificationNode, children: [MessageNode] = []) {
        self.id = compaction.id
        self.content = .compaction(compaction)
        self.children = children
    }

    // MARK: - Legacy Compatibility

    /// Access the message directly (for backward compatibility)
    /// Returns nil if this is a compaction node
    public var message: Message? {
        if case .message(let msg) = content {
            return msg
        }
        return nil
    }

    // MARK: - Flattening Methods

    /// Flatten for LLM context - uses summaries for compacted nodes
    public func flattenedForContext() -> [Message] {
        switch content {
        case .message(let msg):
            var result = [msg]
            for child in children {
                result.append(contentsOf: child.flattenedForContext())
            }
            return result

        case .compaction(let node):
            // Return summary as system message, skip children
            let summaryMsg = Message(
                id: node.id,
                content: node.summary,
                role: .system,
                isSummary: true
            )
            return [summaryMsg]
        }
    }

    /// Flatten for UI display - includes compaction indicators
    public func flattenedForDisplay() -> [(message: Message, isCompacted: Bool)] {
        switch content {
        case .message(let msg):
            var result: [(Message, Bool)] = [(msg, false)]
            for child in children {
                result.append(contentsOf: child.flattenedForDisplay())
            }
            return result

        case .compaction(let node):
            // Return display hint as indicator, then children
            let displayMsg = Message(
                id: node.id,
                content: node.displayHint,
                role: .system,
                isSummary: true
            )
            var result: [(Message, Bool)] = [(displayMsg, true)]
            for child in children {
                result.append(contentsOf: child.flattenedForDisplay())
            }
            return result
        }
    }

    /// Flatten for history/debug - expands all children
    public func flattenedForHistory() -> [Message] {
        switch content {
        case .message(let msg):
            var result = [msg]
            for child in children {
                result.append(contentsOf: child.flattenedForHistory())
            }
            return result

        case .compaction(_):
            // Skip compaction node itself, just return children
            var result: [Message] = []
            for child in children {
                result.append(contentsOf: child.flattenedForHistory())
            }
            return result
        }
    }

    /// Legacy flatten method - uses context flattening for backward compatibility
    public func flattened() -> [Message] {
        flattenedForContext()
    }
}

// MARK: - Array Extension

extension Array where Element == MessageNode {
    /// Flatten a forest for LLM context
    public func flattenedForContext() -> [Message] {
        self.flatMap { $0.flattenedForContext() }
    }

    /// Flatten a forest for UI display
    public func flattenedForDisplay() -> [(message: Message, isCompacted: Bool)] {
        self.flatMap { $0.flattenedForDisplay() }
    }

    /// Flatten a forest for history/debug
    public func flattenedForHistory() -> [Message] {
        self.flatMap { $0.flattenedForHistory() }
    }

    /// Legacy flatten - uses context flattening
    public func flattened() -> [Message] {
        self.flatMap { $0.flattened() }
    }

    /// Construct a forest from a flat list of messages using parentId links
    public static func constructForest(from messages: [Message]) -> [MessageNode] {
        var nodes: [UUID: MessageNode] = [:]
        var roots: [MessageNode] = []

        // 1. Create all nodes first
        for msg in messages {
            nodes[msg.id] = MessageNode(message: msg)
        }

        // 2. Link children to parents or identify as root
        // Important: maintain chronological order from the original messages array
        for msg in messages {
            guard let node = nodes[msg.id] else { continue }

            if let parentId = msg.parentId, var parentNode = nodes[parentId] {
                parentNode.children.append(node)
                nodes[parentId] = parentNode  // Update the map with modified parent
            } else {
                // No parent found in this set, treat as root
                roots.append(node)
            }
        }

        // Root nodes need to be updated with their linked children from the map
        return roots.map { root in
            updateNodeFromMap(root, map: nodes)
        }
    }

    private static func updateNodeFromMap(_ node: MessageNode, map: [UUID: MessageNode])
        -> MessageNode
    {
        guard let updatedNode = map[node.id] else { return node }
        var nodeWithUpdatedChildren = updatedNode
        nodeWithUpdatedChildren.children = updatedNode.children.map {
            updateNodeFromMap($0, map: map)
        }
        return nodeWithUpdatedChildren
    }
}
