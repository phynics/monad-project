import Testing
import Foundation
import GRDB
import MonadServer
@testable import MonadCore
import MonadShared

@Suite struct ModelSerializationTests {

    // MARK: - Timeline

    @Test("Timeline JSON Serialization")
    func testTimelineJSON() throws {
        let session = Timeline(
            id: UUID(),
            title: "Test Session",
            createdAt: Date(),
            updatedAt: Date(),
            isArchived: true,
            tags: ["tag1", "tag2"],
            workingDirectory: "/tmp/test"
        )

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Timeline.self, from: data)

        #expect(decoded.id == session.id)
        #expect(decoded.title == session.title)
        #expect(decoded.isArchived == session.isArchived)
        #expect(decoded.tagArray == session.tagArray)
        #expect(decoded.workingDirectory == session.workingDirectory)
    }

    @Test("Timeline Database Roundtrip")
    func testTimelineDB() throws {
        let dbQueue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(dbQueue)

        let session = Timeline(
            id: UUID(),
            title: "DB Session",
            tags: ["db", "test"]
        )

        try dbQueue.write { db in
            try session.insert(db)
        }

        let fetched = try dbQueue.read { db in
            try Timeline.fetchOne(db, key: ["id": session.id])
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
        // GRDB handles standard UUID objects and hyphenated strings automatically.
        // This test simulates a legacy or unusual non-hyphenated 32-char hex string in the ID column.
        let rawID = uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO memory (id, title, content, createdAt, updatedAt, tags, metadata, embedding)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [rawID, "Test", "Content", Date(), Date(), "[]", "{}", "[]"])
        }

        let fetched = try dbQueue.read { db in
            // Memory model should handle the 32-char hex string via its init(row:)
            try Memory.fetchOne(db, sql: "SELECT * FROM memory WHERE id = ?", arguments: [rawID])
        }

        #expect(fetched != nil)
        #expect(fetched?.id == uuid)
    }

    // MARK: - Edge Cases

    @Test("Edge Case: Empty Fields")
    func testEmptyFields() throws {
        let session = Timeline(title: "")
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Timeline.self, from: data)
        #expect(decoded.title.isEmpty)
        #expect(decoded.tagArray.isEmpty)
    }
}
