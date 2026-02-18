import Testing
@testable import MonadCore
import Foundation

@Suite("Memory JSON Parsing Tests")
struct MemoryJSONTests {
    @Test("Embedding vector parsing correctly parses JSON string")
    func testEmbeddingVectorParsing() {
        let vector: [Double] = [0.1, 0.2, 0.3, -0.5, 1.0]
        let jsonData = try! JSONEncoder().encode(vector)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        let memory = Memory(
            id: UUID(),
            title: "Test",
            content: "Content",
            createdAt: Date(),
            updatedAt: Date(),
            tags: "[]",
            metadata: "{}",
            embedding: jsonString
        )

        let parsedVector = memory.embeddingVector
        #expect(parsedVector.count == vector.count)
        for (index, value) in parsedVector.enumerated() {
            #expect(abs(value - vector[index]) < 0.0001)
        }
    }

    @Test("Tag array parsing correctly parses JSON string")
    func testTagArrayParsing() {
        let tags = ["swift", "json", "performance"]
        let jsonData = try! JSONEncoder().encode(tags)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        let memory = Memory(
            id: UUID(),
            title: "Test",
            content: "Content",
            createdAt: Date(),
            updatedAt: Date(),
            tags: jsonString,
            metadata: "{}",
            embedding: "[]"
        )

        let parsedTags = memory.tagArray
        #expect(parsedTags == tags)
    }

    @Test("Metadata dict parsing correctly parses JSON string")
    func testMetadataDictParsing() {
        let metadata = ["key": "value", "foo": "bar"]
        let jsonData = try! JSONEncoder().encode(metadata)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        let memory = Memory(
            id: UUID(),
            title: "Test",
            content: "Content",
            createdAt: Date(),
            updatedAt: Date(),
            tags: "[]",
            metadata: jsonString,
            embedding: "[]"
        )

        let parsedMetadata = memory.metadataDict
        #expect(parsedMetadata == metadata)
    }

    @Test("Invalid JSON returns empty defaults")
    func testInvalidJSON() {
        let memory = Memory(
            id: UUID(),
            title: "Test",
            content: "Content",
            createdAt: Date(),
            updatedAt: Date(),
            tags: "invalid",
            metadata: "{invalid}",
            embedding: "[invalid"
        )

        #expect(memory.tagArray.isEmpty)
        #expect(memory.metadataDict.isEmpty)
        #expect(memory.embeddingVector.isEmpty)
    }
}
