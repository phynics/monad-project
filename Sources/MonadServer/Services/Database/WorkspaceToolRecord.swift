import Foundation
import GRDB
import PKShared

private enum WorkspaceToolRecordError: Error {
    case missingDefinition
}

struct WorkspaceToolRecord: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workspaceTool"

    let id: UUID
    let workspaceId: UUID
    let toolId: String
    let isKnown: Bool
    let definition: String?

    init(
        id: UUID = UUID(),
        workspaceId: UUID,
        toolReference: ToolReference
    ) throws {
        self.id = id
        self.workspaceId = workspaceId
        toolId = toolReference.toolId

        switch toolReference {
        case .known:
            isKnown = true
            definition = nil
        case let .custom(definition):
            isKnown = false
            let data = try JSONEncoder().encode(definition)
            self.definition = String(data: data, encoding: .utf8)
        }
    }

    func toToolReference() throws -> ToolReference {
        if isKnown {
            return .known(id: toolId)
        }

        guard let definition, let data = definition.data(using: .utf8) else {
            throw WorkspaceToolRecordError.missingDefinition
        }
        let decoded = try JSONDecoder().decode(WorkspaceToolDefinition.self, from: data)
        return .custom(definition: decoded)
    }
}
