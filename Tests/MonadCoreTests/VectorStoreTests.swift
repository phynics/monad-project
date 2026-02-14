import Testing
import Foundation
@testable import MonadCore

@Suite struct VectorStoreTests {
    
    // @Test("Add Vector Only")
    // func testAddVector() async throws {
    //     let store = try VectorStore(dimensions: 4)
    //     try await store.initialize()
    //     let vectors: [[Float]] = [[1.0, 0.0, 0.0, 0.0]]
    //     let keys: [UInt64] = [1]
    //     try await store.add(vectors: vectors, keys: keys)
    // }
    
    @Test("Sanity Check")
    func testSanity() async throws {
        #expect(true)
    }
}
