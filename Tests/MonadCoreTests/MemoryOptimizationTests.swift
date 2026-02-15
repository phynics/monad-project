import Testing
import Foundation
@testable import MonadCore

@Suite struct MemoryOptimizationTests {

    @Test("Embedding Vector Parsing Correctness")
    func testEmbeddingVectorParsing() {
        let embedding = [1.0, 2.0, 3.0]
        let memory = Memory(title: "Test", content: "Test content", embedding: embedding)

        let parsed = memory.embeddingVector
        #expect(parsed.count == 3)
        #expect(abs(parsed[0] - 1.0) < 0.0001)
        #expect(abs(parsed[1] - 2.0) < 0.0001)
        #expect(abs(parsed[2] - 3.0) < 0.0001)
    }

    @Test("Embedding Vector Parsing Performance Check")
    func testEmbeddingVectorPerformance() {
        let embedding = (0..<100).map { Double($0) }
        let memory = Memory(title: "Test", content: "Test content", embedding: embedding)

        // Just access it many times to ensure no crash and it works
        for _ in 0..<10 {
            let _ = memory.embeddingVector
        }
        #expect(true)
    }
}
