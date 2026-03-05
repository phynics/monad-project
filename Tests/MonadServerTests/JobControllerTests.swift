import Dependencies
import Foundation
import Hummingbird
import HummingbirdTesting
import MonadCore
import MonadTestSupport
@testable import MonadServer
import Testing

@Suite(.serialized) struct JobControllerTests {
    private func makeApp() async throws -> (some ApplicationProtocol, MockPersistenceService, SessionManager) {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)

        let (app, sessionManager) = try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.agentRegistry = AgentRegistry()
        } operation: {
            let manager = SessionManager(workspaceRoot: workspaceRoot)
            let router = Router()
            let controller = JobAPIController<BasicRequestContext>(sessionManager: manager)
            controller.addRoutes(to: router.group(""))
            return (Application(router: router), manager)
        }
        return (app, persistence, sessionManager)
    }

    @Test("POST /{id}/jobs creates a job and returns 201")
    func createJob_returnsCreated() async throws {
        let (app, persistence, _) = try await makeApp()
        let sessionId = UUID()
        let body = try JSONEncoder().encode(AddJobRequest(
            title: "Refactor module",
            description: "Clean up the networking layer",
            priority: 5,
            agentId: nil,
            parentId: nil
        ))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/\(sessionId.uuidString)/jobs",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                #expect(response.status == .created)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let job = try decoder.decode(Job.self, from: response.body)
                #expect(job.title == "Refactor module")
                #expect(job.sessionId == sessionId)
                #expect(job.agentId == "default")
                #expect(job.status == .pending)
            }
        }
        let storedJobs = try await persistence.fetchJobs(for: sessionId)
        #expect(storedJobs.count == 1)
    }

    @Test("POST /{id}/jobs uses provided agentId")
    func createJob_usesProvidedAgentId() async throws {
        let (app, _, _) = try await makeApp()
        let sessionId = UUID()
        let body = try JSONEncoder().encode(AddJobRequest(
            title: "Custom agent job",
            description: nil,
            priority: 3,
            agentId: "coder",
            parentId: nil
        ))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/\(sessionId.uuidString)/jobs",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                #expect(response.status == .created)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let job = try decoder.decode(Job.self, from: response.body)
                #expect(job.agentId == "coder")
            }
        }
    }

    @Test("POST with invalid session UUID returns 400")
    func createJob_invalidSessionId_returns400() async throws {
        let (app, _, _) = try await makeApp()
        let body = try JSONEncoder().encode(AddJobRequest(title: "test", description: nil, priority: 1, agentId: nil, parentId: nil))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/not-a-uuid/jobs",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("GET /{id}/jobs returns all jobs for session")
    func listJobs_returnsJobsForSession() async throws {
        let (app, persistence, _) = try await makeApp()
        let sessionId = UUID()

        let job1 = Job(sessionId: sessionId, title: "Job 1", description: nil, priority: 1, agentId: "default", status: .pending)
        let job2 = Job(sessionId: sessionId, title: "Job 2", description: nil, priority: 2, agentId: "default", status: .pending)
        try await persistence.saveJob(job1)
        try await persistence.saveJob(job2)

        try await app.test(.router) { client in
            try await client.execute(uri: "/\(sessionId.uuidString)/jobs", method: .get) { response in
                #expect(response.status == .ok)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let jobs = try decoder.decode([Job].self, from: response.body)
                #expect(jobs.count == 2)
            }
        }
    }

    @Test("GET /{id}/jobs/{jobId} returns specific job")
    func getJob_returnsJob() async throws {
        let (app, persistence, _) = try await makeApp()
        let sessionId = UUID()
        let job = Job(sessionId: sessionId, title: "Specific Job", description: "Details", priority: 1, agentId: "default", status: .pending)
        try await persistence.saveJob(job)

        try await app.test(.router) { client in
            try await client.execute(uri: "/\(sessionId.uuidString)/jobs/\(job.id.uuidString)", method: .get) { response in
                #expect(response.status == .ok)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(Job.self, from: response.body)
                #expect(decoded.id == job.id)
                #expect(decoded.title == "Specific Job")
            }
        }
    }

    @Test("GET /{id}/jobs/{jobId} returns 404 when job not found")
    func getJob_notFound_returns404() async throws {
        let (app, _, _) = try await makeApp()
        let sessionId = UUID()
        let unknownJobId = UUID()

        try await app.test(.router) { client in
            try await client.execute(uri: "/\(sessionId.uuidString)/jobs/\(unknownJobId.uuidString)", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("DELETE /{id}/jobs/{jobId} returns 204 on success")
    func deleteJob_returnsNoContent() async throws {
        let (app, persistence, _) = try await makeApp()
        let sessionId = UUID()
        let job = Job(sessionId: sessionId, title: "Delete Me", description: nil, priority: 1, agentId: "default", status: .pending)
        try await persistence.saveJob(job)

        try await app.test(.router) { client in
            try await client.execute(uri: "/\(sessionId.uuidString)/jobs/\(job.id.uuidString)", method: .delete) { response in
                #expect(response.status == .noContent)
            }
        }
        let remaining = try await persistence.fetchJobs(for: sessionId)
        #expect(remaining.isEmpty)
    }

    @Test("DELETE /{id}/jobs/{jobId} with invalid job UUID returns 400")
    func deleteJob_invalidJobId_returns400() async throws {
        let (app, _, _) = try await makeApp()
        let sessionId = UUID()

        try await app.test(.router) { client in
            try await client.execute(uri: "/\(sessionId.uuidString)/jobs/bad-id", method: .delete) { response in
                #expect(response.status == .badRequest)
            }
        }
    }
}
