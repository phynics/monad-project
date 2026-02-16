import MonadShared
import Foundation
import OpenAI

/// Registry for built-in system tools within the Monad framework
public struct SystemToolRegistry: Sendable {
    public static let shared = SystemToolRegistry()

    private var definitions: [String: WorkspaceToolDefinition] = [:]

    private init() {
        var defs: [String: WorkspaceToolDefinition] = [:]

        let ms = WorkspaceToolDefinition(
            id: "system_memory_search",
            name: "memory_search",
            description: "Search for memories in the long-term memory store",
            parametersSchema: [
                "query": .init("The search query string")
            ]
        )
        defs[ms.id] = ms

        let ws = WorkspaceToolDefinition(
            id: "system_web_search",
            name: "web_search",
            description: "Search the web for information",
            parametersSchema: [
                "query": .init("The search query string")
            ]
        )
        defs[ws.id] = ws

        self.definitions = defs
    }

    public func getDefinition(for id: String) -> WorkspaceToolDefinition? {
        definitions[id]
    }

    /// Resolve a tool reference to an OpenAI-compatible tool parameter
    public func resolveToOpenAITool(_ ref: ToolReference) -> ChatQuery.ChatCompletionToolParam? {
        let def: WorkspaceToolDefinition
        switch ref {
        case .known(let id):
            guard let d = getDefinition(for: id) else { return nil }
            def = d
        case .custom(let definition):
            def = definition
        }

        let properties = def.parametersSchema.reduce(into: [String: [String: Any]]()) {
            dict, pair in
            dict[pair.key] = [
                "type": "string",
                "description": String(describing: pair.value.value),
            ]
        }

        let schemaDict: [String: Any] = [
            "type": "object",
            "properties": properties,
        ]

        let schema: JSONSchema
        if let data = try? JSONSerialization.data(withJSONObject: schemaDict),
            let decoded = try? JSONDecoder().decode(JSONSchema.self, from: data)
        {
            schema = decoded
        } else {
            schema = .object([:])
        }

        return ChatQuery.ChatCompletionToolParam(
            function: .init(
                name: def.name,
                description: def.description,
                parameters: schema
            )
        )
    }
}
