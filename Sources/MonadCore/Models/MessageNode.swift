import Foundation

/// A node in the message forest (tree structure)
public struct MessageNode: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var message: Message
    public var children: [MessageNode]
    
    public init(message: Message, children: [MessageNode] = []) {
        self.id = message.id
        self.message = message
        self.children = children
    }
    
    /// Recursively flatten the tree into a linear array
    /// In-order traversal: Parent then children
    public func flattened() -> [Message] {
        var result = [message]
        for child in children {
            result.append(contentsOf: child.flattened())
        }
        return result
    }
}

extension Array where Element == MessageNode {
    /// Flatten a forest of message nodes into a flat array
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
                nodes[parentId] = parentNode // Update the map with modified parent
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
    
    private static func updateNodeFromMap(_ node: MessageNode, map: [UUID: MessageNode]) -> MessageNode {
        guard let updatedNode = map[node.id] else { return node }
        var nodeWithUpdatedChildren = updatedNode
        nodeWithUpdatedChildren.children = updatedNode.children.map { updateNodeFromMap($0, map: map) }
        return nodeWithUpdatedChildren
    }
}
