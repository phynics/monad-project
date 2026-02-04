import Testing
import Foundation
import GRDB
@testable import MonadCore

@Suite struct ModelSerializationTests {
    
    // MARK: - ConversationSession
    
    @Test("ConversationSession JSON Serialization")
    func testConversationSessionJSON() throws {
        let session = ConversationSession(
            id: UUID(),
            title: "Test Session",
            createdAt: Date(),
            updatedAt: Date(),
            isArchived: true,
            tags: ["tag1", "tag2"],
            workingDirectory: "/tmp/test"
        )
        
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(ConversationSession.self, from: data)
        
        #expect(decoded.id == session.id)
        #expect(decoded.title == session.title)
        #expect(decoded.isArchived == session.isArchived)
        #expect(decoded.tagArray == session.tagArray)
        #expect(decoded.workingDirectory == session.workingDirectory)
    }
    
    @Test("ConversationSession Database Roundtrip")
    func testConversationSessionDB() throws {
        let dbQueue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(dbQueue)
        
        let session = ConversationSession(
            id: UUID(),
            title: "DB Session",
            tags: ["db", "test"]
        )
        
        try dbQueue.write { db in
            try session.insert(db)
        }
        
        let fetched = try dbQueue.read { db in
            try ConversationSession.fetchOne(db, key: ["id": session.id])
        }
        
        #expect(fetched != nil)
        #expect(fetched?.title == "DB Session")
        #expect(fetched?.tagArray == ["db", "test"])
    }
    
    // MARK: - Memory
    
    @Test("Memory JSON Serialization")
    func testMemoryJSON() throws {
        let memory = Memory(
            id: UUID(),
            title: "Test Memory",
            content: "Content with special chars: 🚀 & < > \" '",
            tags: ["m1"],
            metadata: ["source": "test"],
            embedding: [0.1, 0.2, -0.3]
        )
        
        let data = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(Memory.self, from: data)
        
        #expect(decoded.id == memory.id)
        #expect(decoded.content == memory.content)
        #expect(decoded.tagArray == memory.tagArray)
        #expect(decoded.metadataDict == memory.metadataDict)
        #expect(decoded.embeddingVector == memory.embeddingVector)
    }
    
    @Test("Memory Database Decoding with Non-Hyphenated UUID")
    func testMemoryUUIDDecoding() throws {
        let dbQueue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(dbQueue)
        
        let uuid = UUID()
        let rawID = uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO memory (id, title, content, createdAt, updatedAt, tags, metadata, embedding)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [rawID, "Test", "Content", Date(), Date(), "[]", "{}", "[]"])
        }
        
        let fetched = try dbQueue.read { db in
            try Memory.fetchOne(db, sql: "SELECT * FROM memory WHERE id = ?", arguments: [rawID])
        }
        
        #expect(fetched != nil)
        #expect(fetched?.id == uuid)
    }
    
    // MARK: - Note
    
    @Test("Note JSON Serialization")
    func testNoteJSON() throws {
        let note = Note(
            id: UUID(),
            name: "My Note",
            content: "Line 1\nLine 2",
            isReadonly: true,
            tags: ["n1"]
        )
        
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(Note.self, from: data)
        
        #expect(decoded.name == note.name)
        #expect(decoded.isReadonly == true)
    }
    
    // MARK: - Edge Cases
    
    @Test("Edge Case: Empty Fields")
    func testEmptyFields() throws {
        let session = ConversationSession(title: "")
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(ConversationSession.self, from: data)
        #expect(decoded.title.isEmpty)
        #expect(decoded.tagArray.isEmpty)
    }
}
