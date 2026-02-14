import Foundation

public protocol VectorStoreProtocol: Actor, Sendable {
    /// Initialize the vector store index
    func initialize() async throws
    
    /// Add vectors to the store
    /// - Parameters:
    ///   - vectors: Array of Float arrays representing vectors
    ///   - keys: Corresponding keys for the vectors
    func add(vectors: [[Float]], keys: [UInt64]) async throws
    
    /// Search for nearest neighbors
    /// - Parameters:
    ///   - vector: Query vector
    ///   - count: Number of results to return
    /// - Returns: Array of (key, distance) tuples
    func search(vector: [Float], count: Int) async throws -> [(key: UInt64, distance: Float)]
    
    /// Save the index to disk
    func save() async throws
    
    /// Load the index from disk
    func load() async throws
    
    /// Get the number of vectors in the index
    var count: Int { get async }
}
