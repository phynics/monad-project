import Foundation
import Testing
import MonadCore
import MonadServerCore
import MonadTestSupport

@MainActor
@Suite struct BenchmarkTests {
    
    @Test("Benchmark: Memory Search with 1000 items")
    func benchmarkMemorySearch() async throws {
        let persistence = MockPersistenceService()
        let handler = MemoryHandler(persistence: persistence)
        let context = MockServerContext()
        
        // Setup 1000 items
        var mockMemories: [Memory] = []
        for i in 0..<1000 {
            mockMemories.append(Memory(
                title: "Memory \(i)",
                content: "Content for memory \(i)",
                tags: ["tag\(i % 10)"],
                embedding: [0.1, 0.2]
            ))
        }
        persistence.memories = mockMemories
        
        var req = MonadSearchRequest()
        req.text = "search query"
        
        let start = DispatchTime.now()
        _ = try await handler.searchMemories(request: req, context: context)
        let end = DispatchTime.now()
        
        let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
        let timeInterval = Double(nanoTime) / 1_000_000_000
        
        print("BENCHMARK: Memory Search (1000 items) took \(timeInterval)s")
        #expect(timeInterval < 0.1, "Memory search should be fast")
    }
    
    @Test("Benchmark: Chat Prompt Building with History")
    func benchmarkChatPromptBuilding() async throws {
        let persistence = MockPersistenceService()
        let llm = MockLLMService()
        let handler = ChatHandler(llm: llm, persistence: persistence)
        let context = MockServerContext()
        
        var req = MonadChatRequest()
        req.userQuery = "Benchmark query"
        
        // 20 messages of history
        for i in 0..<20 {
            var msg = MonadMessage()
            msg.role = (i % 2 == 0) ? .user : .assistant
            msg.content = "Message content \(i) " + String(repeating: "word ", count: 50)
            req.history.append(msg)
        }
        
        let start = DispatchTime.now()
        _ = try await handler.sendMessage(request: req, context: context)
        let end = DispatchTime.now()
        
        let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
        let timeInterval = Double(nanoTime) / 1_000_000_000
        
        print("BENCHMARK: Chat sendMessage (20 messages history) took \(timeInterval)s")
        #expect(timeInterval < 0.2, "Chat processing should be fast")
    }
}
