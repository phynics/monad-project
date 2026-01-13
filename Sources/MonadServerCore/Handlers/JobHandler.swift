import Foundation
import GRPC
import SwiftProtobuf
import MonadCore

public final class JobHandler: MonadJobServiceAsyncProvider, Sendable {
    private let persistence: any PersistenceServiceProtocol
    
    public init(persistence: any PersistenceServiceProtocol) {
        self.persistence = persistence
    }
    
    public func fetchAllJobs(request: MonadEmpty, context: GRPCAsyncServerCallContext) async throws -> MonadJobList {
        return try await fetchAllJobs(request: request, context: context as any MonadServerContext)
    }

    public func fetchAllJobs(request: MonadEmpty, context: any MonadServerContext) async throws -> MonadJobList {
        let jobs = try await persistence.fetchAllJobs()
        var response = MonadJobList()
        response.jobs = jobs.map { $0.toProto() }
        return response
    }
    
    public func saveJob(request: MonadJob, context: GRPCAsyncServerCallContext) async throws -> MonadJob {
        return try await saveJob(request: request, context: context as any MonadServerContext)
    }

    public func saveJob(request: MonadJob, context: any MonadServerContext) async throws -> MonadJob {
        let job = Job(from: request)
        try await persistence.saveJob(job)
        return job.toProto()
    }
    
    public func deleteJob(request: MonadDeleteJobRequest, context: GRPCAsyncServerCallContext) async throws -> MonadEmpty {
        return try await deleteJob(request: request, context: context as any MonadServerContext)
    }

    public func deleteJob(request: MonadDeleteJobRequest, context: any MonadServerContext) async throws -> MonadEmpty {
        guard let uuid = UUID(uuidString: request.id) else {
            throw GRPCStatus(code: .invalidArgument, message: "Invalid UUID")
        }
        try await persistence.deleteJob(id: uuid)
        return MonadEmpty()
    }
    
    public func dequeueNextJob(request: MonadEmpty, context: GRPCAsyncServerCallContext) async throws -> MonadJob {
        return try await dequeueNextJob(request: request, context: context as any MonadServerContext)
    }

    public func dequeueNextJob(request: MonadEmpty, context: any MonadServerContext) async throws -> MonadJob {
        let jobs = try await persistence.fetchAllJobs()
        if let next = jobs.filter({ $0.status == .pending }).sorted(by: { $0.priority > $1.priority }).first {
            return next.toProto()
        } else {
            throw GRPCStatus(code: .notFound, message: "No pending jobs")
        }
    }
}