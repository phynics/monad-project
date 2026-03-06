import MonadShared
import MonadCore
import Foundation

#if DEBUG
extension Message {
    public static func fixture(
        id: UUID = UUID(),
        role: MessageRole = .user,
        content: String = "Test message content",
        timestamp: Date = Date()
    ) -> Message {
        Message(id: id, timestamp: timestamp, content: content, role: role)
    }
}

extension Memory {
    public static func fixture(
        id: UUID = UUID(),
        title: String = "Test Memory",
        content: String = "Test memory content",
        tags: [String] = ["test"],
        timestamp: Date = Date()
    ) -> Memory {
        Memory(id: id, title: title, content: content, createdAt: timestamp, updatedAt: timestamp, tags: tags)
    }
}

extension BackgroundJob {
    public static func fixture(
        id: UUID = UUID(),
        timelineId: UUID = UUID(),
        parentId: UUID? = nil,
        title: String = "Test BackgroundJob",
        description: String? = nil,
        priority: Int = 0,
        status: BackgroundJob.Status = .pending,
        agentId: String = "default"
    ) -> BackgroundJob {
        BackgroundJob(
            id: id,
            timelineId: timelineId,
            parentId: parentId,
            title: title,
            description: description,
            priority: priority,
            agentId: agentId,
            status: status,
            createdAt: Date(),
            updatedAt: Date(),
            logs: []
        )
    }
}

extension WorkspaceReference {
    public static func fixture(
        id: UUID = UUID(),
        uri: WorkspaceURI = .serverTimeline(UUID()),
        hostType: WorkspaceHostType = .server,
        ownerId: UUID? = nil,
        rootPath: String? = nil,
        tools: [ToolReference] = [],
        status: WorkspaceStatus = .active
    ) -> WorkspaceReference {
        WorkspaceReference(
            id: id,
            uri: uri,
            hostType: hostType,
            ownerId: ownerId,
            tools: tools,
            rootPath: rootPath,
            trustLevel: .full,
            status: status
        )
    }
}
#endif
