import Foundation
import HTTPTypes
import Hummingbird
import PositronicKit
import PKShared
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
    private let timelineManager: TimelineManager
    private let timelineStore: any TimelinePersistenceProtocol
    private let messageStore: any MessageStoreProtocol
    private let toolRouter: ToolRouter

    public init(
        timelineManager: TimelineManager,
        timelineStore: any TimelinePersistenceProtocol,
        messageStore: any MessageStoreProtocol,
        toolRouter: ToolRouter
    ) {
        self.timelineManager = timelineManager
        self.timelineStore = timelineStore
        self.messageStore = messageStore
        self.toolRouter = toolRouter
    }

    public init() {
        let timelineStore = InMemoryTimelinePersistence()
        let messageStore = InMemoryMessageStore()
        let timelineManager = TimelineManager(
            stores: .init(
                timelineStore: timelineStore,
                messageStore: messageStore,
                workspaceStore: InMemoryWorkspacePersistence(),
                toolPersistence: InMemoryToolPersistence()
            ),
            workspaceRoot: FileManager.default.temporaryDirectory
        )
        self.init(
            timelineManager: timelineManager,
            timelineStore: timelineStore,
            messageStore: messageStore,
            toolRouter: ToolRouter(timelineManager: timelineManager, messageStore: messageStore)
        )
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.get("/", use: listSystemTools)
        group.get("/{id}", use: listSessionTools)
        group.post("/execute", use: execute)
        group.post("/{id}/{name}/enable", use: enable)
        group.post("/{id}/{name}/disable", use: disable)
    }

    @Sendable func listSystemTools(_: Request, context _: Context) async throws -> [ToolInfo] {
        currentSystemTools().map { ToolInfo(id: $0.id, name: $0.name, description: $0.description) }
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

        let tools = await toolManager.getEnabledTools()
        return tools.map {
            ToolInfo(
                id: $0.id,
                name: $0.name,
                description: $0.description,
                isEnabled: true,
                source: $0.provenance ?? "System"
            )
        }
    }

    @Sendable func execute(_ request: Request, context: Context) async throws -> String {
        let execReq = try await request.decode(as: ExecuteToolRequest.self, context: context)

        do {
            let outcome = try await toolRouter.execute(
                tool: .known(id: execReq.name),
                arguments: execReq.arguments,
                timelineId: execReq.timelineId
            )
            switch outcome {
            case let .completed(result):
                return result
            case .deferredExternally:
                throw HTTPError(.badRequest, message: "Server API cannot execute externally deferred tools currently")
            }
        } catch let error as ToolError {
            if case .toolNotFound = error {
                throw HTTPError(.notFound)
            }
            throw HTTPError(.internalServerError, message: error.localizedDescription)
        } catch {
            throw error
        }
    }

    private func currentSystemTools() -> [AnyTool] {
        let cwd = FileManager.default.currentDirectoryPath
        return [
            AnyTool(ChangeDirectoryTool(currentPath: cwd, root: cwd, onChange: { _ in })),
            AnyTool(ListDirectoryTool(currentDirectory: cwd, jailRoot: cwd)),
            AnyTool(FindFileTool(currentDirectory: cwd, jailRoot: cwd)),
            AnyTool(SearchFileContentTool(currentDirectory: cwd, jailRoot: cwd)),
            AnyTool(SearchFilesTool(currentDirectory: cwd, jailRoot: cwd)),
            AnyTool(ReadFileTool(currentDirectory: cwd, jailRoot: cwd)),
            AnyTool(TimelineListTool(timelineStore: timelineStore)),
            AnyTool(TimelinePeekTool(messageStore: messageStore, timelineStore: timelineStore)),
        ]
    }
}
