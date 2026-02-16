import MonadShared
import Foundation
import Logging

/// A mock implementation of VectorStoreProtocol for development and testing
/// when the real USearch library is unavailable or unstable.
public actor MockVectorStore: VectorStoreProtocol {
    private let logger = Logger(label: "com.monad.MockVectorStore")
    private var vectors: [UInt64: [Float]] = [:]
    
    public init() {}
    
    public func initialize() async throws {
        logger.info("[MockVectorStore] Initialized")
    }
    
    public func add(vectors: [[Float]], keys: [UInt64]) async throws {
        guard vectors.count == keys.count else {
            throw VectorStoreError.countMismatch
        }
        
        for (vector, key) in zip(vectors, keys) {
            self.vectors[key] = vector
        }
        logger.info("[MockVectorStore] Added \(keys.count) vectors")
    }
    
    public func search(vector: [Float], count: Int) async throws -> [(key: UInt64, distance: Float)] {
        // Simple linear search/sort for mock purposes
        // Calculate cosine similarity or just return random/first ones
        logger.info("[MockVectorStore] Searching with query vector")
        
        let sorted = vectors.map { key, storedVector in
            let dist = cosineDistance(v1: vector, v2: storedVector)
            return (key: key, distance: dist)
        }.sorted { $0.distance < $1.distance }
        
        return Array(sorted.prefix(count))
    }
    
    public func save() async throws {
        logger.info("[MockVectorStore] Save called (no-op)")
    }
    
    public func load() async throws {
        logger.info("[MockVectorStore] Load called (no-op)")
    }
    
    public var count: Int {
        return vectors.count
    }
    
    private func cosineDistance(v1: [Float], v2: [Float]) -> Float {
        guard v1.count == v2.count else { return 1.0 }
        let dot = zip(v1, v2).map(*).reduce(0, +)
        let mag1 = sqrt(v1.map { $0 * $0 }.reduce(0, +))
        let mag2 = sqrt(v2.map { $0 * $0 }.reduce(0, +))
        if mag1 == 0 || mag2 == 0 { return 1.0 }
        return 1.0 - (dot / (mag1 * mag2))
    }
}
