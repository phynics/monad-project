import Foundation
import MonadCore

public struct CreateMemoryEdgeTool: Tool {
    public let id = "create_memory_edge"
    public let name = "create_memory_edge"
    public let description = "Links two memories together to establish a relationship. Use this to stabilize context and connect related concepts."
    public let requiresPermission = false

    private let persistenceService: any PersistenceServiceProtocol

    public init(persistenceService: any PersistenceServiceProtocol) {
        self.persistenceService = persistenceService
    }

    public func canExecute() async -> Bool {
        return true
    }

    public var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "source_id": [
                    "type": "string",
                    "description": "The UUID of the source memory."
                ],
                "target_id": [
                    "type": "string",
                    "description": "The UUID of the target memory to link to."
                ],
                "relationship": [
                    "type": "string",
                    "description": "The type of relationship (e.g., 'related_to', 'part_of', 'caused_by', 'requires')."
                ],
                "weight": [
                    "type": "number",
                    "description": "Optional weight of the relationship (0.0 to 1.0). Default is 1.0."
                ]
            ],
            "required": ["source_id", "target_id", "relationship"]
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let sourceIdStr = parameters["source_id"] as? String,
              let targetIdStr = parameters["target_id"] as? String,
              let relationship = parameters["relationship"] as? String
        else {
            return .failure("Missing required parameters: source_id, target_id, or relationship")
        }

        guard let sourceId = UUID(uuidString: sourceIdStr),
              let targetId = UUID(uuidString: targetIdStr)
        else {
            return .failure("Invalid UUID format for source_id or target_id")
        }

        let weight = (parameters["weight"] as? Double) ?? 1.0

        // Verify memories exist
        if (try? await persistenceService.fetchMemory(id: sourceId)) == nil {
            return .failure("Source memory with ID \(sourceId) not found")
        }
        if (try? await persistenceService.fetchMemory(id: targetId)) == nil {
            return .failure("Target memory with ID \(targetId) not found")
        }

        let edge = MemoryEdge(
            sourceId: sourceId,
            targetId: targetId,
            relationship: relationship,
            weight: weight
        )

        do {
            try await persistenceService.saveMemoryEdge(edge)
            return .success("Successfully created memory edge from \(sourceId) to \(targetId) [\(relationship)]")
        } catch {
            return .failure("Failed to create memory edge: \(error.localizedDescription)")
        }
    }
}
