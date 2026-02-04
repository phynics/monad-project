import Foundation
import MonadCore

/// A Tool implementation that delegates execution to a ToolRouter
public struct DelegatingTool: MonadCore.Tool {
    public let ref: ToolReference
    private let router: ToolRouter
    private let sessionId: UUID
    private let resolvedDefinition: WorkspaceToolDefinition

    public init(
        ref: ToolReference,
        router: ToolRouter,
        sessionId: UUID,
        resolvedDefinition: WorkspaceToolDefinition
    ) {
        self.ref = ref
        self.router = router
        self.sessionId = sessionId
        self.resolvedDefinition = resolvedDefinition
    }

    // MARK: - Tool Protocol

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

    public var parametersSchema: [String: Any] {
        // Convert [String: AnyCodable] to [String: Any]
        var schema: [String: Any] = [:]
        for (key, value) in resolvedDefinition.parametersSchema {
            schema[key] = value.value
        }
        return schema
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        // Convert [String: Any] back to [String: AnyCodable]
        var args: [String: AnyCodable] = [:]
        for (key, value) in parameters {
            args[key] = AnyCodable(value)
        }

        do {
            let output = try await router.execute(tool: ref, arguments: args, sessionId: sessionId)
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
