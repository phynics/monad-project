import Foundation
import MonadShared

/// A Tool implementation that delegates execution to a ToolRouter
public struct DelegatingTool: Tool, ToolReferenceProviding {
    public let ref: ToolReference
    private let router: ToolRouter
    private let timelineId: UUID
    private let resolvedDefinition: WorkspaceToolDefinition

    public init(
        ref: ToolReference,
        router: ToolRouter,
        timelineId: UUID,
        resolvedDefinition: WorkspaceToolDefinition
    ) {
        self.ref = ref
        self.router = router
        self.timelineId = timelineId
        self.resolvedDefinition = resolvedDefinition
    }

    // MARK: - Tool Protocol

    public var toolReference: ToolReference {
        ref
    }

    public var id: String {
        ref.toolId
    }

    public var name: String {
        resolvedDefinition.name
    }

    public var description: String {
        resolvedDefinition.description
    }

    public var requiresPermission: Bool {
        resolvedDefinition.requiresPermission
    }

    public var usageExample: String? {
        resolvedDefinition.usageExample
    }

    public func canExecute() async -> Bool {
        true  // Assume available if routed
    }

    public var parametersSchema: [String: AnyCodable] {
        resolvedDefinition.parametersSchema
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let args = parameters.mapValues { AnyCodable($0) }

        do {
            let output = try await router.execute(tool: ref, arguments: args, timelineId: timelineId)
            return .success(output)
        } catch let error as ToolError {
            if case .clientExecutionRequired = error {
                throw error
            }
            return .failure(error.localizedDescription)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
