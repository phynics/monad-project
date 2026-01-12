import Foundation
import Testing
import MonadCore
import SwiftProtobuf

@testable import MonadCore

@Suite
struct ProtobufMappingTests {
    
    @Test("Test Message mapping")
    func testMessageMapping() throws {
        let id = UUID()
        let timestamp = Date()
        let original = Message(
            id: id,
            timestamp: timestamp,
            content: "Hello",
            role: .assistant,
            think: "Thinking...",
            toolCalls: [ToolCall(name: "test_tool", arguments: ["arg": AnyCodable(123)])],
            parentId: UUID(),
            isSummary: true,
            summaryType: .topic
        )
        
        let proto = original.toProto()
        
        #expect(proto.id == id.uuidString)
        #expect(proto.content == "Hello")
        #expect(proto.role == MonadMessageRole.assistant)
        #expect(proto.think == "Thinking...")
        #expect(proto.toolCalls.count == 1)
        #expect(proto.toolCalls[0].name == "test_tool")
        #expect(proto.isSummary == true)
        #expect(proto.summaryType == "topic")
        
        let restored = Message(from: proto)
        #expect(restored.id == original.id)
        #expect(restored.content == original.content)
        #expect(restored.role == original.role)
        #expect(restored.think == original.think)
        #expect(restored.toolCalls == original.toolCalls)
        #expect(restored.parentId == original.parentId)
        #expect(restored.isSummary == original.isSummary)
        #expect(restored.summaryType == original.summaryType)
    }
    
    @Test("Test Memory mapping")
    func testMemoryMapping() throws {
        let id = UUID()
        let original = Memory(
            id: id,
            title: "Test Memory",
            content: "Some content",
            tags: ["tag1", "tag2"],
            metadata: ["key": "value"],
            embedding: [0.1, 0.2, 0.3]
        )
        
        let proto = original.toProto()
        
        #expect(proto.id == id.uuidString)
        #expect(proto.title == "Test Memory")
        #expect(proto.content == "Some content")
        #expect(proto.tags == ["tag1", "tag2"])
        #expect(proto.metadata["key"] == "value")
        #expect(proto.embedding == [0.1, 0.2, 0.3])
        
        let restored = Memory(from: proto)
        #expect(restored.id == original.id)
        #expect(restored.title == original.title)
        #expect(restored.content == original.content)
        #expect(restored.tagArray == original.tagArray)
        #expect(restored.metadataDict == original.metadataDict)
        #expect(restored.embeddingVector == original.embeddingVector)
    }
    
    @Test("Test Note mapping")
    func testNoteMapping() throws {
        let id = UUID()
        let original = Note(
            id: id,
            name: "Test Note",
            description: "Test Desc",
            content: "Test Content",
            isReadonly: true,
            tags: ["n1", "n2"]
        )
        
        let proto = original.toProto()
        
        #expect(proto.id == id.uuidString)
        #expect(proto.name == "Test Note")
        #expect(proto.description_p == "Test Desc")
        #expect(proto.content == "Test Content")
        #expect(proto.isReadonly == true)
        #expect(proto.tags == ["n1", "n2"])
        
        let restored = Note(from: proto)
        #expect(restored.id == original.id)
        #expect(restored.name == original.name)
        #expect(restored.description == original.description)
        #expect(restored.content == original.content)
        #expect(restored.isReadonly == original.isReadonly)
        #expect(restored.tagArray == original.tagArray)
    }
    
    @Test("Test Job mapping")
    func testJobMapping() throws {
        let id = UUID()
        let original = Job(
            id: id,
            title: "Test Job",
            description: "Job Desc",
            priority: 10,
            status: .inProgress
        )
        
        let proto = original.toProto()
        
        #expect(proto.id == id.uuidString)
        #expect(proto.title == "Test Job")
        #expect(proto.description_p == "Job Desc")
        #expect(proto.priority == 10)
        #expect(proto.status == MonadJobStatus.inProgress)
        
        let restored = Job(from: proto)
        #expect(restored.id == original.id)
        #expect(restored.title == original.title)
        #expect(restored.description == original.description)
        #expect(restored.priority == original.priority)
        #expect(restored.status == original.status)
    }
    
    @Test("Test Session mapping")
    func testSessionMapping() throws {
        let id = UUID()
        let original = ConversationSession(
            id: id,
            title: "Test Session",
            isArchived: true,
            tags: ["s1"],
            workingDirectory: "/tmp"
        )
        
        let proto = original.toProto()
        
        #expect(proto.id == id.uuidString)
        #expect(proto.title == "Test Session")
        #expect(proto.isArchived == true)
        #expect(proto.tags == ["s1"])
        #expect(proto.workingDirectory == "/tmp")
        
        let restored = ConversationSession(from: proto)
        #expect(restored.id == original.id)
        #expect(restored.title == original.title)
        #expect(restored.isArchived == original.isArchived)
        #expect(restored.tagArray == original.tagArray)
        #expect(restored.workingDirectory == original.workingDirectory)
    }
}
