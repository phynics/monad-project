import Dependencies
import Foundation
@testable import MonadCore
@testable import MonadShared
@testable import MonadShared
import MonadTestSupport
import Testing

@Suite(.serialized) struct SessionManagerConcurrencyTests {
    private func makeSessionManager() async -> SessionManager {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)

        return await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.msAgentRegistry = MSAgentRegistry()
        } operation: {
            SessionManager(workspaceRoot: workspaceRoot)
        }
    }

    @Test("Concurrent createSession calls each produce a unique session ID")
    func concurrentCreate_uniqueIds() async throws {
        let manager = await makeSessionManager()

        let concurrency = 5
        let sessions = try await withThrowingTaskGroup(of: Timeline.self, returning: [Timeline].self) { group in
            for _ in 0 ..< concurrency {
                group.addTask {
                    try await manager.createSession()
                }
            }
            var results: [Timeline] = []
            for try await session in group {
                results.append(session)
            }
            return results
        }

        #expect(sessions.count == concurrency)
        let ids = Set(sessions.map { $0.id })
        #expect(ids.count == concurrency, "All sessions must have distinct IDs")
    }

    @Test("Concurrent createSession calls all succeed without data corruption")
    func concurrentCreate_noDataCorruption() async throws {
        let manager = await makeSessionManager()

        let sessions = try await withThrowingTaskGroup(of: Timeline.self, returning: [Timeline].self) { group in
            for index in 0 ..< 4 {
                group.addTask {
                    try await manager.createSession(title: "Session \(index)")
                }
            }
            var results: [Timeline] = []
            for try await session in group {
                results.append(session)
            }
            return results
        }

        for session in sessions {
            #expect(!session.id.uuidString.isEmpty)
            #expect(!session.title.isEmpty)
        }
    }

    @Test("getSession returns nil for unknown ID")
    func getSession_unknownId_returnsNil() async {
        let manager = await makeSessionManager()
        let session = await manager.getSession(id: UUID())
        #expect(session == nil)
    }

    @Test("createSession then getSession returns the created session")
    func createSession_thenGet_returnsSession() async throws {
        let manager = await makeSessionManager()
        let created = try await manager.createSession(title: "Test Session")
        let fetched = await manager.getSession(id: created.id)
        #expect(fetched?.id == created.id)
    }

    @Test("Concurrent getSession calls for different IDs return nil without conflict")
    func concurrentGet_differentIds_allReturnNil() async {
        let manager = await makeSessionManager()
        let ids = (0 ..< 10).map { _ in UUID() }

        let results = await withTaskGroup(of: Timeline?.self, returning: [Timeline?].self) { group in
            for id in ids {
                group.addTask {
                    await manager.getSession(id: id)
                }
            }
            var output: [Timeline?] = []
            for await result in group {
                output.append(result)
            }
            return output
        }

        #expect(results.allSatisfy { $0 == nil })
    }
}
