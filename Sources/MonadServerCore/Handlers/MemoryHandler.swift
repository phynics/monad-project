import Foundation
import GRPC
import SwiftProtobuf
import MonadCore

public final class MemoryHandler: MonadMemoryServiceAsyncProvider, Sendable {
    private let persistence: any PersistenceServiceProtocol
    
    public init(persistence: any PersistenceServiceProtocol) {
        self.persistence = persistence
    }
    
    public func searchMemories(request: MonadSearchRequest, context: GRPCAsyncServerCallContext) async throws -> MonadSearchResponse {
        return try await searchMemories(request: request, context: context as any MonadServerContext)
    }

    public func searchMemories(request: MonadSearchRequest, context: any MonadServerContext) async throws -> MonadSearchResponse {
        var response = MonadSearchResponse()
        
        switch request.query {
        case .text(let query):
            let results = try await persistence.searchMemories(query: query)
            response.results = results.map { memory in
                var result = MonadSearchResult()
                result.memory = memory.toProto()
                return result
            }
        case .vector(let query):
            let results = try await persistence.searchMemories(
                embedding: query.vector,
                limit: Int(request.limit > 0 ? request.limit : 10),
                minSimilarity: query.minSimilarity
            )
            response.results = results.map { res in
                var result = MonadSearchResult()
                result.memory = res.memory.toProto()
                result.similarity = res.similarity
                return result
            }
        case .none:
            break
        }
        
        return response
    }
    
    public func saveMemory(request: MonadMemory, context: GRPCAsyncServerCallContext) async throws -> MonadMemory {
        return try await saveMemory(request: request, context: context as any MonadServerContext)
    }

    public func saveMemory(request: MonadMemory, context: any MonadServerContext) async throws -> MonadMemory {
        let memory = Memory(from: request)
        _ = try await persistence.saveMemory(memory, policy: .always)
        return memory.toProto()
    }
    
    public func deleteMemory(request: MonadDeleteMemoryRequest, context: GRPCAsyncServerCallContext) async throws -> MonadEmpty {
        return try await deleteMemory(request: request, context: context as any MonadServerContext)
    }

    public func deleteMemory(request: MonadDeleteMemoryRequest, context: any MonadServerContext) async throws -> MonadEmpty {
        guard let uuid = UUID(uuidString: request.id) else {
            throw GRPCStatus(code: .invalidArgument, message: "Invalid UUID")
        }
        try await persistence.deleteMemory(id: uuid)
        return MonadEmpty()
    }
    
    public func fetchAllMemories(request: MonadEmpty, context: GRPCAsyncServerCallContext) async throws -> MonadMemoryList {
        return try await fetchAllMemories(request: request, context: context as any MonadServerContext)
    }

    public func fetchAllMemories(request: MonadEmpty, context: any MonadServerContext) async throws -> MonadMemoryList {
        let memories = try await persistence.fetchAllMemories()
        var response = MonadMemoryList()
        response.memories = memories.map { $0.toProto() }
        return response
    }
}