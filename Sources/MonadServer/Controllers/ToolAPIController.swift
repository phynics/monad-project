import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import MonadShared
import NIOCore

public struct ExecuteToolRequest: Codable, Sendable {
    public let timelineId: UUID
    public let name: String
    public let arguments: [String: AnyCodable]

    public init(timelineId: UUID, name: String, arguments: [String: AnyCodable]) {
        self.timelineId = timelineId
        self.name = name
        self.arguments = arguments
    }
}

public struct ToolAPIController<Context: RequestContext>: Sendable {
    public let timelineManager: TimelineManager
    public let toolRouter: ToolRouter

    public init(timelineManager: TimelineManager, toolRouter: ToolRouter) {
        self.timelineManager = timelineManager
        self.toolRouter = toolRouter
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.get("/", use: listSystemTools)
        group.get("/{id}", use: listSessionTools)
        group.post("/execute", use: execute)
        group.post("/{id}/{name}/enable", use: enable)
        group.post("/{id}/{name}/disable", use: disable)
    }

    @Sendable func listSystemTools(_: Request, context _: Context) async throws -> [ToolInfo] {
        let tools = await timelineManager.systemTools()
        return tools.map { ToolInfo(id: $0.id, name: $0.name, description: $0.description) }
    }

    @Sendable func enable(_: Request, context: Context) async throws -> HTTPResponse.Status {
        let idString = try context.parameters.require("id")
        let name = try context.parameters.require("name")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        guard let toolManager = await timelineManager.getToolManager(for: id) else {
            throw HTTPError(.notFound)
        }

        await toolManager.enableTool(id: name)
        return .ok
    }

    @Sendable func disable(_: Request, context: Context) async throws -> HTTPResponse.Status {
        let idString = try context.parameters.require("id")
        let name = try context.parameters.require("name")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        guard let toolManager = await timelineManager.getToolManager(for: id) else {
            throw HTTPError(.notFound)
        }

        await toolManager.disableTool(id: name)
        return .ok
    }

    @Sendable func listSessionTools(_: Request, context: Context) async throws -> [ToolInfo] {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }

        guard let toolManager = await timelineManager.getToolManager(for: id) else {
            throw HTTPError(.notFound)
        }

        var toolInfos: [ToolInfo] = []

        // 1. System Tools
        let systemTools = await toolManager.getEnabledTools()
        for tool in systemTools {
            let source = await timelineManager.getToolSource(toolId: tool.id, for: id)
            toolInfos.append(
                ToolInfo(
                    id: tool.id, name: tool.name, description: tool.description, isEnabled: true,
                    source: source
                )
            )
        }

        // 2. Workspace Tools
        let workspaceTools = try await timelineManager.getAggregatedTools(for: id)
        for toolRef in workspaceTools {
            if toolInfos.contains(where: { $0.id == toolRef.toolId }) { continue }

            let source = await timelineManager.getToolSource(toolId: toolRef.toolId, for: id)
            let name = toolRef.displayName
            var description = "Workspace tool"

            switch toolRef {
            case let .known(toolId):
                if let sysTool = await toolManager.getAvailableTools().first(where: {
                    $0.id == toolId
                }) {
                    description = sysTool.description
                }
            case let .custom(def):
                description = def.description
            }

            toolInfos.append(
                ToolInfo(
                    id: toolRef.toolId, name: name, description: description, isEnabled: true,
                    source: source
                )
            )
        }

        return toolInfos
    }

    @Sendable func execute(_ request: Request, context: Context) async throws -> String {
        let execReq = try await request.decode(as: ExecuteToolRequest.self, context: context)

        do {
            return try await toolRouter.execute(
                tool: .known(execReq.name),
                arguments: execReq.arguments,
                timelineId: execReq.timelineId
            )
        } catch let error as ToolError {
            if case .toolNotFound = error {
                throw HTTPError(.notFound)
            }
            throw HTTPError(.internalServerError, message: error.localizedDescription)
        } catch {
            throw error
        }
    }
}
