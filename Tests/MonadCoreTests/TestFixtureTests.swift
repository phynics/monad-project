import Testing
import Foundation
@testable import MonadCore
@testable import MonadShared
@testable import MonadShared

@Suite("Test Fixtures and Builders Tests")
struct TestFixtureTests {
    
    @Test("Message Builder creates valid message with defaults")
    func testMessageBuilder() {
        let msg = Message.fixture(content: "Custom Content")
        #expect(msg.content == "Custom Content")
        #expect(msg.role == .user) // Default
    }
    
    @Test("Memory Builder creates valid memory")
    func testMemoryBuilder() {
        let memory = Memory.fixture(title: "Important Fact")
        #expect(memory.title == "Important Fact")
        #expect(!memory.content.isEmpty)
    }
    
    @Test("BackgroundJob Builder creates valid job")
    func testJobBuilder() {
        let job = BackgroundJob.fixture(priority: 10)
        #expect(job.priority == 10)
        #expect(job.status == .pending)
    }
}
