import Foundation
import USearch
import Logging

// Mark USearchIndex as unchecked Sendable since we are managing thread safety via serial queue
extension USearchIndex: @unchecked @retroactive Sendable {}

public actor VectorStore: VectorStoreProtocol {
    private let index: USearchIndex
    private let dimensions: Int
    private let path: String
    private let logger = Logger(label: "com.monad.VectorStore")
    
    public init(dimensions: Int = 1536, path: String? = nil) throws {
        self.dimensions = dimensions
        
        // Use default path if none provided (e.g. within app support)
        if let providedPath = path {
            self.path = providedPath
        } else {
            // Use Application Support directory
            let fileManager = FileManager.default
            let appName = "Monad"
            let filename = "monad_vector_index.usearch"
            
            #if os(macOS)
                let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let dir = appSupport.appendingPathComponent(appName)
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                self.path = dir.appendingPathComponent(filename).path
            #else
                // Linux fallback
                let dataHome: URL
                if let xdgData = ProcessInfo.processInfo.environment["XDG_DATA_HOME"] {
                    dataHome = URL(fileURLWithPath: xdgData)
                } else {
                    dataHome = fileManager.homeDirectoryForCurrentUser
                        .appendingPathComponent(".local")
                        .appendingPathComponent("share")
                }
                let dir = dataHome.appendingPathComponent(appName.lowercased())
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                self.path = dir.appendingPathComponent(filename).path
            #endif
        }
        
        // Initialize USearch index
        do {
            self.index = try USearchIndex.make(
                metric: .cos,
                dimensions: UInt32(dimensions),
                connectivity: 16,
                quantization: .f32
            )
        } catch {
            logger.error("Failed to initialize USearch index: \(error)")
            throw error
        }
    }
    
    public func initialize() async throws {
        if FileManager.default.fileExists(atPath: path) {
            try await load()
        } else {
            logger.info("No existing vector store found at \(path). Starting fresh.")
        }
    }
    
    public func add(vectors: [[Float]], keys: [UInt64]) async throws {
        guard vectors.count == keys.count else {
            throw VectorStoreError.countMismatch
        }
        
        for (vector, key) in zip(vectors, keys) {
            guard vector.count == dimensions else {
                logger.error("Vector dimension mismatch. Expected \(dimensions), got \(vector.count)")
                continue
            }
            
            do {
                // Use explicit type conversion and ensure contiguous storage
                // The crash might be due to ArraySlice bridging in the sugar extension
                try vector.withUnsafeBufferPointer { buffer in
                    guard let baseAddress = buffer.baseAddress else { return }
                    try index.addSingle(key: USearchKey(key), vector: baseAddress)
                }
            } catch {
                logger.error("Failed to add vector for key \(key): \(error)")
                throw error
            }
        }
    }
    
    public func search(vector: [Float], count: Int) async throws -> [(key: UInt64, distance: Float)] {
        guard vector.count == dimensions else {
            throw VectorStoreError.dimensionMismatch
        }
        
        // search returns ([Key], [Float])
        // Use direct pointer access to avoid potential sugar crashes
        return try vector.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return [] }
            
            var matchKeys: [USearchKey] = Array(repeating: 0, count: count)
            var matchDistances: [Float] = Array(repeating: 0, count: count)
            
            let foundCount = try index.searchSingle(
                vector: baseAddress,
                count: UInt32(count),
                keys: &matchKeys,
                distances: &matchDistances
            )
            
            // Trim to actual results
            let actualCount = Int(foundCount)
            let finalKeys = matchKeys.prefix(actualCount)
            let finalDistances = matchDistances.prefix(actualCount)
            
            // Zip and map to required format
            return zip(finalKeys, finalDistances).map { (key, distance) in
                (key: UInt64(key), distance: distance)
            }
        }
    }
    
    public func save() async throws {
        try index.save(path: path)
        logger.info("Vector store saved to \(path)")
    }
    
    public func load() async throws {
        try index.load(path: path)
        logger.info("Vector store loaded from \(path)")
    }
    
    public var count: Int {
        get {
            return (try? Int(index.count)) ?? 0
        }
    }
}

public enum VectorStoreError: Error {
    case countMismatch
    case dimensionMismatch
}
