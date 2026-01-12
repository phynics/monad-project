import Foundation
import GRPC
import MonadCore
import SwiftProtobuf

final class JobHandler: MonadJobServiceAsyncProvider {
    private let persistence: PersistenceServiceProtocol
    
    init(persistence: PersistenceServiceProtocol) {
        self.persistence = persistence
    }
    
    func fetchAllJobs(request: MonadEmpty, context: GRPCAsyncServerCallContext) async throws -> MonadJobList {
        let jobs = try await persistence.fetchAllJobs()
        var response = MonadJobList()
        response.jobs = jobs.map { $0.toProto() }
        return response
    }
    
    func saveJob(request: MonadJob, context: GRPCAsyncServerCallContext) async throws -> MonadJob {
        let job = Job(from: request)
        try await persistence.saveJob(job)
        return job.toProto()
    }
    
    func deleteJob(request: MonadDeleteJobRequest, context: GRPCAsyncServerCallContext) async throws -> MonadEmpty {
        guard let uuid = UUID(uuidString: request.id) else {
            throw GRPCStatus(code: .invalidArgument, message: "Invalid UUID")
        }
        try await persistence.deleteJob(id: uuid)
        return MonadEmpty()
    }
    
    func dequeueNextJob(request: MonadEmpty, context: GRPCAsyncServerCallContext) async throws -> MonadJob {
        let jobs = try await persistence.fetchAllJobs()
        if let next = jobs.filter({ $0.status == .pending }).sorted(by: { $0.priority > $1.priority }).first {
            return next.toProto()
        } else {
            throw GRPCStatus(code: .notFound, message: "No pending jobs")
        }
    }
}