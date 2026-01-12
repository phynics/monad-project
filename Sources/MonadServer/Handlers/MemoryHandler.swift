import Foundation
import GRPC
import MonadCore
import SwiftProtobuf

final class MemoryHandler: MonadMemoryServiceAsyncProvider {
    private let persistence: PersistenceServiceProtocol
    
    init(persistence: PersistenceServiceProtocol) {
        self.persistence = persistence
    }
    
    func searchMemories(request: MonadSearchRequest, context: GRPCAsyncServerCallContext) async throws -> MonadSearchResponse {
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
    
    func saveMemory(request: MonadMemory, context: GRPCAsyncServerCallContext) async throws -> MonadMemory {
        let memory = Memory(from: request)
        _ = try await persistence.saveMemory(memory, policy: .always)
        return memory.toProto()
    }
    
    func deleteMemory(request: MonadDeleteMemoryRequest, context: GRPCAsyncServerCallContext) async throws -> MonadEmpty {
        guard let uuid = UUID(uuidString: request.id) else {
            throw GRPCStatus(code: .invalidArgument, message: "Invalid UUID")
        }
        try await persistence.deleteMemory(id: uuid)
        return MonadEmpty()
    }
    
    func fetchAllMemories(request: MonadEmpty, context: GRPCAsyncServerCallContext) async throws -> MonadMemoryList {
        let memories = try await persistence.fetchAllMemories()
        var response = MonadMemoryList()
        response.memories = memories.map { $0.toProto() }
        return response
    }
}