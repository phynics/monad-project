import Foundation
import Testing
import GRPC
import NIOCore
import NIOPosix
import MonadCore
import MonadServerCore
import MonadUI
import MonadTestSupport

@MainActor
@Suite(.serialized) struct E2EIntegrationTests {
    
    @Test("Full E2E: Session and Message Flow")
    func testSessionAndMessageFlow() async throws {
        let (server, clientChannel) = try await setupInProcessServer()
        
        let sessionClient = MonadSessionServiceAsyncClient(channel: clientChannel)
        let chatClient = MonadChatServiceAsyncClient(channel: clientChannel)
        
        // 1. Create Session
        var session = MonadSession()
        session.title = "E2E Test Session"
        let createdSession = try await sessionClient.createSession(session)
        #expect(!createdSession.id.isEmpty)
        #expect(createdSession.title == "E2E Test Session")
        
        // 2. Send Message
        var request = MonadChatRequest()
        request.userQuery = "Hello from E2E test"
        let response = try await chatClient.sendMessage(request)
        #expect(!response.content.isEmpty)
        #expect(response.role == .assistant)
        
        // Cleanup
        try await clientChannel.close().get()
        try await server.close().get()
    }
    
    @Test("Full E2E: Note Management")
    func testNoteManagement() async throws {
        let (server, clientChannel) = try await setupInProcessServer()
        
        let client = MonadNoteServiceAsyncClient(channel: clientChannel)
        
        // 1. Create Note
        var note = MonadNote()
        note.name = "E2E Note"
        note.content = "Content for E2E"
        let created = try await client.saveNote(note)
        #expect(created.name == "E2E Note")
        
        // 2. Fetch All
        let list = try await client.fetchAllNotes(MonadEmpty())
        #expect(list.notes.contains(where: { $0.name == "E2E Note" }))
        
        // Cleanup
        try await clientChannel.close().get()
        try await server.close().get()
    }
    
    @Test("Full E2E: Job Queue")
    func testJobQueue() async throws {
        let (server, clientChannel) = try await setupInProcessServer()
        
        let client = MonadJobServiceAsyncClient(channel: clientChannel)
        
        // 1. Create Job
        var job = MonadJob()
        job.title = "E2E Job"
        job.description_p = "Payload equivalent"
        let created = try await client.saveJob(job)
        #expect(!created.id.isEmpty)
        
        // 2. Fetch All
        let list = try await client.fetchAllJobs(MonadEmpty())
        #expect(list.jobs.count >= 1)
        
        // Cleanup
        try await clientChannel.close().get()
        try await server.close().get()
    }

    // MARK: - Helpers
    
    private func setupInProcessServer() async throws -> (GRPC.Server, GRPCChannel) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        // 1. Core Domain Services (Transient Database)
        let persistence = try await PersistenceService.create()
        let llm = MockLLMService()
        llm.nextResponse = "E2E Mock Response"
        
        // 2. Handlers
        let handlers: [any CallHandlerProvider] = [
            ChatHandler(llm: llm, persistence: persistence),
            SessionHandler(persistence: persistence),
            MemoryHandler(persistence: persistence),
            NoteHandler(persistence: persistence),
            JobHandler(persistence: persistence)
        ]
        
        // 3. Start Server
        let server = try await Server.insecure(group: group)
            .withServiceProviders(handlers)
            .bind(host: "localhost", port: 0)
            .get()
        
        let port = server.channel.localAddress!.port!
        
        // 4. Client Channel
        let clientChannel = try GRPCChannelPool.with(
            target: .host("localhost", port: port),
            transportSecurity: .plaintext,
            eventLoopGroup: group
        )
        
        return (server, clientChannel)
    }
}
