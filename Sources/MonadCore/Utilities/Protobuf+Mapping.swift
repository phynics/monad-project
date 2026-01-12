import Foundation
import SwiftProtobuf

extension Message {
    public func toProto() -> MonadMessage {
        var proto = MonadMessage()
        proto.id = id.uuidString
        proto.content = content
        proto.role = role.toProto()
        proto.timestamp = Google_Protobuf_Timestamp(date: timestamp)
        if let think = think {
            proto.think = think
        }
        if let toolCalls = toolCalls {
            proto.toolCalls = toolCalls.map { $0.toProto() }
        }
        if let parentId = parentId {
            proto.parentID = parentId.uuidString
        }
        proto.isSummary = isSummary
        if let summaryType = summaryType {
            proto.summaryType = summaryType.rawValue
        }
        return proto
    }
    
    public init(from proto: MonadMessage) {
        self.init(
            id: UUID(uuidString: proto.id) ?? UUID(),
            timestamp: proto.timestamp.date,
            content: proto.content,
            role: MessageRole(from: proto.role),
            think: proto.hasThink ? proto.think : nil,
            toolCalls: proto.toolCalls.isEmpty ? nil : proto.toolCalls.map { ToolCall(from: $0) },
            parentId: proto.hasParentID ? UUID(uuidString: proto.parentID) : nil,
            isSummary: proto.isSummary,
            summaryType: proto.hasSummaryType ? SummaryType(rawValue: proto.summaryType) : nil
        )
    }
}

extension Message.MessageRole {
    public func toProto() -> MonadMessageRole {
        switch self {
        case .user: return .user
        case .assistant: return .assistant
        case .system: return .system
        case .tool: return .tool
        case .summary: return .summary
        }
    }
    
    public init(from proto: MonadMessageRole) {
        switch proto {
        case .user: self = .user
        case .assistant: self = .assistant
        case .system: self = .system
        case .tool: self = .tool
        case .summary: self = .summary
        case .UNRECOGNIZED: self = .user
        }
    }
}

extension ToolCall {
    public func toProto() -> MonadToolCall {
        var proto = MonadToolCall()
        proto.id = id.uuidString
        proto.name = name
        if let data = try? JSONEncoder().encode(arguments), let json = String(data: data, encoding: .utf8) {
            proto.argumentsJson = json
        }
        return proto
    }
    
    public init(from proto: MonadToolCall) {
        let args: [String: AnyCodable]
        if let data = proto.argumentsJson.data(using: .utf8) {
            args = (try? JSONDecoder().decode([String: AnyCodable].self, from: data)) ?? [:]
        } else {
            args = [:]
        }
        
        self.init(id: UUID(uuidString: proto.id) ?? UUID(), name: proto.name, arguments: args)
    }
}

extension Memory {
    public func toProto() -> MonadMemory {
        var proto = MonadMemory()
        proto.id = id.uuidString
        proto.title = title
        proto.content = content
        proto.createdAt = Google_Protobuf_Timestamp(date: createdAt)
        proto.updatedAt = Google_Protobuf_Timestamp(date: updatedAt)
        proto.tags = tagArray
        proto.metadata = metadataDict
        proto.embedding = embeddingVector
        return proto
    }
    
    public init(from proto: MonadMemory) {
        self.init(
            id: UUID(uuidString: proto.id) ?? UUID(),
            title: proto.title,
            content: proto.content,
            createdAt: proto.createdAt.date,
            updatedAt: proto.updatedAt.date,
            tags: proto.tags,
            metadata: proto.metadata,
            embedding: proto.embedding
        )
    }
}

extension Note {
    public func toProto() -> MonadNote {
        var proto = MonadNote()
        proto.id = id.uuidString
        proto.name = name
        proto.description_p = description
        proto.content = content
        proto.isReadonly = isReadonly
        proto.tags = tagArray
        proto.createdAt = Google_Protobuf_Timestamp(date: createdAt)
        proto.updatedAt = Google_Protobuf_Timestamp(date: updatedAt)
        return proto
    }
    
    public init(from proto: MonadNote) {
        self.init(
            id: UUID(uuidString: proto.id) ?? UUID(),
            name: proto.name,
            description: proto.description_p,
            content: proto.content,
            isReadonly: proto.isReadonly,
            tags: proto.tags,
            createdAt: proto.createdAt.date,
            updatedAt: proto.updatedAt.date
        )
    }
}

extension Job {
    public func toProto() -> MonadJob {
        var proto = MonadJob()
        proto.id = id.uuidString
        proto.title = title
        if let description = description {
            proto.description_p = description
        }
        proto.priority = Int32(priority)
        proto.status = status.toProto()
        proto.createdAt = Google_Protobuf_Timestamp(date: createdAt)
        proto.updatedAt = Google_Protobuf_Timestamp(date: updatedAt)
        return proto
    }
    
    public init(from proto: MonadJob) {
        self.init(
            id: UUID(uuidString: proto.id) ?? UUID(),
            title: proto.title,
            description: proto.hasDescription_p ? proto.description_p : nil,
            priority: Int(proto.priority),
            status: Job.Status(from: proto.status),
            createdAt: proto.createdAt.date,
            updatedAt: proto.updatedAt.date
        )
    }
}

extension Job.Status {
    public func toProto() -> MonadJobStatus {
        switch self {
        case .pending: return .pending
        case .inProgress: return .inProgress
        case .completed: return .completed
        case .cancelled: return .cancelled
        }
    }
    
    public init(from proto: MonadJobStatus) {
        switch proto {
        case .pending: self = .pending
        case .inProgress: self = .inProgress
        case .completed: self = .completed
        case .cancelled: self = .cancelled
        case .UNRECOGNIZED: self = .pending
        }
    }
}

extension ConversationSession {
    public func toProto() -> MonadSession {
        var proto = MonadSession()
        proto.id = id.uuidString
        proto.title = title
        proto.createdAt = Google_Protobuf_Timestamp(date: createdAt)
        proto.updatedAt = Google_Protobuf_Timestamp(date: updatedAt)
        proto.isArchived = isArchived
        proto.tags = tagArray
        if let workingDirectory = workingDirectory {
            proto.workingDirectory = workingDirectory
        }
        return proto
    }
    
    public init(from proto: MonadSession) {
        self.init(
            id: UUID(uuidString: proto.id) ?? UUID(),
            title: proto.title,
            createdAt: proto.createdAt.date,
            updatedAt: proto.updatedAt.date,
            isArchived: proto.isArchived,
            tags: proto.tags,
            workingDirectory: proto.hasWorkingDirectory ? proto.workingDirectory : nil
        )
    }
}
