import Foundation
import GRDB
import MonadCore
import Testing

@Suite(.serialized)
struct JobPersistenceTests {
    private let dbQueue: DatabaseQueue

    init() throws {
        dbQueue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(dbQueue)
    }

    @Test("Test job table creation")
    func jobTableExists() throws {
        try dbQueue.read { db in
            #expect(try db.tableExists("job"))

            let columns = try db.columns(in: "job")
            let columnNames = Set(columns.map { $0.name })

            #expect(columnNames.contains("id"))
            #expect(columnNames.contains("title"))
            #expect(columnNames.contains("description"))
            #expect(columnNames.contains("priority"))
            #expect(columnNames.contains("status"))
            #expect(columnNames.contains("createdAt"))
            #expect(columnNames.contains("updatedAt"))
        }
    }

    @Test("Test basic job persistence")
    func jobPersistence() throws {
        let job = Job(
            title: "Test Task",
            description: "Some description",
            priority: 10
        )

        try dbQueue.write { db in
            try job.insert(db)
        }

        try dbQueue.read { db in
            let fetched = try Job.fetchOne(db, key: job.id)
            #expect(fetched != nil)
            #expect(fetched?.title == "Test Task")
            #expect(fetched?.priority == 10)
            #expect(fetched?.status == .pending)
        }
    }

    @Test("Test job update")
    func jobUpdate() throws {
        var job = Job(title: "Initial")
        try dbQueue.write { db in
            try job.insert(db)
        }

        job.title = "Updated"
        job.status = .inProgress

        try dbQueue.write { db in
            try job.update(db)
        }

        try dbQueue.read { db in
            let fetched = try Job.fetchOne(db, key: job.id)
            #expect(fetched?.title == "Updated")
            #expect(fetched?.status == .inProgress)
        }
    }
}

@Suite(.serialized)
struct PersistenceServiceJobTests {
    private let persistence: PersistenceService

    init() throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)
        persistence = PersistenceService(dbQueue: queue)
    }

    @Test("Test saving and fetching job via PersistenceService")
    func saveAndFetchJob() async throws {
        let job = Job(title: "Service Task")
        try await persistence.saveJob(job)

        let fetched = try await persistence.fetchJob(id: job.id)
        #expect(fetched != nil)
        #expect(fetched?.title == "Service Task")
    }

    @Test("Test listing all jobs via PersistenceService")
    func listAllJobs() async throws {
        try await persistence.saveJob(Job(title: "Task 1", priority: 1))
        try await persistence.saveJob(Job(title: "Task 2", priority: 2))

        let all = try await persistence.fetchAllJobs()
        #expect(all.count == 2)
        #expect(all.contains { $0.title == "Task 1" })
        #expect(all.contains { $0.title == "Task 2" })
    }

    @Test("Test deleting job via PersistenceService")
    func deleteJob() async throws {
        let job = Job(title: "To Delete")
        try await persistence.saveJob(job)

        try await persistence.deleteJob(id: job.id)

        let fetched = try await persistence.fetchJob(id: job.id)
        #expect(fetched == nil)
    }
}
