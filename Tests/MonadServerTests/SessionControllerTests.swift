import Dependencies
import Foundation
import Hummingbird
import HummingbirdTesting
import MonadCore
@testable import MonadServer
import MonadShared
import MonadTestSupport
import Testing

@Suite struct SessionControllerTests {
    @Test("Test Create Session Endpoint")
    func createSession() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)

        try await withDependencies {
            $0.timelinePersistence = persistence
            $0.workspacePersistence = persistence
            $0.memoryStore = persistence
            $0.messageStore = persistence
            $0.agentTemplateStore = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
        } operation: {
            let timelineManager = TimelineManager(workspaceRoot: workspaceRoot)

            try await withDependencies {
                $0.timelineManager = timelineManager
            } operation: {
                let router = Router()
                let controller = TimelineAPIController<BasicRequestContext>()
                controller.addRoutes(to: router.group("/sessions"))
                let app = Application(router: router)

                try await app.test(.router) { client in
                    try await client.execute(uri: "/sessions", method: .post) { response in
                        #expect(response.status == .created)

                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let session = try decoder.decode(TimelineResponse.self, from: response.body)
                        #expect(session.id.uuidString.isEmpty == false)
                    }
                }
            }
        }
    }
}
