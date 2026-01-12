import Foundation
import GRDB
import MonadCore
import Testing

@Suite(.serialized)
@MainActor
struct JobQueueTests {
    private let persistence: PersistenceService
    private let context: JobQueueContext
    
    init() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)
        
        persistence = PersistenceService(dbQueue: queue)
        context = JobQueueContext(persistenceService: persistence)
    }
    
    @Test("Add job via tool")
    func addJobTool() async throws {
        let tool = AddJobTool(context: context)
        let result = try await tool.execute(parameters: [
            "title": "Fix bug",
            "description": "Critical UI bug",
            "priority": 5
        ])
        
        #expect(result.success)
        
        let jobs = try await persistence.fetchAllJobs()
        #expect(jobs.count == 1)
        #expect(jobs[0].title == "Fix bug")
        #expect(jobs[0].priority == 5)
    }
    
    @Test("List jobs via tool")
    func listJobsTool() async throws {
        _ = try await context.addJob(title: "Task A", description: nil, priority: 1)
        _ = try await context.addJob(title: "Task B", description: nil, priority: 10)
        
        let tool = ListJobsTool(context: context)
        let result = try await tool.execute(parameters: [:])
        
        #expect(result.success)
        #expect(result.output.contains("Task B")) // Priority 10 first
        #expect(result.output.contains("Task A"))
    }
    
    @Test("Update job status via tool")
    func updateStatusTool() async throws {
        let job = try await context.addJob(title: "To Update", description: nil, priority: 0)
        let idShort = job.id.uuidString.prefix(8)
        
        let tool = UpdateJobStatusTool(context: context)
        let result = try await tool.execute(parameters: [
            "id": String(idShort),
            "status": "in_progress"
        ])
        
        #expect(result.success)
        
        let updated = try await persistence.fetchJob(id: job.id)
        #expect(updated?.status == .inProgress)
    }
    
    @Test("Dequeue next job")
    func dequeueNext() async throws {
        _ = try await context.addJob(title: "Low", description: nil, priority: 1)
        _ = try await context.addJob(title: "High", description: nil, priority: 10)
        
        let next = try await context.dequeueNext()
        #expect(next?.title == "High")
        #expect(next?.status == .inProgress)
        
        let updated = try await persistence.fetchJob(id: next!.id)
        #expect(updated?.status == .inProgress)
    }
}
