import Testing
import Foundation
import Dependencies
@testable import MonadCore
import MonadShared

@Suite("Dependency Validator Tests")
struct DependencyValidatorTests {
    
    @Test("Validator identifies missing critical dependencies")
    func testValidateRequiredFails() async {
        // Use default unconfigured dependencies
        let validator = DependencyValidator()
        
        let isValid = await validator.validateRequired()
        #expect(!isValid)
    }
    
    @Test("Validator succeeds when dependencies are configured")
    func testValidateRequiredSuccess() async {
        let mockPersistence = MockPersistenceService()
        let mockLLM = MockLLMService()
        let mockEmbedding = MockEmbeddingService()
        
        await withDependencies {
            $0.persistenceService = mockPersistence
            $0.llmService = mockLLM
            $0.embeddingService = mockEmbedding
            $0.sessionManager = SessionManager(workspaceRoot: FileManager.default.temporaryDirectory)
            $0.chatEngine = ChatEngine()
            $0.toolRouter = ToolRouter()
            $0.agentExecutor = AgentExecutor(persistenceService: mockPersistence, chatEngine: ChatEngine())
        } operation: {
            let validator = DependencyValidator()
            let isValid = await validator.validateRequired()
            #expect(isValid)
        }
    }
}
